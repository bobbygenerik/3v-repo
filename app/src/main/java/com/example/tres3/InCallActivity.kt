package com.example.tres3

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.zIndex
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.border
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import io.livekit.android.compose.state.rememberTracks
import io.livekit.android.room.Room
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.LocalVideoTrack
import io.livekit.android.room.track.LocalTrackPublication
import io.livekit.android.room.participant.LocalParticipant
import io.livekit.android.room.participant.RemoteParticipant
import io.livekit.android.util.LoggingLevel
import io.livekit.android.events.RoomEvent
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.onEach
import com.example.tres3.camera.Camera2Manager
import com.example.tres3.ml.MLKitManager
import com.example.tres3.opencv.OpenCVManager
import com.example.tres3.video.CameraEnhancer
import com.example.tres3.video.VideoCodecManager
import livekit.org.webrtc.EglBase
import android.util.Log
import io.livekit.android.compose.types.TrackReference
import io.livekit.android.compose.local.RoomLocal
import io.livekit.android.compose.state.rememberParticipantTrackReferences
import io.livekit.android.compose.ui.RendererType
import io.livekit.android.compose.ui.ScaleType
import livekit.org.webrtc.PeerConnectionFactory
import androidx.compose.ui.unit.Dp
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.ui.input.pointer.consumeAllChanges
import kotlin.math.roundToInt
import kotlin.time.Duration.Companion.seconds

class InCallActivity : ComponentActivity() {
    private lateinit var room: Room
    private var isIntentionallyClosing = false  // Track if we're intentionally disconnecting
    private var callEndListener: com.google.firebase.firestore.ListenerRegistration? = null
    private var directCallEndListener: com.google.firebase.firestore.ListenerRegistration? = null
    
    // Screen sharing state
    internal var pendingScreenShareEnable = false
    
