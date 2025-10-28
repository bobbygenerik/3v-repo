package com.example.tres3.ai

import android.content.Context
import kotlinx.coroutines.*
import timber.log.Timber
import java.text.SimpleDateFormat
import java.util.*

/**
 * MeetingInsightsBot - AI-powered meeting analysis and insights
 * 
 * Features:
 * - Real-time transcription analysis
 * - Automatic meeting summaries
 * - Action item extraction
 * - Key decision tracking
 * - Participant engagement analysis
 * - Topic detection and clustering
 * 
 * Note: This simulates AI analysis.
 * In production, integrate with:
 * - GPT/Claude API for summarization
 * - NLP libraries for topic modeling
 * - Sentiment analysis models
 * 
 * Usage:
 * ```kotlin
 * val bot = MeetingInsightsBot(context)
 * bot.startMeeting(meetingId, title)
 * bot.addTranscript(participantId, text, timestamp)
 * val summary = bot.generateSummary()
 * ```
 */
class MeetingInsightsBot(
    private val context: Context
) {
    // Meeting metadata
    data class MeetingMetadata(
        val meetingId: String,
        val title: String,
        val startTime: Long,
        val endTime: Long? = null,
        val participantIds: Set<String> = emptySet(),
        val duration: Long = 0  // milliseconds
    )

    // Transcript entry
    data class TranscriptEntry(
        val participantId: String,
        val text: String,
        val timestamp: Long,
        val sentiment: Sentiment = Sentiment.NEUTRAL
    )

    enum class Sentiment {
        POSITIVE,
        NEUTRAL,
        NEGATIVE
    }

    // Action item
    data class ActionItem(
        val description: String,
        val assignee: String? = null,
        val dueDate: Long? = null,
        val priority: Priority = Priority.MEDIUM,
        val extractedAt: Long = System.currentTimeMillis()
    )

    enum class Priority {
        LOW,
        MEDIUM,
        HIGH,
        URGENT
    }

    // Key decision
    data class KeyDecision(
        val description: String,
        val participants: List<String>,
        val timestamp: Long,
        val category: String = "General"
    )

    // Meeting topic
    data class Topic(
        val name: String,
        val mentions: Int,
        val keywords: List<String>,
        val duration: Long  // Time spent on topic
    )

    // Meeting summary
    data class MeetingSummary(
        val metadata: MeetingMetadata,
        val overview: String,
        val keyPoints: List<String>,
        val actionItems: List<ActionItem>,
        val decisions: List<KeyDecision>,
        val topics: List<Topic>,
        val participantInsights: Map<String, ParticipantInsight>,
        val generatedAt: Long = System.currentTimeMillis()
    )

    // Participant insights
    data class ParticipantInsight(
        val participantId: String,
        val talkTime: Long,  // milliseconds
        val messageCount: Int,
        val engagementScore: Float,  // 0-100
        val keyContributions: List<String>
    )

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // State
    private var currentMeeting: MeetingMetadata? = null
    private val transcripts = mutableListOf<TranscriptEntry>()
    private val actionItems = mutableListOf<ActionItem>()
    private val decisions = mutableListOf<KeyDecision>()
    private val topics = mutableMapOf<String, Topic>()

    // Callbacks
    var onActionItemDetected: ((ActionItem) -> Unit)? = null
    var onDecisionMade: ((KeyDecision) -> Unit)? = null
    var onTopicChanged: ((Topic) -> Unit)? = null

    companion object {
        private const val MAX_TRANSCRIPT_SIZE = 10000
        
        // Keywords for action item detection
        private val ACTION_KEYWORDS = listOf(
            "todo", "to do", "action", "task", "follow up",
            "will do", "should", "need to", "must", "assign"
        )
        
        // Keywords for decision detection
        private val DECISION_KEYWORDS = listOf(
            "decide", "decided", "decision", "agree", "agreed",
            "approved", "confirmed", "resolved", "conclusion"
        )
    }

    init {
        Timber.d("MeetingInsightsBot initialized")
    }

    /**
     * Start a new meeting
     */
    fun startMeeting(meetingId: String, title: String, participantIds: Set<String> = emptySet()) {
        currentMeeting = MeetingMetadata(
            meetingId = meetingId,
            title = title,
            startTime = System.currentTimeMillis(),
            participantIds = participantIds
        )
        
        // Clear previous data
        transcripts.clear()
        actionItems.clear()
        decisions.clear()
        topics.clear()
        
        Timber.d("Meeting started: $title ($meetingId)")
    }

    /**
     * End the current meeting
     */
    fun endMeeting() {
        currentMeeting?.let { meeting ->
            val endTime = System.currentTimeMillis()
            val duration = endTime - meeting.startTime
            
            currentMeeting = meeting.copy(
                endTime = endTime,
                duration = duration
            )
            
            Timber.d("Meeting ended: ${meeting.title}, duration: ${duration / 1000}s")
        }
    }

    /**
     * Add transcript entry
     */
    fun addTranscript(participantId: String, text: String, timestamp: Long = System.currentTimeMillis()) {
        val sentiment = analyzeSentiment(text)
        
        val entry = TranscriptEntry(
            participantId = participantId,
            text = text,
            timestamp = timestamp,
            sentiment = sentiment
        )
        
        transcripts.add(entry)
        
        // Keep transcript size manageable
        if (transcripts.size > MAX_TRANSCRIPT_SIZE) {
            transcripts.removeAt(0)
        }
        
        // Analyze for action items and decisions
        scope.launch {
            detectActionItems(text, participantId, timestamp)
            detectDecisions(text, participantId, timestamp)
            updateTopics(text)
        }
    }

    /**
     * Analyze sentiment of text (simulated)
     */
    private fun analyzeSentiment(text: String): Sentiment {
        // In production: Use sentiment analysis model
        val lowerText = text.lowercase()
        
        val positiveWords = listOf("great", "good", "excellent", "happy", "agree", "yes", "perfect")
        val negativeWords = listOf("bad", "poor", "problem", "issue", "disagree", "no", "wrong")
        
        val positiveCount = positiveWords.count { lowerText.contains(it) }
        val negativeCount = negativeWords.count { lowerText.contains(it) }
        
        return when {
            positiveCount > negativeCount -> Sentiment.POSITIVE
            negativeCount > positiveCount -> Sentiment.NEGATIVE
            else -> Sentiment.NEUTRAL
        }
    }

    /**
     * Detect action items from text
     */
    private fun detectActionItems(text: String, participantId: String, timestamp: Long) {
        val lowerText = text.lowercase()
        
        // Check if text contains action keywords
        val hasActionKeyword = ACTION_KEYWORDS.any { lowerText.contains(it) }
        
        if (hasActionKeyword) {
            val priority = when {
                lowerText.contains("urgent") || lowerText.contains("asap") -> Priority.URGENT
                lowerText.contains("important") || lowerText.contains("critical") -> Priority.HIGH
                lowerText.contains("low priority") -> Priority.LOW
                else -> Priority.MEDIUM
            }
            
            val actionItem = ActionItem(
                description = text,
                assignee = participantId,
                priority = priority
            )
            
            actionItems.add(actionItem)
            onActionItemDetected?.invoke(actionItem)
            
            Timber.d("Action item detected: $text")
        }
    }

    /**
     * Detect decisions from text
     */
    private fun detectDecisions(text: String, participantId: String, timestamp: Long) {
        val lowerText = text.lowercase()
        
        val hasDecisionKeyword = DECISION_KEYWORDS.any { lowerText.contains(it) }
        
        if (hasDecisionKeyword) {
            val decision = KeyDecision(
                description = text,
                participants = listOf(participantId),
                timestamp = timestamp
            )
            
            decisions.add(decision)
            onDecisionMade?.invoke(decision)
            
            Timber.d("Decision detected: $text")
        }
    }

    /**
     * Update topics from text
     */
    private fun updateTopics(text: String) {
        // Simple topic extraction (in production: use NLP topic modeling)
        val words = text.lowercase()
            .split("\\s+".toRegex())
            .filter { it.length > 4 }  // Filter short words
        
        words.forEach { word ->
            val topic = topics.getOrPut(word) {
                Topic(
                    name = word,
                    mentions = 0,
                    keywords = listOf(word),
                    duration = 0
                )
            }
            
            topics[word] = topic.copy(mentions = topic.mentions + 1)
        }
    }

    /**
     * Generate meeting summary
     */
    fun generateSummary(): MeetingSummary? {
        val meeting = currentMeeting ?: run {
            Timber.w("No active meeting")
            return null
        }
        
        // Generate overview
        val overview = generateOverview(meeting)
        
        // Extract key points
        val keyPoints = extractKeyPoints()
        
        // Calculate participant insights
        val participantInsights = calculateParticipantInsights()
        
        // Get top topics
        val topTopics = topics.values
            .sortedByDescending { it.mentions }
            .take(5)
        
        return MeetingSummary(
            metadata = meeting,
            overview = overview,
            keyPoints = keyPoints,
            actionItems = actionItems.toList(),
            decisions = decisions.toList(),
            topics = topTopics,
            participantInsights = participantInsights
        )
    }

    /**
     * Generate meeting overview
     */
    private fun generateOverview(meeting: MeetingMetadata): String {
        val duration = (meeting.duration / 1000 / 60).toInt()
        val participantCount = meeting.participantIds.size
        val messageCount = transcripts.size
        
        return buildString {
            append("Meeting '${meeting.title}' lasted $duration minutes ")
            append("with $participantCount participants. ")
            append("A total of $messageCount messages were exchanged. ")
            
            if (actionItems.isNotEmpty()) {
                append("${actionItems.size} action items were identified. ")
            }
            
            if (decisions.isNotEmpty()) {
                append("${decisions.size} key decisions were made.")
            }
        }
    }

    /**
     * Extract key points from discussion
     */
    private fun extractKeyPoints(): List<String> {
        // In production: Use extractive summarization
        val keyPoints = mutableListOf<String>()
        
        // Add important sentences (simulated)
        transcripts
            .filter { it.sentiment != Sentiment.NEGATIVE }
            .filter { it.text.split(" ").size > 10 }  // Substantial messages
            .take(5)
            .forEach { keyPoints.add(it.text) }
        
        return keyPoints
    }

    /**
     * Calculate insights per participant
     */
    private fun calculateParticipantInsights(): Map<String, ParticipantInsight> {
        val insights = mutableMapOf<String, ParticipantInsight>()
        
        val participantMessages = transcripts.groupBy { it.participantId }
        
        participantMessages.forEach { (participantId, messages) ->
            val messageCount = messages.size
            val totalParticipation = transcripts.size.toFloat()
            val engagementScore = (messageCount / totalParticipation * 100).coerceIn(0f, 100f)
            
            // Estimated talk time (5 seconds per message average)
            val talkTime = messageCount * 5000L
            
            // Key contributions (longest messages)
            val keyContributions = messages
                .sortedByDescending { it.text.length }
                .take(3)
                .map { it.text }
            
            insights[participantId] = ParticipantInsight(
                participantId = participantId,
                talkTime = talkTime,
                messageCount = messageCount,
                engagementScore = engagementScore,
                keyContributions = keyContributions
            )
        }
        
        return insights
    }

    /**
     * Generate formatted report
     */
    fun generateReport(): String {
        val summary = generateSummary() ?: return "No meeting data available"
        val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
        
        return buildString {
            appendLine("═══════════════════════════════════════")
            appendLine("  MEETING INSIGHTS REPORT")
            appendLine("═══════════════════════════════════════")
            appendLine()
            appendLine("Meeting: ${summary.metadata.title}")
            appendLine("Date: ${dateFormat.format(Date(summary.metadata.startTime))}")
            appendLine("Duration: ${summary.metadata.duration / 1000 / 60} minutes")
            appendLine("Participants: ${summary.metadata.participantIds.size}")
            appendLine()
            appendLine("OVERVIEW")
            appendLine("────────────────────────────────────────")
            appendLine(summary.overview)
            appendLine()
            
            if (summary.keyPoints.isNotEmpty()) {
                appendLine("KEY POINTS")
                appendLine("────────────────────────────────────────")
                summary.keyPoints.forEachIndexed { index, point ->
                    appendLine("${index + 1}. $point")
                }
                appendLine()
            }
            
            if (summary.actionItems.isNotEmpty()) {
                appendLine("ACTION ITEMS")
                appendLine("────────────────────────────────────────")
                summary.actionItems.forEachIndexed { index, item ->
                    appendLine("${index + 1}. [${item.priority}] ${item.description}")
                    item.assignee?.let { appendLine("   Assignee: $it") }
                }
                appendLine()
            }
            
            if (summary.decisions.isNotEmpty()) {
                appendLine("KEY DECISIONS")
                appendLine("────────────────────────────────────────")
                summary.decisions.forEachIndexed { index, decision ->
                    appendLine("${index + 1}. ${decision.description}")
                }
                appendLine()
            }
            
            if (summary.topics.isNotEmpty()) {
                appendLine("MAIN TOPICS")
                appendLine("────────────────────────────────────────")
                summary.topics.forEach { topic ->
                    appendLine("• ${topic.name} (${topic.mentions} mentions)")
                }
                appendLine()
            }
            
            appendLine("PARTICIPANT ENGAGEMENT")
            appendLine("────────────────────────────────────────")
            summary.participantInsights.forEach { (id, insight) ->
                appendLine("$id:")
                appendLine("  Messages: ${insight.messageCount}")
                appendLine("  Talk Time: ${insight.talkTime / 1000}s")
                appendLine("  Engagement: ${insight.engagementScore.toInt()}%")
            }
        }
    }

    /**
     * Export data for external use
     */
    fun exportData(): ExportData {
        return ExportData(
            meeting = currentMeeting,
            transcripts = transcripts.toList(),
            actionItems = actionItems.toList(),
            decisions = decisions.toList(),
            topics = topics.values.toList()
        )
    }

    data class ExportData(
        val meeting: MeetingMetadata?,
        val transcripts: List<TranscriptEntry>,
        val actionItems: List<ActionItem>,
        val decisions: List<KeyDecision>,
        val topics: List<Topic>
    )

    /**
     * Clear meeting data
     */
    fun clearData() {
        currentMeeting = null
        transcripts.clear()
        actionItems.clear()
        decisions.clear()
        topics.clear()
        Timber.d("Meeting data cleared")
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        scope.cancel()
        onActionItemDetected = null
        onDecisionMade = null
        onTopicChanged = null
        Timber.d("MeetingInsightsBot cleaned up")
    }
}
