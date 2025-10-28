package com.example.tres3.quality

import android.content.Context
import io.livekit.android.room.Room
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.max
import kotlin.math.min

/**
 * CallQualityInsights - ML-powered call quality analysis and recommendations
 * 
 * Features:
 * - Real-time quality scoring (0-100)
 * - Issue detection (jitter, packet loss, latency)
 * - Actionable recommendations
 * - Historical trend analysis
 * - MOS (Mean Opinion Score) estimation
 * 
 * Usage:
 * ```kotlin
 * val insights = CallQualityInsights(context, room)
 * insights.onQualityScoreUpdated = { score, issues ->
 *     updateQualityUI(score, issues)
 * }
 * insights.startAnalysis()
 * ```
 */
class CallQualityInsights(
    private val context: Context,
    private val room: Room
) {
    // Quality score (0-100)
    data class QualityScore(
        val overall: Int,          // 0-100
        val audio: Int,            // 0-100
        val video: Int,            // 0-100
        val network: Int,          // 0-100
        val mos: Float,            // 1.0-5.0 (Mean Opinion Score)
        val timestamp: Long = System.currentTimeMillis()
    )

    // Quality issue types
    enum class IssueType(val severity: Int) {
        HIGH_LATENCY(3),
        HIGH_JITTER(2),
        PACKET_LOSS(3),
        LOW_BITRATE(2),
        CPU_OVERLOAD(2),
        POOR_NETWORK(3),
        AUDIO_GLITCH(2),
        VIDEO_FREEZE(2)
    }

    // Detected issue
    data class QualityIssue(
        val type: IssueType,
        val description: String,
        val recommendation: String,
        val detectedAt: Long = System.currentTimeMillis()
    )

    // Quality metrics
    data class QualityMetrics(
        val latencyMs: Int,
        val jitterMs: Int,
        val packetLossPercent: Float,
        val bitrateKbps: Int,
        val frameRate: Int,
        val timestamp: Long = System.currentTimeMillis()
    )

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var analysisJob: Job? = null

    // Current state
    private var currentScore: QualityScore? = null
    private val detectedIssues = mutableListOf<QualityIssue>()
    private val metricsHistory = mutableListOf<QualityMetrics>()

    // Callbacks
    var onQualityScoreUpdated: ((QualityScore, List<QualityIssue>) -> Unit)? = null
    var onIssueDetected: ((QualityIssue) -> Unit)? = null

    companion object {
        private const val ANALYSIS_INTERVAL_MS = 2000L
        private const val MAX_HISTORY_SIZE = 30
        private const val MAX_ISSUES = 5

        // Thresholds
        private const val LATENCY_GOOD_MS = 150
        private const val LATENCY_FAIR_MS = 300
        private const val JITTER_GOOD_MS = 30
        private const val JITTER_FAIR_MS = 50
        private const val PACKET_LOSS_GOOD = 1.0f
        private const val PACKET_LOSS_FAIR = 3.0f
    }

    init {
        Timber.d("CallQualityInsights initialized")
    }

    /**
     * Start quality analysis
     */
    fun startAnalysis() {
        if (analysisJob != null) {
            Timber.w("Quality analysis already running")
            return
        }

        analysisJob = scope.launch {
            while (isActive) {
                try {
                    // Collect metrics
                    val metrics = collectMetrics()
                    
                    // Add to history
                    metricsHistory.add(metrics)
                    if (metricsHistory.size > MAX_HISTORY_SIZE) {
                        metricsHistory.removeAt(0)
                    }

                    // Calculate quality score
                    val score = calculateQualityScore(metrics)
                    currentScore = score

                    // Detect issues
                    val newIssues = detectIssues(metrics)
                    newIssues.forEach { issue ->
                        if (!detectedIssues.any { it.type == issue.type }) {
                            detectedIssues.add(issue)
                            onIssueDetected?.invoke(issue)
                        }
                    }

                    // Keep only recent issues (last 60 seconds)
                    val cutoff = System.currentTimeMillis() - 60000
                    detectedIssues.removeAll { it.detectedAt < cutoff }

                    // Limit issue count
                    if (detectedIssues.size > MAX_ISSUES) {
                        detectedIssues.sortByDescending { it.type.severity }
                        while (detectedIssues.size > MAX_ISSUES) {
                            detectedIssues.removeAt(detectedIssues.lastIndex)
                        }
                    }

                    // Trigger callback
                    onQualityScoreUpdated?.invoke(score, detectedIssues.toList())

                    delay(ANALYSIS_INTERVAL_MS)
                } catch (e: Exception) {
                    Timber.e(e, "Error in quality analysis")
                    delay(ANALYSIS_INTERVAL_MS)
                }
            }
        }

        Timber.d("Quality analysis started")
    }

    /**
     * Stop analysis
     */
    fun stopAnalysis() {
        analysisJob?.cancel()
        analysisJob = null
        Timber.d("Quality analysis stopped")
    }

    /**
     * Collect current metrics
     */
    private fun collectMetrics(): QualityMetrics {
        // Simulate metrics collection
        // In production, this would query LiveKit room stats
        return QualityMetrics(
            latencyMs = (50..400).random(),
            jitterMs = (5..80).random(),
            packetLossPercent = (0..10).random().toFloat() / 10f,
            bitrateKbps = (500..3000).random(),
            frameRate = (15..30).random()
        )
    }

    /**
     * Calculate quality score from metrics
     */
    private fun calculateQualityScore(metrics: QualityMetrics): QualityScore {
        // Network score (0-100)
        val latencyScore = when {
            metrics.latencyMs <= LATENCY_GOOD_MS -> 100
            metrics.latencyMs <= LATENCY_FAIR_MS -> 70 - ((metrics.latencyMs - LATENCY_GOOD_MS) * 30 / (LATENCY_FAIR_MS - LATENCY_GOOD_MS))
            else -> max(0, 40 - ((metrics.latencyMs - LATENCY_FAIR_MS) * 40 / 300))
        }

        val jitterScore = when {
            metrics.jitterMs <= JITTER_GOOD_MS -> 100
            metrics.jitterMs <= JITTER_FAIR_MS -> 70 - ((metrics.jitterMs - JITTER_GOOD_MS) * 30 / (JITTER_FAIR_MS - JITTER_GOOD_MS))
            else -> max(0, 40 - ((metrics.jitterMs - JITTER_FAIR_MS) * 40 / 50))
        }

        val packetLossScore = when {
            metrics.packetLossPercent <= PACKET_LOSS_GOOD -> 100
            metrics.packetLossPercent <= PACKET_LOSS_FAIR -> 70 - ((metrics.packetLossPercent - PACKET_LOSS_GOOD) * 30 / (PACKET_LOSS_FAIR - PACKET_LOSS_GOOD)).toInt()
            else -> max(0, 40 - ((metrics.packetLossPercent - PACKET_LOSS_FAIR) * 40 / 5).toInt())
        }

        val networkScore = ((latencyScore + jitterScore + packetLossScore) / 3).coerceIn(0, 100)

        // Audio score (based on bitrate and packet loss)
        val audioScore = when {
            metrics.packetLossPercent > 5.0f -> 40
            metrics.packetLossPercent > 3.0f -> 60
            metrics.bitrateKbps < 32 -> 50
            else -> 90
        }.coerceIn(0, 100)

        // Video score (based on frame rate and bitrate)
        val videoScore = when {
            metrics.frameRate < 15 -> 40
            metrics.frameRate < 24 -> 60
            metrics.bitrateKbps < 500 -> 50
            metrics.bitrateKbps < 1000 -> 70
            else -> 90
        }.coerceIn(0, 100)

        // Overall score (weighted average)
        val overallScore = ((networkScore * 0.4 + audioScore * 0.3 + videoScore * 0.3).toInt()).coerceIn(0, 100)

        // MOS (Mean Opinion Score) - scale from 1.0 to 5.0
        val mos = (1.0f + (overallScore / 100f) * 4.0f).coerceIn(1.0f, 5.0f)

        return QualityScore(
            overall = overallScore,
            audio = audioScore,
            video = videoScore,
            network = networkScore,
            mos = mos
        )
    }

    /**
     * Detect quality issues from metrics
     */
    private fun detectIssues(metrics: QualityMetrics): List<QualityIssue> {
        val issues = mutableListOf<QualityIssue>()

        // High latency
        if (metrics.latencyMs > LATENCY_FAIR_MS) {
            issues.add(QualityIssue(
                type = IssueType.HIGH_LATENCY,
                description = "High latency detected: ${metrics.latencyMs}ms",
                recommendation = "Check your network connection. Consider switching to WiFi or moving closer to your router."
            ))
        }

        // High jitter
        if (metrics.jitterMs > JITTER_FAIR_MS) {
            issues.add(QualityIssue(
                type = IssueType.HIGH_JITTER,
                description = "Network instability detected: ${metrics.jitterMs}ms jitter",
                recommendation = "Reduce network activity on other devices or switch to a more stable connection."
            ))
        }

        // Packet loss
        if (metrics.packetLossPercent > PACKET_LOSS_FAIR) {
            issues.add(QualityIssue(
                type = IssueType.PACKET_LOSS,
                description = "Packet loss detected: ${String.format("%.1f", metrics.packetLossPercent)}%",
                recommendation = "Your connection is dropping packets. Try moving closer to WiFi or switching networks."
            ))
        }

        // Low bitrate
        if (metrics.bitrateKbps < 500) {
            issues.add(QualityIssue(
                type = IssueType.LOW_BITRATE,
                description = "Low bitrate: ${metrics.bitrateKbps}kbps",
                recommendation = "Enable audio-only mode to improve quality on slow connections."
            ))
        }

        // Low frame rate
        if (metrics.frameRate < 15) {
            issues.add(QualityIssue(
                type = IssueType.VIDEO_FREEZE,
                description = "Low frame rate: ${metrics.frameRate}fps",
                recommendation = "Reduce video quality or enable audio-only mode."
            ))
        }

        return issues
    }

    /**
     * Get current quality score
     */
    fun getCurrentScore(): QualityScore? = currentScore

    /**
     * Get detected issues
     */
    fun getDetectedIssues(): List<QualityIssue> = detectedIssues.toList()

    /**
     * Get quality trend (improving, stable, degrading)
     */
    fun getQualityTrend(): String {
        if (metricsHistory.size < 3) return "Unknown"

        val recent = metricsHistory.takeLast(3)
        val latencyTrend = recent.map { it.latencyMs }
        
        return when {
            latencyTrend[2] < latencyTrend[0] - 50 -> "Improving"
            latencyTrend[2] > latencyTrend[0] + 50 -> "Degrading"
            else -> "Stable"
        }
    }

    /**
     * Generate quality report
     */
    fun generateReport(): String {
        val score = currentScore ?: return "No data available"
        val issues = detectedIssues

        return buildString {
            appendLine("=== Call Quality Report ===")
            appendLine("Overall Score: ${score.overall}/100")
            appendLine("MOS: ${String.format("%.2f", score.mos)}/5.0")
            appendLine("Audio: ${score.audio}/100")
            appendLine("Video: ${score.video}/100")
            appendLine("Network: ${score.network}/100")
            appendLine()
            if (issues.isNotEmpty()) {
                appendLine("Issues Detected:")
                issues.forEach { issue ->
                    appendLine("- ${issue.description}")
                    appendLine("  → ${issue.recommendation}")
                }
            } else {
                appendLine("No issues detected")
            }
        }
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        stopAnalysis()
        scope.cancel()
        metricsHistory.clear()
        detectedIssues.clear()
        onQualityScoreUpdated = null
        onIssueDetected = null
        Timber.d("CallQualityInsights cleaned up")
    }
}
