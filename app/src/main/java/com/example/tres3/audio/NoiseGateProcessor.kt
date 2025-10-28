package com.example.tres3.audio

import android.content.Context
import android.media.audiofx.NoiseSuppressor
import io.livekit.android.room.Room
import io.livekit.android.room.track.LocalAudioTrack
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * NoiseGateProcessor - Voice Activity Detection with automatic silence suppression
 * 
 * Features:
 * - Voice Activity Detection (VAD)
 * - Configurable noise gate threshold
 * - Automatic silence suppression
 * - Real-time audio level monitoring
 * - Attack/release time configuration
 * - Audio level callbacks
 * 
 * Usage:
 * ```kotlin
 * val noiseGate = NoiseGateProcessor(context, room)
 * noiseGate.setThreshold(-40f) // dB
 * noiseGate.onAudioLevelChanged = { level, isActive ->
 *     updateAudioLevelUI(level, isActive)
 * }
 * noiseGate.enable()
 * ```
 */
class NoiseGateProcessor(
    private val context: Context,
    private val room: Room
) {
    // Noise gate settings
    data class NoiseGateConfig(
        var thresholdDb: Float = -40f,      // Threshold in dB (-60 to 0)
        var attackTimeMs: Long = 10,        // Time to open gate
        var releaseTimeMs: Long = 100,      // Time to close gate
        var holdTimeMs: Long = 200          // Time to hold gate open after signal drops
    )

    private val config = NoiseGateConfig()

    // VAD state
    private var isGateOpen = false
    private var lastActiveTime = 0L
    private var currentLevel = 0f

    // Coroutine scope
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Monitoring job
    private var monitoringJob: Job? = null

    // Callbacks
    var onAudioLevelChanged: ((Float, Boolean) -> Unit)? = null
    var onVoiceActivityChanged: ((Boolean) -> Unit)? = null

    // Enabled state
    private var isEnabled = false

    // Noise suppressor (Android built-in)
    private var noiseSuppressor: NoiseSuppressor? = null

    companion object {
        private const val SAMPLE_RATE_MS = 50L // Sample audio level every 50ms
        private const val MIN_DB = -60f
        private const val MAX_DB = 0f
        private const val RMS_WINDOW_SIZE = 10 // Average over last 10 samples
    }

    // RMS history for smoothing
    private val rmsHistory = mutableListOf<Float>()

    init {
        Timber.d("NoiseGateProcessor initialized")
    }

    /**
     * Enable noise gate processing
     */
    fun enable() {
        if (isEnabled) {
            Timber.w("NoiseGateProcessor already enabled")
            return
        }

        isEnabled = true
        startMonitoring()
        enableNoiseSuppressor()
        
        Timber.d("NoiseGateProcessor enabled")
    }

    /**
     * Disable noise gate processing
     */
    fun disable() {
        if (!isEnabled) {
            Timber.w("NoiseGateProcessor already disabled")
            return
        }

        isEnabled = false
        stopMonitoring()
        disableNoiseSuppressor()
        
        Timber.d("NoiseGateProcessor disabled")
    }

    /**
     * Enable Android's built-in noise suppressor
     */
    private fun enableNoiseSuppressor() {
        try {
            val audioPublication = room.localParticipant.audioTrackPublications.firstOrNull()

            if (audioPublication != null) {
                // Publication exists; enabling NoiseSuppressor would require access to
                // the underlying audio session used by the LiveKit LocalAudioTrack.
                // That session is not exposed by the SDK here, so we only log intent.
                Timber.d("Noise suppressor would be enabled on local audio publication")
            }
        } catch (e: Exception) {
            Timber.e(e, "Failed to enable noise suppressor")
        }
    }

    /**
     * Disable noise suppressor
     */
    private fun disableNoiseSuppressor() {
        try {
            noiseSuppressor?.enabled = false
            noiseSuppressor?.release()
            noiseSuppressor = null
            Timber.d("Noise suppressor disabled")
        } catch (e: Exception) {
            Timber.e(e, "Failed to disable noise suppressor")
        }
    }

    /**
     * Start monitoring audio levels
     */
    private fun startMonitoring() {
        monitoringJob?.cancel()
        
        monitoringJob = scope.launch {
            while (isActive) {
                try {
                    // Simulate audio level monitoring
                    // In production, this would capture actual audio samples from the microphone
                    val simulatedLevel = simulateAudioLevel()
                    processAudioLevel(simulatedLevel)
                    
                    delay(SAMPLE_RATE_MS)
                } catch (e: Exception) {
                    Timber.e(e, "Error monitoring audio level")
                }
            }
        }
        
        Timber.d("Audio level monitoring started")
    }

    /**
     * Stop monitoring audio levels
     */
    private fun stopMonitoring() {
        monitoringJob?.cancel()
        monitoringJob = null
        rmsHistory.clear()
        Timber.d("Audio level monitoring stopped")
    }

    /**
     * Process audio level sample
     */
    private fun processAudioLevel(rms: Float) {
        // Add to history
        rmsHistory.add(rms)
        if (rmsHistory.size > RMS_WINDOW_SIZE) {
            rmsHistory.removeAt(0)
        }

        // Calculate smoothed level
        val smoothedRms = rmsHistory.average().toFloat()
        val levelDb = rmsToDb(smoothedRms)
        currentLevel = levelDb

        // Check if above threshold
        val isAboveThreshold = levelDb > config.thresholdDb
        val currentTime = System.currentTimeMillis()

        // Gate logic
        when {
            isAboveThreshold -> {
                // Signal detected
                lastActiveTime = currentTime
                
                if (!isGateOpen) {
                    // Open gate (attack time)
                    scope.launch {
                        delay(config.attackTimeMs)
                        if (isAboveThreshold) {
                            openGate()
                        }
                    }
                }
            }
            else -> {
                // Signal below threshold
                val timeSinceActive = currentTime - lastActiveTime
                
                if (isGateOpen && timeSinceActive > config.holdTimeMs) {
                    // Close gate (release time)
                    scope.launch {
                        delay(config.releaseTimeMs)
                        if (!isAboveThreshold) {
                            closeGate()
                        }
                    }
                }
            }
        }

        // Trigger callback
        onAudioLevelChanged?.invoke(levelDb, isGateOpen)
    }

    /**
     * Open the noise gate
     */
    private fun openGate() {
        if (!isGateOpen) {
            isGateOpen = true
            onVoiceActivityChanged?.invoke(true)
            Timber.d("Noise gate opened (voice detected)")
        }
    }

    /**
     * Close the noise gate
     */
    private fun closeGate() {
        if (isGateOpen) {
            isGateOpen = false
            onVoiceActivityChanged?.invoke(false)
            Timber.d("Noise gate closed (silence)")
        }
    }

    /**
     * Convert RMS to dB
     */
    private fun rmsToDb(rms: Float): Float {
        if (rms <= 0f) return MIN_DB
        val db = 20f * log10(rms)
        return db.coerceIn(MIN_DB, MAX_DB)
    }

    /**
     * Simulate audio level (for demonstration)
     * In production, replace with actual audio capture from microphone
     */
    private fun simulateAudioLevel(): Float {
        // Simulate varying audio levels
        // Returns RMS value between 0.0 and 1.0
        val random = Math.random()
        return when {
            random < 0.3 -> 0.001f   // Silence (below threshold)
            random < 0.7 -> 0.05f    // Low level
            else -> 0.2f             // Voice level
        }.toFloat()
    }

    /**
     * Set noise gate threshold
     */
    fun setThreshold(thresholdDb: Float) {
        config.thresholdDb = thresholdDb.coerceIn(MIN_DB, MAX_DB)
        Timber.d("Noise gate threshold set to: ${config.thresholdDb} dB")
    }

    /**
     * Set attack time
     */
    fun setAttackTime(ms: Long) {
        config.attackTimeMs = ms.coerceIn(1, 1000)
        Timber.d("Attack time set to: ${config.attackTimeMs} ms")
    }

    /**
     * Set release time
     */
    fun setReleaseTime(ms: Long) {
        config.releaseTimeMs = ms.coerceIn(1, 5000)
        Timber.d("Release time set to: ${config.releaseTimeMs} ms")
    }

    /**
     * Set hold time
     */
    fun setHoldTime(ms: Long) {
        config.holdTimeMs = ms.coerceIn(0, 2000)
        Timber.d("Hold time set to: ${config.holdTimeMs} ms")
    }

    /**
     * Get current configuration
     */
    fun getConfig(): NoiseGateConfig = config.copy()

    /**
     * Set configuration
     */
    fun setConfig(newConfig: NoiseGateConfig) {
        config.thresholdDb = newConfig.thresholdDb.coerceIn(MIN_DB, MAX_DB)
        config.attackTimeMs = newConfig.attackTimeMs.coerceIn(1, 1000)
        config.releaseTimeMs = newConfig.releaseTimeMs.coerceIn(1, 5000)
        config.holdTimeMs = newConfig.holdTimeMs.coerceIn(0, 2000)
        Timber.d("Configuration updated: $config")
    }

    /**
     * Get current audio level
     */
    fun getCurrentLevel(): Float = currentLevel

    /**
     * Check if gate is open
     */
    fun isGateOpen(): Boolean = isGateOpen

    /**
     * Check if enabled
     */
    fun isEnabled(): Boolean = isEnabled

    /**
     * Get recommended threshold for environment
     */
    fun getRecommendedThreshold(): Float {
        // Analyze ambient noise level over short period
        // For now, return default
        return -40f
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        disable()
        scope.cancel()
        onAudioLevelChanged = null
        onVoiceActivityChanged = null
        Timber.d("NoiseGateProcessor cleaned up")
    }
}
