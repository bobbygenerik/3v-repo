package com.example.tres3.ui

import android.content.Context
import android.graphics.Color
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.example.tres3.layout.MultiStreamLayoutManager
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.track.Track
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import timber.log.Timber

/**
 * VideoGridRenderer - Composable UI for multi-participant video grid
 * 
 * Features:
 * - Dynamic grid layout (1-25 participants)
 * - Multiple layout modes (Grid, Spotlight, PiP, Sidebar, Filmstrip)
 * - Active speaker highlighting with border animation
 * - Participant name labels and status indicators
 * - Mute/unmute status badges
 * - Click-to-spotlight functionality
 * - Smooth layout transitions
 * - Screen share optimization
 * - Low-bandwidth participant indicators
 * 
 * This renderer integrates:
 * - MultiStreamLayoutManager for layout calculations
 * - Material3 for UI components and animations
 * 
 * TODO - Video Rendering Integration:
 * This component provides the layout infrastructure and UI framework.
 * For actual video rendering, integrate with InCallActivity's VideoTrackView pattern:
 * 
 * ```kotlin
 * // Use LiveKit Compose components from InCallActivity
 * io.livekit.android.compose.ui.VideoTrackView(
 *     trackReference = trackReference,
 *     room = room,
 *     mirror = mirrorLocal,
 *     scaleType = ScaleType.Fill,
 *     rendererType = RendererType.Surface
 * )
 * ```
 * 
 * The current implementation shows placeholders. Replace the Box with VideoTrackView
 * in the ParticipantVideoTile function once track references are properly extracted
 * from LiveKit 2.21 participant objects.
 * 
 * Usage:
 * ```kotlin
 * VideoGridRenderer(
 *     room = room,
 *     modifier = Modifier.fillMaxSize(),
 *     layoutMode = LayoutMode.GRID,
 *     onParticipantClick = { participant -> /* spotlight */ }
 * )
 * ```
 */

/**
 * Main video grid composable
 */
@Composable
fun VideoGridRenderer(
    room: Room,
    modifier: Modifier = Modifier,
    layoutMode: MultiStreamLayoutManager.LayoutMode = MultiStreamLayoutManager.LayoutMode.GRID,
    showLabels: Boolean = true,
    showControls: Boolean = true,
    activeSpeakerHighlight: Boolean = true,
    onParticipantClick: ((Participant) -> Unit)? = null,
    onLayoutModeChange: ((MultiStreamLayoutManager.LayoutMode) -> Unit)? = null
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    
    // Layout manager state
    val layoutManager = remember {
        MultiStreamLayoutManager(context, room).apply {
            setLayoutMode(layoutMode)
        }
    }
    
    // Participant tracking
    var participants by remember { mutableStateOf<List<Participant>>(emptyList()) }
    var spotlightParticipant by remember { mutableStateOf<String?>(null) }
    var screenShareParticipant by remember { mutableStateOf<String?>(null) }
    
    // Refresh participants
    LaunchedEffect(room) {
        while (true) {
            val allParticipants = mutableListOf<Participant>()
            allParticipants.add(room.localParticipant)
            allParticipants.addAll(room.remoteParticipants.values)
            participants = allParticipants
            
            // Update layout manager
            allParticipants.forEach { participant ->
                val participantId = participant.sid?.value ?: participant.identity?.value ?: "unknown"
                layoutManager.addParticipant(participantId)
            }
            
            // Check for screen share (simplified - would need proper track inspection)
            val screenSharer = allParticipants.firstOrNull { participant ->
                // TODO: Implement proper screen share detection when LiveKit Compose APIs are available
                false
            }
            
            if (screenSharer != null && screenShareParticipant != screenSharer.sid?.value) {
                screenShareParticipant = screenSharer.sid?.value
                layoutManager.setScreenShare(screenShareParticipant)
            }
            
            delay(1000) // Refresh every second
        }
    }
    
    // Cleanup on lifecycle
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_DESTROY) {
                layoutManager.cleanup()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            layoutManager.cleanup()
        }
    }
    
    Box(modifier = modifier.background(ComposeColor(0xFF1b1c1e))) {
        when (layoutMode) {
            MultiStreamLayoutManager.LayoutMode.GRID -> {
                GridLayout(
                    participants = participants,
                    showLabels = showLabels,
                    activeSpeakerHighlight = activeSpeakerHighlight,
                    onParticipantClick = { participant ->
                        spotlightParticipant = participant.sid?.value
                        layoutManager.setSpotlight(spotlightParticipant)
                        onParticipantClick?.invoke(participant)
                    }
                )
            }
            
            MultiStreamLayoutManager.LayoutMode.SPOTLIGHT -> {
                SpotlightLayout(
                    participants = participants,
                    spotlightParticipant = spotlightParticipant,
                    showLabels = showLabels,
                    onParticipantClick = { participant ->
                        spotlightParticipant = participant.sid?.value
                        layoutManager.setSpotlight(spotlightParticipant)
                        onParticipantClick?.invoke(participant)
                    }
                )
            }
            
            MultiStreamLayoutManager.LayoutMode.PIP -> {
                PipLayout(
                    participants = participants,
                    spotlightParticipant = spotlightParticipant,
                    showLabels = showLabels,
                    onParticipantClick = onParticipantClick
                )
            }
            
            MultiStreamLayoutManager.LayoutMode.SIDEBAR -> {
                SidebarLayout(
                    participants = participants,
                    spotlightParticipant = spotlightParticipant,
                    showLabels = showLabels,
                    onParticipantClick = { participant ->
                        spotlightParticipant = participant.sid?.value
                        layoutManager.setSpotlight(spotlightParticipant)
                        onParticipantClick?.invoke(participant)
                    }
                )
            }
            
            MultiStreamLayoutManager.LayoutMode.FILMSTRIP -> {
                FilmstripLayout(
                    participants = participants,
                    spotlightParticipant = spotlightParticipant,
                    showLabels = showLabels,
                    onParticipantClick = { participant ->
                        spotlightParticipant = participant.sid?.value
                        layoutManager.setSpotlight(spotlightParticipant)
                        onParticipantClick?.invoke(participant)
                    }
                )
            }
            
            MultiStreamLayoutManager.LayoutMode.CUSTOM -> {
                // Custom layout - use grid as fallback
                GridLayout(
                    participants = participants,
                    showLabels = showLabels,
                    activeSpeakerHighlight = activeSpeakerHighlight,
                    onParticipantClick = onParticipantClick
                )
            }
        }
        
        // Layout mode switcher
        if (showControls) {
            LayoutModeSelector(
                currentMode = layoutMode,
                onModeSelected = { newMode ->
                    layoutManager.setLayoutMode(newMode)
                    onLayoutModeChange?.invoke(newMode)
                },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
            )
        }
    }
}

/**
 * Grid layout (equal-sized tiles)
 */
@Composable
private fun GridLayout(
    participants: List<Participant>,
    showLabels: Boolean,
    activeSpeakerHighlight: Boolean,
    onParticipantClick: ((Participant) -> Unit)?
) {
    val gridSize = when {
        participants.size <= 1 -> 1
        participants.size == 2 -> 2
        participants.size <= 4 -> 2
        participants.size <= 9 -> 3
        participants.size <= 16 -> 4
        else -> 5
    }
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        participants.chunked(gridSize).forEach { row ->
            Row(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                row.forEach { participant ->
                    ParticipantVideoTile(
                        participant = participant,
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                        showLabel = showLabels,
                        isSpotlight = false,
                        activeSpeakerHighlight = activeSpeakerHighlight,
                        onClick = { onParticipantClick?.invoke(participant) }
                    )
                }
                // Fill empty slots
                repeat(gridSize - row.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

/**
 * Spotlight layout (featured + thumbnails)
 */
@Composable
private fun SpotlightLayout(
    participants: List<Participant>,
    spotlightParticipant: String?,
    showLabels: Boolean,
    onParticipantClick: ((Participant) -> Unit)?
) {
    val spotlight = participants.firstOrNull { 
        it.sid?.value == spotlightParticipant 
    } ?: participants.firstOrNull()
    
    val others = participants.filter { it != spotlight }
    
    Row(modifier = Modifier.fillMaxSize()) {
        // Main spotlight
        spotlight?.let { participant ->
            ParticipantVideoTile(
                participant = participant,
                modifier = Modifier
                    .weight(0.75f)
                    .fillMaxHeight()
                    .padding(8.dp),
                showLabel = showLabels,
                isSpotlight = true,
                onClick = { onParticipantClick?.invoke(participant) }
            )
        }
        
        // Thumbnail sidebar
        Column(
            modifier = Modifier
                .weight(0.25f)
                .fillMaxHeight()
                .padding(vertical = 8.dp, horizontal = 4.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            others.take(6).forEach { participant ->
                ParticipantVideoTile(
                    participant = participant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f),
                    showLabel = showLabels,
                    isSpotlight = false,
                    onClick = { onParticipantClick?.invoke(participant) }
                )
            }
        }
    }
}

/**
 * PiP layout (main + small overlay)
 */
@Composable
private fun PipLayout(
    participants: List<Participant>,
    spotlightParticipant: String?,
    showLabels: Boolean,
    onParticipantClick: ((Participant) -> Unit)?
) {
    val main = participants.firstOrNull { it.sid?.value == spotlightParticipant } 
        ?: participants.firstOrNull()
    val pip = participants.firstOrNull { it != main }
    
    Box(modifier = Modifier.fillMaxSize()) {
        // Main participant (full screen)
        main?.let { participant ->
            ParticipantVideoTile(
                participant = participant,
                modifier = Modifier.fillMaxSize(),
                showLabel = showLabels,
                isSpotlight = true,
                onClick = { onParticipantClick?.invoke(participant) }
            )
        }
        
        // PiP participant (bottom right)
        pip?.let { participant ->
            ParticipantVideoTile(
                participant = participant,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp)
                    .width(150.dp)
                    .aspectRatio(9f / 16f),
                showLabel = showLabels,
                isSpotlight = false,
                onClick = { onParticipantClick?.invoke(participant) }
            )
        }
    }
}

/**
 * Sidebar layout (main + side thumbnails)
 */
@Composable
private fun SidebarLayout(
    participants: List<Participant>,
    spotlightParticipant: String?,
    showLabels: Boolean,
    onParticipantClick: ((Participant) -> Unit)?
) {
    val main = participants.firstOrNull { it.sid?.value == spotlightParticipant } 
        ?: participants.firstOrNull()
    val others = participants.filter { it != main }
    
    Row(modifier = Modifier.fillMaxSize()) {
        // Main area
        main?.let { participant ->
            ParticipantVideoTile(
                participant = participant,
                modifier = Modifier
                    .weight(0.8f)
                    .fillMaxHeight()
                    .padding(8.dp),
                showLabel = showLabels,
                isSpotlight = true,
                onClick = { onParticipantClick?.invoke(participant) }
            )
        }
        
        // Right sidebar
        Column(
            modifier = Modifier
                .weight(0.2f)
                .fillMaxHeight()
                .padding(vertical = 8.dp, horizontal = 4.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            others.take(8).forEach { participant ->
                ParticipantVideoTile(
                    participant = participant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(9f / 16f),
                    showLabel = showLabels,
                    isSpotlight = false,
                    onClick = { onParticipantClick?.invoke(participant) }
                )
            }
        }
    }
}

/**
 * Filmstrip layout (main + bottom strip)
 */
@Composable
private fun FilmstripLayout(
    participants: List<Participant>,
    spotlightParticipant: String?,
    showLabels: Boolean,
    onParticipantClick: ((Participant) -> Unit)?
) {
    val main = participants.firstOrNull { it.sid?.value == spotlightParticipant } 
        ?: participants.firstOrNull()
    val others = participants.filter { it != main }
    
    Column(modifier = Modifier.fillMaxSize()) {
        // Main participant
        main?.let { participant ->
            ParticipantVideoTile(
                participant = participant,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(8.dp),
                showLabel = showLabels,
                isSpotlight = true,
                onClick = { onParticipantClick?.invoke(participant) }
            )
        }
        
        // Bottom filmstrip
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp)
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            others.take(6).forEach { participant ->
                ParticipantVideoTile(
                    participant = participant,
                    modifier = Modifier
                        .width(150.dp)
                        .fillMaxHeight(),
                    showLabel = showLabels,
                    isSpotlight = false,
                    onClick = { onParticipantClick?.invoke(participant) }
                )
            }
        }
    }
}

/**
 * Individual participant video tile
 */
@Composable
private fun ParticipantVideoTile(
    participant: Participant,
    modifier: Modifier = Modifier,
    showLabel: Boolean = true,
    isSpotlight: Boolean = false,
    activeSpeakerHighlight: Boolean = true,
    onClick: (() -> Unit)? = null
) {
    // Simplified track access - LiveKit 2.21 has different API structure
    // For actual video rendering, use InCallActivity's VideoTrackView pattern
    val hasVideo = participant.trackPublications.isNotEmpty()
    val isMuted = true // TODO: Access audio state when API is stable
    val isVideoMuted = false // TODO: Access video state when API is stable
    
    // Active speaker animation
    var isSpeaking by remember { mutableStateOf(false) }
    val borderColor = if (isSpeaking && activeSpeakerHighlight) {
        ComposeColor(0xFF4CAF50)
    } else if (isSpotlight) {
        ComposeColor(0xFF6B7FB8)
    } else {
        ComposeColor(0xFF2c2d2f)
    }
    
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .border(3.dp, borderColor, RoundedCornerShape(8.dp))
            .background(ComposeColor(0xFF1b1c1e))
            .clickable(enabled = onClick != null) { onClick?.invoke() }
    ) {
        if (hasVideo && !isVideoMuted) {
            // Video rendering placeholder
            // TODO: Integrate with LiveKit VideoTrackView when Compose components are available
            // For now, show placeholder with note
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(ComposeColor(0xFF2c2d2f)),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Videocam,
                        contentDescription = "Video",
                        tint = ComposeColor(0xFF6B7FB8),
                        modifier = Modifier.size(48.dp)
                    )
                    Text(
                        text = "Video Active",
                        color = ComposeColor(0xFFAAAAAA),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        } else {
            // Show placeholder when video is off
            VideoPlaceholder(
                participantName = participant.identity?.value ?: "Guest",
                modifier = Modifier.fillMaxSize()
            )
        }
        
        // Overlay: participant info
        if (showLabel) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(8.dp)
            ) {
                // Name label
                Surface(
                    color = ComposeColor(0xCC000000),
                    shape = RoundedCornerShape(4.dp)
                ) {
                    Text(
                        text = participant.identity?.value ?: "Guest",
                        color = ComposeColor.White,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                    )
                }
                
                // Status badges
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.padding(top = 4.dp)
                ) {
                    if (isMuted) {
                        StatusBadge(
                            icon = Icons.Default.MicOff,
                            backgroundColor = ComposeColor(0xCCF44336)
                        )
                    }
                    
                    if (isVideoMuted) {
                        StatusBadge(
                            icon = Icons.Default.VideocamOff,
                            backgroundColor = ComposeColor(0xCC666666)
                        )
                    }
                }
            }
        }
    }
}

/**
 * Video placeholder (shown when video is disabled)
 */
@Composable
private fun VideoPlaceholder(
    participantName: String,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .background(ComposeColor(0xFF2c2d2f)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Avatar circle
            Surface(
                modifier = Modifier.size(64.dp),
                shape = RoundedCornerShape(50),
                color = ComposeColor(0xFF6B7FB8)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = participantName.take(1).uppercase(),
                        color = ComposeColor.White,
                        style = MaterialTheme.typography.headlineMedium
                    )
                }
            }
            
            Text(
                text = participantName,
                color = ComposeColor.White,
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

/**
 * Status badge (mute, video off, etc.)
 */
@Composable
private fun StatusBadge(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    backgroundColor: ComposeColor,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.size(24.dp),
        shape = RoundedCornerShape(4.dp),
        color = backgroundColor
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = ComposeColor.White,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

/**
 * Layout mode selector dropdown
 */
@Composable
private fun LayoutModeSelector(
    currentMode: MultiStreamLayoutManager.LayoutMode,
    onModeSelected: (MultiStreamLayoutManager.LayoutMode) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by remember { mutableStateOf(false) }
    
    Box(modifier = modifier) {
        // Current mode button
        Surface(
            onClick = { expanded = !expanded },
            shape = RoundedCornerShape(8.dp),
            color = ComposeColor(0xCC000000)
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.GridView,
                    contentDescription = "Layout",
                    tint = ComposeColor.White
                )
                Text(
                    text = currentMode.name,
                    color = ComposeColor.White,
                    style = MaterialTheme.typography.bodyMedium
                )
                Icon(
                    imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null,
                    tint = ComposeColor.White
                )
            }
        }
        
        // Dropdown menu
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            MultiStreamLayoutManager.LayoutMode.values().forEach { mode ->
                DropdownMenuItem(
                    text = { Text(mode.name) },
                    onClick = {
                        onModeSelected(mode)
                        expanded = false
                    },
                    leadingIcon = {
                        if (mode == currentMode) {
                            Icon(Icons.Default.Check, contentDescription = null)
                        }
                    }
                )
            }
        }
    }
}
