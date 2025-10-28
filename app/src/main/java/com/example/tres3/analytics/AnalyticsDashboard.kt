package com.example.tres3.analytics

import android.content.Context
import kotlinx.coroutines.*
import timber.log.Timber
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.roundToInt

/**
 * AnalyticsDashboard - Comprehensive call analytics and metrics dashboard
 * 
 * Features:
 * - Real-time call quality metrics
 * - Historical trend analysis
 * - Usage statistics (duration, frequency)
 * - Network performance tracking
 * - Participant engagement metrics
 * - Custom event tracking
 * 
 * Usage:
 * ```kotlin
 * val dashboard = AnalyticsDashboard(context)
 * dashboard.trackCallStart(callId, participantCount)
 * dashboard.trackQualityMetric(QualityMetric.VIDEO_QUALITY, 85)
 * val summary = dashboard.generateSummary()
 * ```
 */
class AnalyticsDashboard(
    private val context: Context
) {
    // Metric types
    enum class MetricType {
        CALL_DURATION,
        VIDEO_QUALITY,
        AUDIO_QUALITY,
        NETWORK_LATENCY,
        PACKET_LOSS,
        FRAME_RATE,
        BITRATE,
        CPU_USAGE,
        MEMORY_USAGE,
        PARTICIPANT_COUNT
    }

    // Time granularity for trends
    enum class TimeGranularity {
        HOURLY,
        DAILY,
        WEEKLY,
        MONTHLY
    }

    // Call session data
    data class CallSession(
        val callId: String,
        val startTime: Long,
        val endTime: Long? = null,
        val duration: Long = 0,  // milliseconds
        val participantCount: Int = 0,
        val averageQuality: Int = 0,  // 0-100
        val networkType: String = "Unknown",
        val issuesEncountered: List<String> = emptyList()
    )

    // Metric data point
    data class MetricDataPoint(
        val type: MetricType,
        val value: Float,
        val timestamp: Long = System.currentTimeMillis()
    )

    // Analytics summary
    data class AnalyticsSummary(
        val totalCalls: Int,
        val totalDuration: Long,  // milliseconds
        val averageDuration: Long,
        val averageQuality: Int,
        val averageParticipants: Int,
        val mostCommonIssues: List<Pair<String, Int>>,
        val qualityTrend: String,  // "Improving", "Stable", "Degrading"
        val peakUsageHour: Int,
        val generatedAt: Long = System.currentTimeMillis()
    )

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Data storage
    private val callSessions = mutableListOf<CallSession>()
    private val metricsData = mutableMapOf<MetricType, MutableList<MetricDataPoint>>()
    private val customEvents = mutableListOf<CustomEvent>()

    // Active sessions
    private val activeCalls = mutableMapOf<String, CallSession>()

    // Callbacks
    var onMetricUpdated: ((MetricType, Float) -> Unit)? = null
    var onSessionCompleted: ((CallSession) -> Unit)? = null

    companion object {
        private const val MAX_SESSIONS = 1000
        private const val MAX_METRICS_PER_TYPE = 1000
        private const val MAX_CUSTOM_EVENTS = 500
    }

    init {
        Timber.d("AnalyticsDashboard initialized")
    }

    /**
     * Track call start
     */
    fun trackCallStart(
        callId: String, 
        participantCount: Int = 1,
        networkType: String = "Unknown"
    ) {
        val session = CallSession(
            callId = callId,
            startTime = System.currentTimeMillis(),
            participantCount = participantCount,
            networkType = networkType
        )
        
        activeCalls[callId] = session
        Timber.d("Call started: $callId with $participantCount participants")
    }

    /**
     * Track call end
     */
    fun trackCallEnd(callId: String, issues: List<String> = emptyList()) {
        val activeCall = activeCalls.remove(callId) ?: run {
            Timber.w("No active call found: $callId")
            return
        }

        val endTime = System.currentTimeMillis()
        val duration = endTime - activeCall.startTime

        // Calculate average quality from metrics
        val qualityMetrics = metricsData[MetricType.VIDEO_QUALITY]
            ?.filter { it.timestamp >= activeCall.startTime && it.timestamp <= endTime }
            ?: emptyList()
        
        val avgQuality = if (qualityMetrics.isNotEmpty()) {
            qualityMetrics.map { it.value }.average().roundToInt()
        } else 0

        val completedSession = activeCall.copy(
            endTime = endTime,
            duration = duration,
            averageQuality = avgQuality,
            issuesEncountered = issues
        )

        // Store session
        callSessions.add(completedSession)
        if (callSessions.size > MAX_SESSIONS) {
            callSessions.removeAt(0)
        }

        // Trigger callback
        onSessionCompleted?.invoke(completedSession)

        Timber.d("Call ended: $callId, duration: ${duration / 1000}s, quality: $avgQuality")
    }

    /**
     * Track metric value
     */
    fun trackMetric(type: MetricType, value: Float) {
        val dataPoint = MetricDataPoint(type, value)
        
        val metricList = metricsData.getOrPut(type) { mutableListOf() }
        metricList.add(dataPoint)
        
        // Keep list size manageable
        if (metricList.size > MAX_METRICS_PER_TYPE) {
            metricList.removeAt(0)
        }

        // Trigger callback
        onMetricUpdated?.invoke(type, value)
    }

    /**
     * Track custom event
     */
    fun trackEvent(eventName: String, properties: Map<String, Any> = emptyMap()) {
        val event = CustomEvent(
            name = eventName,
            properties = properties,
            timestamp = System.currentTimeMillis()
        )

        customEvents.add(event)
        if (customEvents.size > MAX_CUSTOM_EVENTS) {
            customEvents.removeAt(0)
        }

        Timber.d("Event tracked: $eventName")
    }

    data class CustomEvent(
        val name: String,
        val properties: Map<String, Any>,
        val timestamp: Long
    )

    /**
     * Get metric history
     */
    fun getMetricHistory(
        type: MetricType,
        startTime: Long? = null,
        endTime: Long? = null
    ): List<MetricDataPoint> {
        val metrics = metricsData[type] ?: return emptyList()
        
        return metrics.filter { metric ->
            (startTime == null || metric.timestamp >= startTime) &&
            (endTime == null || metric.timestamp <= endTime)
        }
    }

    /**
     * Get average metric value
     */
    fun getAverageMetric(type: MetricType, timeRangeMs: Long? = null): Float {
        val cutoff = timeRangeMs?.let { System.currentTimeMillis() - it }
        val metrics = getMetricHistory(type, startTime = cutoff)
        
        return if (metrics.isNotEmpty()) {
            metrics.map { it.value }.average().toFloat()
        } else 0f
    }

    /**
     * Get metric trend (improving/stable/degrading)
     */
    fun getMetricTrend(type: MetricType, sampleSize: Int = 10): String {
        val metrics = metricsData[type] ?: return "Unknown"
        
        if (metrics.size < sampleSize * 2) {
            return "Insufficient Data"
        }

        val recent = metrics.takeLast(sampleSize).map { it.value }.average()
        val previous = metrics.takeLast(sampleSize * 2).take(sampleSize).map { it.value }.average()

        return when {
            recent > previous + 5 -> "Improving"
            recent < previous - 5 -> "Degrading"
            else -> "Stable"
        }
    }

    /**
     * Generate analytics summary
     */
    fun generateSummary(timeRangeMs: Long? = null): AnalyticsSummary {
        val cutoff = timeRangeMs?.let { System.currentTimeMillis() - it }
        val relevantSessions = callSessions.filter { session ->
            cutoff == null || session.startTime >= cutoff
        }

        val totalCalls = relevantSessions.size
        val totalDuration = relevantSessions.sumOf { it.duration }
        val avgDuration = if (totalCalls > 0) totalDuration / totalCalls else 0L
        val avgQuality = if (totalCalls > 0) {
            relevantSessions.map { it.averageQuality }.average().roundToInt()
        } else 0
        val avgParticipants = if (totalCalls > 0) {
            (relevantSessions.sumOf { it.participantCount }.toFloat() / totalCalls).roundToInt()
        } else 0

        // Most common issues
        val allIssues = relevantSessions.flatMap { it.issuesEncountered }
        val issueFrequency = allIssues.groupingBy { it }.eachCount()
        val topIssues = issueFrequency.entries
            .sortedByDescending { it.value }
            .take(5)
            .map { it.key to it.value }

        // Quality trend
        val qualityTrend = getMetricTrend(MetricType.VIDEO_QUALITY)

        // Peak usage hour
        val callsByHour = relevantSessions.groupingBy { 
            Calendar.getInstance().apply {
                timeInMillis = it.startTime
            }.get(Calendar.HOUR_OF_DAY)
        }.eachCount()
        val peakHour = callsByHour.maxByOrNull { it.value }?.key ?: 0

        return AnalyticsSummary(
            totalCalls = totalCalls,
            totalDuration = totalDuration,
            averageDuration = avgDuration,
            averageQuality = avgQuality,
            averageParticipants = avgParticipants,
            mostCommonIssues = topIssues,
            qualityTrend = qualityTrend,
            peakUsageHour = peakHour
        )
    }

    /**
     * Generate detailed report
     */
    fun generateReport(format: ReportFormat = ReportFormat.TEXT): String {
        val summary = generateSummary()
        val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

        return when (format) {
            ReportFormat.TEXT -> buildString {
                appendLine("=== Call Analytics Report ===")
                appendLine("Generated: ${dateFormat.format(Date(summary.generatedAt))}")
                appendLine()
                appendLine("Overview:")
                appendLine("- Total Calls: ${summary.totalCalls}")
                appendLine("- Total Duration: ${formatDuration(summary.totalDuration)}")
                appendLine("- Average Duration: ${formatDuration(summary.averageDuration)}")
                appendLine("- Average Quality: ${summary.averageQuality}/100")
                appendLine("- Average Participants: ${summary.averageParticipants}")
                appendLine()
                appendLine("Trends:")
                appendLine("- Quality Trend: ${summary.qualityTrend}")
                appendLine("- Peak Usage Hour: ${summary.peakUsageHour}:00")
                appendLine()
                if (summary.mostCommonIssues.isNotEmpty()) {
                    appendLine("Common Issues:")
                    summary.mostCommonIssues.forEach { (issue, count) ->
                        appendLine("- $issue: $count occurrences")
                    }
                }
            }
            
            ReportFormat.JSON -> {
                // Simplified JSON representation
                """
                {
                    "totalCalls": ${summary.totalCalls},
                    "totalDuration": ${summary.totalDuration},
                    "averageQuality": ${summary.averageQuality},
                    "qualityTrend": "${summary.qualityTrend}",
                    "peakUsageHour": ${summary.peakUsageHour}
                }
                """.trimIndent()
            }
            
            ReportFormat.CSV -> {
                buildString {
                    appendLine("Metric,Value")
                    appendLine("Total Calls,${summary.totalCalls}")
                    appendLine("Total Duration (ms),${summary.totalDuration}")
                    appendLine("Average Quality,${summary.averageQuality}")
                    appendLine("Average Participants,${summary.averageParticipants}")
                    appendLine("Quality Trend,${summary.qualityTrend}")
                }
            }
        }
    }

    enum class ReportFormat {
        TEXT,
        JSON,
        CSV
    }

    /**
     * Format duration for display
     */
    private fun formatDuration(durationMs: Long): String {
        val seconds = durationMs / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        
        return when {
            hours > 0 -> "${hours}h ${minutes % 60}m"
            minutes > 0 -> "${minutes}m ${seconds % 60}s"
            else -> "${seconds}s"
        }
    }

    /**
     * Export data for external analysis
     */
    fun exportData(): ExportData {
        return ExportData(
            sessions = callSessions.toList(),
            metrics = metricsData.mapValues { it.value.toList() },
            events = customEvents.toList()
        )
    }

    data class ExportData(
        val sessions: List<CallSession>,
        val metrics: Map<MetricType, List<MetricDataPoint>>,
        val events: List<CustomEvent>
    )

    /**
     * Clear all analytics data
     */
    fun clearData() {
        callSessions.clear()
        metricsData.clear()
        customEvents.clear()
        activeCalls.clear()
        Timber.d("Analytics data cleared")
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        scope.cancel()
        onMetricUpdated = null
        onSessionCompleted = null
        Timber.d("AnalyticsDashboard cleaned up")
    }
}
