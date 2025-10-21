package com.example.tres3

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.zIndex
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.border
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import io.livekit.android.compose.state.rememberTracks
import io.livekit.android.room.Room
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.LocalVideoTrack
import io.livekit.android.room.track.LocalTrackPublication
import io.livekit.android.room.participant.LocalParticipant
import io.livekit.android.util.LoggingLevel
import kotlinx.coroutines.launch
import livekit.org.webrtc.EglBase
import android.util.Log
import io.livekit.android.compose.types.TrackReference
import io.livekit.android.compose.local.RoomLocal
import io.livekit.android.compose.state.rememberParticipantTrackReferences
import io.livekit.android.compose.ui.RendererType
import io.livekit.android.compose.ui.ScaleType
import livekit.org.webrtc.PeerConnectionFactory
import androidx.compose.ui.unit.Dp
import kotlin.time.Duration.Companion.seconds

class InCallActivity : ComponentActivity() {
    private lateinit var room: Room
    private var isIntentionallyClosing = false  // Track if we're intentionally disconnecting
    
    companion object {
        // Shared EglBase context for video rendering
        private val eglBase: EglBase by lazy { EglBase.create() }
        fun getEglBaseContext(): EglBase.Context = eglBase.eglBaseContext
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        Log.d("InCallActivity", "🎬 InCallActivity onCreate - starting")
        
        // Start foreground service to prevent battery optimization from freezing the app
        val recipientName = intent.getStringExtra("recipient_name") ?: "Unknown"
        CallForegroundService.start(this, recipientName)
        Log.d("InCallActivity", "🔔 Started foreground service")
        
        // Make full screen - draw content behind system bars
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        // Enable drawing behind system bars
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        
        val windowInsetsController = WindowInsetsControllerCompat(window, window.decorView)
        
        // Make status bar background transparent (video shows through)
        // But keep the icons visible
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        
        // Keep status bar icons visible but hide navigation bar
        windowInsetsController.show(WindowInsetsCompat.Type.statusBars())
        windowInsetsController.hide(WindowInsetsCompat.Type.navigationBars())
        
        // Make status bar icons WHITE (visible over video)
        windowInsetsController.isAppearanceLightStatusBars = false
        
        // Set immersive mode for navigation bar - swipe shows it temporarily
        windowInsetsController.systemBarsBehavior = 
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        
        // Keep screen on during call
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Initialize LiveKit with proper logging
        io.livekit.android.LiveKit.loggingLevel = LoggingLevel.DEBUG
        
        // --- CRITICAL FIX: Grab Room from Singleton ---
        room = LiveKitManager.currentRoom ?: run {
            Log.e("InCallActivity", "CRITICAL: LiveKit Room was not found in singleton.")
            finish()
            return
        }
        // --- END FIX ---
        
        val recipientEmail = intent.getStringExtra("recipient_email") ?: ""
        
        Log.d("InCallActivity", "🎬 InCallActivity ready - recipient: $recipientName")
        
        setupContent(recipientName, recipientEmail)
    }
    
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        Log.d("InCallActivity", "🔄 onNewIntent - New call starting on existing activity")
        
        // Update the intent
        setIntent(intent)
        
        // Get the new room
        room = LiveKitManager.currentRoom ?: run {
            Log.e("InCallActivity", "CRITICAL: No room found in onNewIntent")
            finish()
            return
        }
        
        val recipientName = intent?.getStringExtra("recipient_name") ?: "Unknown"
        val recipientEmail = intent?.getStringExtra("recipient_email") ?: ""
        
        Log.d("InCallActivity", "🔄 onNewIntent - Setting up new call with: $recipientName")
        
        // Reset the closing flag
        isIntentionallyClosing = false
        
