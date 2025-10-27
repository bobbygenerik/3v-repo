package com.example.tres3

import android.content.Context
import android.os.Build
import android.util.Log
import com.example.tres3.video.VideoCodecManager
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import io.livekit.android.RoomOptions
import io.livekit.android.room.track.LocalVideoTrack
import io.livekit.android.room.track.LocalVideoTrackOptions
import io.livekit.android.room.track.VideoCaptureParameter
import io.livekit.android.util.LoggingLevel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient
import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
// Processed video capturer scaffolding is currently not wired to avoid using internal APIs.
import com.example.tres3.video.ProcessedVideoCapturer
import com.example.tres3.video.EnhancedCameraCapturer
import com.example.tres3.video.CameraEnhancer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// LiveKit types for publishing/unpublishing
import io.livekit.android.room.participant.LocalParticipant
import io.livekit.android.room.participant.ConnectionQuality

object LiveKitManager {
    private val roomMutex = Mutex()
    var currentRoom: Room? = null
    private var lastAudioFocusRequest: android.media.AudioFocusRequest? = null
    private var appContext: Context? = null
    private var isProcessedCameraPublished: Boolean = false
    private var processedTrack: LocalVideoTrack? = null
    private var processedPublishJob: Job? = null
    private var isEnhancedCameraPublished: Boolean = false
    private var enhancedTrack: LocalVideoTrack? = null
    
    // ===== NETWORK QUALITY & RECONNECTION STATE =====
    
    /**
     * Connection quality state (Excellent, Good, Poor)
     */
    private val _connectionQuality = MutableStateFlow(ConnectionQuality.EXCELLENT)
    val connectionQuality: StateFlow<ConnectionQuality> = _connectionQuality.asStateFlow()
    
    /**
     * Reconnection state
     */
    sealed class ReconnectionState {
        object Connected : ReconnectionState()
        data class Reconnecting(val attempt: Int, val maxAttempts: Int = 5) : ReconnectionState()
        data class Reconnected(val wasReconnecting: Boolean = true) : ReconnectionState()
        data class Failed(val reason: String) : ReconnectionState()
    }
    
    private val _reconnectionState = MutableStateFlow<ReconnectionState>(ReconnectionState.Connected)
    val reconnectionState: StateFlow<ReconnectionState> = _reconnectionState.asStateFlow()
    
    private var reconnectAttempts = 0
    private val MAX_RECONNECT_ATTEMPTS = 5
    
    /**
     * Video quality presets
     * - ULTRA: 1080p @ 60fps (flagship phones, 4GB+ RAM)
     * - HIGH: 1080p @ 30fps (most phones, 3GB+ RAM)
     * - AUTO: 720p @ 30fps (adaptive, 2GB+ RAM)
     * - LOW: 540p @ 30fps (poor connection or <2GB RAM - still good quality)
     */
    enum class VideoQuality {
        ULTRA,      // 1080p @ 60fps (flagship phones)
        HIGH,       // 1080p @ 30fps (most phones)
        AUTO,       // 720p @ 30fps (adaptive)
        LOW         // 540p @ 30fps (low-end but still good quality)
    }
    
    private var currentQuality = VideoQuality.HIGH // Default to HIGH (1080p)
    
