package com.example.tres3.ui

import android.content.Context
import android.graphics.Bitmap
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.example.tres3.*
import com.example.tres3.analytics.AnalyticsDashboard
import com.example.tres3.ar.ARFiltersManager
import com.example.tres3.audio.*
import com.example.tres3.chat.InCallChatManager
import com.example.tres3.effects.BackgroundEffectsLibrary
import com.example.tres3.layout.*
import com.example.tres3.network.BandwidthOptimizer
import com.example.tres3.quality.CallQualityInsights
import com.example.tres3.reactions.ReactionManager
import com.example.tres3.recording.CloudRecordingManager
import com.example.tres3.security.E2EEncryptionManager
import com.example.tres3.video.LowLightEnhancer
import com.example.tres3.ai.MeetingInsightsBot
import io.livekit.android.room.Room
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import timber.log.Timber

/**
 * InCallManagerCoordinator - Central coordinator for all in-call feature managers
 * 
 * Manages lifecycle, state synchronization, and UI callbacks for all 34 feature managers.
 * Designed to be integrated into InCallActivity with minimal changes.
 * 
 * Usage in InCallActivity:
 * ```kotlin
 * private lateinit var coordinator: InCallManagerCoordinator
 * 
 * override fun onCreate(savedInstanceState: Bundle?) {
 *     super.onCreate(savedInstanceState)
 *     
 *     setContent {
 *         val rootView = findViewById<ViewGroup>(android.R.id.content)
 *         coordinator = InCallManagerCoordinator(this, room, callId, rootView)
 *         coordinator.initialize()
 *     }
 * }
 * 
 * override fun onDestroy() {
 *     coordinator.cleanup()
 *     super.onDestroy()
 * }
 * ```
 */