    // Screen capture permission handler
    internal val screenCaptureRequest = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            Log.d("InCallActivity", "✅ Screen capture permission granted")
            // The LiveKit SDK exposes an overload that accepts only a boolean here
            // (passing the raw Intent caused an overload type mismatch in this SDK version).
            lifecycleScope.launch {
                try {
                    room.localParticipant.setScreenShareEnabled(true)
                    this@InCallActivity.pendingScreenShareEnable = false
                    Log.d("InCallActivity", "✅ Screen sharing started successfully")
                    Toast.makeText(
                        this@InCallActivity,
                        "Screen sharing started",
                        Toast.LENGTH_SHORT
                    ).show()
                } catch (e: Exception) {
                    Log.e("InCallActivity", "❌ Failed to start screen sharing: ${e.message}", e)
                    Toast.makeText(
                        this@InCallActivity,
                        "Screen sharing failed: ${e.message}",
                        Toast.LENGTH_LONG
                    ).show()
                    pendingScreenShareEnable = false
                }
            }
        } else {
            Log.w("InCallActivity", "⚠️ Screen capture permission denied")
            Toast.makeText(this, "Screen sharing permission denied", Toast.LENGTH_SHORT).show()
            pendingScreenShareEnable = false
        }
    }
    
    // Enhancement managers
    private lateinit var cameraEnhancer: CameraEnhancer
    private var enhancementsInitialized = false
    
    companion object {
        // Shared EglBase context for video rendering
        private val eglBase: EglBase by lazy { EglBase.create() }
        fun getEglBaseContext(): EglBase.Context = eglBase.eglBaseContext
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val tActivityStart = System.currentTimeMillis()
        
        Log.d("InCallActivity", "🎬 InCallActivity onCreate - starting")
        
        // Start foreground service to prevent battery optimization from freezing the app
        val recipientName = intent.getStringExtra("recipient_name") ?: "Unknown"
        CallForegroundService.start(this, recipientName)
        Log.d("InCallActivity", "🔔 Started foreground service")
        
        // Make full screen - draw content behind system bars
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        // Enable drawing behind system bars
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        
        val windowInsetsController = WindowInsetsControllerCompat(window, window.decorView)
        
        // Make status bar background transparent (video shows through)
        // But keep the icons visible
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        
        // Keep status bar icons visible but hide navigation bar
        windowInsetsController.show(WindowInsetsCompat.Type.statusBars())
        windowInsetsController.hide(WindowInsetsCompat.Type.navigationBars())
        
        // Make status bar icons WHITE (visible over video)
        windowInsetsController.isAppearanceLightStatusBars = false
        
        // Set immersive mode for navigation bar - swipe shows it temporarily
        windowInsetsController.systemBarsBehavior = 
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        
        // Keep screen on during call
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Initialize LiveKit with proper logging
        io.livekit.android.LiveKit.loggingLevel = LoggingLevel.DEBUG
        
        // Initialize OpenCV
        OpenCVManager.initialize(this)
        
        // --- CRITICAL FIX: Grab Room from Singleton ---
        room = LiveKitManager.currentRoom ?: run {
            Log.e("InCallActivity", "CRITICAL: LiveKit Room was not found in singleton.")
            finish()
            return
        }
        // --- END FIX ---
        
        // TODO: Re-enable data message listener for guest call ending (requires LiveKit 2.21+ event handling pattern)
        // Listen for data messages from browser (e.g., guest ending call)
        /*
        lifecycleScope.launch {
            room.events.collect { event ->
                when (event) {
                    is RoomEvent.DataReceived -> {
                        try {
                            val data = String(event.data, Charsets.UTF_8)
                            val json = org.json.JSONObject(data)
                            if (json.optString("type") == "call_ended" && json.optString("source") == "guest") {
                                Log.d("InCallActivity", "🔚 Guest ended the call from browser")
                                runOnUiThread {
                                    Toast.makeText(this@InCallActivity, "Guest ended the call", Toast.LENGTH_SHORT).show()
                                    val homeIntent = Intent(this@InCallActivity, HomeActivity::class.java).apply {
                                        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                                    }
                                    startActivity(homeIntent)
                                    finish()
                                }
                            }
                        } catch (e: Exception) {
                            Log.e("InCallActivity", "Error parsing data message: ${e.message}")
                        }
                    }
                    else -> { /* Ignore other events */ }
                }
            }
        }
        */
        
        // Initialize camera enhancements
        initializeEnhancements()
        
        val recipientEmail = intent.getStringExtra("recipient_email") ?: ""
        val guestLink = intent.getStringExtra("guest_link")
        
        Log.d("InCallActivity", "🎬 InCallActivity ready - recipient: $recipientName")
        if (guestLink != null) {
            Log.d("InCallActivity", "🔗 Guest call mode - link available")
        }
        
    setupContent(recipientName, recipientEmail, guestLink)
    Log.d("InCallActivity", "⏱️ ACTIVITY_CREATED -> UI composed started at t0=${tActivityStart}")
        
        // Listen for call end signals from the other participant (two channels for reliability)
        val roomName = room.name ?: ""
        if (roomName.isNotEmpty()) {
            // Channel 1: activeCallRooms document listener
            callEndListener = CallSignalingManager.listenForCallEnd(roomName) {
                Log.d("InCallActivity", "🔚 [Channel 1] Other participant ended the call via activeCallRooms")
                handleCallEnded()
            }
            
            // Channel 2: Direct callSignals listener for this user
            val currentUser = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
            if (currentUser != null) {
                directCallEndListener = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(currentUser.uid)
                    .collection("callSignals")
                    .whereEqualTo("type", "call_ended")
                    .whereEqualTo("roomName", roomName)
                    .addSnapshotListener { snapshots, error ->
                        if (error != null) {
                            Log.e("InCallActivity", "Error in direct call end listener: ${error.message}")
                            return@addSnapshotListener
                        }
                        
                        snapshots?.documentChanges?.forEach { change ->
                            if (change.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                                val endedBy = change.document.getString("endedBy") ?: ""
                                if (endedBy != currentUser.uid) {
                                    Log.d("InCallActivity", "🔚 [Channel 2] Other participant ended call via callSignals")
                                    // Mark as processed
                                    change.document.reference.update("status", "processed")
                                    handleCallEnded()
                                }
                            }
                        }
                    }
            }
        }
    }
    
    /**
     * Handle call ended by other participant - common logic for both channels
     */
    private fun handleCallEnded() {
        if (isIntentionallyClosing) {
            Log.d("InCallActivity", "ℹ️ Already closing - ignoring call end signal")
            return
        }
        
        isIntentionallyClosing = true // Prevent duplicate handling
        runOnUiThread {
            Toast.makeText(this, "Call ended by other participant", Toast.LENGTH_SHORT).show()
            val homeIntent = Intent(this, HomeActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            startActivity(homeIntent)
            finish()
        }
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("InCallActivity", "🔄 onNewIntent - New call starting on existing activity")
        
        // Update the intent
        setIntent(intent)
        
        // Get the new room
        room = LiveKitManager.currentRoom ?: run {
            Log.e("InCallActivity", "CRITICAL: No room found in onNewIntent")
            finish()
            return
        }
        
        val recipientName = intent?.getStringExtra("recipient_name") ?: "Unknown"
        val recipientEmail = intent?.getStringExtra("recipient_email") ?: ""
        
        Log.d("InCallActivity", "🔄 onNewIntent - Setting up new call with: $recipientName")
        
        // Reset the closing flag
        isIntentionallyClosing = false
        
        // Recreate the UI with the new room
        setupContent(recipientName, recipientEmail)
    }
    
    private fun setupContent(recipientName: String, recipientEmail: String, guestLink: String? = null) {
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    surface = Color.Black,
                    background = Color.Black
                )
            ) {
                // Black surface to ensure no transparency
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = Color.Black
                ) {
                    // The CompositionLocalProvider makes the room available to all children
                    CompositionLocalProvider(
                        RoomLocal provides room
                    ) {
                        InCallScreen(
                            recipientName = recipientName,
                            recipientEmail = recipientEmail,
                            guestLink = guestLink,
                            onDisconnect = {
                                // Set flag BEFORE disconnecting to prevent crash
                                isIntentionallyClosing = true
                                Log.d("InCallActivity", "🔚 Intentionally closing - starting disconnect")
                                
                                lifecycleScope.launch {
                                    try {
                                        // Safely get room information with null checks
                                        val roomName = if (::room.isInitialized) room.name else null
                                        val otherParticipantId = try {
                                            if (::room.isInitialized) {
                                                // Use identity (Firebase UID) not sid (LiveKit session ID)
                                                room.remoteParticipants.values.firstOrNull()?.identity?.value
                                            } else null
                                        } catch (e: Exception) {
                                            Log.e("InCallActivity", "Error getting participant ID: ${e.message}")
                                            null
                                        }
                                        
                                        Log.d("InCallActivity", "Disconnect info - Room: $roomName, Other participant: $otherParticipantId, Total participants: ${room.remoteParticipants.size}")
                                        
                                        // End call and notify other participant
                                        // Only force-end for 1-on-1 calls, let group calls continue with remaining participants
                                        if (!roomName.isNullOrEmpty()) {
                                            try {
                                                val totalParticipants = if (::room.isInitialized) room.remoteParticipants.size + 1 else 1
                                                if (totalParticipants <= 2) {
                                                    // 1-on-1 call: End it for both people
                                                    CallSignalingManager.endCall(roomName, otherParticipantId)
                                                    Log.d("InCallActivity", "✓ 1-on-1 call ended, signaled other participant")
                                                } else {
                                                    // Group call (3+ people): Just leave, don't end for others
                                                    Log.d("InCallActivity", "✓ Leaving group call (${totalParticipants} participants), others will continue")
                                                }
                                            } catch (e: Exception) {
                                                Log.e("InCallActivity", "Error sending end call signal: ${e.message}", e)
                                            }
                                        }
                                        
                                        // Disconnect room with additional safety checks
                                        if (::room.isInitialized) {
                                            try {
                                                LiveKitManager.disconnectSpecificRoom(room)
                                                Log.d("InCallActivity", "✓ Room disconnected successfully")
                                            } catch (e: Exception) {
                                                Log.e("InCallActivity", "Error disconnecting room: ${e.message}", e)
                                            }
                                        } else {
                                            Log.w("InCallActivity", "⚠️ Room not initialized, skipping disconnect")
                                        }
                                    } catch (e: Exception) {
                                        Log.e("InCallActivity", "Critical error during room cleanup: ${e.message}", e)
                                    } finally {
                                        // Always navigate back, even if errors occurred
                                        withContext(Dispatchers.Main) {
                                            try {
                                                val homeIntent = Intent(this@InCallActivity, HomeActivity::class.java).apply {
                                                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                                                }
                                                startActivity(homeIntent)
                                                finish()
                                            } catch (e: Exception) {
                                                Log.e("InCallActivity", "Error navigating to home: ${e.message}", e)
                                                finish() // Try to finish anyway
                                            }
                                        }
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    /**
     * Initialize camera and ML Kit enhancements
     */
    private fun initializeEnhancements() {
        try {
            Log.d("InCallActivity", "🎨 Initializing video enhancements...")
            
            // Initialize camera enhancer
            cameraEnhancer = CameraEnhancer(this)
            
            // Apply camera enhancements if enabled (independent of Performance Overlay)
            if (FeatureFlags.isCameraEnhancementsEnabled()) {
                applyCameraEnhancements()
            }
            enhancementsInitialized = true
            Log.d("InCallActivity", "✅ Video enhancements initialized successfully")
            
        } catch (e: Exception) {
            Log.e("InCallActivity", "❌ Failed to initialize enhancements: ${e.message}", e)
            enhancementsInitialized = false
        }
    }
    
    /**
     * Apply camera enhancements based on feature flags
     */
    private fun applyCameraEnhancements() {
        lifecycleScope.launch {
            try {
                // Get front camera ID (default for video calls)
                val cameraId = getCameraId(isFrontCamera = true) ?: run {
                    Log.w("InCallActivity", "⚠️ Could not find front camera")
                    return@launch
                }
                
                Log.d("InCallActivity", "📷 Applying camera enhancements to camera: $cameraId")
                
                // Enable continuous auto-focus
                if (FeatureFlags.isCameraAutofocusEnhanced()) {
                    if (cameraEnhancer.enableContinuousAutoFocus(cameraId)) {
                        Log.d("InCallActivity", "✅ Continuous auto-focus enabled")
                    }
                }
                
                // Enable auto-exposure
                if (FeatureFlags.isCameraEnhancementsEnabled()) {
                    if (cameraEnhancer.enableAutoExposure(cameraId)) {
                        Log.d("InCallActivity", "✅ Auto-exposure enabled")
                    }
                    
                    // Enable white balance
                    if (cameraEnhancer.setWhiteBalanceMode(cameraId, android.hardware.camera2.CaptureRequest.CONTROL_AWB_MODE_AUTO)) {
                        Log.d("InCallActivity", "✅ Auto white balance enabled")
                    }
                    
                    // Enable color correction
                    if (cameraEnhancer.enableColorCorrection(cameraId)) {
                        Log.d("InCallActivity", "✅ Color correction enabled")
                    }
                    
                    // Enable edge enhancement
                    if (cameraEnhancer.enableEdgeEnhancement(cameraId)) {
                        Log.d("InCallActivity", "✅ Edge enhancement enabled")
                    }
                    
                    // Enable hot pixel correction
                    if (cameraEnhancer.enableHotPixelCorrection(cameraId)) {
                        Log.d("InCallActivity", "✅ Hot pixel correction enabled")
                    }
                }
                
                // Enable video stabilization
                if (FeatureFlags.isCameraStabilizationEnabled()) {
                    if (cameraEnhancer.enableVideoStabilization(cameraId)) {
                        Log.d("InCallActivity", "✅ Video stabilization enabled")
                    }
                    // Try optical stabilization too
                    cameraEnhancer.enableOpticalStabilization(cameraId)
                }
                
                // Enable low-light mode
                if (FeatureFlags.isCameraLowLightEnabled()) {
                    if (cameraEnhancer.enableLowLightMode(cameraId)) {
                        Log.d("InCallActivity", "✅ Low-light mode enabled")
                    }
                }
                
                // ENHANCEMENT: Enable HDR video for better color/contrast (FaceTime quality)
                // Only enable on devices with 3GB+ RAM to prevent performance issues
                try {
                    if (LiveKitManager.supportsAdvancedFeatures(this@InCallActivity)) {
                        if (cameraEnhancer.enableHDRMode(cameraId)) {
                            Log.d("InCallActivity", "✅ HDR video mode enabled (FaceTime-level quality)")
                        } else {
                            Log.d("InCallActivity", "⚠️ HDR not supported on this device")
                        }
                    } else {
                        Log.d("InCallActivity", "⚠️ HDR disabled (low-end device)")
                    }
                } catch (e: Exception) {
                    Log.e("InCallActivity", "⚠️ Error checking/enabling HDR: ${e.message}", e)
                }
                
                // Get diagnostics
                val diagnostics = cameraEnhancer.getDiagnostics(cameraId)
                Log.d("InCallActivity", "📊 Camera enhancement diagnostics: $diagnostics")

                // Start using our enhanced Camera2 capturer so HDR/low-light actually apply
                try {
                    val ok = LiveKitManager.publishEnhancedCameraTrack(this@InCallActivity, useFront = true)
                    Log.d("InCallActivity", "🚀 Enhanced camera capturer publish result: $ok")
                } catch (e: Exception) {
                    Log.e("InCallActivity", "Failed to publish enhanced camera track: ${e.message}", e)
                }
                
            } catch (e: Exception) {
                Log.e("InCallActivity", "❌ Error applying camera enhancements: ${e.message}", e)
            }
        }
    }
    
    /**
     * Get camera ID for front or back camera
     */
    private fun getCameraId(isFrontCamera: Boolean): String? {
        val allCapabilities = Camera2Manager.getAllCameraCapabilities(this)
        return allCapabilities.entries.firstOrNull { (_, caps) ->
            if (isFrontCamera) !caps.isBackCamera else caps.isBackCamera
        }?.key
    }
    
    /**
     * Clean up enhancement resources
     */
    private fun cleanupEnhancements() {
        try {
            if (enhancementsInitialized) {
                Log.d("InCallActivity", "🧹 Cleaning up video enhancements...")
                
                // Reset camera enhancements
                getCameraId(isFrontCamera = true)?.let { cameraId ->
                    cameraEnhancer.resetEnhancements(cameraId)
                }
                
                // ML Kit cleanup happens in DiagnosticsActivity or app cleanup
                
                Log.d("InCallActivity", "✅ Video enhancements cleaned up")
            }
        } catch (e: Exception) {
            Log.e("InCallActivity", "❌ Error cleaning up enhancements: ${e.message}", e)
        }
    }
    
    override fun onDestroy() {
        Log.d("InCallActivity", "💀 InCallActivity onDestroy - starting cleanup (isFinishing=$isFinishing)")
        
        // Wrap everything in try-catch to prevent crashes during cleanup
        try {
            super.onDestroy()
        } catch (e: Exception) {
            Log.e("InCallActivity", "Error in super.onDestroy(): ${e.message}", e)
        }
        
        // Reset reconnection state
        try {
            LiveKitManager.resetReconnectionState()
        } catch (e: Exception) {
            Log.e("InCallActivity", "Error resetting reconnection state: ${e.message}", e)
        }
        
        // Remove call end listener
        try {
            callEndListener?.remove()
            callEndListener = null
            directCallEndListener?.remove()
            directCallEndListener = null
            Log.d("InCallActivity", "✅ Removed call end listeners")
        } catch (e: Exception) {
            Log.e("InCallActivity", "Error removing call end listener: ${e.message}", e)
        }
        
        // Clean up enhancements
        try {
            cleanupEnhancements()
        } catch (e: Exception) {
            Log.e("InCallActivity", "Error cleaning enhancements: ${e.message}", e)
        }
        
        // Stop foreground service
        try {
            CallForegroundService.stop(this)
            Log.d("InCallActivity", "🔕 Stopped foreground service")
        } catch (e: Exception) {
            Log.e("InCallActivity", "Error stopping foreground service: ${e.message}", e)
        }
        
        // Only disconnect if NOT intentionally closing (which already disconnected)
        if (!isIntentionallyClosing) {
            try {
                val activeRoom = when {
                    ::room.isInitialized -> room
                    else -> LiveKitManager.currentRoom
                }

                if (activeRoom != null) {
                    Log.d("InCallActivity", "🔌 Disconnecting room in onDestroy")

                    // Disable media tracks safely
                    try {
                        kotlinx.coroutines.runBlocking {
                            try {
                                kotlinx.coroutines.withTimeoutOrNull(2000) { // 2 second timeout
                                    activeRoom.localParticipant?.setCameraEnabled(false)
                                    activeRoom.localParticipant?.setMicrophoneEnabled(false)
                                }
                                Log.d("InCallActivity", "✓ Media tracks disabled")
                            } catch (e: Exception) {
                                Log.e("InCallActivity", "Error disabling media: ${e.message}", e)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("InCallActivity", "Error disabling media: ${e.message}", e)
                    }

                    // Disconnect room safely
                    try {
                        kotlinx.coroutines.runBlocking {
                            try {
                                kotlinx.coroutines.withTimeoutOrNull(3000) { // 3 second timeout
                                    LiveKitManager.disconnectSpecificRoom(activeRoom)
                                }
                                Log.d("InCallActivity", "✓ Room disconnected")
                            } catch (e: Exception) {
                                Log.e("InCallActivity", "Error during disconnect: ${e.message}", e)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("InCallActivity", "Error during room disconnect: ${e.message}", e)
                    }
                } else {
                    Log.d("InCallActivity", "ℹ️ No active room to disconnect")
                }
            } catch (e: Exception) {
                Log.e("InCallActivity", "Critical error in onDestroy cleanup: ${e.message}", e)
            }
        } else {
            Log.d("InCallActivity", "✓ Skipping disconnect - already done intentionally")
        }
        
        Log.d("InCallActivity", "✅ onDestroy cleanup completed")
    }
    
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        Log.d("InCallActivity", "🪟 Window focus changed: hasFocus=$hasFocus, isIntentionallyClosing=$isIntentionallyClosing")
        if (hasFocus) {
            Log.d("InCallActivity", "✅ InCallActivity HAS window focus - video should be visible")
        } else {
            // Avoid aggressive relaunching to reduce instability; just log.
            Log.d("InCallActivity", "Focus lost (isFinishing=$isFinishing). Not forcing relaunch.")
        }
    }
    
    override fun onResume() {
        super.onResume()
        Log.d("InCallActivity", "▶️ InCallActivity onResume - FORCING camera enabled")
        // Force camera enabled every time we resume
        if (::room.isInitialized) {
                lifecycleScope.launch {
                    room.localParticipant.setCameraEnabled(true)
                }
        }

        // Also ensure microphone is enabled if permission is granted
        try {
            if (::room.isInitialized) {
                val micGranted = ContextCompat.checkSelfPermission(
                    this@InCallActivity,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                if (micGranted) {
                    lifecycleScope.launch {
                        try {
                            room.localParticipant.setMicrophoneEnabled(true)
                            Log.d("InCallActivity", "🎙️ onResume: Microphone enabled")
                        } catch (e: Exception) {
                            Log.w("InCallActivity", "Mic enable onResume failed: ${e.message}")
                        }
                    }
                } else {
                    Log.w("InCallActivity", "🎙️ Mic permission not granted; leaving mic disabled")
                }
            }
        } catch (e: Exception) {
            Log.w("InCallActivity", "onResume mic assert failed: ${e.message}")
        }

        // Re-assert call audio routing on resume (helps recover from route flips)
        try {
            val am = getSystemService(android.content.Context.AUDIO_SERVICE) as? android.media.AudioManager
            if (am != null) {
                @Suppress("DEPRECATION")
                am.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
                var routedToBt = false
                try {
                    if (android.os.Build.VERSION.SDK_INT >= 31) {
                        val bt = am.availableCommunicationDevices.firstOrNull {
                            it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                        }
                        if (bt != null) {
                            routedToBt = am.setCommunicationDevice(bt)
                            am.isSpeakerphoneOn = false
                            Log.d("InCallActivity", "🎧 onResume: Routed audio to Bluetooth: $routedToBt")
                        }
                    }
                } catch (e: Exception) {
                    Log.w("InCallActivity", "Bluetooth route re-assert failed: ${e.message}")
                }
                if (!routedToBt) {
                    am.isSpeakerphoneOn = true
                    Log.d("InCallActivity", "📢 onResume: Using speakerphone")
                }

                // Ensure call stream has audible volume (bump to ~80% if currently very low)
                try {
                    val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_VOICE_CALL)
                    val cur = am.getStreamVolume(android.media.AudioManager.STREAM_VOICE_CALL)
                    if (max > 0 && cur < (max * 0.3).toInt()) {
                        val target = (max * 0.8).toInt().coerceAtLeast(cur)
                        am.setStreamVolume(android.media.AudioManager.STREAM_VOICE_CALL, target, 0)
                        Log.d("InCallActivity", "🔊 Raised call volume from $cur to $target (max=$max)")
                    }
                } catch (ve: Exception) {
                    Log.w("InCallActivity", "Volume adjust failed: ${ve.message}")
                }
            }
        } catch (e: Exception) {
            Log.w("InCallActivity", "⚠️ onResume audio route assert failed: ${e.message}")
        }
    }
    
    override fun onPause() {
        super.onPause()
        Log.w("InCallActivity", "⏸️ InCallActivity onPause - activity going to background!")
    }
    
    override fun onStop() {
        super.onStop()
        Log.e("InCallActivity", "⏹️ InCallActivity onStop - activity no longer visible!")
    }
}

// Data classes for animation values
data class AnimationValues(val offsetY: Dp, val alpha: Float)
data class SpringAnimationValues(val offsetX: Dp, val alpha: Float, val scale: Float)

// Custom Composable for Staggered Animation Logic
@Composable
fun rememberAnimatedButton(show: Boolean, index: Int, totalButtons: Int = 5): AnimationValues {
    val targetY = if (show) 0.dp else 150.dp
    val targetAlpha = if (show) 1f else 0f
    
    // Animate Y offset - Menu (index 0) is ALWAYS first for both appearing and disappearing
    val offsetY by animateDpAsState(
        targetValue = targetY,
        animationSpec = tween(300, delayMillis = index * 80, easing = FastOutSlowInEasing),
        label = "offsetY$index"
    )

    // Animate Alpha - Menu (index 0) is ALWAYS first for both appearing and disappearing
    val alpha by animateFloatAsState(
        targetValue = targetAlpha,
        animationSpec = tween(300, delayMillis = index * 80, easing = FastOutSlowInEasing),
        label = "alpha$index"
    )
    
    return AnimationValues(offsetY, alpha)
}

// Cascading slide-up animation for Landscape Side Rail
@Composable
fun rememberAnimatedButtonSpring(show: Boolean, index: Int): SpringAnimationValues {
    val targetY = if (show) 0.dp else 150.dp // Slide up from bottom
    val targetAlpha = if (show) 1f else 0f
    val targetScale = if (show) 1f else 0.8f
    
    // Cascading delay - each button animates slightly after the previous one
    val cascadeDelay = index * 70 // 70ms between each button
    
    // Animate Y offset with cascading timing
    val offsetY by animateDpAsState(
        targetValue = targetY,
        animationSpec = tween(
            durationMillis = 400,
            delayMillis = cascadeDelay,
            easing = FastOutSlowInEasing
        ),
        label = "offsetY$index"
    )

    // Animate Alpha with cascading timing
    val alpha by animateFloatAsState(
        targetValue = targetAlpha,
        animationSpec = tween(
            durationMillis = 350,
            delayMillis = cascadeDelay,
            easing = LinearOutSlowInEasing
        ),
        label = "alpha$index"
    )
    
    // Animate Scale with cascade effect
    val scale by animateFloatAsState(
        targetValue = targetScale,
        animationSpec = tween(
            durationMillis = 450,
            delayMillis = cascadeDelay,
            easing = FastOutSlowInEasing
        ),
        label = "scale$index"
    )
    
    // Return Y offset instead of X for vertical animation
    return SpringAnimationValues(offsetY, alpha, scale)
}

@Composable
fun ParticipantItem(
    trackReference: io.livekit.android.compose.types.TrackReference,
    isLocal: Boolean
) {
    val participant = trackReference.participant
    val hasVideo = trackReference.publication?.track != null
    val hasAudio = participant.isMicrophoneEnabled
    
    // Use participant.name (set in LiveKit token) instead of identity (Firebase UID)
    val displayName = participant.name?.takeIf { it.isNotBlank() } 
        ?: participant.identity?.value 
        ?: "Unknown"
    val initial = displayName.firstOrNull()?.uppercase() ?: "?"
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.1f))
            .padding(12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Avatar/Initial
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(AppColors.PrimaryBlue),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = initial,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }
            
            // Name and status
            Column {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = displayName,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    if (isLocal) {
                        Text(
                            text = "(You)",
                            fontSize = 12.sp,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                    }
                }
                Text(
                    text = if (hasVideo && hasAudio) "Active" 
                           else if (hasAudio) "Audio only" 
                           else "Muted",
                    fontSize = 12.sp,
                    color = if (hasVideo && hasAudio) Color.Green else Color.White.copy(alpha = 0.6f)
                )
            }
        }
        
        // Status indicators
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = if (hasAudio) Icons.Default.Mic else Icons.Default.MicOff,
                contentDescription = if (hasAudio) "Mic on" else "Mic off",
                tint = if (hasAudio) Color.White else Color.Red,
                modifier = Modifier.size(20.dp)
            )
            Icon(
                imageVector = if (hasVideo) Icons.Default.Videocam else Icons.Default.VideocamOff,
                contentDescription = if (hasVideo) "Camera on" else "Camera off",
                tint = if (hasVideo) Color.White else Color.Red,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
fun AddPersonDialog(
    onDismiss: () -> Unit,
    onInvite: (String) -> Unit,
    onGenerateGuestLink: (String) -> Unit,
    generatedLink: String,
    isLinkLoading: Boolean
) {
    var emailInput by remember { mutableStateOf("") }
    var guestNameInput by remember { mutableStateOf("") }
    var selectedTab by remember { mutableStateOf(0) }
    val context = androidx.compose.ui.platform.LocalContext.current
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.85f))
            .pointerInput(Unit) {
                detectTapGestures(onTap = { onDismiss() })
            },
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(0.9f)
                .clip(RoundedCornerShape(20.dp))
                .background(Color(0xFF1A1A1A))
                .padding(24.dp)
                .pointerInput(Unit) {
                    detectTapGestures(onTap = { /* Consume tap */ })
                }
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Add Person to Call",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                IconButton(onClick = onDismiss) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Close",
                        tint = Color.White.copy(alpha = 0.8f),
                        modifier = Modifier.size(24.dp)
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // Tab Row
            TabRow(
                selectedTabIndex = selectedTab,
                containerColor = Color(0xFF252525),
                contentColor = Color(0xFF67B5FF),
                indicator = { tabPositions ->
                    TabRowDefaults.Indicator(
                        modifier = Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                        color = Color(0xFF67B5FF)
                    )
                }
            ) {
                Tab(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    text = { Text("App User", color = if (selectedTab == 0) Color.White else Color.White.copy(alpha = 0.6f)) }
                )
                Tab(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    text = { Text("Guest Link", color = if (selectedTab == 1) Color.White else Color.White.copy(alpha = 0.6f)) }
                )
            }
            
            Spacer(modifier = Modifier.height(20.dp))
            
            // Content based on selected tab
            when (selectedTab) {
                0 -> {
                    // App User Tab
                    Text(
                        text = "Invite someone who has the app installed",
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 14.sp
                    )
                    
                    Spacer(modifier = Modifier.height(12.dp))
                    
                    OutlinedTextField(
                        value = emailInput,
                        onValueChange = { emailInput = it },
                        label = { Text("User", color = Color.White.copy(alpha = 0.6f)) },
                        placeholder = { Text("Email, phone, or username", color = Color.White.copy(alpha = 0.4f)) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedBorderColor = Color(0xFF67B5FF),
                            unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                            cursorColor = Color(0xFF67B5FF),
                            focusedContainerColor = Color(0xFF252525),
                            unfocusedContainerColor = Color(0xFF252525)
                        ),
                        singleLine = true,
                        shape = RoundedCornerShape(12.dp)
                    )
                    
                    Spacer(modifier = Modifier.height(20.dp))
                    
                    // Action buttons
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        TextButton(
                            onClick = onDismiss,
                            modifier = Modifier.padding(end = 8.dp)
                        ) {
                            Text("Cancel", color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp)
                        }
                        
                        Button(
                            onClick = {
                                if (emailInput.isNotBlank()) {
                                    onInvite(emailInput.trim())
                                }
                            },
                            enabled = emailInput.isNotBlank(),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color(0xFF67B5FF),
                                contentColor = Color.White,
                                disabledContainerColor = Color(0xFF67B5FF).copy(alpha = 0.3f)
                            ),
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.height(44.dp).widthIn(min = 110.dp)
                        ) {
                            Text("Invite", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
                1 -> {
                    // Guest Link Tab
                    if (generatedLink.isEmpty()) {
                        Text(
                            text = "Create a link for someone without the app",
                            color = Color.White.copy(alpha = 0.6f),
                            fontSize = 14.sp
                        )
                        
                        Spacer(modifier = Modifier.height(12.dp))
                        
                        OutlinedTextField(
                            value = guestNameInput,
                            onValueChange = { guestNameInput = it },
                            label = { Text("Guest Name", color = Color.White.copy(alpha = 0.6f)) },
                            placeholder = { Text("e.g., John Doe", color = Color.White.copy(alpha = 0.4f)) },
                            modifier = Modifier.fillMaxWidth(),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White,
                                focusedBorderColor = Color(0xFF67B5FF),
                                unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                                cursorColor = Color(0xFF67B5FF),
                                focusedContainerColor = Color(0xFF252525),
                                unfocusedContainerColor = Color(0xFF252525)
                            ),
                            singleLine = true,
                            shape = RoundedCornerShape(12.dp)
                        )
                        
                        Spacer(modifier = Modifier.height(20.dp))
                        
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End
                        ) {
                            TextButton(
                                onClick = onDismiss,
                                modifier = Modifier.padding(end = 8.dp)
                            ) {
                                Text("Cancel", color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp)
                            }
                            
                            Button(
                                onClick = {
                                    if (guestNameInput.isNotBlank()) {
                                        onGenerateGuestLink(guestNameInput.trim())
                                    }
                                },
                                enabled = guestNameInput.isNotBlank() && !isLinkLoading,
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(0xFF67B5FF),
                                    contentColor = Color.White,
                                    disabledContainerColor = Color(0xFF67B5FF).copy(alpha = 0.3f)
                                ),
                                shape = RoundedCornerShape(12.dp),
                                modifier = Modifier.height(44.dp).widthIn(min = 110.dp)
                            ) {
                                if (isLinkLoading) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(20.dp),
                                        color = Color.White
                                    )
                                } else {
                                    Text("Generate", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    } else {
                        // Show generated link
                        Text(
                            text = "Share this link with the guest:",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                        
                        Spacer(modifier = Modifier.height(12.dp))
                        
                        androidx.compose.foundation.text.selection.SelectionContainer {
                            Text(
                                generatedLink,
                                color = Color(0xFF67B5FF),
                                fontSize = 12.sp,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(Color(0xFF252525), RoundedCornerShape(8.dp))
                                    .padding(12.dp)
                            )
                        }
                        
                        Spacer(modifier = Modifier.height(20.dp))
                        
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End
                        ) {
                            TextButton(
                                onClick = onDismiss,
                                modifier = Modifier.padding(end = 8.dp)
                            ) {
                                Text("Close", color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp)
                            }
                            
                            Button(
                                onClick = {
                                    val shareIntent = android.content.Intent().apply {
                                        action = android.content.Intent.ACTION_SEND
                                        type = "text/plain"
                                        putExtra(android.content.Intent.EXTRA_TEXT, 
                                            "📞 Join my video call!\n\n$generatedLink\n\n✨ No app needed - just click to join from your browser!")
                                        putExtra(android.content.Intent.EXTRA_SUBJECT, "Video Call Invitation")
                                    }
                                    context.startActivity(android.content.Intent.createChooser(shareIntent, "Share guest link"))
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(0xFF67B5FF),
                                    contentColor = Color.White
                                ),
                                shape = RoundedCornerShape(12.dp),
                                modifier = Modifier.height(44.dp).widthIn(min = 110.dp)
                            ) {
                                Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("Share", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun InfiniteRotatingIcon() {
    val infiniteTransition = rememberInfiniteTransition(label = "rotation")
    val rotation by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "rotation"
    )
    
    Icon(
        imageVector = Icons.Default.Sync,
        contentDescription = "Connecting",
        modifier = Modifier
            .size(80.dp)
            .rotate(rotation),
        tint = Color(0xFF67B5FF) // Using a light blue color, assuming AppColors.PrimaryBlue is something similar
    )
}

@Composable
fun CallVideoTrackView(
    trackReference: io.livekit.android.compose.types.TrackReference,
    modifier: Modifier = Modifier,
    isOverlay: Boolean = false
) {
    val room = RoomLocal.current
    val participant = trackReference.participant
    val mirrorLocal = participant is LocalParticipant
    val rendererType = if (isOverlay) RendererType.Texture else RendererType.Surface
    val scaleType = ScaleType.Fill // Always fill to avoid black bars

    io.livekit.android.compose.ui.VideoTrackView(
        trackReference = trackReference,
        modifier = modifier,
        room = room,
        mirror = mirrorLocal,
        scaleType = scaleType,
        rendererType = rendererType
    )
}

fun formatDuration(seconds: Int): String {
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    val secs = seconds % 60
    
    return if (hours > 0) {
        String.format(java.util.Locale.US, "%d:%02d:%02d", hours, minutes, secs)
    } else {
        String.format(java.util.Locale.US, "%02d:%02d", minutes, secs)
    }
}

@Composable
fun InCallScreen(
    recipientName: String,
    recipientEmail: String,
    guestLink: String? = null,
    onDisconnect: () -> Unit
) {
    // Retrieve Room object using RoomLocal.current
    val room = RoomLocal.current 
    val context = androidx.compose.ui.platform.LocalContext.current
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    
    // Detect orientation
    val isLandscape = configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    
    var isMicEnabled by remember { mutableStateOf(room.localParticipant.isMicrophoneEnabled) }
    var isCameraEnabled by remember { mutableStateOf(room.localParticipant.isCameraEnabled) }
    var showMenu by remember { mutableStateOf(false) }
    var showControls by remember { mutableStateOf(true) }
    var callDuration by remember { mutableStateOf(0) }
    var showParticipantsList by remember { mutableStateOf(false) }
    var isScreenSharing by remember { mutableStateOf(false) }
    var showAddPersonDialog by remember { mutableStateOf(false) }
    var isVideoSwapped by remember { mutableStateOf(false) }
    var isLocalVideoEnlarged by remember { mutableStateOf(false) }
    // Track current facing for processed-camera pipeline toggles
    var isFrontCamera by remember { mutableStateOf(true) }
    // Audio-only mode (disables video transmission)
    var isAudioOnlyMode by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    // Performance overlay toggle (developer setting)
    var showPerfOverlay by remember { mutableStateOf(FeatureFlags.isPerformanceOverlayEnabled()) }
    // Quick toggles (top-left) visibility for double-tap
    var showTopLeftQuickToggles by remember { mutableStateOf(true) }

    // Track if this call ever had 2+ remote participants (group call)
    var everHadMultipleParticipants by remember { mutableStateOf(false) }

    // Mic permission state and launcher
    val micPermissionGranted = remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        )
    }
    val requestMicPermission = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        micPermissionGranted.value = granted
        if (granted) {
            // Re-enable mic immediately when granted
            scope.launch { room.localParticipant.setMicrophoneEnabled(true) }
        }
    }

    // Auto-request mic permission on enter if not granted (improves first-time guest experience)
    LaunchedEffect(Unit) {
        if (!micPermissionGranted.value) {
            try {
                // small delay to avoid jank during initial composition
                kotlinx.coroutines.delay(300)
                requestMicPermission.launch(Manifest.permission.RECORD_AUDIO)
            } catch (_: Exception) {}
        }
    }
    
    // Portrait mode enhancement states - OPTIMIZED with Animatable to reduce recompositions
    val videoScale = remember { Animatable(1f) }
    val videoOffsetX = remember { Animatable(0f) }
    val videoOffsetY = remember { Animatable(0f) }
    var portraitAspectRatioMode by remember { mutableStateOf(false) } // default to fill screen
    
    // Background blur state (Portrait Mode / FaceTime feature)
    var isBackgroundBlurEnabled by remember { mutableStateOf(false) }
    
    // Guest link state
    var generatedGuestLink by remember { mutableStateOf("") }
    var guestLinkLoading by remember { mutableStateOf(false) }
    
    // Track actual remote participant name from Firestore
    var actualRemoteName by remember { mutableStateOf<String?>(null) }
    
    // Save call history helper
    val saveCallHistory = {
        scope.launch {
            try {
                val currentUserId = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid ?: ""
                val firestore = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                
                // Get current user's name
                var currentUserName = "You"
                if (currentUserId.isNotEmpty()) {
                    try {
                        val userDoc = firestore.collection("users").document(currentUserId).get().await()
                        currentUserName = userDoc.getString("displayName") 
                            ?: userDoc.getString("email")?.substringBefore("@") 
                            ?: "You"
                    } catch (e: Exception) {
                        Log.e("InCallActivity", "Failed to fetch current user name: ${e.message}")
                    }
                }
                
                // Get receiver ID from remote participant
                val remoteParticipant = room.remoteParticipants.values.firstOrNull()
                val receiverId = remoteParticipant?.identity?.value ?: recipientEmail
                val roomName = room.name ?: ""
                
                if (currentUserId.isNotEmpty() && receiverId.isNotEmpty()) {
                    val callHistoryRepo = com.example.tres3.data.CallHistoryRepository()
                    callHistoryRepo.saveCallHistoryForBoth(
                        callerId = currentUserId,
                        callerName = currentUserName,
                        receiverId = receiverId,
                        receiverName = actualRemoteName ?: recipientName,
                        roomName = roomName,
                        duration = callDuration.toLong(),
                        callType = com.example.tres3.data.CallType.VIDEO,
                        callStatus = com.example.tres3.data.CallStatus.COMPLETED
                    )
                    Log.d("InCallActivity", "✅ Call history saved for both users (duration: ${callDuration}s)")
                }
            } catch (e: Exception) {
                Log.e("InCallActivity", "❌ Failed to save call history: ${e.message}", e)
            }
        }
    }
    
    // Generate guest link for non-app users
    val generateGuestLink: (String) -> Unit = { guestName ->
        scope.launch {
            try {
                guestLinkLoading = true
                
                val currentUser = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser 
                    ?: throw Exception("Not authenticated")
                val roomName = room.name ?: "unknown_room"
                
                // Call Firebase Function to generate guest token
                val functions = com.google.firebase.functions.FirebaseFunctions.getInstance()
                val data = hashMapOf(
                    "roomName" to roomName,
                    "guestName" to guestName
                )
                
                val result = functions
                    .getHttpsCallable("generateGuestToken")
                    .call(data)
                    .await()
                
                val responseData = result.data as Map<*, *>
                val link = responseData["link"] as? String 
                    ?: throw Exception("No link received from server")
                
                Log.d("InCallActivity", "✅ Generated guest link: $link")
                generatedGuestLink = link
                
                android.widget.Toast.makeText(
                    context,
                    "Guest link generated!",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
                
            } catch (e: Exception) {
                Log.e("InCallActivity", "❌ Failed to generate guest link", e)
                android.widget.Toast.makeText(
                    context, 
                    "Failed to generate link: ${e.message}", 
                    android.widget.Toast.LENGTH_LONG
                ).show()
            } finally {
                guestLinkLoading = false
            }
        }
    }
    
    // Get all video tracks from the room (both local and remote)
    val allTracks = rememberTracks()
    
    // Add logging when tracks change
    LaunchedEffect(allTracks.size) {
        Log.d("InCallActivity", "📹 Total tracks changed: ${allTracks.size}")
        allTracks.forEachIndexed { index, (participant, publication) ->
            val isLocal = participant is LocalParticipant
            val participantName = participant.name ?: participant.identity?.value ?: "Unknown"
            val trackKind = publication?.kind?.name ?: "None"
            val trackSource = publication?.source?.name ?: "None"
            Log.d("InCallActivity", "  Track $index: ${if (isLocal) "LOCAL" else "REMOTE"} - $participantName - $trackKind from $trackSource")
        }
    }
    
    // Separate local and remote tracks using rememberTracks (which is already observable)
    val localTrack by remember {
        derivedStateOf {
            val track = allTracks.find { (participant, publication) ->
                participant is LocalParticipant && 
                publication?.source == Track.Source.CAMERA &&
                publication?.kind == Track.Kind.VIDEO
            }?.let { (participant, publication) ->
                publication?.let {
                    io.livekit.android.compose.types.TrackReference(
                        participant = participant,
                        publication = it,
                        source = Track.Source.CAMERA
                    )
                }
            }
            if (track == null) {
                Log.d("InCallActivity", "📷 Local track is NULL - camera icon will show")
            } else {
                Log.d("InCallActivity", "✅ Local track available - camera feed should display")
            }
            track
        }
    }
    
    // Use mutableStateOf instead of derivedStateOf to ensure reactivity
    var remoteTracks by remember { mutableStateOf<List<io.livekit.android.compose.types.TrackReference>>(emptyList()) }
    
    // Track ALL remote participants (even without video) for showing profile pictures
    var allRemoteParticipants by remember { mutableStateOf<List<RemoteParticipant>>(emptyList()) }
    
    // Manually update remoteTracks whenever allTracks changes
    LaunchedEffect(allTracks, room.remoteParticipants) {
        val t0 = System.currentTimeMillis()
        // Update list of ALL remote participants
        allRemoteParticipants = room.remoteParticipants.values.toList()
        
        Log.d("InCallActivity", "🔄 Recalculating remote tracks (allTracks.size=${allTracks.size}, participants=${allRemoteParticipants.size}) t=${t0}")
        
        val filtered = allTracks.filter { (participant, publication) ->
            val isLocal = participant is LocalParticipant
            val isCamera = publication?.source == Track.Source.CAMERA
            val isVideo = publication?.kind == Track.Kind.VIDEO
            val isSubscribed = publication?.subscribed ?: false
            val isMuted = publication?.muted ?: false
            val hasTrack = publication?.track != null
            // Only include active, subscribed remote camera video tracks to avoid showing frozen frames
            val shouldInclude = !isLocal && isCamera && isVideo && isSubscribed && !isMuted && hasTrack
            
            // Debug logging for each track
            Log.d("InCallActivity", "🔍 Filter check: ${participant.identity?.value} - " +
                "isLocal=$isLocal, isCamera=$isCamera, isVideo=$isVideo, subscribed=$isSubscribed, muted=$isMuted, hasTrack=$hasTrack, shouldInclude=$shouldInclude, " +
                "participantClass=${participant::class.simpleName}")
            
            shouldInclude
        }.mapNotNull { (participant, publication) ->
            publication?.let {
                io.livekit.android.compose.types.TrackReference(
                    participant = participant,
                    publication = it,
                    source = Track.Source.CAMERA
                )
            }
        }
        
        remoteTracks = filtered
        
        Log.d("InCallActivity", "✅ Remote tracks updated: ${remoteTracks.size} (dt=${System.currentTimeMillis()-t0}ms)")
        remoteTracks.forEachIndexed { index, trackRef ->
            val participantName = trackRef.participant.name ?: trackRef.participant.identity?.value ?: "Unknown"
            val isSubscribed = trackRef.publication?.subscribed ?: false
            Log.d("InCallActivity", "  Remote track $index: $participantName - Subscribed: $isSubscribed")
        }
    }
    
    // Combined track references for participants list
    val trackReferences by remember {
        derivedStateOf {
            listOfNotNull(localTrack) + remoteTracks
        }
    }
    
    // Calculate focused participant name dynamically based on video swap state
    val focusedParticipantName by remember {
        derivedStateOf {
            if (remoteTracks.isEmpty()) {
                // No remote participants yet, show recipient name
                actualRemoteName ?: recipientName
            } else if (remoteTracks.size >= 2) {
                // Group call: show name based on which remote is focused
                val focusedParticipant = if (isVideoSwapped && remoteTracks.size >= 2) {
                    remoteTracks.getOrNull(1)?.participant
                } else {
                    remoteTracks.first().participant
                }
                focusedParticipant?.name?.takeIf { it.isNotBlank() } 
                    ?: focusedParticipant?.identity?.value 
                    ?: actualRemoteName 
                    ?: recipientName
            } else {
                // 1-on-1 call: show remote name when focused on remote, "You" when focused on local
                if (isVideoSwapped) {
                    "You"
                } else {
                    remoteTracks.firstOrNull()?.participant?.name?.takeIf { it.isNotBlank() }
                        ?: remoteTracks.firstOrNull()?.participant?.identity?.value
                        ?: actualRemoteName 
                        ?: recipientName
                }
            }
        }
    }

    // Timer for call duration
    LaunchedEffect(Unit) {
        // FORCE camera to be enabled at start
        room.localParticipant.setCameraEnabled(true)
        Log.d("InCallActivity", "🎥 FORCED camera enabled at launch")
        
        while (true) {
            kotlinx.coroutines.delay(1000)
            callDuration++
        }
    }

    // Do NOT auto-publish processed track; only when user taps the blur button
    // This avoids startup crashes and ensures default camera is visible immediately
    
    // Fetch actual remote participant name from Firestore when they join
    LaunchedEffect(remoteTracks.size) {
        if (remoteTracks.isNotEmpty() && actualRemoteName == null) {
            val remoteParticipant = remoteTracks.firstOrNull()?.participant
            val remoteUserId = remoteParticipant?.identity?.value
            
            if (remoteUserId != null) {
                try {
                    val firestore = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    firestore.collection("users")
                        .document(remoteUserId)
                        .get()
                        .addOnSuccessListener { document ->
                            if (document.exists()) {
                                val displayName = document.getString("displayName")
                                    ?: document.getString("email")?.substringBefore("@")
                                    ?: "Unknown"
                                actualRemoteName = displayName
                                Log.d("InCallActivity", "✅ Fetched remote participant name: $displayName")
                            }
                        }
                        .addOnFailureListener { e ->
                            Log.e("InCallActivity", "❌ Failed to fetch participant name: ${e.message}")
                        }
                } catch (e: Exception) {
                    Log.e("InCallActivity", "❌ Error fetching participant info: ${e.message}", e)
                }
            }
        }
    }
    
    // ALSO fetch name from allRemoteParticipants (even without video tracks)
    LaunchedEffect(allRemoteParticipants.size) {
        if (allRemoteParticipants.isNotEmpty() && actualRemoteName == null) {
            val remoteParticipant = allRemoteParticipants.firstOrNull()
            val remoteUserId = remoteParticipant?.identity?.value
            
            if (remoteUserId != null) {
                try {
                    val firestore = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    val document = firestore.collection("users")
                        .document(remoteUserId)
                        .get()
                        .await()
                    
                    if (document.exists()) {
                        val displayName = document.getString("displayName")
                            ?: document.getString("email")?.substringBefore("@")
                            ?: "Unknown"
                        actualRemoteName = displayName
                        Log.d("InCallActivity", "✅ Fetched remote participant name from allRemoteParticipants: $displayName")
                    }
                } catch (e: Exception) {
                    Log.e("InCallActivity", "❌ Error fetching participant info: ${e.message}", e)
                }
            }
        }
    }
    
    // Track transition to group call
    LaunchedEffect(remoteTracks.size) {
        if (remoteTracks.size >= 2) everHadMultipleParticipants = true
    }

    // Monitor remote participants - end call if all leave (only for true 1-on-1 sessions)
    LaunchedEffect(remoteTracks.size) {
        // Grace period to stabilize subscriptions
        kotlinx.coroutines.delay(1500)

        val hadRemoteParticipants = remoteTracks.isNotEmpty()
        if (hadRemoteParticipants) {
            Log.d("InCallActivity", "📊 Monitoring remote participants: ${remoteTracks.size}")
        }

        // Only auto-end if this call never became a group call
        if (!hadRemoteParticipants) return@LaunchedEffect

        if (remoteTracks.isEmpty()) {
            // Double-check after debounce to avoid ending during participant handoffs
            kotlinx.coroutines.delay(3000)
            val stillEmpty = room.remoteParticipants.isEmpty()
            val safeToEnd = !everHadMultipleParticipants && stillEmpty
            Log.w(
                "InCallActivity",
                "👋 Remote participants empty (stillEmpty=$stillEmpty, everGroup=$everHadMultipleParticipants)"
            )
            if (safeToEnd) {
                Log.w("InCallActivity", "✅ Ending 1-on-1 call after remote left")
                saveCallHistory()
                onDisconnect()
            } else {
                Log.d("InCallActivity", "Skip auto-end (group or transient state)")
            }
        }
    }

    // Debug logging
    LaunchedEffect(localTrack, remoteTracks.size) {
        Log.d("InCallActivity", "=== Track Debug ===")
        Log.d("InCallActivity", "Camera enabled: ${room.localParticipant.isCameraEnabled}")
        Log.d("InCallActivity", "All tracks count: ${allTracks.size}")
        Log.d("InCallActivity", "Local track: ${if (localTrack != null) "EXISTS" else "NULL"}")
        Log.d("InCallActivity", "Remote tracks: ${remoteTracks.size}")
        if (localTrack != null) {
            Log.d("InCallActivity", "Local track publication: ${localTrack?.publication}")
            Log.d("InCallActivity", "Local track has video: ${localTrack?.publication?.track != null}")
        } else {
            Log.w("InCallActivity", "⚠️ PiP will NOT show - localTrack is NULL")
        }
        Log.d("InCallActivity", "==================")
    }

    // Simple timing log: first time we see any remote video track
    LaunchedEffect(remoteTracks.size) {
        if (remoteTracks.size == 1) {
            Log.d("InCallActivity", "⏱️ SUBSCRIBE_FIRST_REMOTE detected; remoteTracks=${remoteTracks.size}")
        }
    }
    
    // ===== NETWORK QUALITY & RECONNECTION STATE =====
    val connectionQuality by LiveKitManager.connectionQuality.collectAsState()
    val reconnectionState by LiveKitManager.reconnectionState.collectAsState()
    
    // OUTER Box to contain everything including PiP overlay
    Box(modifier = Modifier.fillMaxSize()) {
        // INNER Box for main video and controls
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black) // Pure black for video background
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = {
                            showControls = !showControls
                            showMenu = false
                        },
                        onDoubleTap = {
                            // Double-tap toggles top-left quick toggles (aspect/blur)
                            showTopLeftQuickToggles = !showTopLeftQuickToggles
                        }
                    )
                }
        ) {
    // Main video area - show remote or local based on swap state
        if (remoteTracks.isNotEmpty()) {
            val isGroupCall = remoteTracks.size >= 2
            val mainTrack = if (isGroupCall) {
                // Group call: main view shows first or second remote based on swap
                if (isVideoSwapped && remoteTracks.size >= 2) {
                    remoteTracks.getOrNull(1) ?: remoteTracks.first()
                } else {
                    remoteTracks.first()
                }
            } else {
                // 1-on-1: main view shows remote or local based on swap
                if (isVideoSwapped) {
                    localTrack ?: remoteTracks.first()
                } else {
                    remoteTracks.first()
                }
            }
            
            // Pinch-to-zoom gesture state - OPTIMIZED to reduce recompositions
            val transformableState = rememberTransformableState { zoomChange, offsetChange, _ ->
                scope.launch {
                    // Use snapTo for immediate updates without triggering full recomposition
                    val newScale = (videoScale.value * zoomChange).coerceIn(1f, 4f)
                    videoScale.snapTo(newScale)
                    
                    if (newScale > 1f) {
                        val newOffsetX = (videoOffsetX.value + offsetChange.x).coerceIn(-500f, 500f)
                        val newOffsetY = (videoOffsetY.value + offsetChange.y).coerceIn(-800f, 800f)
                        videoOffsetX.snapTo(newOffsetX)
                        videoOffsetY.snapTo(newOffsetY)
                    } else {
                        // Reset offsets when zoomed out completely
                        videoOffsetX.snapTo(0f)
                        videoOffsetY.snapTo(0f)
                    }
                }
            }
            
            // Portrait mode: optimize aspect ratio for vertical screen
            val videoModifier = if (!isLandscape && portraitAspectRatioMode) {
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(9f / 16f) // Portrait aspect ratio
                    .align(Alignment.Center)
            } else {
                Modifier.fillMaxSize()
            }
            
            CallVideoTrackView(
                trackReference = mainTrack,
                modifier = videoModifier
                    .transformable(state = transformableState)
                    .graphicsLayer(
                        scaleX = videoScale.value,
                        scaleY = videoScale.value,
                        translationX = videoOffsetX.value,
                        translationY = videoOffsetY.value
                    )
            )
        } else if (allRemoteParticipants.isNotEmpty()) {
            // Remote participant connected but camera is OFF - show profile picture/initial
            val firstParticipant = allRemoteParticipants.first()
            val participantName = firstParticipant.name ?: firstParticipant.identity?.value ?: "Guest"
            val initials = participantName.split(" ").mapNotNull { it.firstOrNull()?.uppercase() }.take(2).joinToString("")
            
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                // Profile picture/initials
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                        .background(AppColors.PrimaryBlue),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = initials.ifEmpty { participantName.firstOrNull()?.uppercase() ?: "?" },
                        fontSize = 48.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
                
                // "Camera Off" indicator below avatar
                Text(
                    text = "Camera Off",
                    fontSize = 16.sp,
                    color = Color.White.copy(alpha = 0.7f),
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(top = 180.dp)
                )
            }
        } else {
            // No remote participants yet - show "Calling..." placeholder
            // Local feed will be shown in PiP, not main view
            // No participants yet - Connecting placeholder with animation under avatar
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    // Recipient avatar/initial
                    val displayName = actualRemoteName ?: recipientName
                    Box(
                        modifier = Modifier
                            .size(120.dp)
                            .clip(CircleShape)
                            .background(AppColors.PrimaryBlue),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = displayName.firstOrNull()?.uppercase() ?: "?",
                            fontSize = 48.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = AppColors.PrimaryBlue,
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(text = "Connecting…", color = Color.White.copy(alpha = 0.85f), fontSize = 14.sp)
                    }
                }
            }
        }
        
        // Mic permission banner (top)
        AnimatedVisibility(
            visible = !micPermissionGranted.value,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 28.dp)
        ) {
            Surface(
                color = Color(0xFFB71C1C),
                shape = RoundedCornerShape(corner = CornerSize(12.dp))
            ) {
                Row(
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.MicOff,
                        contentDescription = null,
                        tint = Color.White
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Microphone blocked",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "The other person can’t hear you. Allow mic access.",
                            color = Color.White.copy(alpha = 0.9f),
                            fontSize = 12.sp
                        )
                    }
                    TextButton(onClick = {
                        // Request RECORD_AUDIO at runtime
                        requestMicPermission.launch(Manifest.permission.RECORD_AUDIO)
                    }) {
                        Text("Allow", color = Color.White)
                    }
                    TextButton(onClick = {
                        val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", context.packageName, null)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                    }) {
                        Text("Settings", color = Color.White)
                    }
                }
            }
        }

        // Top info bar - with padding to avoid status bar overlap
        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 24.dp, end = 24.dp, top = 48.dp, bottom = 24.dp) // Extra top padding for status bar
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = focusedParticipantName,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                    style = androidx.compose.ui.text.TextStyle(
                        shadow = Shadow(
                            color = Color.Black.copy(alpha = 0.8f),
                            offset = Offset(2f, 2f),
                            blurRadius = 4f
                        )
                    )
                )
                // Quality dot next to name (always visible)
                val qualityColor = when (connectionQuality) {
                    io.livekit.android.room.participant.ConnectionQuality.EXCELLENT -> Color(0xFF22C55E)
                    io.livekit.android.room.participant.ConnectionQuality.GOOD -> Color(0xFFEAB308)
                    io.livekit.android.room.participant.ConnectionQuality.POOR -> Color(0xFFEF4444)
                    else -> Color.Gray
                }
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(qualityColor)
                        .shadow(4.dp, CircleShape)
                )
            }
            Text(
                text = formatDuration(callDuration),
                fontSize = 14.sp,
                color = Color.White.copy(alpha = 0.9f),
                style = androidx.compose.ui.text.TextStyle(
                    shadow = Shadow(
                        color = Color.Black.copy(alpha = 0.8f),
                        offset = Offset(2f, 2f),
                        blurRadius = 4f
                    )
                )
            )
        }
        
        // PiP is now OUTSIDE this inner box as an overlay
        
        // Control buttons with adaptive layout
        // Portrait: Bottom center with slide-up animation
        // Landscape: Left side rail with cascading slide-up animation (smaller, bottom-left with notch padding)
        if (isLandscape) {
            // LANDSCAPE MODE: Side Rail (Left Edge, Lower Position, 30% Smaller, Notch-Safe)
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 48.dp, bottom = 32.dp), // Extra left padding for camera notch/hole
                verticalArrangement = Arrangement.spacedBy(8.dp), // Reduced spacing
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Menu button (30% smaller: 56dp -> 39dp)
                val menuAnim = rememberAnimatedButtonSpring(showControls, 0)
                
                IconButton(
                    onClick = { showMenu = !showMenu },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = menuAnim.offsetX)
                        .graphicsLayer(
                            alpha = menuAnim.alpha,
                            scaleX = menuAnim.scale,
                            scaleY = menuAnim.scale
                        )
                        .background(AppColors.Gray.copy(alpha = 0.3f), CircleShape)
                ) {
                    Icon(
                        imageVector = Icons.Default.MoreVert,
                        contentDescription = "Menu",
                        tint = Color.White,
                        modifier = Modifier.size(17.dp)
                    )
                }
                
                // Mic toggle (30% smaller)
                val micAnim = rememberAnimatedButtonSpring(showControls, 1)
                var lastMicToggle by remember { mutableLongStateOf(0L) }

                IconButton(
                    onClick = {
                        val now = System.currentTimeMillis()
                        if (now - lastMicToggle < 300) return@IconButton // Debounce 300ms
                        lastMicToggle = now
                        
                        val newState = !isMicEnabled
                        isMicEnabled = newState // Update UI immediately
                        scope.launch(Dispatchers.Default) {
                            room.localParticipant.setMicrophoneEnabled(newState)
                        }
                    },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = micAnim.offsetX)
                        .graphicsLayer(
                            alpha = micAnim.alpha,
                            scaleX = micAnim.scale,
                            scaleY = micAnim.scale
                        )
                        .background(
                            if (isMicEnabled) AppColors.Gray.copy(alpha = 0.3f) else Color(0xFFE53935),
                            CircleShape
                        )
                ) {
                    Icon(
                        imageVector = if (isMicEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                        contentDescription = "Toggle Microphone",
                        tint = Color.White,
                        modifier = Modifier.size(17.dp)
                    )
                }
                
                // End call - Modern flat design (30% smaller: 56dp -> 39dp, keep red)
                val endCallAnim = rememberAnimatedButtonSpring(showControls, 2)
                var lastEndCallClick by remember { mutableLongStateOf(0L) }
                
                IconButton(
                    onClick = {
                        val now = System.currentTimeMillis()
                        if (now - lastEndCallClick < 1000) return@IconButton // Prevent double-tap
                        lastEndCallClick = now
                        
                        // Save history in background, don't block disconnect
                        scope.launch(Dispatchers.IO) {
                            try { saveCallHistory() } catch (e: Exception) {
                                Log.e("InCallActivity", "Error saving call history: ${e.message}")
                            }
                        }
                        onDisconnect()
                    },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = endCallAnim.offsetX)
                        .graphicsLayer(
                            alpha = endCallAnim.alpha,
                            scaleX = endCallAnim.scale,
                            scaleY = endCallAnim.scale
                        )
                        .background(
                            Color(0xFFE53935),
                            shape = CircleShape
                        )
                ) {
                    Icon(
                        imageVector = Icons.Default.CallEnd,
                        contentDescription = "End Call",
                        tint = Color.White,
                        modifier = Modifier.size(17.dp)
                    )
                }
                
                // Switch Camera button (landscape only, 30% smaller)
                val cameraAnim = rememberAnimatedButtonSpring(showControls, 3)
                var lastCameraToggle by remember { mutableLongStateOf(0L) }
                
                IconButton(
                    onClick = {
                        val now = System.currentTimeMillis()
                        if (now - lastCameraToggle < 500) return@IconButton // Debounce 500ms
                        lastCameraToggle = now
                        
                        scope.launch(Dispatchers.Default) {
                            try {
                                // If processed track is active, republish with flipped facing
                                if (LiveKitManager.isProcessedCameraActive()) {
                                    // Toggle facing by unpublishing and republishing processed track
                                    // Track front/back locally
                                    isFrontCamera = !isFrontCamera
                                    val ok = LiveKitManager.unpublishProcessedCameraTrackAndRestoreDefault()
                                    if (ok) {
                                        LiveKitManager.publishProcessedCameraTrack(context, useFront = isFrontCamera)
                                    }
                                } else {
                                    val cameraTrack = room.localParticipant.getTrackPublication(io.livekit.android.room.track.Track.Source.CAMERA)
                                        ?.track as? LocalVideoTrack
                                    cameraTrack?.switchCamera(null, null)
                                }
                            } catch (e: Exception) {
                                Log.e("InCallActivity", "Failed to switch camera", e)
                            }
                        }
                    },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = cameraAnim.offsetX)
                        .graphicsLayer(
                            alpha = cameraAnim.alpha,
                            scaleX = cameraAnim.scale,
                            scaleY = cameraAnim.scale
                        )
                        .background(AppColors.Gray.copy(alpha = 0.3f), CircleShape)
                ) {
                    Icon(
                        imageVector = Icons.Default.Cameraswitch,
                        contentDescription = "Switch Camera",
                        tint = Color.White,
                        modifier = Modifier.size(17.dp)
                    )
                }
                
                // Add Person button (30% smaller)
                val addPersonAnim = rememberAnimatedButtonSpring(showControls, 4)
                
                IconButton(
                    onClick = { showAddPersonDialog = true },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = addPersonAnim.offsetX)
                        .graphicsLayer(
                            alpha = addPersonAnim.alpha,
                            scaleX = addPersonAnim.scale,
                            scaleY = addPersonAnim.scale
                        )
                        .background(AppColors.Gray.copy(alpha = 0.3f), CircleShape)
                ) {
                    Icon(
                        imageVector = Icons.Default.PersonAdd,
                        contentDescription = "Add Person",
                        tint = Color.White,
                        modifier = Modifier.size(17.dp)
                    )
                }
                
                // Audio-only Mode toggle (30% smaller)
                val audioOnlyAnim = rememberAnimatedButtonSpring(showControls, 5)
                var lastAudioOnlyToggle by remember { mutableLongStateOf(0L) }
                
                IconButton(
                    onClick = {
                        val now = System.currentTimeMillis()
                        if (now - lastAudioOnlyToggle < 500) return@IconButton // Debounce 500ms
                        lastAudioOnlyToggle = now
                        
                        val newState = !isAudioOnlyMode
                        isAudioOnlyMode = newState
                        scope.launch(Dispatchers.Default) {
                            try {
                                // Disable camera when entering audio-only, enable when exiting
                                room.localParticipant.setCameraEnabled(!newState)
                                withContext(Dispatchers.Main) { isCameraEnabled = !newState }
                            } catch (e: Exception) {
                                Log.e("InCallActivity", "Failed to toggle audio-only mode", e)
                            }
                        }
                    },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = audioOnlyAnim.offsetX)
                        .graphicsLayer(
                            alpha = audioOnlyAnim.alpha,
                            scaleX = audioOnlyAnim.scale,
                            scaleY = audioOnlyAnim.scale
                        )
                        .background(
                            if (isAudioOnlyMode) AppColors.PrimaryBlue else AppColors.Gray.copy(alpha = 0.3f),
                            CircleShape
                        )
                ) {
                    Icon(
                        imageVector = if (isAudioOnlyMode) Icons.Default.Videocam else Icons.Default.VideocamOff,
                        contentDescription = "Toggle Audio-only Mode",
                        tint = Color.White,
                        modifier = Modifier.size(17.dp)
                    )
                }
            }
        } else {
            // PORTRAIT MODE: Bottom Center (Original)
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 80.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
            // Menu button (animates first)
            val menuAnim = rememberAnimatedButton(showControls, 0)
            
            IconButton(
                onClick = { showMenu = !showMenu },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = menuAnim.offsetY)
                    .graphicsLayer(alpha = menuAnim.alpha)
                    .background(AppColors.Gray.copy(alpha = 0.3f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.MoreVert,
                    contentDescription = "Menu",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }
            
            // Mic toggle (animates second)
            val micAnim = rememberAnimatedButton(showControls, 1)
            var lastMicTogglePortrait by remember { mutableLongStateOf(0L) }

            IconButton(
                onClick = {
                    val now = System.currentTimeMillis()
                    if (now - lastMicTogglePortrait < 300) return@IconButton // Debounce 300ms
                    lastMicTogglePortrait = now
                    
                    val newState = !isMicEnabled
                    isMicEnabled = newState // Update UI immediately
                    scope.launch(Dispatchers.Default) {
                        room.localParticipant.setMicrophoneEnabled(newState)
                    }
                },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = micAnim.offsetY)
                    .graphicsLayer(alpha = micAnim.alpha)
                    .background(
                        if (isMicEnabled) AppColors.Gray.copy(alpha = 0.3f) else Color(0xFFE53935),
                        CircleShape
                    )
            ) {
                Icon(
                    imageVector = if (isMicEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                    contentDescription = "Toggle Microphone",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }
            
            // End call (animates third - center) - Modern flat design
            val endCallAnim = rememberAnimatedButton(showControls, 2)
            var lastEndCallClickPortrait by remember { mutableLongStateOf(0L) }
            
            IconButton(
                onClick = {
                    val now = System.currentTimeMillis()
                    if (now - lastEndCallClickPortrait < 1000) return@IconButton // Prevent double-tap
                    lastEndCallClickPortrait = now
                    
                    // Save history and cleanup in background
                    scope.launch(Dispatchers.IO) {
                        try {
                            saveCallHistory()
                            withContext(Dispatchers.Default) {
                                try { LiveKitManager.unpublishProcessedCameraTrackAndRestoreDefault() } catch (_: Exception) {}
                                try { room.localParticipant.setCameraEnabled(false) } catch (_: Exception) {}
                                try { room.localParticipant.setMicrophoneEnabled(false) } catch (_: Exception) {}
                            }
                        } catch (e: Exception) {
                            Log.e("InCallActivity", "Error during cleanup: ${e.message}")
                        }
                    }
                    onDisconnect()
                },
                modifier = Modifier
                    .size(70.dp)
                    .offset(y = endCallAnim.offsetY)
                    .graphicsLayer(alpha = endCallAnim.alpha)
                    .background(
                        Color(0xFFE53935),
                        shape = CircleShape
                    )
            ) {
                Icon(
                    imageVector = Icons.Default.CallEnd,
                    contentDescription = "End Call",
                    tint = Color.White,
                    modifier = Modifier.size(30.dp)
                )
            }
            
            // Switch camera (animates fourth)
            val switchCamAnim = rememberAnimatedButton(showControls, 3)
            var lastCameraSwitchPortrait by remember { mutableLongStateOf(0L) }

            IconButton(
                onClick = {
                    val now = System.currentTimeMillis()
                    if (now - lastCameraSwitchPortrait < 500) return@IconButton // Debounce 500ms
                    lastCameraSwitchPortrait = now
                    
                    scope.launch(Dispatchers.Default) {
                        try {
                            val publication = room.localParticipant
                                .getTrackPublication(Track.Source.CAMERA) as? LocalTrackPublication
                            val localVideoTrack = publication?.track as? LocalVideoTrack

                            if (!room.localParticipant.isCameraEnabled) {
                                Log.d("InCallActivity", "📷 Camera disabled, re-enabling before switch")
                                val enabled = room.localParticipant.setCameraEnabled(true)
                                withContext(Dispatchers.Main) { isCameraEnabled = enabled }
                            }

                            if (localVideoTrack != null) {
                                Log.d("InCallActivity", "🔁 Switching camera source")
                                localVideoTrack.switchCamera(null, null)
                                withContext(Dispatchers.Main) {
                                    isCameraEnabled = room.localParticipant.isCameraEnabled
                                }
                            } else {
                                Log.w("InCallActivity", "⚠️ No LocalVideoTrack available, toggling camera state instead")
                                val enabled = room.localParticipant.setCameraEnabled(!room.localParticipant.isCameraEnabled)
                                withContext(Dispatchers.Main) { isCameraEnabled = enabled }
                            }
                        } catch (e: Exception) {
                            Log.e("InCallActivity", "Error switching camera", e)
                            withContext(Dispatchers.Main) {
                                Toast.makeText(context, "Camera switch failed: ${e.message}", Toast.LENGTH_SHORT).show()
                            }
                        }
                    }
                },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = switchCamAnim.offsetY)
                    .graphicsLayer(alpha = switchCamAnim.alpha)
                    .background(AppColors.Gray.copy(alpha = 0.3f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.Cameraswitch,
                    contentDescription = "Switch Camera",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }
            
            // Add person (animates fifth)
            val addPersonAnim = rememberAnimatedButton(showControls, 4)

            IconButton(
                onClick = {
                    showAddPersonDialog = true
                },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = addPersonAnim.offsetY)
                    .graphicsLayer(alpha = addPersonAnim.alpha)
                    .background(AppColors.Gray.copy(alpha = 0.3f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.PersonAdd,
                    contentDescription = "Add Person",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }
            
            // Audio-only Mode toggle (animates sixth)
            val audioOnlyAnim = rememberAnimatedButton(showControls, 5)
            var lastAudioOnlyTogglePortrait by remember { mutableLongStateOf(0L) }
            
            IconButton(
                onClick = {
                    val now = System.currentTimeMillis()
                    if (now - lastAudioOnlyTogglePortrait < 500) return@IconButton // Debounce 500ms
                    lastAudioOnlyTogglePortrait = now
                    
                    val newState = !isAudioOnlyMode
                    isAudioOnlyMode = newState
                    scope.launch(Dispatchers.Default) {
                        try {
                            // Disable camera when entering audio-only, enable when exiting
                            room.localParticipant.setCameraEnabled(!newState)
                            withContext(Dispatchers.Main) { isCameraEnabled = !newState }
                        } catch (e: Exception) {
                            Log.e("InCallActivity", "Failed to toggle audio-only mode", e)
                        }
                    }
                },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = audioOnlyAnim.offsetY)
                    .graphicsLayer(alpha = audioOnlyAnim.alpha)
                    .background(
                        if (isAudioOnlyMode) AppColors.PrimaryBlue else AppColors.Gray.copy(alpha = 0.3f),
                        CircleShape
                    )
            ) {
                Icon(
                    imageVector = if (isAudioOnlyMode) Icons.Default.Videocam else Icons.Default.VideocamOff,
                    contentDescription = "Toggle Audio-only Mode",
                    tint = Color.White,
                    modifier = Modifier.size(24.dp)
                )
            }
        } // End of portrait/landscape conditional
        
        // Portrait Mode Enhancements - move to Top LEFT to avoid overlapping PiP
        if (!isLandscape) {
            AnimatedVisibility(
                visible = showTopLeftQuickToggles,
                enter = slideInVertically(initialOffsetY = { full -> -full }) + fadeIn(),
                exit = slideOutVertically(targetOffsetY = { full -> -full }) + fadeOut(),
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 120.dp)
            ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Local context for Compose scope
                val context = androidx.compose.ui.platform.LocalContext.current
                // Removed aspect ratio toggle per request (fullscreen is default)
                
                // ENHANCEMENT: Background Blur Toggle (Portrait Mode like FaceTime!)
                // Only show on devices with 3GB+ RAM to prevent crashes
                val supportsAdvancedFeatures = remember(context) {
                    try {
                        LiveKitManager.supportsAdvancedFeatures(context)
                    } catch (e: Exception) {
                        Log.e("InCallActivity", "⚠️ Error checking device capabilities: ${e.message}", e)
                        false
                    }
                }
                
                if (supportsAdvancedFeatures && FeatureFlags.isBackgroundBlurEnabled()) {
                    // Background Blur toggle (processed camera track publish/unpublish)
                    val isBlurActive = remember { mutableStateOf(LiveKitManager.isProcessedCameraActive()) }
                    var isTogglingBlur by remember { mutableStateOf(false) }
                    var lastBlurToggle by remember { mutableLongStateOf(0L) }

                    IconButton(
                        onClick = {
                            val now = System.currentTimeMillis()
                            if (now - lastBlurToggle < 500 || isTogglingBlur) return@IconButton // Debounce 500ms
                            lastBlurToggle = now
                            
                            scope.launch {
                                isTogglingBlur = true
                                try {
                                    if (!room.localParticipant.isCameraEnabled) {
                                        room.localParticipant.setCameraEnabled(true)
                                    }
                                    if (!LiveKitManager.isProcessedCameraActive()) {
                                        val ok = withContext(Dispatchers.Default) {
                                            LiveKitManager.publishProcessedCameraTrack(context)
                                        }
                                        isBlurActive.value = ok
                                        if (!ok) Log.w("InCallActivity", "Processed track publish returned false")
                                    } else {
                                        val ok = withContext(Dispatchers.Default) {
                                            LiveKitManager.unpublishProcessedCameraTrackAndRestoreDefault()
                                        }
                                        isBlurActive.value = !ok
                                        if (!ok) Log.w("InCallActivity", "Unpublish processed track failed")
                                    }
                                } catch (e: Exception) {
                                    Log.e("InCallActivity", "Failed to toggle blur: ${e.message}", e)
                                    try {
                                        if (LiveKitManager.isProcessedCameraActive()) {
                                            LiveKitManager.unpublishProcessedCameraTrackAndRestoreDefault()
                                            isBlurActive.value = false
                                        }
                                    } catch (_: Exception) {}
                                } finally {
                                    isTogglingBlur = false
                                }
                            }
                        },
                        modifier = Modifier
                            .size(48.dp)
                            .background(
                                if (LiveKitManager.isProcessedCameraActive()) AppColors.PrimaryBlue.copy(alpha = 0.6f) else AppColors.Gray.copy(alpha = 0.35f),
                                CircleShape
                            )
                    ) {
                        Icon(
                            imageVector = Icons.Default.BlurOn,
                            contentDescription = "Toggle Portrait Mode",
                            tint = Color.White,
                            modifier = Modifier.size(22.dp)
                        )
                    }
                }
                
                // Zoom Reset Button (shows when zoomed)
                if (videoScale.value > 1.1f) {
                    IconButton(
                        onClick = {
                            scope.launch {
                                videoScale.snapTo(1f)
                                videoOffsetX.snapTo(0f)
                                videoOffsetY.snapTo(0f)
                            }
                        },
                        modifier = Modifier
                            .size(48.dp)
                            .background(AppColors.PrimaryBlue.copy(alpha = 0.6f), CircleShape)
                    ) {
                        Icon(
                            imageVector = Icons.Default.ZoomOut,
                            contentDescription = "Reset zoom",
                            tint = Color.White,
                            modifier = Modifier.size(22.dp)
                        )
                    }
                }
                
                // Zoom indicator (shows current zoom level when > 1x)
                if (videoScale.value > 1.1f) {
                    Surface(
                        shape = RoundedCornerShape(16.dp),
                        color = Color.Black.copy(alpha = 0.6f),
                        modifier = Modifier.padding(horizontal = 4.dp)
                    ) {
                        Text(
                            text = "${String.format(java.util.Locale.US, "%.1f", videoScale.value)}x",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                }
            }
            }
        }
        
        // Menu dropdown - positioned above menu button (portrait) or to right of buttons (landscape)
        if (showMenu) {
            Box(
                modifier = Modifier
                    .align(if (isLandscape) Alignment.BottomStart else Alignment.BottomStart)
                    .padding(
                        start = if (isLandscape) 72.dp else 32.dp,
                        end = if (isLandscape) 0.dp else 0.dp,
                        bottom = if (isLandscape) 40.dp else 160.dp
                    )
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.White.copy(alpha = 0.2f))
                    .padding(8.dp)
            ) {
                Column {
                    TextButton(
                        onClick = {
                            showMenu = false
                            showParticipantsList = true
                            Log.d("InCallActivity", "Participants clicked")
                        }
                    ) {
                        Icon(
                            Icons.Default.People,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Participants", color = Color.White)
                    }
                    
                    TextButton(
                        onClick = {
                            showMenu = false
                            isScreenSharing = !isScreenSharing
                            scope.launch {
                                try {
                                    if (isScreenSharing) {
                                        // Request screen capture permission
                                        Log.d("InCallActivity", "🖥️ Requesting screen capture permission")
                                        // Use the Compose-provided context to access system services
                                        val projectionManager = context.getSystemService(MediaProjectionManager::class.java)
                                        // Launch the permission request via the activity's result handler
                                        (context as? InCallActivity)?.screenCaptureRequest?.launch(projectionManager.createScreenCaptureIntent())
                                    } else {
                                        // Stop screen sharing
                                        Log.d("InCallActivity", "🖥️ Stopping screen share")
                                        room.localParticipant.setScreenShareEnabled(false)
                                        Log.d("InCallActivity", "✅ Screen sharing stopped")
                                        Toast.makeText(
                                            context,
                                            "Screen sharing stopped",
                                            Toast.LENGTH_SHORT
                                        ).show()
                                    }
                                } catch (e: Exception) {
                                    Log.e("InCallActivity", "❌ Error toggling screen share: ${e.message}", e)
                                    Toast.makeText(
                                        context,
                                        "Screen sharing failed: ${e.message}",
                                        Toast.LENGTH_LONG
                                    ).show()
                                    isScreenSharing = !isScreenSharing // Revert on error
                                }
                            }
                        }
                    ) {
                        Icon(
                            Icons.Default.ScreenShare,
                            contentDescription = null,
                            tint = if (isScreenSharing) Color.Green else Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = if (isScreenSharing) "Stop Sharing" else "Share Screen",
                            color = Color.White
                        )
                    }

                    // Toggle Performance Overlay (developer)
                    TextButton(
                        onClick = {
                            showMenu = false
                            val newVal = !showPerfOverlay
                            showPerfOverlay = newVal
                            // Persist via FeatureFlags
                            FeatureFlags.setPerformanceOverlayEnabled(newVal)
                            // Mirror to settings prefs for SettingsActivity consistency
                            context.getSharedPreferences("settings", android.content.Context.MODE_PRIVATE)
                                .edit().putBoolean("show_performance_overlay", newVal).apply()
                        }
                    ) {
                        Icon(
                            Icons.Default.Info,
                            contentDescription = null,
                            tint = if (showPerfOverlay) Color.Green else Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = if (showPerfOverlay) "Hide Call Health" else "Show Call Health",
                            color = Color.White
                        )
                    }
                }
            }
        }
        
        // Participants list dialog
        if (showParticipantsList) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.7f))
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onTap = {
                                showParticipantsList = false
                            }
                        )
                    },
                contentAlignment = Alignment.Center
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth(0.85f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(AppColors.BackgroundDark)
                        .padding(24.dp)
                        .pointerInput(Unit) {
                            detectTapGestures(
                                onTap = { /* Consume tap to prevent closing */ }
                            )
                        }
                ) {
                    // Header
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Participants (${trackReferences.size})",
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        IconButton(onClick = { showParticipantsList = false }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Close",
                                tint = Color.White
                            )
                        }
                    }
                    
                    Spacer(modifier = Modifier.height(16.dp))
                    
                    // Participants list
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        items(trackReferences.size) { index ->
                            val trackRef = trackReferences[index]
                            ParticipantItem(
                                trackReference = trackRef,
                                isLocal = trackRef.participant.sid?.value == room.localParticipant.sid?.value
                            )
                        }
                    }
                }
            }
        }
        
        // Add Person Dialog
        if (showAddPersonDialog) {
            AddPersonDialog(
                onDismiss = { 
                    showAddPersonDialog = false
                    generatedGuestLink = ""
                    guestLinkLoading = false
                },
                onGenerateGuestLink = generateGuestLink,
                generatedLink = generatedGuestLink,
                isLinkLoading = guestLinkLoading,
                onInvite = { contactInput ->
                    Log.d("InCallActivity", "===== INVITE CALLBACK TRIGGERED =====")
                    Log.d("InCallActivity", "Contact input received: '$contactInput'")
                    
                    // Send invitation via Firestore
                    val currentUser = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
                    val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    
                    Log.d("InCallActivity", "Current user: ${currentUser?.email}")
                    
                    if (currentUser != null) {
                        Log.d("InCallActivity", "Searching for user: $contactInput")
                        
                        // Search by email, phone, or username
                        val searchQueries = listOf(
                            db.collection("users").whereEqualTo("email", contactInput),
                            db.collection("users").whereEqualTo("phoneNumber", contactInput),
                            db.collection("users").whereEqualTo("username", contactInput)
                        )
                        
                        var userFound = false
                        
                        fun tryNextQuery(index: Int) {
                            Log.d("InCallActivity", "Trying query $index of ${searchQueries.size}")
                            
                            if (index >= searchQueries.size) {
                                if (!userFound) {
                                    Log.w("InCallActivity", "User not found: $contactInput")
                                    android.widget.Toast.makeText(
                                        context,
                                        "User not found: $contactInput",
                                        android.widget.Toast.LENGTH_SHORT
                                    ).show()
                                }
                                return
                            }
                            
                            searchQueries[index].get()
                                .addOnSuccessListener { documents ->
                                    if (!documents.isEmpty && !userFound) {
                                        userFound = true
                                        val inviteeId = documents.documents[0].id
                                        
                                        Log.d("InCallActivity", "User found: $inviteeId, sending invite...")
                                        
                                        // Send call invitation
                                        val inviteData = hashMapOf(
                                            "type" to "call_invite",
                                            "fromUserId" to currentUser.uid,
                                            "fromUserName" to (currentUser.displayName ?: currentUser.email),
                                            "roomName" to room.name,
                                            "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                                        )
                                        
                                        db.collection("users")
                                            .document(inviteeId)
                                            .collection("callSignals")
                                            .add(inviteData)
                                            .addOnSuccessListener {
                                                Log.d("InCallActivity", "Invite sent successfully to: $contactInput")
                                                android.widget.Toast.makeText(
                                                    context,
                                                    "Invitation sent!",
                                                    android.widget.Toast.LENGTH_SHORT
                                                ).show()
                                                showAddPersonDialog = false
                                            }
                                            .addOnFailureListener { e ->
                                                Log.e("InCallActivity", "Error sending invite", e)
                                                android.widget.Toast.makeText(
                                                    context,
                                                    "Failed to send invite: ${e.message}",
                                                    android.widget.Toast.LENGTH_SHORT
                                                ).show()
                                            }
                                    } else {
                                        tryNextQuery(index + 1)
                                    }
                                }
                                .addOnFailureListener { e ->
                                    Log.e("InCallActivity", "Error searching for user", e)
                                    tryNextQuery(index + 1)
                                }
                        }
                        
                        tryNextQuery(0)
                    } else {
                        Log.e("InCallActivity", "Current user is null")
                        android.widget.Toast.makeText(
                            context,
                            "Error: Not authenticated",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            )
        }
    } // End of INNER Box (main video + controls)
    
    // Top-Right PiP Box - Picture-in-picture overlay
    // In 1-on-1: Shows local feed (swappable with main)
    // In group call (2+ remote): Shows second remote participant (swappable with main)
    // Tap = enlarge/shrink, Long press = swap feeds
    // Auto-adjusts aspect ratio based on device orientation
    val isGroupCall = remoteTracks.size >= 2
    // Allow dragging the PiP box around the screen
    var pipOffset by remember { mutableStateOf(Offset(0f, 0f)) }
    
    Box(
            modifier = Modifier
            .align(Alignment.TopEnd)
            .zIndex(999f)
            .padding(top = 56.dp, end = 16.dp) // Extra top padding to avoid status bar
            .offset { androidx.compose.ui.unit.IntOffset(pipOffset.x.roundToInt(), pipOffset.y.roundToInt()) }
            .size(
                width = if (isLandscape) {
                    if (isLocalVideoEnlarged) 280.dp else 160.dp
                } else {
                    if (isLocalVideoEnlarged) 200.dp else 120.dp
                },
                height = if (isLandscape) {
                    if (isLocalVideoEnlarged) 160.dp else 90.dp
                } else {
                    if (isLocalVideoEnlarged) 300.dp else 200.dp
                }
            )
            .border(
                width = 2.dp, 
                color = if (isVideoSwapped) AppColors.PrimaryBlue else Color.White.copy(alpha = 0.5f),
                shape = RoundedCornerShape(12.dp)
            )
            .clip(RoundedCornerShape(12.dp))
                .background(Color.Black.copy(alpha = 0.25f))
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { 
                        // Quick tap = enlarge/shrink
                        isLocalVideoEnlarged = !isLocalVideoEnlarged
                        showControls = true
                    },
                    onLongPress = {
                        // Long press = swap main and PiP feeds
                        if (remoteTracks.isNotEmpty()) {
                            isVideoSwapped = !isVideoSwapped
                            showControls = true
                            Log.d("InCallActivity", "📺 Video feeds swapped: $isVideoSwapped")
                        }
                    }
                )
            }
            .pointerInput(Unit) {
                detectDragGestures(
                    onDrag = { change, dragAmount ->
                        change.consumeAllChanges()
                        pipOffset = pipOffset + dragAmount
                    }
                )
            }
    ) {
        // In group call: show second remote participant
        // In 1-on-1: show local or remote based on swap state
        if (remoteTracks.isNotEmpty()) {
            val pipTrack = if (isGroupCall) {
                // Group call: top-right PiP always shows second remote participant
                if (isVideoSwapped && remoteTracks.size >= 2) {
                    remoteTracks.first() // When swapped, second remote moves to main, so show first remote
                } else {
                    remoteTracks.getOrNull(1) ?: remoteTracks.first()
                }
            } else {
                // 1-on-1: show local or remote based on swap
                if (isVideoSwapped) {
                    remoteTracks.first()
                } else {
                    localTrack
                }
            }
            
            pipTrack?.let {
                CallVideoTrackView(
                    trackReference = it,
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(12.dp)), // Ensure video fills and clips to rounded corners
                    isOverlay = true
                )
            } ?: run {
                // Fallback placeholder if no track resolved (e.g., local not ready yet)
                Box(
                    modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(text = "You", color = Color.White.copy(alpha = 0.9f), fontWeight = FontWeight.SemiBold)
                }
            }
        } else if (localTrack != null) {
            // No remote participants yet, show local feed
            CallVideoTrackView(
                trackReference = localTrack!!,
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(12.dp)),
                isOverlay = true
            )
        } else {
            // Waiting for camera
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "📷",
                    fontSize = 32.sp,
                    color = Color.White
                )
            }
        }
        
        // Swap indicator when feeds are swapped
        if (isVideoSwapped && remoteTracks.isNotEmpty()) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(4.dp)
                    .size(24.dp)
                    .background(AppColors.PrimaryBlue, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.SwapVert,
                    contentDescription = "Swapped",
                    tint = Color.White,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
    
    // Bottom-Left Small PiP - Only in group calls (2+ remote participants)
    // Shows user's local feed (non-swappable)
    // Auto-adjusts aspect ratio based on device orientation
    if (isGroupCall && localTrack != null) {
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .zIndex(999f)
                .padding(start = 16.dp, bottom = if (isLandscape) 24.dp else 100.dp) // Position above buttons
                .size(
                    width = if (isLandscape) 120.dp else 90.dp,
                    height = if (isLandscape) 68.dp else 120.dp
                )
                .border(
                    width = 2.dp,
                    color = Color.White.copy(alpha = 0.5f),
                    shape = RoundedCornerShape(12.dp)
                )
                .clip(RoundedCornerShape(12.dp))
        ) {
            CallVideoTrackView(
                trackReference = localTrack!!,
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(12.dp)),
                isOverlay = true
            )
            
            // "You" label
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(4.dp)
                    .background(
                        color = Color.Black.copy(alpha = 0.6f),
                        shape = RoundedCornerShape(4.dp)
                    )
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            ) {
                Text(
                    text = "You",
                    fontSize = 10.sp,
                    color = Color.White,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
    
    // Call Health Overlay (debug) - top-left below header
    if (showPerfOverlay) {
        val codecName = remember { LiveKitManager.getPreferredCodec().displayName }
        val qualityName = remember { LiveKitManager.getCurrentVideoOptions().captureParams.let { params ->
            when (params.width to params.maxFps) {
                1920 to 60 -> "ULTRA (1080p60)"
                1920 to 30 -> "HIGH (1080p30)"
                1280 to 30 -> "AUTO (720p30)"
                640 to 24 -> "LOW (360p24)"
                else -> "Custom ${params.width}x${params.height}@${params.maxFps}"
            }
        } }
        // Lightweight sampling timer for future metrics
        var tick by remember { mutableStateOf(0) }
        LaunchedEffect(Unit) {
            while (true) {
                kotlinx.coroutines.delay(1000)
                tick++
            }
        }
        Box(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 16.dp, top = 96.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color.Black.copy(alpha = 0.55f))
                .border(1.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(12.dp))
                .padding(horizontal = 12.dp, vertical = 10.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Call Health", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                Text("Video: $qualityName", color = Color.White, fontSize = 12.sp)
                Text("Codec: ${codecName}", color = Color.White, fontSize = 12.sp)
                Text("Participants: ${1 + room.remoteParticipants.size}", color = Color.White, fontSize = 12.sp)
                Text("Cam/Mic: ${if (room.localParticipant.isCameraEnabled) "On" else "Off"}/${if (room.localParticipant.isMicrophoneEnabled) "On" else "Off"}", color = Color.White, fontSize = 12.sp)
            }
        }
    }

    // Remote audio activity indicator (lightweight): shows green when any remote audio track is subscribed
    val remoteAudioActive by remember {
        derivedStateOf {
            room.remoteParticipants.values.any { rp ->
                try { rp.isMicrophoneEnabled } catch (_: Exception) { false }
            }
        }
    }

    // Ensure we stay subscribed to remote audio/video tracks (defensive in case of toggles)
    LaunchedEffect(room.remoteParticipants) {
        try {
            room.remoteParticipants.values.forEach { rp ->
                try {
                    rp.audioTrackPublications.forEach { pub ->
                        val r = pub as? io.livekit.android.room.track.RemoteTrackPublication
                        if (r != null && !r.subscribed) {
                            r.setSubscribed(true)
                            Log.d("InCallActivity", "🔊 Subscribed to remote audio for ${rp.name ?: rp.identity?.value}")
                        }
                    }
                    // Also subscribe to camera video publications to ensure remote video renders
                    rp.videoTrackPublications.forEach { pub ->
                        val r = pub as? io.livekit.android.room.track.RemoteTrackPublication
                        if (r != null && !r.subscribed) {
                            r.setSubscribed(true)
                            Log.d("InCallActivity", "📺 Subscribed to remote video for ${rp.name ?: rp.identity?.value}")
                        }
                    }
                } catch (_: Exception) { }
            }
        } catch (e: Exception) {
            Log.w("InCallActivity", "Audio subscription enforcement failed: ${e.message}")
        }
    }
    if (showPerfOverlay) {
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 16.dp, bottom = 16.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(Color.Black.copy(alpha = 0.55f))
                .border(1.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(10.dp))
                .padding(horizontal = 10.dp, vertical = 8.dp)
        ) {
            val audioSummary = try {
                val remotes = room.remoteParticipants.values
                var pubs = 0
                var subs = 0
                var muted = 0
                remotes.forEach { rp ->
                    try {
                        val ap = rp.audioTrackPublications
                        pubs += ap.size
                        ap.forEach { p ->
                            val rPub = p as? io.livekit.android.room.track.RemoteTrackPublication
                            if (rPub != null) {
                                if (rPub.subscribed) subs++
                                if (rPub.muted) muted++
                            }
                        }
                    } catch (_: Exception) { }
                }
                Triple(pubs, subs, muted)
            } catch (_: Exception) {
                Triple(0, 0, 0)
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(if (remoteAudioActive) Color(0xFF4CAF50) else Color.Gray)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(text = if (remoteAudioActive) "Remote audio active" else "No remote audio", color = Color.White, fontSize = 12.sp)
                }
                Text(
                    text = "Audio pubs: ${audioSummary.first}, sub: ${audioSummary.second}, muted: ${audioSummary.third}",
                    color = Color.White.copy(alpha = 0.9f),
                    fontSize = 11.sp
                )
            }
        }
    }

    // Local mic state indicator: permission + publish state
    val micStateLabel by remember {
        derivedStateOf {
            when {
                !micPermissionGranted.value -> "Mic: Permission"
                room.localParticipant.isMicrophoneEnabled -> "Mic: On"
                else -> "Mic: Off"
            }
        }
    }
    if (showPerfOverlay) {
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 16.dp, bottom = 16.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(Color.Black.copy(alpha = 0.55f))
                .border(1.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(10.dp))
                .padding(horizontal = 10.dp, vertical = 6.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(
                            when {
                                !micPermissionGranted.value -> Color(0xFFFFC107)
                                room.localParticipant.isMicrophoneEnabled -> Color(0xFF4CAF50)
                                else -> Color.Gray
                            }
                        )
                )
                Spacer(Modifier.width(6.dp))
                Text(text = micStateLabel, color = Color.White, fontSize = 12.sp)
            }
        }
    }
    
        // Connection Quality Indicator removed - now shown as dot next to participant name
        
        // ===== RECONNECTION OVERLAY =====
        ReconnectionOverlay(
            state = reconnectionState,
            modifier = Modifier.fillMaxSize()
        )
    
    } // Close OUTER Box (line 441)
} // End of InCallScreen
}