    /**
     * Detect device capability and auto-adjust quality for lower-end devices
     */
    private fun detectDeviceCapability(context: Context): VideoQuality {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            if (activityManager == null) {
                Log.w("LiveKitManager", "⚠️ ActivityManager not available, defaulting to AUTO quality")
                return VideoQuality.AUTO
            }
            
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            val totalRamGB = memoryInfo.totalMem / (1024.0 * 1024.0 * 1024.0)
            val availableRamMB = memoryInfo.availMem / (1024.0 * 1024.0)
            val sdkVersion = Build.VERSION.SDK_INT
            
            Log.d("LiveKitManager", "📱 Device: RAM=${String.format("%.1f", totalRamGB)}GB, Available=${String.format("%.0f", availableRamMB)}MB, SDK=$sdkVersion, LowMemory=${memoryInfo.lowMemory}")
            
            when {
                // CRITICAL: Very low available memory (less than 512MB free)
                memoryInfo.lowMemory || availableRamMB < 512 -> {
                    Log.w("LiveKitManager", "🚨 CRITICAL LOW MEMORY! Using LOW quality (540p@30fps)")
                    VideoQuality.LOW
                }
                // Low-end devices: <= 2GB RAM - use AUTO for best quality while stable
                totalRamGB <= 2.0 || sdkVersion < 26 -> {
                    Log.w("LiveKitManager", "⚠️ Low-end device detected (${String.format("%.1f", totalRamGB)}GB RAM), using AUTO quality (720p@30fps)")
                    VideoQuality.AUTO // Better quality than LOW, still stable
                }
                // Mid-range devices: 2-3GB RAM
                totalRamGB < 3.0 -> {
                    Log.d("LiveKitManager", "📱 Mid-range device, using AUTO quality (720p)")
                    VideoQuality.AUTO
                }
                // High-end devices: 3-4GB RAM
                totalRamGB < 4.0 -> {
                    Log.d("LiveKitManager", "📱 High-end device, using HIGH quality (1080p @ 30fps)")
                    VideoQuality.HIGH
                }
                // Flagship devices: 4GB+ RAM
                else -> {
                    Log.d("LiveKitManager", "🚀 Flagship device, HIGH quality (1080p). ULTRA (60fps) available in settings.")
                    VideoQuality.HIGH // Don't auto-enable ULTRA (battery intensive)
                }
            }
        } catch (e: Exception) {
            Log.e("LiveKitManager", "⚠️ Error detecting device capability, defaulting to AUTO quality: ${e.message}", e)
            VideoQuality.AUTO
        }
    }
    
    /**
     * Check if device is currently low on memory
     * Returns true if available memory is critically low
     */
    fun isLowMemory(context: Context): Boolean {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            if (activityManager == null) return false
            
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            // Warn if available memory < 20% of total OR system reports low memory
            val availablePercent = (memoryInfo.availMem.toDouble() / memoryInfo.totalMem) * 100
            val isLow = availablePercent < 20.0 || memoryInfo.lowMemory
            
            if (isLow) {
                Log.w("LiveKitManager", "⚠️ LOW MEMORY: ${String.format("%.1f", availablePercent)}% available, System low memory flag: ${memoryInfo.lowMemory}")
            }
            
            isLow
        } catch (e: Exception) {
            Log.e("LiveKitManager", "Error checking memory status: ${e.message}", e)
            false
        }
    }
    
    /**
     * Check if device supports advanced features (HDR, background blur)
     * Returns true only for devices with 3GB+ RAM and Android 8.0+
     */
    fun supportsAdvancedFeatures(context: Context): Boolean {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            if (activityManager == null) {
                Log.w("LiveKitManager", "⚠️ ActivityManager not available, disabling advanced features")
                return false
            }
            
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            
            val totalRamGB = memoryInfo.totalMem / (1024.0 * 1024.0 * 1024.0)
            val sdkVersion = Build.VERSION.SDK_INT
            
            val supported = totalRamGB >= 3.0 && sdkVersion >= 26
            
            if (!supported) {
                Log.d("LiveKitManager", "⚠️ Advanced features (HDR, blur) disabled on this device (RAM=${String.format("%.1f", totalRamGB)}GB, SDK=$sdkVersion)")
            }
            
            supported
        } catch (e: Exception) {
            Log.e("LiveKitManager", "⚠️ Error checking device capabilities, disabling advanced features: ${e.message}", e)
            false
        }
    }
    
    /**
     * Preferred video codec for encoding
     * Default: H.264 (universal compatibility)
     * Advanced codecs (H.265, VP9, VP8) can be enabled via FeatureFlags
     */
    private var preferredCodec: VideoCodecManager.PreferredCodec = VideoCodecManager.PreferredCodec.H264
    
    // Video optimization settings - can be changed dynamically
    fun getCurrentVideoOptions(quality: VideoQuality = currentQuality): LocalVideoTrackOptions {
        val params = when (quality) {
            VideoQuality.ULTRA -> VideoCaptureParameter(
                width = 1920,
                height = 1080,
                maxFps = 60  // 60fps for flagship devices
            )
            VideoQuality.HIGH -> VideoCaptureParameter(
                width = 1920,
                height = 1080,
                maxFps = 30  // 1080p @ 30fps (FaceTime quality)
            )
            VideoQuality.AUTO -> VideoCaptureParameter(
                width = 1280,
                height = 720,
                maxFps = 30  // 720p adaptive
            )
            VideoQuality.LOW -> VideoCaptureParameter(
                width = 960,
                height = 540,
                maxFps = 30  // 540p @ 30fps - still good quality for low-end devices
            )
        }
        
        return LocalVideoTrackOptions(
            captureParams = params
        )
    }
    
    /**
     * Check if simulcast should be enabled for current quality
     */
    private fun shouldEnableSimulcast(): Boolean {
        // Enable simulcast for HIGH and ULTRA for better adaptive streaming
        return currentQuality == VideoQuality.AUTO || currentQuality == VideoQuality.HIGH || currentQuality == VideoQuality.ULTRA
    }
    
    /**
     * Change video quality dynamically (call this if user has poor connection)
     * This is called from Settings or can be used to manually adjust quality
     */
    fun setVideoQuality(quality: VideoQuality) {
        currentQuality = quality
        Log.d("LiveKitManager", "📹 Video quality changed to: $quality")
    }
    
    /**
     * Load video quality from SharedPreferences with device capability detection
     * Automatically downgrades quality on lower-end devices to prevent crashes
     */
    fun loadQualityFromSettings(context: Context) {
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val qualityString = prefs.getString("call_quality", "Auto") ?: "Auto" // Changed default to Auto
        
        val requestedQuality = when (qualityString.lowercase()) {
            "ultra" -> VideoQuality.ULTRA
            "high" -> VideoQuality.HIGH
            "auto" -> VideoQuality.AUTO
            "low" -> VideoQuality.LOW
            else -> VideoQuality.AUTO  // Safe default
        }
        
        // Detect device capability
        val maxSupportedQuality = detectDeviceCapability(context)
        
        // Use the lower of requested quality and device capability (graceful degradation)
        currentQuality = if (requestedQuality.ordinal <= maxSupportedQuality.ordinal) {
            Log.d("LiveKitManager", "✅ Using requested quality: $requestedQuality")
            requestedQuality
        } else {
            Log.w("LiveKitManager", "⚠️ Device capability: $maxSupportedQuality, requested: $requestedQuality. Auto-downgrading.")
            maxSupportedQuality
        }

        // Auto boost to ULTRA when thermals are OK and device is capable (no charging requirement)
        // Applies only if the user has 'boost_ultra_on_charger' enabled and requested 'Auto'.
        try {
            val boostOnCharger = prefs.getBoolean("boost_ultra_on_charger", false)
            if (requestedQuality == VideoQuality.AUTO && boostOnCharger) {
                val thermalOk = isThermalOk(context)
                val hasRam = hasSufficientRam(context, 4.0)

                if (thermalOk && hasRam) {
                    currentQuality = VideoQuality.ULTRA
                    Log.d("LiveKitManager", "🚀 Auto-boosted to ULTRA (thermalOk=$thermalOk, ram>=4GB=$hasRam)")
                } else {
                    Log.d(
                        "LiveKitManager",
                        "Auto-boost skipped (thermalOk=$thermalOk, ram>=4GB=$hasRam)"
                    )
                }
            }
        } catch (e: Exception) {
            Log.w("LiveKitManager", "Auto-boost check failed: ${e.message}")
        }
        
        Log.d("LiveKitManager", "📹 Final video quality: $currentQuality")
        if (currentQuality == VideoQuality.LOW) {
            // Extra safety: Disable advanced features proactively on low-end devices
            Log.d("LiveKitManager", "🛡️ Low quality selected: ensuring HDR/Blur disabled by UI controls")
        }
    }

    private fun isDeviceCharging(context: Context): Boolean {
        return try {
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus: Intent? = context.registerReceiver(null, ifilter)
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val chargePlug = batteryStatus?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
            val plugged = chargePlug == BatteryManager.BATTERY_PLUGGED_AC ||
                    chargePlug == BatteryManager.BATTERY_PLUGGED_USB ||
                    (android.os.Build.VERSION.SDK_INT >= 17 && chargePlug == BatteryManager.BATTERY_PLUGGED_WIRELESS)
            charging || plugged
        } catch (_: Exception) {
            false
        }
    }

    private fun isThermalOk(context: Context): Boolean {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= 29) {
                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                val status = pm?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
                // Consider up to MODERATE acceptable for 60fps; skip on SEVERE+.
                status <= PowerManager.THERMAL_STATUS_MODERATE
            } else {
                true // No API, assume OK
            }
        } catch (_: Exception) {
            true
        }
    }

    private fun hasSufficientRam(context: Context, minGb: Double): Boolean {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val info = ActivityManager.MemoryInfo()
            am?.getMemoryInfo(info)
            val totalRamGB = (info.totalMem / (1024.0 * 1024.0 * 1024.0))
            totalRamGB >= minGb
        } catch (_: Exception) {
            false
        }
    }
    
    /**
     * Load codec preference from settings
     * Only loads if advanced codecs feature flag is enabled
     * Automatically selects best codec based on device performance if no user preference
     */
    fun loadCodecFromSettings(context: Context) {
        // Check if advanced codecs are enabled
        if (!FeatureFlags.isAdvancedCodecsEnabled()) {
            preferredCodec = VideoCodecManager.PreferredCodec.H264
            Log.d("LiveKitManager", "🎬 Advanced codecs disabled, using H.264")
            return
        }
        
        // Load user preference
        val userCodec = VideoCodecManager.loadPreferredCodec(context)
        
        // If user has H.264 preference (default), auto-select best codec for device
        if (userCodec == VideoCodecManager.PreferredCodec.H264) {
            val bestCodec = VideoCodecManager.getBestCodec(context, preferQuality = true)
            if (VideoCodecManager.isCodecSupported(bestCodec)) {
                preferredCodec = bestCodec
                Log.d("LiveKitManager", "🎬 Auto-selected codec based on device: ${bestCodec.displayName}")
                return
            }
        }
        
        // Validate user's codec preference is supported on this device
        if (VideoCodecManager.isCodecSupported(userCodec)) {
            preferredCodec = userCodec
            Log.d("LiveKitManager", "🎬 Loaded codec preference: ${userCodec.displayName}")
        } else {
            // Fall back to H.264 if unsupported
            preferredCodec = VideoCodecManager.PreferredCodec.H264
            Log.w("LiveKitManager", "⚠️ Preferred codec ${userCodec.displayName} not supported, falling back to H.264")
        }
    }
    
    /**
     * Set preferred video codec
     * @param codec The codec to use for video encoding
     */
    fun setPreferredCodec(codec: VideoCodecManager.PreferredCodec) {
        if (VideoCodecManager.isCodecSupported(codec)) {
            preferredCodec = codec
            Log.d("LiveKitManager", "🎬 Codec preference changed to: ${codec.displayName}")
        } else {
            Log.w("LiveKitManager", "⚠️ Codec ${codec.displayName} not supported on this device")
        }
    }
    
    /**
     * Get current preferred codec
     */
    fun getPreferredCodec(): VideoCodecManager.PreferredCodec = preferredCodec
    
    /**
     * Get codec information for diagnostics
     */
    fun getCodecInfo(context: Context): String {
        val info = VideoCodecManager.getCodecInfo(preferredCodec)
        return buildString {
            appendLine("Current Codec: ${preferredCodec.displayName}")
            appendLine("Hardware Accelerated: ${info.hasHardwareEncoder}")
            appendLine("Encoder: ${info.encoderName ?: "Unknown"}")
            appendLine("Supported: ${info.isSupported}")
            if (info.supportedResolutions.isNotEmpty()) {
                appendLine("Resolutions: ${info.supportedResolutions.take(3).joinToString(", ")}")
            }
        }
    }

    suspend fun connectToRoom(context: Context, url: String, token: String): Room {
        // Load quality and codec settings before connecting
        loadQualityFromSettings(context)
        loadCodecFromSettings(context)
        
        return roomMutex.withLock {
            try {
                // Clean up any existing room INSIDE the lock
                val existingRoom = currentRoom
                if (existingRoom != null) {
                    Log.d("LiveKitManager", "connectToRoom: Found existing room, forcing cleanup")
                    currentRoom = null
                    
                    try {
                        // Quick cleanup without delays
                        withContext(Dispatchers.Main) {
                            try {
                                existingRoom.localParticipant.setCameraEnabled(false)
                                existingRoom.localParticipant.setMicrophoneEnabled(false)
                            } catch (e: Exception) {
                                Log.e("LiveKitManager", "Error disabling media: ${e.message}")
                            }
                            existingRoom.disconnect()
                        }
                        
                        existingRoom.release()
                        Log.d("LiveKitManager", "connectToRoom: Cleanup completed")
                    } catch (e: Exception) {
                        Log.e("LiveKitManager", "connectToRoom: Cleanup error: ${e.message}", e)
                    }
                    
                    // Minimal delay removed - rely on async cleanup
                }
                
                io.livekit.android.LiveKit.loggingLevel = LoggingLevel.WARN // Reduce logging overhead

                Log.d("LiveKitManager", "connectToRoom: Creating new room instance with quality: $currentQuality")
                
                // Enable adaptive streaming and dynacast to avoid freezing on constrained networks
                val roomOptions = RoomOptions(
                    adaptiveStream = true,
                    dynacast = true
                )
                val room = LiveKit.create(
                    appContext = context.applicationContext,
                    options = roomOptions
                )
                // Keep reference for audio cleanup routines
                appContext = context.applicationContext

                Log.d("LiveKitManager", "connectToRoom: Configuring audio routing and Connecting to room")
                // Ensure proper audio routing for call: request focus, communication mode, speakerphone on
                try {
                    val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                    @Suppress("DEPRECATION")
                    am.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
                    
                    // Request audio focus (API 26+ uses AudioFocusRequest, older uses deprecated method)
                    val focusResult = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        val focusReq = android.media.AudioFocusRequest.Builder(android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                            .setOnAudioFocusChangeListener { }
                            .setAudioAttributes(
                                android.media.AudioAttributes.Builder()
                                    .setUsage(android.media.AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                                    .build()
                            )
                            // Encourage other apps to PAUSE instead of DUCK during calls
                            .setWillPauseWhenDucked(true)
                            .build()
                        val result = am.requestAudioFocus(focusReq)
                        lastAudioFocusRequest = focusReq
                        result
                    } else {
                        // Fallback for API < 26
                        @Suppress("DEPRECATION")
                        am.requestAudioFocus(
                            { },
                            android.media.AudioManager.STREAM_VOICE_CALL,
                            android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                        )
                    }

                    // Prefer Bluetooth route if available (car/headset). Otherwise use speakerphone.
                    var routedToBluetooth = false
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= 31) {
                            val btDevice = am.availableCommunicationDevices.firstOrNull {
                                it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                            }
                            if (btDevice != null) {
                                routedToBluetooth = am.setCommunicationDevice(btDevice)
                                am.isSpeakerphoneOn = false
                                Log.d("LiveKitManager", "🎧 Routed call audio to Bluetooth (SCO) via setCommunicationDevice: $routedToBluetooth")
                            }
                        } else {
                            // Fallback for older Android versions
                            if (am.isBluetoothScoAvailableOffCall) {
                                @Suppress("DEPRECATION")
                                am.startBluetoothSco()
                                @Suppress("DEPRECATION")
                                am.isBluetoothScoOn = true
                                am.isSpeakerphoneOn = false
                                routedToBluetooth = true
                                Log.d("LiveKitManager", "🎧 Started Bluetooth SCO and disabled speakerphone (legacy path)")
                            }
                        }
                    } catch (routeErr: Exception) {
                        Log.w("LiveKitManager", "⚠️ Bluetooth routing attempt failed: ${routeErr.message}")
                    }

                    if (!routedToBluetooth) {
                        am.isSpeakerphoneOn = true // default to speaker when BT not present
                        Log.d("LiveKitManager", "📢 Using speakerphone (no Bluetooth route available)")
                    }

                    Log.d(
                        "LiveKitManager",
                        "✅ AudioManager configured: MODE_IN_COMMUNICATION, focus=$focusResult, bt=$routedToBluetooth"
                    )
                } catch (e: Exception) {
                    Log.w("LiveKitManager", "⚠️ Failed configuring AudioManager: ${e.message}")
                }
                
                // Connect with precise timing logs for diagnostics
                val tConnectStart = System.currentTimeMillis()
                withContext(Dispatchers.IO) {
                    room.connect(url, token)
                }
                val tConnectEnd = System.currentTimeMillis()
                Log.d("LiveKitManager", "⏱️ CONNECT duration: ${tConnectEnd - tConnectStart}ms (adaptiveStream=${roomOptions.adaptiveStream}, dynacast=${roomOptions.dynacast})")

                // ENHANCEMENT: Enable advanced audio processing (FaceTime-level quality)
                try {
                    withContext(Dispatchers.Main) {
                        // Apply Voice Isolation preference from Settings
                        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
                        val voiceIsolation = prefs.getBoolean("voice_isolation", true)

                        val audioOptions = io.livekit.android.room.track.LocalAudioTrackOptions(
                            noiseSuppression = voiceIsolation,   // Voice Isolation (filters background noise)
                            echoCancellation = true,             // Prevents feedback/echo
                            autoGainControl = voiceIsolation      // Normalizes voice levels
                        )
                        // Ensure local mic is enabled/published with options if supported
                        // Some SDK versions ignore options here; we log the preference regardless
                        // Current SDK signature doesn't accept options on setMicrophoneEnabled.
                        // We enable mic normally and keep options for future upgrades/logging.
                        val enabled = room.localParticipant.setMicrophoneEnabled(true)
                        val pubs = room.localParticipant.audioTrackPublications
                        Log.d(
                            "LiveKitManager",
                            "✅ Mic enabled=$enabled, pubs=${pubs.size}, voiceIsolation=$voiceIsolation"
                        )
                    }
                } catch (e: Exception) {
                    Log.w("LiveKitManager", "⚠️ Could not enable audio/mic: ${e.message}")
                }

                currentRoom = room

                Log.d("LiveKitManager", "Successfully connected to room")
                
                // ===== SETUP EVENT LISTENERS FOR NETWORK QUALITY & RECONNECTION =====
                // LiveKit Android SDK uses flows instead of listeners
                // These will be collected in InCallActivity
                
                // Portrait Mode capture pipeline: will publish a processed track in a follow-up
                room
            } catch (e: Exception) {
                Log.e("LiveKitManager", "Failed to connect to room: ${e.message}", e)
                throw e
            }
        }
    }
    
    // ===== NETWORK QUALITY & RECONNECTION MONITORING =====
    
    /**
     * Update connection quality state
     */
    fun updateConnectionQuality(quality: ConnectionQuality) {
        _connectionQuality.value = quality
    }
    
    /**
     * Handle reconnection attempt (call when connection is lost)
     */
    fun onReconnecting() {
        reconnectAttempts++
        Log.d("LiveKitManager", "🔄 Reconnecting... (attempt $reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)")
        _reconnectionState.value = ReconnectionState.Reconnecting(reconnectAttempts, MAX_RECONNECT_ATTEMPTS)
    }
    
    /**
     * Handle successful reconnection
     */
    suspend fun onReconnected() {
        Log.d("LiveKitManager", "✅ Successfully reconnected!")
        val wasReconnecting = reconnectAttempts > 0
        reconnectAttempts = 0
        _reconnectionState.value = ReconnectionState.Reconnected(wasReconnecting)
        
        // Reset to Connected state after brief delay
        kotlinx.coroutines.delay(2000)
        _reconnectionState.value = ReconnectionState.Connected
    }
    
    /**
     * Handle disconnection
     */
    fun onDisconnected(reason: String? = null) {
        Log.d("LiveKitManager", "🔌 Disconnected from room: ${reason ?: "Normal disconnect"}")
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            _reconnectionState.value = ReconnectionState.Failed("Max reconnection attempts reached")
        } else if (reason != null) {
            _reconnectionState.value = ReconnectionState.Failed(reason)
        }
    }
    
    /**
     * Handle connection quality changes and auto-adjust video quality
     */
    fun handleConnectionQualityChange(quality: ConnectionQuality, context: Context) {
        updateConnectionQuality(quality)
        
        val newQuality = when (quality) {
            ConnectionQuality.EXCELLENT -> {
                if (currentQuality != VideoQuality.HIGH && currentQuality != VideoQuality.ULTRA) {
                    Log.d("LiveKitManager", "📶 Excellent connection - upgrading to HIGH quality (1080p)")
                    VideoQuality.HIGH
                } else null
            }
            ConnectionQuality.GOOD -> {
                if (currentQuality != VideoQuality.AUTO) {
                    Log.d("LiveKitManager", "📶 Good connection - using AUTO quality (720p)")
                    VideoQuality.AUTO
                } else null
            }
            ConnectionQuality.POOR -> {
                if (currentQuality != VideoQuality.LOW) {
                    Log.d("LiveKitManager", "⚠️ Poor connection - downgrading to LOW quality (360p)")
                    VideoQuality.LOW
                } else null
            }
            else -> null
        }
        
        // Apply quality change if needed
        newQuality?.let { 
            setVideoQuality(it)
            Log.d("LiveKitManager", "📹 Quality changed to: $it (restart track to apply)")
        }
    }
    
    /**
     * Reset reconnection state (call when leaving activity)
     */
    fun resetReconnectionState() {
        reconnectAttempts = 0
        _reconnectionState.value = ReconnectionState.Connected
        _connectionQuality.value = ConnectionQuality.EXCELLENT
    }

    /**
     * Publish a processed camera track using a custom capturer that can apply MLKit-based blur.
     * Returns true if publication succeeded.
     */
    suspend fun publishProcessedCameraTrack(context: Context, useFront: Boolean = true): Boolean {
        val room = currentRoom ?: return false
        if (isProcessedCameraPublished && processedTrack != null) {
            Log.d("LiveKitManager", "publishProcessedCameraTrack: already published")
            return true
        }

        return try {
            // Determine capture params based on current quality
            val options = getCurrentVideoOptions(currentQuality)
            val capturer = ProcessedVideoCapturer(context, useFront)

            // Safety: disable any existing default camera track to avoid duplicates
            withContext(Dispatchers.Main) {
                try {
                    room.localParticipant.setCameraEnabled(false)
                } catch (_: Exception) {
                }
            }

            // Create a LocalVideoTrack using our custom capturer and publish it
            val localTrack = withContext(Dispatchers.Main) {
                try {
                    // createVideoTrack(String, VideoCapturer, LocalVideoTrackOptions, VideoProcessor?)
                    room.localParticipant.createVideoTrack(
                        "camera",
                        capturer,
                        options,
                        null
                    )
                } catch (e: Throwable) {
                    Log.e("LiveKitManager", "createVideoTrack failed: ${e.message}", e)
                    null
                }
            }

            if (localTrack == null) {
                Log.w("LiveKitManager", "publishProcessedCameraTrack: LocalVideoTrack creation returned null")
                return false
            }

            val published = withContext(Dispatchers.Main) {
                try {
                    // Note: Android SDK doesn't support VideoTrackPublishOptions like web SDK
                    // Codec selection and quality are configured via VideoCodecManager
                    val pub = room.localParticipant.publishVideoTrack(localTrack)
                    pub != null
                } catch (e: Throwable) {
                    Log.e("LiveKitManager", "publishVideoTrack failed: ${e.message}", e)
                    false
                }
            }

            if (published) {
                processedTrack = localTrack
                isProcessedCameraPublished = true
                Log.d("LiveKitManager", "✅ Published processed camera track (quality=$currentQuality)")
                true
            } else {
                // Cleanup on failure
                try { localTrack.stop() } catch (_: Exception) {}
                try { localTrack.dispose() } catch (_: Exception) {}
                false
            }
        } catch (e: Throwable) {
            Log.e("LiveKitManager", "Failed to publish processed camera track: ${e.message}", e)
            false
        }
    }

    /**
     * Unpublish and dispose processed camera track and restore default camera.
     */
    suspend fun unpublishProcessedCameraTrackAndRestoreDefault(): Boolean {
        val room = currentRoom ?: return false

        if (!isProcessedCameraPublished) {
            Log.d("LiveKitManager", "unpublishProcessedCameraTrackAndRestoreDefault: nothing to do")
            return true
        }

        try {
            // Strategy: disable camera to unpublish current track, stop and dispose processed track, then enable default camera
            withContext(Dispatchers.Main) {
                try {
                    room.localParticipant.setCameraEnabled(false)
                } catch (_: Exception) { }
            }

            processedTrack?.let { track ->
                try { track.stop() } catch (_: Exception) {}
                try { track.dispose() } catch (_: Exception) {}
            }
            processedTrack = null
            isProcessedCameraPublished = false

            // Prefer restoring enhanced camera if enhancements are enabled
            val enhancedPreferred = FeatureFlags.isCameraEnhancementsEnabled()
            val restored: Boolean = if (enhancedPreferred) {
                val ctx = appContext ?: return false
                publishEnhancedCameraTrack(ctx, useFront = true)
            } else {
                // Fallback: re-enable default camera
                withContext(Dispatchers.Main) {
                    try { room.localParticipant.setCameraEnabled(true) } catch (_: Throwable) { false }
                }
            }
            Log.d(
                "LiveKitManager",
                "✅ Restored camera after processed toggle (enhancedPreferred=$enhancedPreferred): $restored"
            )
            return restored
        } catch (e: Throwable) {
            Log.e("LiveKitManager", "Failed to unpublish processed track: ${e.message}", e)
            return false
        }
    }

    /**
     * Diagnostics: is a processed camera track currently published?
     */
    fun isProcessedCameraActive(): Boolean = isProcessedCameraPublished
    
    /**
     * Publish an enhanced Camera2-based track using our custom capturer that applies
     * HDR/low-light/CAF/stabilization via Camera2 CaptureRequests.
     */
    suspend fun publishEnhancedCameraTrack(context: Context, useFront: Boolean = true): Boolean {
        val room = currentRoom ?: return false

        if (isEnhancedCameraPublished && enhancedTrack != null) {
            Log.d("LiveKitManager", "publishEnhancedCameraTrack: already published")
            return true
        }

        return try {
            val options = getCurrentVideoOptions(currentQuality)

            // Configure enhancements for this cameraId via CameraEnhancer (per-instance)
            val cameraEnhancer = CameraEnhancer(context)
            try {
                val camId = getFrontBackCameraId(context, useFront)
                if (camId != null) {
                    if (FeatureFlags.isCameraAutofocusEnhanced()) cameraEnhancer.enableContinuousAutoFocus(camId)
                    if (FeatureFlags.isCameraEnhancementsEnabled()) {
                        cameraEnhancer.enableAutoExposure(camId)
                        cameraEnhancer.enableColorCorrection(camId)
                        cameraEnhancer.enableEdgeEnhancement(camId)
                        cameraEnhancer.enableHotPixelCorrection(camId)
                    }
                    if (FeatureFlags.isCameraStabilizationEnabled()) {
                        cameraEnhancer.enableVideoStabilization(camId)
                        cameraEnhancer.enableOpticalStabilization(camId)
                    }
                    if (FeatureFlags.isCameraLowLightEnabled()) cameraEnhancer.enableLowLightMode(camId)
                    if (supportsAdvancedFeatures(context)) cameraEnhancer.enableHDRMode(camId)
                }
            } catch (e: Exception) {
                Log.w("LiveKitManager", "CameraEnhancer pre-config failed: ${e.message}")
            }

            val capturer = EnhancedCameraCapturer(context, useFront, cameraEnhancer = cameraEnhancer)

            // Disable default camera to avoid duplicates
            withContext(Dispatchers.Main) {
                try { room.localParticipant.setCameraEnabled(false) } catch (_: Exception) {}
            }

            val localTrack = withContext(Dispatchers.Main) {
                try {
                    room.localParticipant.createVideoTrack(
                        "camera",
                        capturer,
                        options,
                        null
                    )
                } catch (e: Throwable) {
                    Log.e("LiveKitManager", "createVideoTrack (enhanced) failed: ${e.message}", e)
                    null
                }
            }

            if (localTrack == null) {
                Log.w("LiveKitManager", "publishEnhancedCameraTrack: LocalVideoTrack creation returned null")
                return false
            }

            val published = withContext(Dispatchers.Main) {
                try {
                    // Note: Android SDK doesn't support VideoTrackPublishOptions like web SDK
                    // Codec selection and quality are configured via VideoCodecManager
                    val pub = room.localParticipant.publishVideoTrack(localTrack)
                    pub != null
                } catch (e: Throwable) {
                    Log.e("LiveKitManager", "publishVideoTrack (enhanced) failed: ${e.message}", e)
                    false
                }
            }

            if (published) {
                enhancedTrack = localTrack
                isEnhancedCameraPublished = true
                Log.d("LiveKitManager", "✅ Published enhanced camera track (quality=$currentQuality)")
                true
            } else {
                // Use safe calls to satisfy Kotlin's nullability analysis across scopes
                try { localTrack?.stop() } catch (_: Exception) {}
                try { localTrack?.dispose() } catch (_: Exception) {}
                false
            }
        } catch (e: Throwable) {
            Log.e("LiveKitManager", "Failed to publish enhanced camera track: ${e.message}", e)
            false
        }
    }

    fun isEnhancedCameraActive(): Boolean = isEnhancedCameraPublished

    private fun getFrontBackCameraId(context: Context, front: Boolean): String? {
        return try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
            cm.cameraIdList.firstOrNull { id ->
                val facing = cm.getCameraCharacteristics(id).get(android.hardware.camera2.CameraCharacteristics.LENS_FACING)
                if (front) facing == android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT
                else facing == android.hardware.camera2.CameraCharacteristics.LENS_FACING_BACK
            }
        } catch (_: Exception) { null }
    }
    
    suspend fun disconnectFromRoom() {
        disconnectRoomInternal(currentRoom, clearCurrent = true)
    }

    suspend fun disconnectSpecificRoom(target: Room?) {
        disconnectRoomInternal(target, clearCurrent = (target != null && currentRoom == target))
    }

    private suspend fun disconnectRoomInternal(target: Room?, clearCurrent: Boolean) {
        if (target == null) {
            return
        }

        roomMutex.withLock {
            val room = target

            Log.d("LiveKitManager", "disconnectRoomInternal: starting cleanup for room=${room.name}")

            muteLocalMedia(room)

            Log.d("LiveKitManager", "disconnectRoomInternal: local media muted, proceeding to disconnect")

            try {
                // Restore audio routing and abandon focus before full disconnect
                try {
                    val ctx = appContext
                    val am = (ctx?.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager)
                        ?: throw IllegalStateException("AudioManager unavailable during disconnect")
                    if (android.os.Build.VERSION.SDK_INT >= 31) {
                        am.clearCommunicationDevice()
                    } else {
                        @Suppress("DEPRECATION")
                        if (am.isBluetoothScoOn) {
                            @Suppress("DEPRECATION")
                            am.stopBluetoothSco()
                            @Suppress("DEPRECATION")
                            am.isBluetoothScoOn = false
                        }
                    }
                    @Suppress("DEPRECATION")
                    am.mode = android.media.AudioManager.MODE_NORMAL
                    lastAudioFocusRequest?.let {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            am.abandonAudioFocusRequest(it)
                        }
                    }
                    // For API < 26, abandon using deprecated method
                    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) {
                        @Suppress("DEPRECATION")
                        am.abandonAudioFocus { }
                    }
                    lastAudioFocusRequest = null
                    Log.d("LiveKitManager", "🔇 Audio focus abandoned and routing cleared")
                } catch (afErr: Exception) {
                    Log.w("LiveKitManager", "⚠️ Error clearing audio focus/routing: ${afErr.message}")
                }

                withContext(Dispatchers.Main) {
                    Log.d("LiveKitManager", "disconnectRoomInternal: calling room.disconnect() on thread=${Thread.currentThread().name}")
                    room.disconnect()
                    Log.d("LiveKitManager", "disconnectRoomInternal: room.disconnect() completed")
                }
            } catch (e: Exception) {
                Log.e("LiveKitManager", "Error disconnecting room: ${e.message}", e)
            } finally {
                try {
                    Log.d("LiveKitManager", "disconnectRoomInternal: releasing room resources")
                    room.release()
                    Log.d("LiveKitManager", "disconnectRoomInternal: room.release() completed")
                } catch (releaseError: Exception) {
                    Log.e("LiveKitManager", "Error releasing room: ${releaseError.message}", releaseError)
                }

                if (clearCurrent && currentRoom == room) {
                    currentRoom = null
                }

                Log.d("LiveKitManager", "disconnectRoomInternal: cleanup finished; currentRoomCleared=$clearCurrent")
            }
        }
    }

    private suspend fun muteLocalMedia(room: Room) {
        val participant = room.localParticipant
        try {
            withContext(Dispatchers.Main) {
                participant.setCameraEnabled(false)
            }
        } catch (e: Exception) {
            Log.e("LiveKitManager", "Error disabling camera: ${e.message}", e)
        }

        try {
            withContext(Dispatchers.Main) {
                participant.setMicrophoneEnabled(false)
            }
        } catch (e: Exception) {
            Log.e("LiveKitManager", "Error disabling microphone: ${e.message}", e)
        }
    }
}