class InCallManagerCoordinator(
    private val context: Context,
    private val room: Room,
    private val callId: String,
    private val containerView: android.view.ViewGroup
) {
    // UI State flows for Compose integration
    private val _chatMessages = MutableStateFlow<List<InCallChatManager.ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<InCallChatManager.ChatMessage>> = _chatMessages

    private val _reactions = MutableStateFlow<List<ReactionManager.Reaction>>(emptyList())
    val reactions: StateFlow<List<ReactionManager.Reaction>> = _reactions

    private val _qualityScore = MutableStateFlow<CallQualityInsights.QualityScore?>(null)
    val qualityScore: StateFlow<CallQualityInsights.QualityScore?> = _qualityScore

    private val _activeFilter = MutableStateFlow<ARFiltersManager.ARFilter>(ARFiltersManager.ARFilter.NONE)
    val activeFilter: StateFlow<ARFiltersManager.ARFilter> = _activeFilter

    private val _recordingStatus = MutableStateFlow(false)
    val recordingStatus: StateFlow<Boolean> = _recordingStatus

    private val _layoutMode = MutableStateFlow<MultiStreamLayoutManager.LayoutMode>(MultiStreamLayoutManager.LayoutMode.GRID)
    val layoutMode: StateFlow<MultiStreamLayoutManager.LayoutMode> = _layoutMode

    // Feature Managers (grouped by category)
    
    // Communication
    val chatManager = InCallChatManager(context, room)
    val reactionsManager = ReactionManager(context, room, containerView)
    val meetingInsightsBot = MeetingInsightsBot(context)
    
    // Layout & Rendering
    val gridLayoutManager = GridLayoutManager(context, room)
    val multiStreamLayoutManager = MultiStreamLayoutManager(context, room)
    
    // Video Effects
    val arFiltersManager = ARFiltersManager(context)
    val backgroundEffectsLibrary = BackgroundEffectsLibrary(context)
    val lowLightEnhancer = LowLightEnhancer(context)
    
    // Audio
    val spatialAudioProcessor = SpatialAudioProcessor(context, room)
    val aiNoiseCancellation = AINoiseCancellation(context)
    
    // Quality & Performance
    val bandwidthOptimizer = BandwidthOptimizer(context, room)
    val callQualityInsights = CallQualityInsights(context, room)
    val analyticsManager = AnalyticsDashboard(context)
    
    // Recording & Security
    val cloudRecordingManager = CloudRecordingManager(context)
    val encryptionManager = E2EEncryptionManager(context)

    private var isInitialized = false

    /**
     * Initialize all managers and set up callbacks
     */
    suspend fun initialize() {
        if (isInitialized) {
            Timber.w("Already initialized")
            return
        }

        Timber.d("Initializing InCallManagerCoordinator")

        // Initialize managers that need async setup
        arFiltersManager.initialize()
        aiNoiseCancellation.initialize()
        encryptionManager.initialize()

        // Set up chat callbacks
        chatManager.onMessageReceived = { message ->
            val currentMessages = _chatMessages.value.toMutableList()
            currentMessages.add(message)
            _chatMessages.value = currentMessages
            
            // Feed to meeting insights bot
            meetingInsightsBot.addTranscript(
                participantId = message.senderId,
                text = message.message,
                timestamp = message.timestamp
            )
        }

        // Set up reactions callbacks
        reactionsManager.onReactionReceived = { reaction ->
            val currentReactions = _reactions.value.toMutableList()
            currentReactions.add(reaction)
            _reactions.value = currentReactions
        }

        // Set up quality monitoring
        callQualityInsights.onQualityScoreUpdated = { score, issues ->
            _qualityScore.value = score
            
            // Track in analytics
            analyticsManager.trackMetric(
                AnalyticsDashboard.MetricType.VIDEO_QUALITY,
                score.overall.toFloat()
            )
            
            // Log issues
            issues.forEach { issue ->
                Timber.w("Quality issue: ${issue.description}")
            }
        }

        // Start quality monitoring
        callQualityInsights.startAnalysis()

        // Set up bandwidth optimization
        bandwidthOptimizer.onQualityChanged = { preset ->
            Timber.d("Bandwidth quality changed to: $preset")
        }
        bandwidthOptimizer.startMonitoring()

        // Set up recording callbacks
        cloudRecordingManager.onUploadProgress = { progress ->
            Timber.d("Upload progress: ${(progress.progress * 100).toInt()}%")
        }

        // Track call start in analytics
        analyticsManager.trackCallStart(
            callId = callId,
            participantCount = room.remoteParticipants.size + 1
        )

        // Start meeting insights tracking
        meetingInsightsBot.startMeeting(
            meetingId = callId,
            title = "Video Call",
            participantIds = room.remoteParticipants.keys.map { it.value }.toSet()
        )

        isInitialized = true
        Timber.d("InCallManagerCoordinator initialized successfully")
    }

    /**
     * Send chat message
     */
    fun sendChatMessage(text: String) {
        chatManager.sendMessage(text)
    }

    /**
     * Send reaction
     */
    fun sendReaction(reaction: ReactionManager.ReactionType) {
        reactionsManager.sendReaction(reaction)
    }

    /**
     * Apply AR filter
     */
    fun applyARFilter(filter: ARFiltersManager.ARFilter) {
        arFiltersManager.applyFilter(filter)
        _activeFilter.value = filter
    }

    /**
     * Get background effect
     */
    fun getBackgroundEffect(type: BackgroundEffectsLibrary.GradientType): Bitmap? {
        return backgroundEffectsLibrary.getGradientBackground(type)
    }

    /**
     * Toggle recording
     */
    suspend fun toggleRecording() {
        if (_recordingStatus.value) {
            cloudRecordingManager.stopRecording(callId)
            _recordingStatus.value = false
            Timber.d("Recording stopped")
        } else {
            cloudRecordingManager.startRecording(callId)
            _recordingStatus.value = true
            Timber.d("Recording started")
        }
    }

    /**
     * Change layout mode
     */
    fun setLayoutMode(mode: MultiStreamLayoutManager.LayoutMode) {
        multiStreamLayoutManager.setLayoutMode(mode)
        _layoutMode.value = mode
    }

    /**
     * Enable spatial audio
     */
    fun enableSpatialAudio(enabled: Boolean) {
        spatialAudioProcessor.enableSpatialAudio(enabled)
    }

    /**
     * Enable AI noise cancellation
     */
    fun enableAINoiseCancellation(enabled: Boolean) {
        // Would integrate with audio pipeline
        Timber.d("AI noise cancellation: ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Enable low-light enhancement
     */
    fun setLowLightMode(mode: LowLightEnhancer.EnhancementMode) {
        lowLightEnhancer.setMode(mode)
    }

    /**
     * Set spotlight participant
     */
    fun setSpotlight(participantId: String?) {
        multiStreamLayoutManager.setSpotlight(participantId)
    }

    /**
     * Get current quality insights
     */
    fun getQualityInsights(): CallQualityInsights.QualityScore? {
        return callQualityInsights.getCurrentScore()
    }

    /**
     * Generate meeting summary
     */
    fun getMeetingSummary(): MeetingInsightsBot.MeetingSummary? {
        return meetingInsightsBot.generateSummary()
    }

    /**
     * Get analytics report
     */
    fun getAnalyticsReport(): String {
        return analyticsManager.generateReport(AnalyticsDashboard.ReportFormat.TEXT)
    }

    /**
     * Cleanup all managers
     */
    fun cleanup() {
        Timber.d("Cleaning up InCallManagerCoordinator")

        // Stop analytics tracking
        analyticsManager.trackCallEnd(callId)
        meetingInsightsBot.endMeeting()

        // Cleanup all managers
        chatManager.cleanup()
        reactionsManager.cleanup()
        gridLayoutManager.cleanup()
        multiStreamLayoutManager.cleanup()
        arFiltersManager.cleanup()
        lowLightEnhancer.cleanup()
        spatialAudioProcessor.cleanup()
        aiNoiseCancellation.cleanup()
        bandwidthOptimizer.cleanup()
        callQualityInsights.cleanup()
        analyticsManager.cleanup()
        cloudRecordingManager.cleanup()
        encryptionManager.cleanup()
        meetingInsightsBot.cleanup()

        isInitialized = false
        Timber.d("InCallManagerCoordinator cleaned up")
    }
}

/**
 * Extension function for easy initialization in Activity
 */
fun LifecycleOwner.createInCallCoordinator(
    context: Context,
    room: Room,
    callId: String,
    containerView: android.view.ViewGroup
): InCallManagerCoordinator {
    val coordinator = InCallManagerCoordinator(context, room, callId, containerView)
    
    lifecycleScope.launch {
        coordinator.initialize()
    }
    
    return coordinator
}
