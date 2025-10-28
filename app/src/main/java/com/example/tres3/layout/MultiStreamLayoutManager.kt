package com.example.tres3.layout

import android.content.Context
import android.graphics.Rect
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.ceil
import kotlin.math.min
import kotlin.math.sqrt

/**
 * MultiStreamLayoutManager - Advanced layout management for multi-party video calls
 * 
 * Features:
 * - Multiple layout modes (Grid, Spotlight, PiP, Sidebar)
 * - Dynamic layout switching based on context
 * - Active speaker detection and highlighting
 * - Screen share optimization
 * - Custom layout configurations
 * - Smooth transitions between layouts
 * 
 * Usage:
 * ```kotlin
 * val layoutManager = MultiStreamLayoutManager(context, room)
 * layoutManager.setLayoutMode(LayoutMode.SPOTLIGHT)
 * layoutManager.addParticipant(participant)
 * val layouts = layoutManager.calculateLayouts(containerWidth, containerHeight)
 * ```
 */
class MultiStreamLayoutManager(
    private val context: Context,
    private val room: Room
) {
    // Layout modes
    enum class LayoutMode {
        GRID,           // Equal-sized grid
        SPOTLIGHT,      // Featured speaker + thumbnails
        PIP,            // Picture-in-picture
        SIDEBAR,        // Main view + sidebar thumbnails
        FILMSTRIP,      // Horizontal strip of participants
        CUSTOM          // User-defined layout
    }

    // Participant layout info
    data class ParticipantLayout(
        val participantId: String,
        val bounds: Rect,
        val isSpotlight: Boolean = false,
        val zIndex: Int = 0,
        val scale: Float = 1.0f,
        val visible: Boolean = true
    )

    // Layout configuration
    data class LayoutConfig(
        val mode: LayoutMode = LayoutMode.GRID,
        val maxVisibleParticipants: Int = 25,
        val aspectRatio: Float = 16f / 9f,
        val spacing: Int = 8,  // pixels
        val spotlightRatio: Float = 0.75f,  // % of screen for spotlight
        val pipPosition: PipPosition = PipPosition.BOTTOM_RIGHT,
        val pipSize: Float = 0.25f  // % of screen
    )

    enum class PipPosition {
        TOP_LEFT,
        TOP_RIGHT,
        BOTTOM_LEFT,
        BOTTOM_RIGHT
    }

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // State
    private var currentMode = LayoutMode.GRID
    private var config = LayoutConfig()
    private val participants = mutableListOf<String>()
    private var spotlightParticipantId: String? = null
    private var screenShareParticipantId: String? = null

    // Cached layouts
    private var cachedLayouts: List<ParticipantLayout> = emptyList()
    private var containerWidth = 0
    private var containerHeight = 0

    // Callbacks
    var onLayoutChanged: ((List<ParticipantLayout>) -> Unit)? = null
    var onSpotlightChanged: ((String?) -> Unit)? = null

    companion object {
        private const val MIN_PARTICIPANT_SIZE = 100  // pixels
        private const val MAX_GRID_SIZE = 5  // 5x5 max
    }

    init {
        Timber.d("MultiStreamLayoutManager initialized")
    }

    /**
     * Set layout mode
     */
    fun setLayoutMode(mode: LayoutMode) {
        if (currentMode == mode) return
        
        currentMode = mode
        Timber.d("Layout mode changed to: $mode")
        
        // Recalculate layouts
        if (containerWidth > 0 && containerHeight > 0) {
            recalculateLayouts()
        }
    }

    /**
     * Get current layout mode
     */
    fun getLayoutMode(): LayoutMode = currentMode

    /**
     * Update layout configuration
     */
    fun updateConfig(newConfig: LayoutConfig) {
        config = newConfig
        currentMode = newConfig.mode
        recalculateLayouts()
        Timber.d("Layout config updated")
    }

    /**
     * Add participant to layout
     */
    fun addParticipant(participantId: String) {
        if (participantId in participants) {
            Timber.w("Participant already exists: $participantId")
            return
        }
        
        participants.add(participantId)
        recalculateLayouts()
        Timber.d("Participant added: $participantId (total: ${participants.size})")
    }

    /**
     * Remove participant from layout
     */
    fun removeParticipant(participantId: String) {
        if (participants.remove(participantId)) {
            if (spotlightParticipantId == participantId) {
                spotlightParticipantId = null
            }
            recalculateLayouts()
            Timber.d("Participant removed: $participantId (total: ${participants.size})")
        }
    }

    /**
     * Set spotlight participant
     */
    fun setSpotlight(participantId: String?) {
        spotlightParticipantId = participantId
        onSpotlightChanged?.invoke(participantId)
        
        // Switch to spotlight mode if not already
        if (participantId != null && currentMode != LayoutMode.SPOTLIGHT) {
            setLayoutMode(LayoutMode.SPOTLIGHT)
        }
        
        recalculateLayouts()
        Timber.d("Spotlight set to: $participantId")
    }

    /**
     * Set screen share participant
     */
    fun setScreenShare(participantId: String?) {
        screenShareParticipantId = participantId
        
        // Auto-switch to spotlight for screen share
        if (participantId != null) {
            setSpotlight(participantId)
        }
        
        Timber.d("Screen share participant: $participantId")
    }

    /**
     * Calculate layouts for current participants
     */
    fun calculateLayouts(width: Int, height: Int): List<ParticipantLayout> {
        containerWidth = width
        containerHeight = height
        
        cachedLayouts = when (currentMode) {
            LayoutMode.GRID -> calculateGridLayout(width, height)
            LayoutMode.SPOTLIGHT -> calculateSpotlightLayout(width, height)
            LayoutMode.PIP -> calculatePipLayout(width, height)
            LayoutMode.SIDEBAR -> calculateSidebarLayout(width, height)
            LayoutMode.FILMSTRIP -> calculateFilmstripLayout(width, height)
            LayoutMode.CUSTOM -> cachedLayouts  // Use existing custom layout
        }
        
        onLayoutChanged?.invoke(cachedLayouts)
        return cachedLayouts
    }

    /**
     * Calculate grid layout (equal-sized tiles)
     */
    private fun calculateGridLayout(width: Int, height: Int): List<ParticipantLayout> {
        val visibleCount = min(participants.size, config.maxVisibleParticipants)
        if (visibleCount == 0) return emptyList()

        // Calculate grid dimensions
        val cols = ceil(sqrt(visibleCount.toDouble())).toInt()
        val rows = ceil(visibleCount.toDouble() / cols).toInt()

        val tileWidth = (width - config.spacing * (cols + 1)) / cols
        val tileHeight = (height - config.spacing * (rows + 1)) / rows

        val layouts = mutableListOf<ParticipantLayout>()

        participants.take(visibleCount).forEachIndexed { index, participantId ->
            val col = index % cols
            val row = index / cols

            val x = config.spacing + col * (tileWidth + config.spacing)
            val y = config.spacing + row * (tileHeight + config.spacing)

            layouts.add(ParticipantLayout(
                participantId = participantId,
                bounds = Rect(x, y, x + tileWidth, y + tileHeight),
                isSpotlight = false,
                zIndex = 0,
                visible = true
            ))
        }

        return layouts
    }

    /**
     * Calculate spotlight layout (featured + thumbnails)
     */
    private fun calculateSpotlightLayout(width: Int, height: Int): List<ParticipantLayout> {
        if (participants.isEmpty()) return emptyList()

        val spotlightId = spotlightParticipantId ?: participants.firstOrNull() ?: return emptyList()
        val others = participants.filter { it != spotlightId }

        val layouts = mutableListOf<ParticipantLayout>()

        // Main spotlight area
        val spotlightWidth = (width * config.spotlightRatio).toInt()
        val spotlightHeight = height - config.spacing * 2

        layouts.add(ParticipantLayout(
            participantId = spotlightId,
            bounds = Rect(
                config.spacing,
                config.spacing,
                spotlightWidth,
                spotlightHeight
            ),
            isSpotlight = true,
            zIndex = 0,
            visible = true
        ))

        // Thumbnail sidebar
        val thumbnailsX = spotlightWidth + config.spacing * 2
        val thumbnailsWidth = width - thumbnailsX - config.spacing
        val thumbnailHeight = 150

        others.take(config.maxVisibleParticipants - 1).forEachIndexed { index, participantId ->
            val y = config.spacing + index * (thumbnailHeight + config.spacing)
            
            if (y + thumbnailHeight <= height - config.spacing) {
                layouts.add(ParticipantLayout(
                    participantId = participantId,
                    bounds = Rect(
                        thumbnailsX,
                        y,
                        thumbnailsX + thumbnailsWidth,
                        y + thumbnailHeight
                    ),
                    isSpotlight = false,
                    zIndex = 1,
                    scale = 0.5f,
                    visible = true
                ))
            }
        }

        return layouts
    }

    /**
     * Calculate picture-in-picture layout
     */
    private fun calculatePipLayout(width: Int, height: Int): List<ParticipantLayout> {
        if (participants.size < 2) return calculateGridLayout(width, height)

        val layouts = mutableListOf<ParticipantLayout>()

        // Main participant (full screen)
        val mainId = spotlightParticipantId ?: participants.first()
        layouts.add(ParticipantLayout(
            participantId = mainId,
            bounds = Rect(0, 0, width, height),
            isSpotlight = true,
            zIndex = 0,
            visible = true
        ))

        // PiP participant
        val pipId = participants.firstOrNull { it != mainId } ?: return layouts
        val pipWidth = (width * config.pipSize).toInt()
        val pipHeight = (pipWidth / config.aspectRatio).toInt()

        val pipBounds = when (config.pipPosition) {
            PipPosition.TOP_LEFT -> Rect(
                config.spacing,
                config.spacing,
                config.spacing + pipWidth,
                config.spacing + pipHeight
            )
            PipPosition.TOP_RIGHT -> Rect(
                width - pipWidth - config.spacing,
                config.spacing,
                width - config.spacing,
                config.spacing + pipHeight
            )
            PipPosition.BOTTOM_LEFT -> Rect(
                config.spacing,
                height - pipHeight - config.spacing,
                config.spacing + pipWidth,
                height - config.spacing
            )
            PipPosition.BOTTOM_RIGHT -> Rect(
                width - pipWidth - config.spacing,
                height - pipHeight - config.spacing,
                width - config.spacing,
                height - config.spacing
            )
        }

        layouts.add(ParticipantLayout(
            participantId = pipId,
            bounds = pipBounds,
            isSpotlight = false,
            zIndex = 10,
            scale = 0.4f,
            visible = true
        ))

        return layouts
    }

    /**
     * Calculate sidebar layout
     */
    private fun calculateSidebarLayout(width: Int, height: Int): List<ParticipantLayout> {
        if (participants.isEmpty()) return emptyList()

        val layouts = mutableListOf<ParticipantLayout>()
        val sidebarWidth = 200
        val mainWidth = width - sidebarWidth - config.spacing * 3

        // Main area
        val mainId = spotlightParticipantId ?: participants.first()
        layouts.add(ParticipantLayout(
            participantId = mainId,
            bounds = Rect(
                config.spacing,
                config.spacing,
                mainWidth,
                height - config.spacing * 2
            ),
            isSpotlight = true,
            zIndex = 0,
            visible = true
        ))

        // Sidebar thumbnails
        val others = participants.filter { it != mainId }
        val thumbnailHeight = 120

        others.forEachIndexed { index, participantId ->
            val y = config.spacing + index * (thumbnailHeight + config.spacing)
            
            if (y + thumbnailHeight <= height - config.spacing) {
                layouts.add(ParticipantLayout(
                    participantId = participantId,
                    bounds = Rect(
                        mainWidth + config.spacing * 2,
                        y,
                        width - config.spacing,
                        y + thumbnailHeight
                    ),
                    isSpotlight = false,
                    zIndex = 1,
                    scale = 0.5f,
                    visible = true
                ))
            }
        }

        return layouts
    }

    /**
     * Calculate filmstrip layout (horizontal strip)
     */
    private fun calculateFilmstripLayout(width: Int, height: Int): List<ParticipantLayout> {
        if (participants.isEmpty()) return emptyList()

        val layouts = mutableListOf<ParticipantLayout>()
        val stripHeight = 150
        val mainHeight = height - stripHeight - config.spacing * 3

        // Main participant
        val mainId = spotlightParticipantId ?: participants.first()
        layouts.add(ParticipantLayout(
            participantId = mainId,
            bounds = Rect(
                config.spacing,
                config.spacing,
                width - config.spacing * 2,
                mainHeight
            ),
            isSpotlight = true,
            zIndex = 0,
            visible = true
        ))

        // Filmstrip at bottom
        val others = participants.filter { it != mainId }
        val thumbnailWidth = 200

        others.forEachIndexed { index, participantId ->
            val x = config.spacing + index * (thumbnailWidth + config.spacing)
            
            if (x + thumbnailWidth <= width - config.spacing) {
                layouts.add(ParticipantLayout(
                    participantId = participantId,
                    bounds = Rect(
                        x,
                        mainHeight + config.spacing * 2,
                        x + thumbnailWidth,
                        height - config.spacing
                    ),
                    isSpotlight = false,
                    zIndex = 1,
                    scale = 0.5f,
                    visible = true
                ))
            }
        }

        return layouts
    }

    /**
     * Recalculate layouts with current container size
     */
    private fun recalculateLayouts() {
        if (containerWidth > 0 && containerHeight > 0) {
            calculateLayouts(containerWidth, containerHeight)
        }
    }

    /**
     * Get all participants
     */
    fun getParticipants(): List<String> = participants.toList()

    /**
     * Get cached layouts
     */
    fun getCachedLayouts(): List<ParticipantLayout> = cachedLayouts

    /**
     * Clean up resources
     */
    fun cleanup() {
        scope.cancel()
        participants.clear()
        cachedLayouts = emptyList()
        onLayoutChanged = null
        onSpotlightChanged = null
        Timber.d("MultiStreamLayoutManager cleaned up")
    }
}