        // Recreate the UI with the new room
        setupContent(recipientName, recipientEmail)
    }
    
    private fun setupContent(recipientName: String, recipientEmail: String) {
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    surface = Color.Black,
                    background = Color.Black
                )
            ) {
                // Black surface to ensure no transparency
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = Color.Black
                ) {
                    // The CompositionLocalProvider makes the room available to all children
                    CompositionLocalProvider(
                        RoomLocal provides room
                    ) {
                        InCallScreen(
                            recipientName = recipientName,
                            recipientEmail = recipientEmail,
                            onDisconnect = {
                                // Set flag BEFORE disconnecting to prevent crash
                                isIntentionallyClosing = true
                                Log.d("InCallActivity", "🔚 Intentionally closing - starting disconnect")
                                
                                lifecycleScope.launch {
                                    try {
                                        LiveKitManager.disconnectSpecificRoom(room)
                                        Log.d("InCallActivity", "✓ Room disconnected successfully")
                                    } catch (e: Exception) {
                                        Log.e("InCallActivity", "Error during room cleanup: ${e.message}", e)
                                    }

                                    val homeIntent = Intent(this@InCallActivity, HomeActivity::class.java).apply {
                                        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                                    }
                                    startActivity(homeIntent)
                                    finishAffinity() // Properly close activity without jarring flash
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d("InCallActivity", "💀 InCallActivity onDestroy - cleaning up")
        
        // Stop foreground service
        CallForegroundService.stop(this)
        Log.d("InCallActivity", "🔕 Stopped foreground service")
        
        // Only disconnect if NOT intentionally closing (which already disconnected)
        if (!isIntentionallyClosing) {
            lifecycleScope.launch {
                try {
                    val activeRoom = when {
                        ::room.isInitialized -> room
                        else -> LiveKitManager.currentRoom
                    }

                    if (activeRoom != null) {
                        Log.d("InCallActivity", "🔌 Disconnecting room in onDestroy")

                        try {
                            activeRoom.localParticipant.setCameraEnabled(false)
                            activeRoom.localParticipant.setMicrophoneEnabled(false)
                        } catch (e: Exception) {
                            Log.e("InCallActivity", "Error disabling media during onDestroy: ${e.message}", e)
                        }

                        LiveKitManager.disconnectSpecificRoom(activeRoom)
                    }
                } catch (e: Exception) {
                    Log.e("InCallActivity", "Error disconnecting in onDestroy: ${e.message}", e)
                }
            }
        } else {
            Log.d("InCallActivity", "✓ Skipping disconnect - already done intentionally")
        }
    }
    
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        Log.d("InCallActivity", "🪟 Window focus changed: hasFocus=$hasFocus, isIntentionallyClosing=$isIntentionallyClosing")
        if (hasFocus) {
            Log.d("InCallActivity", "✅ InCallActivity HAS window focus - video should be visible")
        } else {
            // Avoid aggressive relaunching to reduce instability; just log.
            Log.d("InCallActivity", "Focus lost (isFinishing=$isFinishing). Not forcing relaunch.")
        }
    }
    
    override fun onResume() {
        super.onResume()
        Log.d("InCallActivity", "▶️ InCallActivity onResume - FORCING camera enabled")
        // Force camera enabled every time we resume
        if (::room.isInitialized) {
            lifecycleScope.launch {
                room.localParticipant.setCameraEnabled(true)
            }
        }
    }
    
    override fun onPause() {
        super.onPause()
        Log.w("InCallActivity", "⏸️ InCallActivity onPause - activity going to background!")
    }
    
    override fun onStop() {
        super.onStop()
        Log.e("InCallActivity", "⏹️ InCallActivity onStop - activity no longer visible!")
    }
}

// Data classes for animation values
data class AnimationValues(val offsetY: Dp, val alpha: Float)
data class SpringAnimationValues(val offsetX: Dp, val alpha: Float, val scale: Float)

// Custom Composable for Staggered Animation Logic
@Composable
fun rememberAnimatedButton(show: Boolean, index: Int, totalButtons: Int = 5): AnimationValues {
    val targetY = if (show) 0.dp else 150.dp
    val targetAlpha = if (show) 1f else 0f
    
    // Animate Y offset - Menu (index 0) is ALWAYS first for both appearing and disappearing
    val offsetY by animateDpAsState(
        targetValue = targetY,
        animationSpec = tween(300, delayMillis = index * 80, easing = FastOutSlowInEasing),
        label = "offsetY$index"
    )

    // Animate Alpha - Menu (index 0) is ALWAYS first for both appearing and disappearing
    val alpha by animateFloatAsState(
        targetValue = targetAlpha,
        animationSpec = tween(300, delayMillis = index * 80, easing = FastOutSlowInEasing),
        label = "alpha$index"
    )
    
    return AnimationValues(offsetY, alpha)
}

// Cascading slide-up animation for Landscape Side Rail
@Composable
fun rememberAnimatedButtonSpring(show: Boolean, index: Int): SpringAnimationValues {
    val targetY = if (show) 0.dp else 150.dp // Slide up from bottom
    val targetAlpha = if (show) 1f else 0f
    val targetScale = if (show) 1f else 0.8f
    
    // Cascading delay - each button animates slightly after the previous one
    val cascadeDelay = index * 70 // 70ms between each button
    
    // Animate Y offset with cascading timing
    val offsetY by animateDpAsState(
        targetValue = targetY,
        animationSpec = tween(
            durationMillis = 400,
            delayMillis = cascadeDelay,
            easing = FastOutSlowInEasing
        ),
        label = "offsetY$index"
    )

    // Animate Alpha with cascading timing
    val alpha by animateFloatAsState(
        targetValue = targetAlpha,
        animationSpec = tween(
            durationMillis = 350,
            delayMillis = cascadeDelay,
            easing = LinearOutSlowInEasing
        ),
        label = "alpha$index"
    )
    
    // Animate Scale with cascade effect
    val scale by animateFloatAsState(
        targetValue = targetScale,
        animationSpec = tween(
            durationMillis = 450,
            delayMillis = cascadeDelay,
            easing = FastOutSlowInEasing
        ),
        label = "scale$index"
    )
    
    // Return Y offset instead of X for vertical animation
    return SpringAnimationValues(offsetY, alpha, scale)
}

@Composable
fun ParticipantItem(
    trackReference: io.livekit.android.compose.types.TrackReference,
    isLocal: Boolean
) {
    val participant = trackReference.participant
    val hasVideo = trackReference.publication?.track != null
    val hasAudio = participant.isMicrophoneEnabled
    
    // Use participant.name (set in LiveKit token) instead of identity (Firebase UID)
    val displayName = participant.name?.takeIf { it.isNotBlank() } 
        ?: participant.identity?.value 
        ?: "Unknown"
    val initial = displayName.firstOrNull()?.uppercase() ?: "?"
    
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.1f))
            .padding(12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Avatar/Initial
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(AppColors.PrimaryBlue),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = initial,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            }
            
            // Name and status
            Column {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = displayName,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White
                    )
                    if (isLocal) {
                        Text(
                            text = "(You)",
                            fontSize = 12.sp,
                            color = Color.White.copy(alpha = 0.7f)
                        )
                    }
                }
                Text(
                    text = if (hasVideo && hasAudio) "Active" 
                           else if (hasAudio) "Audio only" 
                           else "Muted",
                    fontSize = 12.sp,
                    color = if (hasVideo && hasAudio) Color.Green else Color.White.copy(alpha = 0.6f)
                )
            }
        }
        
        // Status indicators
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = if (hasAudio) Icons.Default.Mic else Icons.Default.MicOff,
                contentDescription = if (hasAudio) "Mic on" else "Mic off",
                tint = if (hasAudio) Color.White else Color.Red,
                modifier = Modifier.size(20.dp)
            )
            Icon(
                imageVector = if (hasVideo) Icons.Default.Videocam else Icons.Default.VideocamOff,
                contentDescription = if (hasVideo) "Camera on" else "Camera off",
                tint = if (hasVideo) Color.White else Color.Red,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
fun AddPersonDialog(
    onDismiss: () -> Unit,
    onInvite: (String) -> Unit
) {
    var emailInput by remember { mutableStateOf("") }
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.85f)) // More opaque backdrop
            .pointerInput(Unit) {
                detectTapGestures(onTap = { onDismiss() })
            },
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth(0.9f)
                .clip(RoundedCornerShape(20.dp)) // Slightly less rounded
                .background(Color(0xFF1A1A1A)) // Fully opaque dark background
                .padding(24.dp) // Reduced padding
                .pointerInput(Unit) {
                    detectTapGestures(onTap = { /* Consume tap */ })
                }
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Add Person to Call",
                    fontSize = 20.sp, // Smaller title
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
                IconButton(onClick = onDismiss) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Close",
                        tint = Color.White.copy(alpha = 0.8f),
                        modifier = Modifier.size(24.dp)
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // User input (supports email, phone, or username)
            OutlinedTextField(
                value = emailInput,
                onValueChange = { emailInput = it },
                label = { Text("User", color = Color.White.copy(alpha = 0.6f)) },
                placeholder = { Text("Email, phone, or username", color = Color.White.copy(alpha = 0.4f)) },
                modifier = Modifier.fillMaxWidth(),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    focusedBorderColor = Color(0xFF67B5FF), // Modern blue
                    unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                    cursorColor = Color(0xFF67B5FF),
                    focusedContainerColor = Color(0xFF252525),
                    unfocusedContainerColor = Color(0xFF252525)
                ),
                singleLine = true,
                shape = RoundedCornerShape(12.dp) // Rounded input field
            )
            
            Spacer(modifier = Modifier.height(20.dp))
            
            // Action buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.padding(end = 8.dp)
                ) {
                    Text(
                        "Cancel", 
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 15.sp
                    )
                }
                
                Button(
                    onClick = {
                        Log.d("AddPersonDialog", "Invite button clicked, input: '$emailInput'")
                        if (emailInput.isNotBlank()) {
                            Log.d("AddPersonDialog", "Calling onInvite with: '${emailInput.trim()}'")
                            onInvite(emailInput.trim())
                        } else {
                            Log.w("AddPersonDialog", "Email input is blank, not calling onInvite")
                        }
                    },
                    enabled = emailInput.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFF67B5FF),
                        contentColor = Color.White,
                        disabledContainerColor = Color(0xFF67B5FF).copy(alpha = 0.3f)
                    ),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.height(44.dp).widthIn(min = 110.dp)
                ) {
                    Text("Invite", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
fun InfiniteRotatingIcon() {
    val infiniteTransition = rememberInfiniteTransition(label = "rotation")
    val rotation by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "rotation"
    )
    
    Icon(
        imageVector = Icons.Default.Sync,
        contentDescription = "Connecting",
        modifier = Modifier
            .size(80.dp)
            .rotate(rotation),
        tint = Color(0xFF67B5FF) // Using a light blue color, assuming AppColors.PrimaryBlue is something similar
    )
}

@Composable
fun CallVideoTrackView(
    trackReference: io.livekit.android.compose.types.TrackReference,
    modifier: Modifier = Modifier,
    isOverlay: Boolean = false
) {
    val room = RoomLocal.current
    val participant = trackReference.participant
    val mirrorLocal = participant is LocalParticipant
    val rendererType = if (isOverlay) RendererType.Texture else RendererType.Surface
    val scaleType = ScaleType.Fill // Always fill to avoid black bars

    io.livekit.android.compose.ui.VideoTrackView(
        trackReference = trackReference,
        modifier = modifier,
        room = room,
        mirror = mirrorLocal,
        scaleType = scaleType,
        rendererType = rendererType
    )
}

fun formatDuration(seconds: Int): String {
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    val secs = seconds % 60
    
    return if (hours > 0) {
        String.format("%d:%02d:%02d", hours, minutes, secs)
    } else {
        String.format("%02d:%02d", minutes, secs)
    }
}

@Composable
fun InCallScreen(
    recipientName: String,
    recipientEmail: String,
    onDisconnect: () -> Unit
) {
    // Retrieve Room object using RoomLocal.current
    val room = RoomLocal.current 
    val context = androidx.compose.ui.platform.LocalContext.current
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    
    // Detect orientation
    val isLandscape = configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    
    var isMicEnabled by remember { mutableStateOf(room.localParticipant.isMicrophoneEnabled) }
    var isCameraEnabled by remember { mutableStateOf(room.localParticipant.isCameraEnabled) }
    var showMenu by remember { mutableStateOf(false) }
    var showControls by remember { mutableStateOf(true) }
    var callDuration by remember { mutableStateOf(0) }
    var showParticipantsList by remember { mutableStateOf(false) }
    var isScreenSharing by remember { mutableStateOf(false) }
    var showAddPersonDialog by remember { mutableStateOf(false) }
    var isVideoSwapped by remember { mutableStateOf(false) }
    var isLocalVideoEnlarged by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    
    // Get all video tracks from the room (both local and remote)
    val allTracks = rememberTracks()
    
    // Separate local and remote tracks using rememberTracks (which is already observable)
    val localTrack by remember {
        derivedStateOf {
            allTracks.find { (participant, publication) ->
                participant is LocalParticipant && 
                publication?.source == Track.Source.CAMERA &&
                publication?.kind == Track.Kind.VIDEO
            }?.let { (participant, publication) ->
                publication?.let {
                    io.livekit.android.compose.types.TrackReference(
                        participant = participant,
                        publication = it,
                        source = Track.Source.CAMERA
                    )
                }
            }
        }
    }
    
    val remoteTracks by remember {
        derivedStateOf {
            allTracks.filter { (participant, publication) ->
                participant !is LocalParticipant &&
                publication?.source == Track.Source.CAMERA && 
                publication?.kind == Track.Kind.VIDEO
            }.mapNotNull { (participant, publication) ->
                publication?.let {
                    io.livekit.android.compose.types.TrackReference(
                        participant = participant,
                        publication = it,
                        source = Track.Source.CAMERA
                    )
                }
            }
        }
    }
    
    // Combined track references for participants list
    val trackReferences by remember {
        derivedStateOf {
            listOfNotNull(localTrack) + remoteTracks
        }
    }

    // Timer for call duration
    LaunchedEffect(Unit) {
        // FORCE camera to be enabled at start
        room.localParticipant.setCameraEnabled(true)
        Log.d("InCallActivity", "🎥 FORCED camera enabled at launch")
        
        while (true) {
            kotlinx.coroutines.delay(1000)
            callDuration++
        }
    }
    
    // Monitor remote participants - end call if all leave
    LaunchedEffect(remoteTracks.size) {
        // Give a grace period after call starts before checking
        kotlinx.coroutines.delay(3000)
        
        // Check if we ever had a remote participant
        val hadRemoteParticipants = remoteTracks.isNotEmpty()
        
        if (hadRemoteParticipants) {
            Log.d("InCallActivity", "📊 Monitoring remote participants: ${remoteTracks.size}")
        }
        
        // Monitor for participant leaving
        if (hadRemoteParticipants && remoteTracks.isEmpty()) {
            Log.w("InCallActivity", "👋 All remote participants left - ending call")
            kotlinx.coroutines.delay(2000) // Brief delay to show disconnection
            onDisconnect()
        }
    }

    // Debug logging
    LaunchedEffect(localTrack, remoteTracks.size) {
        Log.d("InCallActivity", "=== Track Debug ===")
        Log.d("InCallActivity", "Camera enabled: ${room.localParticipant.isCameraEnabled}")
        Log.d("InCallActivity", "All tracks count: ${allTracks.size}")
        Log.d("InCallActivity", "Local track: ${if (localTrack != null) "EXISTS" else "NULL"}")
        Log.d("InCallActivity", "Remote tracks: ${remoteTracks.size}")
        if (localTrack != null) {
            Log.d("InCallActivity", "Local track publication: ${localTrack?.publication}")
            Log.d("InCallActivity", "Local track has video: ${localTrack?.publication?.track != null}")
        } else {
            Log.w("InCallActivity", "⚠️ PiP will NOT show - localTrack is NULL")
        }
        Log.d("InCallActivity", "==================")
    }
    
    // OUTER Box to contain everything including PiP overlay
    Box(modifier = Modifier.fillMaxSize()) {
        // INNER Box for main video and controls
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black) // Pure black for video background
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = {
                            showControls = !showControls
                            showMenu = false
                        }
                    )
                }
        ) {
        // Main video area - show remote or local based on swap state
        if (remoteTracks.isNotEmpty()) {
            val isGroupCall = remoteTracks.size >= 2
            val mainTrack = if (isGroupCall) {
                // Group call: main view shows first or second remote based on swap
                if (isVideoSwapped && remoteTracks.size >= 2) {
                    remoteTracks.getOrNull(1) ?: remoteTracks.first()
                } else {
                    remoteTracks.first()
                }
            } else {
                // 1-on-1: main view shows remote or local based on swap
                if (isVideoSwapped) {
                    localTrack ?: remoteTracks.first()
                } else {
                    remoteTracks.first()
                }
            }
            CallVideoTrackView(
                trackReference = mainTrack,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            // Placeholder with recipient initial/avatar
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                // Connecting animation
                InfiniteRotatingIcon()
                
                // Recipient avatar/initial
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                        .background(AppColors.PrimaryBlue),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = recipientName.firstOrNull()?.uppercase() ?: "?",
                        fontSize = 48.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
            }
        }
        
        // Top info bar - with padding to avoid status bar overlap
        Column(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 24.dp, end = 24.dp, top = 48.dp, bottom = 24.dp) // Extra top padding for status bar
        ) {
            Text(
                text = recipientName,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White,
                style = androidx.compose.ui.text.TextStyle(
                    shadow = Shadow(
                        color = Color.Black.copy(alpha = 0.8f),
                        offset = Offset(2f, 2f),
                        blurRadius = 4f
                    )
                )
            )
            Text(
                text = formatDuration(callDuration),
                fontSize = 14.sp,
                color = Color.White.copy(alpha = 0.9f),
                style = androidx.compose.ui.text.TextStyle(
                    shadow = Shadow(
                        color = Color.Black.copy(alpha = 0.8f),
                        offset = Offset(2f, 2f),
                        blurRadius = 4f
                    )
                )
            )
        }
        
        // PiP is now OUTSIDE this inner box as an overlay
        
        // Control buttons with adaptive layout
        // Portrait: Bottom center with slide-up animation
        // Landscape: Left side rail with cascading slide-up animation
        if (isLandscape) {
            // LANDSCAPE MODE: Side Rail (Left Edge, Lower Position)
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 16.dp, bottom = 40.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Menu button
                val menuAnim = rememberAnimatedButtonSpring(showControls, 0)
                
                IconButton(
                    onClick = { showMenu = !showMenu },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = menuAnim.offsetX)
                        .graphicsLayer(
                            alpha = menuAnim.alpha,
                            scaleX = menuAnim.scale,
                            scaleY = menuAnim.scale
                        )
                        .background(Color.White.copy(alpha = 0.2f), CircleShape)
                ) {
                    Icon(
                        imageVector = Icons.Default.MoreVert,
                        contentDescription = "Menu",
                        tint = Color.White
                    )
                }
                
                // Mic toggle
                val micAnim = rememberAnimatedButtonSpring(showControls, 1)

                IconButton(
                    onClick = {
                        isMicEnabled = !isMicEnabled
                        scope.launch {
                            room.localParticipant.setMicrophoneEnabled(isMicEnabled)
                        }
                    },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = micAnim.offsetX)
                        .graphicsLayer(
                            alpha = micAnim.alpha,
                            scaleX = micAnim.scale,
                            scaleY = micAnim.scale
                        )
                        .background(
                            if (isMicEnabled) Color.White.copy(alpha = 0.2f) else Color.Red.copy(alpha = 0.3f),
                            CircleShape
                        )
                ) {
                    Icon(
                        imageVector = if (isMicEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                        contentDescription = "Toggle Microphone",
                        tint = if (isMicEnabled) Color.White else Color.Red
                    )
                }
                
                // End call - Glossy 3D style
                val endCallAnim = rememberAnimatedButtonSpring(showControls, 2)
                
                IconButton(
                    onClick = onDisconnect,
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = endCallAnim.offsetX)
                        .graphicsLayer(
                            alpha = endCallAnim.alpha,
                            scaleX = endCallAnim.scale,
                            scaleY = endCallAnim.scale
                        )
                        .background(
                            brush = androidx.compose.ui.graphics.Brush.radialGradient(
                                colors = listOf(
                                    Color(0xFFFF6B6B),
                                    Color(0xFFEE5A52),
                                    Color(0xFFDC3545)
                                ),
                                radius = 80f
                            ),
                            shape = CircleShape
                        )
                ) {
                    Icon(
                        imageVector = Icons.Default.CallEnd,
                        contentDescription = "End Call",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp)
                    )
                }
                
                // Switch Camera button (landscape only)
                val cameraAnim = rememberAnimatedButtonSpring(showControls, 3)
                
                IconButton(
                    onClick = {
                        scope.launch {
                            try {
                                val cameraTrack = room.localParticipant.getTrackPublication(io.livekit.android.room.track.Track.Source.CAMERA)
                                    ?.track as? LocalVideoTrack
                                cameraTrack?.switchCamera(null, null)
                            } catch (e: Exception) {
                                Log.e("InCallActivity", "Failed to switch camera", e)
                            }
                        }
                    },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = cameraAnim.offsetX)
                        .graphicsLayer(
                            alpha = cameraAnim.alpha,
                            scaleX = cameraAnim.scale,
                            scaleY = cameraAnim.scale
                        )
                        .background(Color.White.copy(alpha = 0.2f), CircleShape)
                ) {
                    Icon(
                        imageVector = Icons.Default.Cameraswitch,
                        contentDescription = "Switch Camera",
                        tint = Color.White
                    )
                }
                
                // Add Person button
                val addPersonAnim = rememberAnimatedButtonSpring(showControls, 4)
                
                IconButton(
                    onClick = { showAddPersonDialog = true },
                    modifier = Modifier
                        .size(39.dp)
                        .offset(y = addPersonAnim.offsetX)
                        .graphicsLayer(
                            alpha = addPersonAnim.alpha,
                            scaleX = addPersonAnim.scale,
                            scaleY = addPersonAnim.scale
                        )
                        .background(Color.White.copy(alpha = 0.2f), CircleShape)
                ) {
                    Icon(
                        imageVector = Icons.Default.PersonAdd,
                        contentDescription = "Add Person",
                        tint = Color.White
                    )
                }
            }
        } else {
            // PORTRAIT MODE: Bottom Center (Original)
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 80.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
            // Menu button (animates first)
            val menuAnim = rememberAnimatedButton(showControls, 0)
            
            IconButton(
                onClick = { showMenu = !showMenu }, // Toggle instead of just setting to true
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = menuAnim.offsetY)
                    .graphicsLayer(alpha = menuAnim.alpha)
                    .background(Color.White.copy(alpha = 0.2f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.MoreVert,
                    contentDescription = "Menu",
                    tint = Color.White
                )
            }
            
            // Mic toggle (animates second)
            val micAnim = rememberAnimatedButton(showControls, 1)

            IconButton(
                onClick = {
                    isMicEnabled = !isMicEnabled
                    scope.launch {
                        room.localParticipant.setMicrophoneEnabled(isMicEnabled)
                    }
                },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = micAnim.offsetY)
                    .graphicsLayer(alpha = micAnim.alpha)
                    .background(
                        if (isMicEnabled) Color.White.copy(alpha = 0.2f) else Color.Red.copy(alpha = 0.3f),
                        CircleShape
                    )
            ) {
                Icon(
                    imageVector = if (isMicEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                    contentDescription = "Toggle Microphone",
                    tint = if (isMicEnabled) Color.White else Color.Red
                )
            }
            
            // End call (animates third - center) - Glossy 3D style
            val endCallAnim = rememberAnimatedButton(showControls, 2)
            
            Box(
                modifier = Modifier
                    .size(70.dp)
                    .offset(y = endCallAnim.offsetY)
                    .graphicsLayer(alpha = endCallAnim.alpha)
                    .clickable(onClick = onDisconnect),
                contentAlignment = Alignment.Center
            ) {
                // Outer shadow/glow
                Box(
                    modifier = Modifier
                        .size(70.dp)
                        .background(
                            brush = androidx.compose.ui.graphics.Brush.radialGradient(
                                colors = listOf(
                                    Color(0xFFE53935).copy(alpha = 0.4f),
                                    Color.Transparent
                                )
                            ),
                            shape = CircleShape
                        )
                )
                // Main button with gradient
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .background(
                            brush = androidx.compose.ui.graphics.Brush.verticalGradient(
                                colors = listOf(
                                    Color(0xFFE53935), // Top - lighter
                                    Color(0xFFC62828)  // Bottom - darker
                                )
                            ),
                            shape = CircleShape
                        )
                        .border(2.dp, Color.White.copy(alpha = 0.2f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    // Glossy highlight
                    Box(
                        modifier = Modifier
                            .size(52.dp)
                            .offset(y = (-8).dp)
                            .background(
                                brush = androidx.compose.ui.graphics.Brush.verticalGradient(
                                    colors = listOf(
                                        Color.White.copy(alpha = 0.3f),
                                        Color.Transparent
                                    )
                                ),
                                shape = CircleShape
                            )
                    )
                    Icon(
                        imageVector = Icons.Default.CallEnd,
                        contentDescription = "End Call",
                        tint = Color.White,
                        modifier = Modifier.size(30.dp)
                    )
                }
            }
            
            // Switch camera (animates fourth)
            val switchCamAnim = rememberAnimatedButton(showControls, 3)

            IconButton(
                onClick = {
                    scope.launch {
                        try {
                            val publication = room.localParticipant
                                .getTrackPublication(Track.Source.CAMERA) as? LocalTrackPublication
                            val localVideoTrack = publication?.track as? LocalVideoTrack

                            if (!room.localParticipant.isCameraEnabled) {
                                Log.d("InCallActivity", "📷 Camera disabled, re-enabling before switch")
                                val enabled = room.localParticipant.setCameraEnabled(true)
                                isCameraEnabled = enabled
                            }

                            if (localVideoTrack != null) {
                                Log.d("InCallActivity", "🔁 Switching camera source")
                                localVideoTrack.switchCamera(null, null)
                                isCameraEnabled = room.localParticipant.isCameraEnabled
                            } else {
                                Log.w("InCallActivity", "⚠️ No LocalVideoTrack available, toggling camera state instead")
                                val enabled = room.localParticipant.setCameraEnabled(!room.localParticipant.isCameraEnabled)
                                isCameraEnabled = enabled
                            }
                        } catch (e: Exception) {
                            Log.e("InCallActivity", "Error switching camera", e)
                            Toast.makeText(context, "Camera switch failed: ${e.message}", Toast.LENGTH_SHORT).show()
                        }
                    }
                },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = switchCamAnim.offsetY)
                    .graphicsLayer(alpha = switchCamAnim.alpha)
                    .background(Color.White.copy(alpha = 0.2f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.Cameraswitch,
                    contentDescription = "Switch Camera",
                    tint = Color.White
                )
            }
            
            // Add person (animates fifth/last)
            val addPersonAnim = rememberAnimatedButton(showControls, 4)

            IconButton(
                onClick = {
                    showAddPersonDialog = true
                },
                modifier = Modifier
                    .size(56.dp)
                    .offset(y = addPersonAnim.offsetY)
                    .graphicsLayer(alpha = addPersonAnim.alpha)
                    .background(Color.White.copy(alpha = 0.2f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.PersonAdd,
                    contentDescription = "Add Person",
                    tint = Color.White
                )
            }
        } // End of portrait/landscape conditional
        
        // Menu dropdown - positioned above menu button (portrait) or to right of buttons (landscape)
        if (showMenu) {
            Box(
                modifier = Modifier
                    .align(if (isLandscape) Alignment.BottomStart else Alignment.BottomStart)
                    .padding(
                        start = if (isLandscape) 72.dp else 32.dp,
                        end = if (isLandscape) 0.dp else 0.dp,
                        bottom = if (isLandscape) 40.dp else 160.dp
                    )
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.White.copy(alpha = 0.2f))
                    .padding(8.dp)
            ) {
                Column {
                    TextButton(
                        onClick = {
                            showMenu = false
                            showParticipantsList = true
                            Log.d("InCallActivity", "Participants clicked")
                        }
                    ) {
                        Icon(
                            Icons.Default.People,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Participants", color = Color.White)
                    }
                    
                    TextButton(
                        onClick = {
                            showMenu = false
                            isScreenSharing = !isScreenSharing
                            scope.launch {
                                try {
                                    Log.d("InCallActivity", "🖥️ Toggling screen share to: $isScreenSharing")
                                    room.localParticipant.setScreenShareEnabled(isScreenSharing)
                                    Log.d("InCallActivity", "✅ Screen sharing ${if (isScreenSharing) "started" else "stopped"} successfully")
                                    Toast.makeText(
                                        context,
                                        if (isScreenSharing) "Screen sharing started" else "Screen sharing stopped",
                                        Toast.LENGTH_SHORT
                                    ).show()
                                } catch (e: Exception) {
                                    Log.e("InCallActivity", "❌ Error toggling screen share: ${e.message}", e)
                                    Toast.makeText(
                                        context,
                                        "Screen sharing failed: ${e.message}",
                                        Toast.LENGTH_LONG
                                    ).show()
                                    isScreenSharing = !isScreenSharing // Revert on error
                                }
                            }
                        }
                    ) {
                        Icon(
                            Icons.Default.ScreenShare,
                            contentDescription = null,
                            tint = if (isScreenSharing) Color.Green else Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = if (isScreenSharing) "Stop Sharing" else "Share Screen",
                            color = Color.White
                        )
                    }
                }
            }
        }
        
        // Participants list dialog
        if (showParticipantsList) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.7f))
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onTap = {
                                showParticipantsList = false
                            }
                        )
                    },
                contentAlignment = Alignment.Center
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth(0.85f)
                        .clip(RoundedCornerShape(16.dp))
                        .background(AppColors.BackgroundDark)
                        .padding(24.dp)
                        .pointerInput(Unit) {
                            detectTapGestures(
                                onTap = { /* Consume tap to prevent closing */ }
                            )
                        }
                ) {
                    // Header
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Participants (${trackReferences.size})",
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                        IconButton(onClick = { showParticipantsList = false }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Close",
                                tint = Color.White
                            )
                        }
                    }
                    
                    Spacer(modifier = Modifier.height(16.dp))
                    
                    // Participants list
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        items(trackReferences.size) { index ->
                            val trackRef = trackReferences[index]
                            ParticipantItem(
                                trackReference = trackRef,
                                isLocal = trackRef.participant.sid?.value == room.localParticipant.sid?.value
                            )
                        }
                    }
                }
            }
        }
        
        // Add Person Dialog
        if (showAddPersonDialog) {
            AddPersonDialog(
                onDismiss = { showAddPersonDialog = false },
                onInvite = { contactInput ->
                    Log.d("InCallActivity", "===== INVITE CALLBACK TRIGGERED =====")
                    Log.d("InCallActivity", "Contact input received: '$contactInput'")
                    
                    // Send invitation via Firestore
                    val currentUser = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
                    val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    
                    Log.d("InCallActivity", "Current user: ${currentUser?.email}")
                    
                    if (currentUser != null) {
                        Log.d("InCallActivity", "Searching for user: $contactInput")
                        
                        // Search by email, phone, or username
                        val searchQueries = listOf(
                            db.collection("users").whereEqualTo("email", contactInput),
                            db.collection("users").whereEqualTo("phoneNumber", contactInput),
                            db.collection("users").whereEqualTo("username", contactInput)
                        )
                        
                        var userFound = false
                        
                        fun tryNextQuery(index: Int) {
                            Log.d("InCallActivity", "Trying query $index of ${searchQueries.size}")
                            
                            if (index >= searchQueries.size) {
                                if (!userFound) {
                                    Log.w("InCallActivity", "User not found: $contactInput")
                                    android.widget.Toast.makeText(
                                        context,
                                        "User not found: $contactInput",
                                        android.widget.Toast.LENGTH_SHORT
                                    ).show()
                                }
                                return
                            }
                            
                            searchQueries[index].get()
                                .addOnSuccessListener { documents ->
                                    if (!documents.isEmpty && !userFound) {
                                        userFound = true
                                        val inviteeId = documents.documents[0].id
                                        
                                        Log.d("InCallActivity", "User found: $inviteeId, sending invite...")
                                        
                                        // Send call invitation
                                        val inviteData = hashMapOf(
                                            "type" to "call_invite",
                                            "fromUserId" to currentUser.uid,
                                            "fromUserName" to (currentUser.displayName ?: currentUser.email),
                                            "roomName" to room.name,
                                            "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                                        )
                                        
                                        db.collection("users")
                                            .document(inviteeId)
                                            .collection("callSignals")
                                            .add(inviteData)
                                            .addOnSuccessListener {
                                                Log.d("InCallActivity", "Invite sent successfully to: $contactInput")
                                                android.widget.Toast.makeText(
                                                    context,
                                                    "Invitation sent!",
                                                    android.widget.Toast.LENGTH_SHORT
                                                ).show()
                                                showAddPersonDialog = false
                                            }
                                            .addOnFailureListener { e ->
                                                Log.e("InCallActivity", "Error sending invite", e)
                                                android.widget.Toast.makeText(
                                                    context,
                                                    "Failed to send invite: ${e.message}",
                                                    android.widget.Toast.LENGTH_SHORT
                                                ).show()
                                            }
                                    } else {
                                        tryNextQuery(index + 1)
                                    }
                                }
                                .addOnFailureListener { e ->
                                    Log.e("InCallActivity", "Error searching for user", e)
                                    tryNextQuery(index + 1)
                                }
                        }
                        
                        tryNextQuery(0)
                    } else {
                        Log.e("InCallActivity", "Current user is null")
                        android.widget.Toast.makeText(
                            context,
                            "Error: Not authenticated",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            )
        }
    } // End of INNER Box (main video + controls)
    
    // Top-Right PiP Box - Picture-in-picture overlay
    // In 1-on-1: Shows local feed (swappable with main)
    // In group call (2+ remote): Shows second remote participant (swappable with main)
    // Tap = enlarge/shrink, Long press = swap feeds
    // Auto-adjusts aspect ratio based on device orientation
    val isGroupCall = remoteTracks.size >= 2
    
    Box(
        modifier = Modifier
            .align(Alignment.TopEnd)
            .zIndex(999f)
            .padding(top = 56.dp, end = 16.dp) // Extra top padding to avoid status bar
            .size(
                width = if (isLandscape) {
                    if (isLocalVideoEnlarged) 280.dp else 160.dp
                } else {
                    if (isLocalVideoEnlarged) 200.dp else 120.dp
                },
                height = if (isLandscape) {
                    if (isLocalVideoEnlarged) 160.dp else 90.dp
                } else {
                    if (isLocalVideoEnlarged) 300.dp else 200.dp
                }
            )
            .border(
                width = 2.dp, 
                color = if (isVideoSwapped) AppColors.PrimaryBlue else Color.White.copy(alpha = 0.5f),
                shape = RoundedCornerShape(12.dp)
            )
            .clip(RoundedCornerShape(12.dp))
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { 
                        // Quick tap = enlarge/shrink
                        isLocalVideoEnlarged = !isLocalVideoEnlarged
                        showControls = true
                    },
                    onLongPress = {
                        // Long press = swap main and PiP feeds
                        if (remoteTracks.isNotEmpty()) {
                            isVideoSwapped = !isVideoSwapped
                            showControls = true
                            Log.d("InCallActivity", "📺 Video feeds swapped: $isVideoSwapped")
                        }
                    }
                )
            }
    ) {
        // In group call: show second remote participant
        // In 1-on-1: show local or remote based on swap state
        if (remoteTracks.isNotEmpty()) {
            val pipTrack = if (isGroupCall) {
                // Group call: top-right PiP always shows second remote participant
                if (isVideoSwapped && remoteTracks.size >= 2) {
                    remoteTracks.first() // When swapped, second remote moves to main, so show first remote
                } else {
                    remoteTracks.getOrNull(1) ?: remoteTracks.first()
                }
            } else {
                // 1-on-1: show local or remote based on swap
                if (isVideoSwapped) {
                    remoteTracks.first()
                } else {
                    localTrack
                }
            }
            
            pipTrack?.let {
                CallVideoTrackView(
                    trackReference = it,
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(12.dp)), // Ensure video fills and clips to rounded corners
                    isOverlay = true
                )
            }
        } else if (localTrack != null) {
            // No remote participants yet, show local feed
            CallVideoTrackView(
                trackReference = localTrack!!,
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(12.dp)),
                isOverlay = true
            )
        } else {
            // Waiting for camera
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "📷",
                    fontSize = 32.sp,
                    color = Color.White
                )
            }
        }
        
        // Swap indicator when feeds are swapped
        if (isVideoSwapped && remoteTracks.isNotEmpty()) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(4.dp)
                    .size(24.dp)
                    .background(AppColors.PrimaryBlue, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.SwapVert,
                    contentDescription = "Swapped",
                    tint = Color.White,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
    
    // Bottom-Left Small PiP - Only in group calls (2+ remote participants)
    // Shows user's local feed (non-swappable)
    // Auto-adjusts aspect ratio based on device orientation
    if (isGroupCall && localTrack != null) {
        Box(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .zIndex(999f)
                .padding(start = 16.dp, bottom = if (isLandscape) 24.dp else 100.dp) // Position above buttons
                .size(
                    width = if (isLandscape) 120.dp else 90.dp,
                    height = if (isLandscape) 68.dp else 120.dp
                )
                .border(
                    width = 2.dp,
                    color = Color.White.copy(alpha = 0.5f),
                    shape = RoundedCornerShape(12.dp)
                )
                .clip(RoundedCornerShape(12.dp))
        ) {
            CallVideoTrackView(
                trackReference = localTrack!!,
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(12.dp)),
                isOverlay = true
            )
            
            // "You" label
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(4.dp)
                    .background(
                        color = Color.Black.copy(alpha = 0.6f),
                        shape = RoundedCornerShape(4.dp)
                    )
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            ) {
                Text(
                    text = "You",
                    fontSize = 10.sp,
                    color = Color.White,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
    } // Close OUTER Box (line 441)
} // End of InCallScreen
}
