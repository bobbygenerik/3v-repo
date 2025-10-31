package com.example.tres3.ui

import android.content.Context
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.example.tres3.analytics.AttendanceTracker
import com.example.tres3.audio.BackgroundNoiseReplacer
import com.example.tres3.video.HighlightMomentDetector
import com.example.tres3.video.LipSyncDetector
import io.livekit.android.room.Room
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import timber.log.Timber

/**
 * NewAIFeaturesCoordinator - Manages the 4 new AI features
 * 
 * Integrates:
 * - LipSyncDetector - Audio/video sync monitoring
 * - AttendanceTracker - Face recognition attendance
 * - HighlightMomentDetector - Auto highlight reel
 * - BackgroundNoiseReplacer - Ambient sound replacement
 * 
 * Usage in InCallActivity:
 * ```kotlin
 * private lateinit var aiCoordinator: NewAIFeaturesCoordinator
 * 
 * override fun onCreate(savedInstanceState: Bundle?) {
 *     aiCoordinator = NewAIFeaturesCoordinator(this, room, callId)
 *     aiCoordinator.initialize()
 * }
 * 
 * override fun onDestroy() {
 *     aiCoordinator.cleanup()
 *     super.onDestroy()
 * }
 * ```
 */
class NewAIFeaturesCoordinator(
    private val context: Context,
    private val room: Room,
    private val callId: String
) {
    // UI State flows for Compose integration
    private val _lipSyncStatus = MutableStateFlow("Good")
    val lipSyncStatus: StateFlow<String> = _lipSyncStatus

    private val _lipSyncLag = MutableStateFlow(0)
    val lipSyncLag: StateFlow<Int> = _lipSyncLag

    private val _highlightCount = MutableStateFlow(0)
    val highlightCount: StateFlow<Int> = _highlightCount

    private val _detectedEmotion = MutableStateFlow("")
    val detectedEmotion: StateFlow<String> = _detectedEmotion

    private val _detectedGesture = MutableStateFlow("")
    val detectedGesture: StateFlow<String> = _detectedGesture

    private val _attendanceCount = MutableStateFlow(0)
    val attendanceCount: StateFlow<Int> = _attendanceCount
    
    // Feature managers
    val lipSyncDetector = LipSyncDetector(context)
    val attendanceTracker = AttendanceTracker(context)
    val highlightDetector = HighlightMomentDetector(context)
    val noiseReplacer = BackgroundNoiseReplacer(context)

    // Callbacks
    var onSyncIssueDetected: ((Long, LipSyncDetector.SyncSeverity) -> Unit)? = null
    var onHighlightDetected: ((HighlightMomentDetector.HighlightMoment) -> Unit)? = null
    var onParticipantJoined: ((String, String) -> Unit)? = null

    private var isInitialized = false

    /**
     * Initialize all AI features
     */
    fun initialize() {
        if (isInitialized) {
            Timber.w("Already initialized")
            return
        }

        // 1. Setup Lip Sync Detection
        setupLipSyncDetection()

        // 2. Setup Attendance Tracking
        setupAttendanceTracking()

        // 3. Setup Highlight Detection
        setupHighlightDetection()

        // 4. Setup Background Noise Replacement
        setupNoiseReplacement()

        isInitialized = true
        Timber.d("NewAIFeaturesCoordinator initialized")
    }

    /**
     * Setup lip sync detection
     */
    private fun setupLipSyncDetection() {
        lipSyncDetector.onSyncIssueDetected = { lag, severity ->
            // Update StateFlows
            _lipSyncLag.value = lag.toInt()
            _lipSyncStatus.value = when (severity) {
                LipSyncDetector.SyncSeverity.CRITICAL -> "Critical"
                LipSyncDetector.SyncSeverity.WARNING -> "Warning"
                LipSyncDetector.SyncSeverity.GOOD -> "Good"
            }
            
            onSyncIssueDetected?.invoke(lag, severity)
            
            when (severity) {
                LipSyncDetector.SyncSeverity.CRITICAL -> {
                    Timber.w("Critical sync issue: ${lag}ms")
                }
                LipSyncDetector.SyncSeverity.WARNING -> {
                    Timber.d("Sync warning: ${lag}ms")
                }
                else -> {}
            }
        }

        lipSyncDetector.startMonitoring()
        Timber.d("Lip sync detection enabled")
    }

    /**
     * Setup attendance tracking
     */
    private fun setupAttendanceTracking() {
        // Start session
        attendanceTracker.startSession(callId, "Video Call")

        // Register local participant
        val localIdentity = room.localParticipant.identity?.value ?: "Local User"
        attendanceTracker.registerParticipant(
            room.localParticipant.sid.value,
            localIdentity
        )

        // Register remote participants
        room.remoteParticipants.forEach { (sid, participant) ->
            val name = participant.identity?.value ?: "Unknown"
            attendanceTracker.registerParticipant(sid.value, name)
        }

        // Update attendance count
        _attendanceCount.value = room.remoteParticipants.size + 1

        // Callbacks
        attendanceTracker.onParticipantJoined = { userId, name ->
            _attendanceCount.value = room.remoteParticipants.size + 1
            onParticipantJoined?.invoke(userId, name)
            Timber.d("Attendance: $name joined")
        }

        attendanceTracker.onParticipantLeft = { userId, name, duration ->
            _attendanceCount.value = room.remoteParticipants.size + 1
            Timber.d("Attendance: $name left (${duration / 1000}s)")
        }

        Timber.d("Attendance tracking enabled")
    }

    /**
     * Setup highlight detection
     */
    private fun setupHighlightDetection() {
        highlightDetector.startRecording(callId)

        highlightDetector.onHighlightDetected = { moment ->
            _highlightCount.value += 1
            
            // Update emotion/gesture if detected
            when (moment.type) {
                HighlightMomentDetector.MomentType.LAUGHTER,
                HighlightMomentDetector.MomentType.EXCITEMENT,
                HighlightMomentDetector.MomentType.SURPRISE -> {
                    _detectedEmotion.value = when (moment.type) {
                        HighlightMomentDetector.MomentType.LAUGHTER -> "😊"
                        HighlightMomentDetector.MomentType.EXCITEMENT -> "🎉"
                        HighlightMomentDetector.MomentType.SURPRISE -> "😮"
                        else -> ""
                    }
                }
                HighlightMomentDetector.MomentType.AGREEMENT -> {
                    _detectedGesture.value = "👍"
                }
                else -> {}
            }
            
            onHighlightDetected?.invoke(moment)
            Timber.d("Highlight detected: ${moment.type} - ${moment.description}")
        }

        Timber.d("Highlight detection enabled")
    }

    /**
     * Setup background noise replacement
     */
    private fun setupNoiseReplacement() {
        // Set default ambience (can be changed by user)
        noiseReplacer.setAmbience(
            type = BackgroundNoiseReplacer.AmbienceType.SILENCE,
            volume = 0.3f
        )

        noiseReplacer.onProcessingStats = { stats ->
            // Log statistics periodically
            Timber.v("Noise reduction: ${stats.noiseReduction}dB")
        }

        // Start processing (if enabled in settings)
        // noiseReplacer.startProcessing()

        Timber.d("Background noise replacer ready")
    }

    /**
     * Update audio/video timestamps for lip sync detection
     */
    fun updateTimestamps(audioTimestamp: Long, videoTimestamp: Long) {
        lipSyncDetector.addAudioTimestamp(audioTimestamp)
        lipSyncDetector.addVideoTimestamp(videoTimestamp)
    }

    /**
     * Process video frame for attendance and highlights
     */
    suspend fun processVideoFrame(bitmap: android.graphics.Bitmap, participantId: String) {
        // Attendance tracking (face detection)
        attendanceTracker.processFaceDetection(bitmap)

        // Highlight detection (emotion analysis)
        highlightDetector.processFrame(bitmap, participantId)
    }

    /**
     * Update audio level for highlight detection
     */
    fun updateAudioLevel(level: Float) {
        highlightDetector.addAudioLevel(level)
    }

    /**
     * Set ambient sound type
     */
    fun setAmbience(type: BackgroundNoiseReplacer.AmbienceType, volume: Float = 0.3f) {
        noiseReplacer.setAmbience(type, volume)
        Timber.d("Ambience set to: $type")
    }

    /**
     * Enable/disable background noise replacement
     */
    fun setNoiseReplacementEnabled(enabled: Boolean) {
        if (enabled) {
            noiseReplacer.startProcessing()
        } else {
            noiseReplacer.stopProcessing()
        }
    }

    /**
     * Get attendance report
     */
    fun getAttendanceReport(): AttendanceTracker.AttendanceReport? {
        return attendanceTracker.generateReport()
    }

    /**
     * Get highlight reel
     */
    fun getHighlightReel(): HighlightMomentDetector.HighlightReel? {
        return highlightDetector.generateHighlightReel()
    }

    /**
     * Get sync status message
     */
    fun getSyncStatusMessage(): String {
        return lipSyncDetector.getSyncStatusMessage()
    }

    /**
     * Get all statistics
     */
    fun getStatistics(): Statistics {
        return Statistics(
            lipSync = lipSyncDetector.getStatistics(),
            attendance = attendanceTracker.getStatistics(),
            highlights = highlightDetector.getStatistics(),
            noiseReplacement = noiseReplacer.getStatistics()
        )
    }

    data class Statistics(
        val lipSync: LipSyncDetector.Statistics,
        val attendance: AttendanceTracker.Statistics,
        val highlights: HighlightMomentDetector.Statistics,
        val noiseReplacement: BackgroundNoiseReplacer.Statistics
    )

    /**
     * Clean up all resources
     */
    fun cleanup() {
        // End attendance session and get report
        val attendanceReport = attendanceTracker.generateReportText()
        Timber.d("Attendance Report:\n$attendanceReport")

        // Generate highlight summary
        val highlightSummary = highlightDetector.generateSummary()
        Timber.d("Highlight Summary:\n$highlightSummary")

        // Cleanup all features
        lipSyncDetector.cleanup()
        attendanceTracker.cleanup()
        highlightDetector.cleanup()
        noiseReplacer.cleanup()

        isInitialized = false
        Timber.d("NewAIFeaturesCoordinator cleaned up")
    }
}
