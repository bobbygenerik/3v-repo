package com.example.tres3.audio

import android.content.Context
import io.livekit.android.room.Room
import io.livekit.android.room.participant.RemoteParticipant
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * SpatialAudioProcessor - Simulated spatial audio positioning for video calls
 * 
 * Features:
 * - 2D spatial positioning based on video grid layout
 * - Distance-based volume attenuation
 * - Stereo panning (left/right)
 * - Dynamic participant positioning
 * - Customizable audio zones
 * 
 * Note: This is a simplified simulation. Full spatial audio requires:
 * - HRTF (Head-Related Transfer Function) filtering
 * - Room acoustics modeling
 * - Low-level audio buffer manipulation
 * 
 * Usage:
 * ```kotlin
 * val spatialAudio = SpatialAudioProcessor(context, room)
 * spatialAudio.setListenerPosition(0f, 0f) // Center
 * spatialAudio.setParticipantPosition(participantId, x = 1.0f, y = 0.5f)
 * spatialAudio.enableSpatialAudio(true)
 * ```
 */
class SpatialAudioProcessor(
    private val context: Context,
    private val room: Room
) {
    // 2D position in normalized space (-1.0 to 1.0)
    data class Position2D(
        val x: Float,  // -1.0 (left) to 1.0 (right)
        val y: Float   // -1.0 (back) to 1.0 (front)
    ) {
        companion object {
            val CENTER = Position2D(0f, 0f)
        }
    }

    // Spatial audio parameters for a participant
    data class SpatialParams(
        val position: Position2D,
        val volume: Float,      // 0.0-1.0 (distance-based)
        val pan: Float,         // -1.0 (left) to 1.0 (right)
        val distance: Float     // Euclidean distance from listener
    )

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // State
    private var spatialEnabled = false
    private var listenerPosition = Position2D.CENTER
    private val participantPositions = mutableMapOf<String, Position2D>()
    private val participantParams = mutableMapOf<String, SpatialParams>()

    // Callbacks
    var onSpatialParamsUpdated: ((String, SpatialParams) -> Unit)? = null

    companion object {
        private const val MAX_DISTANCE = 2.0f  // Maximum audible distance
        private const val MIN_VOLUME = 0.1f    // Minimum volume at max distance
        private const val DISTANCE_ATTENUATION = 0.5f  // How quickly volume drops off

        // Grid positioning presets for common layouts
        fun calculateGridPositions(participantCount: Int): List<Position2D> {
            return when (participantCount) {
                1 -> listOf(Position2D.CENTER)
                2 -> listOf(
                    Position2D(-0.5f, 0f),
                    Position2D(0.5f, 0f)
                )
                3 -> listOf(
                    Position2D(-0.7f, 0f),
                    Position2D(0f, 0f),
                    Position2D(0.7f, 0f)
                )
                4 -> listOf(
                    Position2D(-0.5f, 0.5f),
                    Position2D(0.5f, 0.5f),
                    Position2D(-0.5f, -0.5f),
                    Position2D(0.5f, -0.5f)
                )
                else -> {
                    // Circular arrangement for 5+ participants
                    val positions = mutableListOf<Position2D>()
                    val radius = 0.7f
                    val angleStep = (2 * Math.PI / participantCount).toFloat()
                    
                    for (i in 0 until participantCount) {
                        val angle = i * angleStep
                        positions.add(Position2D(
                            x = (radius * cos(angle)).toFloat(),
                            y = (radius * sin(angle)).toFloat()
                        ))
                    }
                    positions
                }
            }
        }
    }

    init {
        Timber.d("SpatialAudioProcessor initialized")
    }

    /**
     * Enable or disable spatial audio processing
     */
    fun enableSpatialAudio(enabled: Boolean) {
        spatialEnabled = enabled
        
        if (enabled) {
            // Recalculate all spatial params
            updateAllSpatialParams()
            Timber.d("Spatial audio enabled")
        } else {
            // Reset all participants to center panning and full volume
            participantParams.keys.forEach { participantId ->
                participantParams[participantId] = SpatialParams(
                    position = Position2D.CENTER,
                    volume = 1.0f,
                    pan = 0f,
                    distance = 0f
                )
                onSpatialParamsUpdated?.invoke(participantId, participantParams[participantId]!!)
            }
            Timber.d("Spatial audio disabled")
        }
    }

    /**
     * Set listener position (typically the local user)
     */
    fun setListenerPosition(x: Float, y: Float) {
        listenerPosition = Position2D(x.coerceIn(-1f, 1f), y.coerceIn(-1f, 1f))
        
        if (spatialEnabled) {
            updateAllSpatialParams()
        }
        
        Timber.d("Listener position set to ($x, $y)")
    }

    /**
     * Set participant position in 2D space
     */
    fun setParticipantPosition(participantId: String, x: Float, y: Float) {
        val position = Position2D(x.coerceIn(-1f, 1f), y.coerceIn(-1f, 1f))
        participantPositions[participantId] = position
        
        if (spatialEnabled) {
            updateSpatialParams(participantId, position)
        }
        
        Timber.d("Participant $participantId position set to ($x, $y)")
    }

    /**
     * Automatically arrange participants in a grid layout
     */
    fun autoArrangeParticipants(participantIds: List<String>) {
        val positions = calculateGridPositions(participantIds.size)
        
        participantIds.forEachIndexed { index, participantId ->
            if (index < positions.size) {
                setParticipantPosition(participantId, positions[index].x, positions[index].y)
            }
        }
        
        Timber.d("Auto-arranged ${participantIds.size} participants")
    }

    /**
     * Update spatial parameters for a single participant
     */
    private fun updateSpatialParams(participantId: String, position: Position2D) {
        // Calculate distance from listener
        val dx = position.x - listenerPosition.x
        val dy = position.y - listenerPosition.y
        val distance = sqrt(dx * dx + dy * dy)

        // Calculate volume based on distance (inverse square law with minimum)
        val volume = if (distance >= MAX_DISTANCE) {
            MIN_VOLUME
        } else {
            val attenuation = 1.0f - (distance / MAX_DISTANCE * DISTANCE_ATTENUATION)
            (attenuation.coerceIn(MIN_VOLUME, 1.0f))
        }

        // Calculate stereo pan (-1.0 to 1.0)
        val pan = dx.coerceIn(-1f, 1f)

        // Store parameters
        val params = SpatialParams(
            position = position,
            volume = volume,
            pan = pan,
            distance = distance
        )
        participantParams[participantId] = params

        // Trigger callback
        onSpatialParamsUpdated?.invoke(participantId, params)
    }

    /**
     * Update spatial params for all participants
     */
    private fun updateAllSpatialParams() {
        participantPositions.forEach { (participantId, position) ->
            updateSpatialParams(participantId, position)
        }
    }

    /**
     * Remove participant from spatial processing
     */
    fun removeParticipant(participantId: String) {
        participantPositions.remove(participantId)
        participantParams.remove(participantId)
        Timber.d("Removed participant $participantId from spatial audio")
    }

    /**
     * Get current spatial parameters for a participant
     */
    fun getSpatialParams(participantId: String): SpatialParams? {
        return participantParams[participantId]
    }

    /**
     * Get all participant positions
     */
    fun getAllPositions(): Map<String, Position2D> {
        return participantPositions.toMap()
    }

    /**
     * Check if spatial audio is enabled
     */
    fun isSpatialEnabled(): Boolean = spatialEnabled

    /**
     * Apply preset audio zone configuration
     */
    fun applyPreset(preset: SpatialPreset, participantIds: List<String>) {
        when (preset) {
            SpatialPreset.CONFERENCE_ROOM -> {
                // Arrange in a U-shape
                val positions = mutableListOf<Position2D>()
                val count = participantIds.size
                
                // Left side
                val leftCount = count / 3
                for (i in 0 until leftCount) {
                    positions.add(Position2D(-0.8f, 0.6f - i * 0.4f))
                }
                
                // Center
                val centerCount = count / 3
                for (i in 0 until centerCount) {
                    positions.add(Position2D(-0.4f + i * 0.4f, -0.8f))
                }
                
                // Right side
                val rightCount = count - leftCount - centerCount
                for (i in 0 until rightCount) {
                    positions.add(Position2D(0.8f, -0.6f + i * 0.4f))
                }
                
                participantIds.forEachIndexed { index, participantId ->
                    if (index < positions.size) {
                        setParticipantPosition(participantId, positions[index].x, positions[index].y)
                    }
                }
            }
            
            SpatialPreset.STAGE -> {
                // Arrange in a line (stage performers)
                val spacing = 1.6f / (participantIds.size + 1)
                participantIds.forEachIndexed { index, participantId ->
                    setParticipantPosition(participantId, -0.8f + spacing * (index + 1), 0.6f)
                }
            }
            
            SpatialPreset.CIRCLE -> {
                // Default circular arrangement
                autoArrangeParticipants(participantIds)
            }
            
            SpatialPreset.AUDIENCE -> {
                // Arrange in rows (audience view)
                val rows = (participantIds.size / 3).coerceAtLeast(1)
                val perRow = (participantIds.size.toFloat() / rows).toInt()
                
                participantIds.forEachIndexed { index, participantId ->
                    val row = index / perRow
                    val col = index % perRow
                    val x = -0.8f + (col * 1.6f / (perRow - 1).coerceAtLeast(1))
                    val y = 0.8f - (row * 0.5f)
                    setParticipantPosition(participantId, x, y)
                }
            }
        }
        
        Timber.d("Applied spatial preset: $preset for ${participantIds.size} participants")
    }

    /**
     * Spatial audio presets
     */
    enum class SpatialPreset {
        CONFERENCE_ROOM,  // U-shaped arrangement
        STAGE,            // Linear stage arrangement
        CIRCLE,           // Circular arrangement
        AUDIENCE          // Audience rows
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        scope.cancel()
        participantPositions.clear()
        participantParams.clear()
        onSpatialParamsUpdated = null
        Timber.d("SpatialAudioProcessor cleaned up")
    }
}