@Composable
fun ConnectionQualityIndicator(
    quality: io.livekit.android.room.participant.ConnectionQuality,
    modifier: Modifier = Modifier
) {
    val (dots, text, color) = when (quality) {
        io.livekit.android.room.participant.ConnectionQuality.EXCELLENT -> 
            Triple("🟢🟢🟢", "Excellent", Color(0xFF22C55E))
        io.livekit.android.room.participant.ConnectionQuality.GOOD -> 
            Triple("🟢🟢⚪", "Good", Color(0xFFEAB308))
        io.livekit.android.room.participant.ConnectionQuality.POOR -> 
            Triple("🟢⚪⚪", "Poor", Color(0xFFEF4444))
        else -> 
            Triple("⚪⚪⚪", "Unknown", Color.Gray)
    }
    
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Color(0xFF2F3448).copy(alpha = 0.9f))
            .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(20.dp))
            .padding(horizontal = 15.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = dots,
            fontSize = 13.sp
        )
        Text(
            text = text,
            color = color,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
fun ReconnectionOverlay(
    state: LiveKitManager.ReconnectionState,
    modifier: Modifier = Modifier
) {
    when (state) {
        is LiveKitManager.ReconnectionState.Reconnecting -> {
            Box(
                modifier = modifier
                    .background(Color.Black.copy(alpha = 0.85f))
                    .zIndex(500f),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color(0xFF2F3448).copy(alpha = 0.95f))
                        .border(2.dp, Color(0xFF6B7FB8).copy(alpha = 0.5f), RoundedCornerShape(20.dp))
                        .padding(40.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    // Spinning indicator
                    CircularProgressIndicator(
                        modifier = Modifier.size(60.dp),
                        color = Color(0xFF7589C4),
                        strokeWidth = 4.dp
                    )
                    
                    Text(
                        text = "Connection lost",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                    
                    Text(
                        text = "Reconnecting... (attempt ${state.attempt}/${state.maxAttempts})",
                        fontSize = 14.sp,
                        color = Color(0xFFA0A2A6)
                    )
                }
            }
        }
        is LiveKitManager.ReconnectionState.Reconnected -> {
            // Show brief success message
            LaunchedEffect(Unit) {
                kotlinx.coroutines.delay(2000)
                // State will auto-transition to Connected
            }
            
            // Success toast at top of screen
            Box(modifier = modifier, contentAlignment = Alignment.TopCenter) {
                Box(
                    modifier = Modifier
                        .padding(top = 80.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color(0xFF22C55E).copy(alpha = 0.95f))
                        .padding(horizontal = 24.dp, vertical = 12.dp)
                        .zIndex(200f)
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "✅", fontSize = 16.sp)
                        Text(
                            text = "Connection restored",
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }
        }
        is LiveKitManager.ReconnectionState.Failed -> {
            Box(
                modifier = modifier
                    .background(Color.Black.copy(alpha = 0.9f))
                    .zIndex(500f),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color(0xFF2F3448))
                        .border(2.dp, Color(0xFFEF4444).copy(alpha = 0.5f), RoundedCornerShape(20.dp))
                        .padding(40.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(20.dp)
                ) {
                    Text(
                        text = "❌",
                        fontSize = 48.sp
                    )
                    
                    Text(
                        text = "Connection Failed",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White
                    )
                    
                    Text(
                        text = state.reason,
                        fontSize = 14.sp,
                        color = Color(0xFFA0A2A6),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                }
            }
        }
        else -> {
            // Connected state - no overlay
        }
    }
}

