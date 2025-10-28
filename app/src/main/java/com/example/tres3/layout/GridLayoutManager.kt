package com.example.tres3.layout

import android.content.Context
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.events.RoomEvent
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.ceil

/**
 * GridLayoutManager - Multi-participant grid view with dynamic sizing
 * 
 * Features:
 * - Dynamic grid sizing (1-9+ participants)
 * - Automatic layout transitions
 * - Active speaker highlighting
 * - Participant tracking
 * - Layout calculation and callbacks
 * 
 * Note: This manager handles grid layout logic. Actual video rendering
 * should be done with LiveKit Compose VideoRenderer components.
 * 
 * Usage:
 * ```kotlin
 * val gridManager = GridLayoutManager(context, room)
 * gridManager.onLayoutChanged = { participants, spanCount ->
 *     updateGridUI(participants, spanCount)
 * }
 * gridManager.refresh()
 * ```
 */
class GridLayoutManager(
    private val context: Context,
    private val room: Room
) {
    // Participant info
    data class ParticipantInfo(
        val participant: Participant,
        val isActiveSpeaker: Boolean = false,
        val isLocal: Boolean = false
    )

    companion object {
        private const val MAX_VISIBLE_PARTICIPANTS = 25
    }

    // Current participants
    private val participants = mutableListOf<ParticipantInfo>()

    // Active speaker tracking
    private var activeSpeakerId: String? = null
    private var activeSpeakerHighlightEnabled = true

    // Coroutine scope
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Callbacks
    var onParticipantClicked: ((Participant) -> Unit)? = null
    var onLayoutChanged: ((List<ParticipantInfo>, Int) -> Unit)? = null
    var onActiveSpeakerChanged: ((String?) -> Unit)? = null

    init {
        // TODO: Enable active speaker listener when LiveKit 2.21+ event handling is fixed
        // Currently room.events.collect() pattern has issues in LiveKit SDK
        Timber.w("GridLayoutManager: Active speaker listener disabled (LiveKit 2.21 limitation)")
        Timber.d("GridLayoutManager initialized")
    }

    /**
     * Setup room event listeners
     * 
     * TODO: Re-enable when LiveKit 2.21+ event handling pattern is clarified
     */
    private fun setupRoomListeners() {
        // Commented out due to LiveKit SDK limitations
        /*
        // Listen for active speaker changes via room events
        scope.launch {
            room.events.collect { event ->
                when (event) {
                    is RoomEvent.ActiveSpeakersChanged -> {
                        val speakers = event.speakers
                        if (speakers.isNotEmpty()) {
                            val activeSpeaker = speakers.first()
                            handleActiveSpeaker(activeSpeaker.sid?.value ?: "")
                        }
                    }
                    else -> { /* Ignore other events */ }
                }
            }
        }

        Timber.d("Room listeners setup complete")
        */
    }

    /**
     * Calculate optimal span count based on participant count
     */
    fun calculateSpanCount(participantCount: Int): Int {
        return when {
            participantCount <= 1 -> 1
            participantCount == 2 -> 2
            participantCount <= 4 -> 2
            participantCount <= 6 -> 3
            participantCount <= 9 -> 3
            participantCount <= 16 -> 4
            else -> 5
        }
    }

    /**
     * Calculate optimal row count based on participant count and span count
     */
    fun calculateRowCount(participantCount: Int, spanCount: Int): Int {
        return ceil(participantCount.toDouble() / spanCount).toInt()
    }

    /**
     * Refresh grid layout with current participants
     */
    fun refresh() {
        scope.launch {
            participants.clear()

            // Add local participant
            participants.add(ParticipantInfo(
                participant = room.localParticipant,
                isLocal = true,
                isActiveSpeaker = room.localParticipant.sid?.value == activeSpeakerId
            ))

            // Add remote participants (limit to max visible)
            room.remoteParticipants.values.take(MAX_VISIBLE_PARTICIPANTS - 1).forEach { remote ->
                participants.add(ParticipantInfo(
                    participant = remote,
                    isLocal = false,
                    isActiveSpeaker = remote.sid?.value == activeSpeakerId
                ))
            }

            // Calculate layout
            val spanCount = calculateSpanCount(participants.size)

            // Trigger callback
            onLayoutChanged?.invoke(participants.toList(), spanCount)

            Timber.d("Grid refreshed with ${participants.size} participants, span count: $spanCount")
        }
    }

    /**
     * Handle active speaker change
     */
    private fun handleActiveSpeaker(speakerId: String) {
        if (!activeSpeakerHighlightEnabled) return

        scope.launch {
            activeSpeakerId = speakerId
            onActiveSpeakerChanged?.invoke(speakerId)

            // Refresh to update isActiveSpeaker flags
            refresh()

            Timber.d("Active speaker changed to: $speakerId")
        }
    }

    /**
     * Enable/disable active speaker highlighting
     */
    fun enableActiveSpeakerHighlight(enabled: Boolean) {
        activeSpeakerHighlightEnabled = enabled
        
        if (!enabled) {
            activeSpeakerId = null
            refresh()
        }

        Timber.d("Active speaker highlight ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Get current participant count
     */
    fun getParticipantCount(): Int = participants.size

    /**
     * Get current participants
     */
    fun getParticipants(): List<ParticipantInfo> = participants.toList()

    /**
     * Get active speaker ID
     */
    fun getActiveSpeakerId(): String? = activeSpeakerId

    /**
     * Clean up resources
     */
    fun cleanup() {
        participants.clear()
        scope.cancel()
        onParticipantClicked = null
        onLayoutChanged = null
        onActiveSpeakerChanged = null
        Timber.d("GridLayoutManager cleaned up")
    }
}
