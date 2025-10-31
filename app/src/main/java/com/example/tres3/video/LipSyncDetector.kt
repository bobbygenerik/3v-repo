package com.example.tres3.video

import android.content.Context
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.abs

/**
 * LipSyncDetector - Audio/Video synchronization monitor
 * 
 * Features:
 * - Real-time A/V sync detection
 * - Lag measurement (audio ahead/behind video)
 * - Automatic alerts when sync issues detected
 * - Statistical analysis over time
 * - Adaptive threshold adjustment
 * 
 * Sync Issues:
 * - Audio ahead: User hears sound before seeing lips move
 * - Video ahead: User sees lips move before hearing sound
 * - Acceptable range: ±60ms (human perception threshold)
 * - Warning threshold: ±100ms
 * - Critical threshold: ±200ms
 * 
 * Usage:
 * ```kotlin
 * val detector = LipSyncDetector(context)
 * detector.onSyncIssueDetected = { lag, severity ->
 *     showWarning("Audio/video sync issue: ${lag}ms lag")
 * }
 * detector.addAudioTimestamp(System.currentTimeMillis())
 * detector.addVideoTimestamp(System.currentTimeMillis())
 * ```
 */
class LipSyncDetector(
    private val context: Context
) {
    // Sync severity levels
    enum class SyncSeverity {
        GOOD,      // < 60ms lag
        WARNING,   // 60-150ms lag
        CRITICAL   // > 150ms lag
    }

    // Sync analysis result
    data class SyncAnalysis(
        val avgLagMs: Float,
        val maxLagMs: Long,
        val severity: SyncSeverity,
        val audioAhead: Boolean,  // true if audio ahead of video
        val sampleCount: Int,
        val timestamp: Long = System.currentTimeMillis()
    )

    // Sync event with detailed info
    data class SyncEvent(
        val lagMs: Long,
        val severity: SyncSeverity,
        val audioTimestamp: Long,
        val videoTimestamp: Long,
        val detectedAt: Long = System.currentTimeMillis()
    )

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Timestamp buffers (circular buffers)
    private val audioTimestamps = ArrayDeque<Long>()
    private val videoTimestamps = ArrayDeque<Long>()
    
    // Sync statistics
    private val lagHistory = mutableListOf<Long>()
    private var totalChecks = 0L
    private var issuesDetected = 0L
    
    // State
    private var isMonitoring = false
    private var lastAlertTime = 0L

    // Callbacks
    var onSyncIssueDetected: ((Long, SyncSeverity) -> Unit)? = null
    var onSyncImproved: (() -> Unit)? = null
    var onAnalysisUpdate: ((SyncAnalysis) -> Unit)? = null

    companion object {
        private const val MAX_BUFFER_SIZE = 100
        private const val GOOD_THRESHOLD_MS = 60L
        private const val WARNING_THRESHOLD_MS = 150L
        private const val CRITICAL_THRESHOLD_MS = 250L
        private const val ALERT_COOLDOWN_MS = 5000L  // 5 seconds between alerts
        private const val ANALYSIS_INTERVAL_MS = 2000L  // Analyze every 2 seconds
    }

    init {
        Timber.d("LipSyncDetector initialized")
    }

    /**
     * Start monitoring audio/video sync
     */
    fun startMonitoring() {
        if (isMonitoring) {
            Timber.w("Already monitoring")
            return
        }

        isMonitoring = true
        lagHistory.clear()
        totalChecks = 0
        issuesDetected = 0

        // Start periodic analysis
        scope.launch {
            while (isMonitoring) {
                delay(ANALYSIS_INTERVAL_MS)
                performSyncAnalysis()
            }
        }

        Timber.d("Lip sync monitoring started")
    }

    /**
     * Stop monitoring
     */
    fun stopMonitoring() {
        isMonitoring = false
        Timber.d("Lip sync monitoring stopped")
    }

    /**
     * Add audio frame timestamp
     */
    fun addAudioTimestamp(timestamp: Long) {
        if (!isMonitoring) return

        synchronized(audioTimestamps) {
            audioTimestamps.add(timestamp)
            if (audioTimestamps.size > MAX_BUFFER_SIZE) {
                audioTimestamps.removeFirst()
            }
        }

        // Check sync immediately when we have both
        checkSync()
    }

    /**
     * Add video frame timestamp
     */
    fun addVideoTimestamp(timestamp: Long) {
        if (!isMonitoring) return

        synchronized(videoTimestamps) {
            videoTimestamps.add(timestamp)
            if (videoTimestamps.size > MAX_BUFFER_SIZE) {
                videoTimestamps.removeFirst()
            }
        }

        // Check sync immediately when we have both
        checkSync()
    }

    /**
     * Check current sync status
     */
    private fun checkSync() {
        val audioTs = synchronized(audioTimestamps) { audioTimestamps.lastOrNull() }
        val videoTs = synchronized(videoTimestamps) { videoTimestamps.lastOrNull() }

        if (audioTs == null || videoTs == null) return

        totalChecks++

        // Calculate lag (positive = audio ahead, negative = video ahead)
        val lag = audioTs - videoTs
        val absLag = abs(lag)

        // Record lag
        synchronized(lagHistory) {
            lagHistory.add(lag)
            if (lagHistory.size > 1000) {
                lagHistory.removeAt(0)
            }
        }

        // Determine severity
        val severity = when {
            absLag < GOOD_THRESHOLD_MS -> SyncSeverity.GOOD
            absLag < WARNING_THRESHOLD_MS -> SyncSeverity.WARNING
            else -> SyncSeverity.CRITICAL
        }

        // Alert if needed
        if (severity != SyncSeverity.GOOD) {
            issuesDetected++
            alertSyncIssue(lag, severity, audioTs, videoTs)
        }
    }

    /**
     * Alert user of sync issue (with cooldown)
     */
    private fun alertSyncIssue(lag: Long, severity: SyncSeverity, audioTs: Long, videoTs: Long) {
        val currentTime = System.currentTimeMillis()
        
        // Check cooldown
        if (currentTime - lastAlertTime < ALERT_COOLDOWN_MS) {
            return
        }

        lastAlertTime = currentTime
        
        val event = SyncEvent(
            lagMs = lag,
            severity = severity,
            audioTimestamp = audioTs,
            videoTimestamp = videoTs
        )

        Timber.w("Lip sync issue detected: ${lag}ms lag (${severity})")
        onSyncIssueDetected?.invoke(lag, severity)
    }

    /**
     * Perform periodic sync analysis
     */
    private fun performSyncAnalysis() {
        val lags = synchronized(lagHistory) { lagHistory.toList() }
        
        if (lags.isEmpty()) return

        val avgLag = lags.average().toFloat()
        val maxLag = lags.maxOf { abs(it) }
        val audioAhead = avgLag > 0

        val severity = when {
            maxLag < GOOD_THRESHOLD_MS -> SyncSeverity.GOOD
            maxLag < WARNING_THRESHOLD_MS -> SyncSeverity.WARNING
            else -> SyncSeverity.CRITICAL
        }

        val analysis = SyncAnalysis(
            avgLagMs = avgLag,
            maxLagMs = maxLag,
            severity = severity,
            audioAhead = audioAhead,
            sampleCount = lags.size
        )

        onAnalysisUpdate?.invoke(analysis)

        // Log periodic summary
        if (totalChecks % 50 == 0L) {
            Timber.d("Sync analysis: avg=${avgLag.toInt()}ms, max=${maxLag}ms, severity=$severity, issues=$issuesDetected/$totalChecks")
        }
    }

    /**
     * Get current sync status
     */
    fun getCurrentStatus(): SyncAnalysis? {
        val lags = synchronized(lagHistory) { lagHistory.toList() }
        
        if (lags.isEmpty()) return null

        val avgLag = lags.average().toFloat()
        val maxLag = lags.maxOf { abs(it) }
        val audioAhead = avgLag > 0

        val severity = when {
            maxLag < GOOD_THRESHOLD_MS -> SyncSeverity.GOOD
            maxLag < WARNING_THRESHOLD_MS -> SyncSeverity.WARNING
            else -> SyncSeverity.CRITICAL
        }

        return SyncAnalysis(
            avgLagMs = avgLag,
            maxLagMs = maxLag,
            severity = severity,
            audioAhead = audioAhead,
            sampleCount = lags.size
        )
    }

    /**
     * Get sync statistics
     */
    fun getStatistics(): Statistics {
        val lags = synchronized(lagHistory) { lagHistory.toList() }
        
        val avgLag = if (lags.isNotEmpty()) lags.average().toFloat() else 0f
        val minLag = if (lags.isNotEmpty()) lags.minOf { it } else 0L
        val maxLag = if (lags.isNotEmpty()) lags.maxOf { it } else 0L
        val issueRate = if (totalChecks > 0) (issuesDetected.toFloat() / totalChecks) else 0f

        return Statistics(
            totalChecks = totalChecks,
            issuesDetected = issuesDetected,
            averageLagMs = avgLag,
            minLagMs = minLag,
            maxLagMs = maxLag,
            issueRate = issueRate
        )
    }

    data class Statistics(
        val totalChecks: Long,
        val issuesDetected: Long,
        val averageLagMs: Float,
        val minLagMs: Long,
        val maxLagMs: Long,
        val issueRate: Float
    )

    /**
     * Reset statistics
     */
    fun resetStatistics() {
        synchronized(lagHistory) { lagHistory.clear() }
        totalChecks = 0
        issuesDetected = 0
        Timber.d("Statistics reset")
    }

    /**
     * Get human-readable sync status
     */
    fun getSyncStatusMessage(): String {
        val status = getCurrentStatus() ?: return "No data available"

        return when (status.severity) {
            SyncSeverity.GOOD -> "Audio and video are in sync (${status.avgLagMs.toInt()}ms)"
            SyncSeverity.WARNING -> {
                val direction = if (status.audioAhead) "ahead" else "behind"
                "Audio is ${abs(status.avgLagMs).toInt()}ms $direction of video"
            }
            SyncSeverity.CRITICAL -> {
                val direction = if (status.audioAhead) "ahead" else "behind"
                "⚠️ Significant sync issue: Audio ${abs(status.avgLagMs).toInt()}ms $direction"
            }
        }
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        stopMonitoring()
        scope.cancel()
        synchronized(audioTimestamps) { audioTimestamps.clear() }
        synchronized(videoTimestamps) { videoTimestamps.clear() }
        synchronized(lagHistory) { lagHistory.clear() }
        onSyncIssueDetected = null
        onSyncImproved = null
        onAnalysisUpdate = null
        Timber.d("LipSyncDetector cleaned up")
    }
}
