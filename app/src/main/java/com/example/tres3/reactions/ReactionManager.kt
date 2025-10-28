package com.example.tres3.reactions

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.content.Context
import android.view.ViewGroup
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.TextView
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.participant.RemoteParticipant
import io.livekit.android.events.RoomEvent
import kotlinx.coroutines.*
import org.json.JSONObject
import timber.log.Timber
import kotlin.random.Random

/**
 * ReactionManager - Quick emoji reactions with animated floating overlays
 * 
 * Features:
 * - Quick emoji reactions (❤️😂👏🎉😮👍)
 * - Animated floating overlays with physics-based motion
 * - Auto-dismiss after animation completes
 * - Broadcast via LiveKit DataChannel
 * - Configurable animation duration and paths
 * 
 * Usage:
 * ```kotlin
 * val reactionManager = ReactionManager(context, room, containerView)
 * reactionManager.sendReaction(ReactionType.HEART)
 * ```
 */
class ReactionManager(
    private val context: Context,
    private val room: Room,
    private val containerView: ViewGroup
) {
    // Reaction types
    enum class ReactionType(val emoji: String) {
        HEART("❤️"),
        LAUGH("😂"),
        CLAP("👏"),
        PARTY("🎉"),
        SURPRISED("😮"),
        THUMBS_UP("👍")
    }

    // Reaction data class
    data class Reaction(
        val id: String = java.util.UUID.randomUUID().toString(),
        val type: ReactionType,
        val senderId: String,
        val senderName: String,
        val timestamp: Long = System.currentTimeMillis()
    )

    companion object {
        private const val MESSAGE_TYPE_REACTION = "reaction"
        private const val ANIMATION_DURATION = 2500L
        private const val FADE_OUT_DURATION = 500L
        private const val EMOJI_TEXT_SIZE = 48f
        private const val MAX_CONCURRENT_REACTIONS = 10
    }

    // Active animations
    private val activeAnimations = mutableMapOf<String, AnimatorSet>()

    // Coroutine scope
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Callbacks
    var onReactionReceived: ((Reaction) -> Unit)? = null
    var onReactionSent: ((Reaction) -> Unit)? = null

    init {
        // TODO: Enable DataChannel listener when LiveKit 2.21+ event handling is fixed
        // Currently room.events.collect() pattern has issues in LiveKit SDK
        // For now, reactions can be sent but won't be received automatically
        Timber.w("ReactionManager: DataChannel listener disabled (LiveKit 2.21 limitation)")
        Timber.d("ReactionManager initialized")
    }

    /**
     * Setup LiveKit DataChannel listener
     * 
     * TODO: Re-enable when LiveKit 2.21+ event handling pattern is clarified
     */
    private fun setupDataChannelListener() {
        // Commented out due to LiveKit SDK limitations
        /*
        try {
            scope.launch {
                room.events.collect { event ->
                    when (event) {
                        is RoomEvent.DataReceived -> {
                            handleIncomingData(event.data, event.participant)
                        }
                        else -> { /* Ignore other events */ }
                    }
                }
            }
            Timber.d("Reaction DataChannel listener setup complete")
        } catch (e: Exception) {
            Timber.e(e, "Failed to setup DataChannel listener")
        }
        */
    }

    /**
     * Handle incoming data from DataChannel
     */
    private fun handleIncomingData(data: ByteArray, participant: Participant?) {
        try {
            val jsonString = String(data, Charsets.UTF_8)
            val json = JSONObject(jsonString)
            val messageType = json.optString("type", "")

            if (messageType == MESSAGE_TYPE_REACTION) {
                val reactionTypeStr = json.getString("reaction")
                val reactionType = ReactionType.values().find { it.name == reactionTypeStr }

                if (reactionType != null) {
                    val reaction = Reaction(
                        id = json.optString("id", java.util.UUID.randomUUID().toString()),
                        type = reactionType,
                        senderId = participant?.sid?.value ?: "unknown",
                        senderName = participant?.name ?: "Unknown",
                        timestamp = json.optLong("timestamp", System.currentTimeMillis())
                    )
                    handleReceivedReaction(reaction)
                } else {
                    Timber.w("Unknown reaction type: $reactionTypeStr")
                }
            }
        } catch (e: Exception) {
            Timber.e(e, "Failed to parse reaction data")
        }
    }

    /**
     * Send a reaction to all participants
     */
    fun sendReaction(type: ReactionType) {
        scope.launch {
            try {
                val reaction = Reaction(
                    type = type,
                    senderId = room.localParticipant.sid?.value ?: "local",
                    senderName = room.localParticipant.name ?: "You"
                )

                // Create JSON payload
                val json = JSONObject().apply {
                    put("type", MESSAGE_TYPE_REACTION)
                    put("id", reaction.id)
                    put("reaction", type.name)
                    put("timestamp", reaction.timestamp)
                }

                // Send via DataChannel
                val data = json.toString().toByteArray(Charsets.UTF_8)
                room.localParticipant.publishData(data)

                // Show local animation
                showReactionAnimation(reaction)
                onReactionSent?.invoke(reaction)

                Timber.d("Sent reaction: ${type.emoji}")
            } catch (e: Exception) {
                Timber.e(e, "Failed to send reaction")
            }
        }
    }

    /**
     * Handle received reaction
     */
    private fun handleReceivedReaction(reaction: Reaction) {
        showReactionAnimation(reaction)
        onReactionReceived?.invoke(reaction)
        Timber.d("Received reaction from ${reaction.senderName}: ${reaction.type.emoji}")
    }

    /**
     * Show animated reaction overlay
     */
    private fun showReactionAnimation(reaction: Reaction) {
        scope.launch {
            // Limit concurrent reactions
            if (activeAnimations.size >= MAX_CONCURRENT_REACTIONS) {
                val oldestKey = activeAnimations.keys.firstOrNull()
                if (oldestKey != null) {
                    activeAnimations[oldestKey]?.cancel()
                    activeAnimations.remove(oldestKey)
                }
            }

            // Create emoji TextView
            val emojiView = TextView(context).apply {
                text = reaction.type.emoji
                textSize = EMOJI_TEXT_SIZE
                alpha = 0f
            }

            // Add to container
            containerView.addView(emojiView)

            // Calculate random starting position (bottom of screen)
            val containerWidth = containerView.width
            val containerHeight = containerView.height
            val startX = Random.nextInt(containerWidth / 4, containerWidth * 3 / 4).toFloat()
            val startY = containerHeight.toFloat()

            // Calculate random ending position (top of screen with horizontal drift)
            val endX = startX + Random.nextInt(-200, 200)
            val endY = containerHeight * 0.2f // 20% from top

            // Position emoji at start
            emojiView.x = startX
            emojiView.y = startY

            // Create animation set
            val animatorSet = AnimatorSet()

            // Fade in animation
            val fadeIn = ObjectAnimator.ofFloat(emojiView, "alpha", 0f, 1f).apply {
                duration = 300
                interpolator = DecelerateInterpolator()
            }

            // Vertical movement (float upward)
            val moveY = ObjectAnimator.ofFloat(emojiView, "translationY", 0f, -(startY - endY)).apply {
                duration = ANIMATION_DURATION
                interpolator = DecelerateInterpolator()
            }

            // Horizontal drift
            val moveX = ObjectAnimator.ofFloat(emojiView, "translationX", 0f, endX - startX).apply {
                duration = ANIMATION_DURATION
                interpolator = AccelerateInterpolator()
            }

            // Scale animation (slight grow then shrink)
            val scaleXUp = ObjectAnimator.ofFloat(emojiView, "scaleX", 1f, 1.3f).apply {
                duration = ANIMATION_DURATION / 2
                interpolator = DecelerateInterpolator()
            }
            val scaleYUp = ObjectAnimator.ofFloat(emojiView, "scaleY", 1f, 1.3f).apply {
                duration = ANIMATION_DURATION / 2
                interpolator = DecelerateInterpolator()
            }
            val scaleXDown = ObjectAnimator.ofFloat(emojiView, "scaleX", 1.3f, 0.8f).apply {
                duration = ANIMATION_DURATION / 2
                startDelay = ANIMATION_DURATION / 2
                interpolator = AccelerateInterpolator()
            }
            val scaleYDown = ObjectAnimator.ofFloat(emojiView, "scaleY", 1.3f, 0.8f).apply {
                duration = ANIMATION_DURATION / 2
                startDelay = ANIMATION_DURATION / 2
                interpolator = AccelerateInterpolator()
            }

            // Fade out animation
            val fadeOut = ObjectAnimator.ofFloat(emojiView, "alpha", 1f, 0f).apply {
                duration = FADE_OUT_DURATION
                startDelay = ANIMATION_DURATION - FADE_OUT_DURATION
                interpolator = AccelerateInterpolator()
            }

            // Combine all animations
            animatorSet.playTogether(fadeIn, moveY, moveX, scaleXUp, scaleYUp, scaleXDown, scaleYDown, fadeOut)

            // Remove view after animation
            animatorSet.addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    containerView.removeView(emojiView)
                    activeAnimations.remove(reaction.id)
                    Timber.d("Reaction animation completed: ${reaction.type.emoji}")
                }

                override fun onAnimationCancel(animation: Animator) {
                    containerView.removeView(emojiView)
                    activeAnimations.remove(reaction.id)
                }
            })

            // Start animation
            activeAnimations[reaction.id] = animatorSet
            animatorSet.start()

            Timber.d("Started reaction animation: ${reaction.type.emoji} from ${reaction.senderName}")
        }
    }

    /**
     * Get all available reaction types
     */
    fun getAvailableReactions(): List<ReactionType> = ReactionType.values().toList()

    /**
     * Cancel all active animations
     */
    fun cancelAllAnimations() {
        activeAnimations.values.forEach { it.cancel() }
        activeAnimations.clear()
        Timber.d("Cancelled all reaction animations")
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        cancelAllAnimations()
        scope.cancel()
        onReactionReceived = null
        onReactionSent = null
        Timber.d("ReactionManager cleaned up")
    }
}
