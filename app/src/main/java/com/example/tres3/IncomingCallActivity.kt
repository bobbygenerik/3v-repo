package com.example.tres3

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.setContent
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import androidx.core.content.ContextCompat
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Full-screen incoming call activity
 * Shows caller information and accept/reject buttons
 */
class IncomingCallActivity : ComponentActivity() {
    
    private lateinit var invitation: CallInvitation
    private var afterPermissions: (() -> Unit)? = null

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        val audioGranted = result[Manifest.permission.RECORD_AUDIO] == true
        val cameraGranted = result[Manifest.permission.CAMERA] == true
        if (audioGranted && cameraGranted) {
            afterPermissions?.invoke()
        } else {
            android.widget.Toast.makeText(
                this,
                "Microphone/Camera permissions are required to join the call",
                android.widget.Toast.LENGTH_LONG
            ).show()
        }
        afterPermissions = null
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Get call invitation data from intent
        val invitationId = intent.getStringExtra("invitationId") ?: ""
        val fromUserName = intent.getStringExtra("fromUserName") ?: "Unknown"
        val fromUserId = intent.getStringExtra("fromUserId") ?: ""
        val roomName = intent.getStringExtra("roomName") ?: ""
        val url = intent.getStringExtra("url") ?: ""
        val token = intent.getStringExtra("token") ?: ""
        val callerPhotoUrl = intent.getStringExtra("callerPhotoUrl") // Profile picture URL
        val isGuestCall = intent.getBooleanExtra("isGuestCall", false) // Flag for guest calls
        
        invitation = CallInvitation(
            id = invitationId,
            fromUserId = fromUserId,
            fromUserName = fromUserName,
            roomName = roomName,
            url = url,
            token = token,
            timestamp = null
        )
        
        Log.d("IncomingCallActivity", "Call from: $fromUserName, isGuest: $isGuestCall, hasToken: ${token.isNotEmpty()}")
        
        setContent {
            IncomingCallScreen(
                callerName = fromUserName,
                callerPhotoUrl = callerPhotoUrl,
                onAccept = { acceptCall(isGuestCall, url, token, roomName) },
                onReject = { rejectCall(isGuestCall) }
            )
        }
    }
    
    private fun acceptCall(isGuestCall: Boolean, providedUrl: String, providedToken: String, providedRoomName: String) {
        // Ensure RECORD_AUDIO and CAMERA runtime permissions before connecting/publishing
        val needsAudio = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        val needsCamera = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        if (needsAudio || needsCamera) {
            afterPermissions = { acceptCall(isGuestCall, providedUrl, providedToken, providedRoomName) }
            permissionLauncher.launch(arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA))
            return
        }

        lifecycleScope.launch {
            try {
                if (isGuestCall && providedRoomName.isNotEmpty() && providedUrl.isNotEmpty()) {
                    // Guest call: Fetch a NEW token for the host (not the guest's token!)
                    Log.d("IncomingCallActivity", "Accepting guest call - fetching NEW token for host")
                    
                    val auth = com.google.firebase.auth.FirebaseAuth.getInstance()
                    val currentUser = auth.currentUser
                        ?: throw IllegalStateException("Not authenticated")
                    
                    // Fetch a fresh LiveKit token for the HOST using the same room name
                    val functions = com.google.firebase.functions.FirebaseFunctions.getInstance("us-central1")
                    val request = hashMapOf(
                        "calleeId" to "guest", // arbitrary, server uses auth.uid for identity
                        "roomName" to providedRoomName
                    )
                    
                    val result = functions
                        .getHttpsCallable("getLiveKitToken")
                        .call(request)
                        .await()
                    
                    @Suppress("UNCHECKED_CAST")
                    val response = result.data as? Map<String, Any>
                        ?: throw IllegalStateException("Invalid response from token function")
                    
                    val url = response["url"] as? String ?: providedUrl
                    val token = response["token"] as? String
                        ?: throw IllegalStateException("Missing token in response")
                    
                    Log.d("IncomingCallActivity", "✅ Got NEW token for host (length: ${token.length})")
                    
                    // Connect to the call with the host's NEW token
                    val room = LiveKitManager.connectToRoom(
                        this@IncomingCallActivity,
                        url,
                        token
                    )

                    // Enable camera and microphone
                    room.localParticipant.setCameraEnabled(true)
                    room.localParticipant.setMicrophoneEnabled(true)
                    
                    // Launch InCallActivity with guest information
                    val intent = Intent(this@IncomingCallActivity, InCallActivity::class.java).apply {
                        putExtra("recipient_name", invitation.fromUserName) // Pass guest name
                        putExtra("recipient_email", "") // Guests don't have email
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    startActivity(intent)
                    finish()
                } else {
                    // Regular call: Use existing flow with Firestore signaling
                    Log.d("IncomingCallActivity", "Accepting regular call, fetching new token")
                    
                    // Mark as accepted
                    CallSignalingManager.acceptCallInvitation(invitation.id)

                // Fetch a fresh LiveKit token for THIS user (recipient) using the callable
                val auth = com.google.firebase.auth.FirebaseAuth.getInstance()
                val currentUser = auth.currentUser
                    ?: throw IllegalStateException("Not authenticated")

                // Use the same room name provided in the invitation so both join the same room
                val roomName = invitation.roomName

                val functions = com.google.firebase.functions.FirebaseFunctions.getInstance("us-central1")
                val request = hashMapOf(
                    "calleeId" to currentUser.uid, // arbitrary second party; server uses auth.uid
                    "roomName" to roomName
                )

                val result = functions
                    .getHttpsCallable("getLiveKitToken")
                    .call(request)
                    .await()

                @Suppress("UNCHECKED_CAST")
                val response = result.data as? Map<String, Any>
                    ?: throw IllegalStateException("Invalid response from token function")

                val url = response["url"] as? String
                    ?: throw IllegalStateException("Missing url in response")
                val token = response["token"] as? String
                    ?: throw IllegalStateException("Missing token in response")

                // Connect to the call with recipient's identity
                val room = LiveKitManager.connectToRoom(
                    this@IncomingCallActivity,
                    url,
                    token
                )

                // Enable camera and microphone
                room.localParticipant.setCameraEnabled(true)
                room.localParticipant.setMicrophoneEnabled(true)
                
                // Launch InCallActivity
                val intent = Intent(this@IncomingCallActivity, InCallActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                    startActivity(intent)
                    finish()
                }
            } catch (e: Exception) {
                Log.e("IncomingCallActivity", "Error accepting call", e)
                e.printStackTrace()
                finish()
            }
        }
    }
    
    private fun rejectCall(isGuestCall: Boolean) {
        lifecycleScope.launch {
            try {
                // Only update Firestore for regular calls, not guest calls
                if (!isGuestCall) {
                    CallSignalingManager.rejectCallInvitation(invitation.id)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                finish()
            }
        }
    }
    
    override fun onBackPressed() {
        super.onBackPressed()
        // Treat back press as reject
        val isGuestCall = intent.getBooleanExtra("isGuestCall", false)
        rejectCall(isGuestCall)
    }
}

@Composable
fun IncomingCallScreen(
    callerName: String,
    callerPhotoUrl: String? = null,
    onAccept: () -> Unit,
    onReject: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.BackgroundDark),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(32.dp),
            modifier = Modifier.padding(32.dp)
        ) {
            // Pulsing animation for the ring
            val infiniteTransition = rememberInfiniteTransition(label = "pulse")
            val ringScale by infiniteTransition.animateFloat(
                initialValue = 1f,
                targetValue = 1.2f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1200, easing = FastOutSlowInEasing),
                    repeatMode = RepeatMode.Reverse
                ),
                label = "ringScale"
            )
            val ringAlpha by infiniteTransition.animateFloat(
                initialValue = 0.8f,
                targetValue = 0.3f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1200, easing = FastOutSlowInEasing),
                    repeatMode = RepeatMode.Reverse
                ),
                label = "ringAlpha"
            )
            
            // Caller avatar/photo with pulsing ring effect
            Box(
                modifier = Modifier.size(180.dp),
                contentAlignment = Alignment.Center
            ) {
                // Pulsing ring
                Box(
                    modifier = Modifier
                        .size(170.dp)
                        .graphicsLayer(scaleX = ringScale, scaleY = ringScale, alpha = ringAlpha)
                        .border(
                            width = 4.dp,
                            color = AppColors.PrimaryBlue,
                            shape = CircleShape
                        )
                )
                
                // Profile picture or initials
                Box(
                    modifier = Modifier
                        .size(150.dp)
                        .border(
                            width = 4.dp,
                            color = AppColors.PrimaryBlue,
                            shape = CircleShape
                        )
                        .clip(CircleShape)
                        .background(if (callerPhotoUrl.isNullOrEmpty()) AppColors.PrimaryBlue else Color.Transparent),
                    contentAlignment = Alignment.Center
                ) {
                    if (!callerPhotoUrl.isNullOrEmpty()) {
                        // Show profile picture
                        coil.compose.AsyncImage(
                            model = callerPhotoUrl,
                            contentDescription = "Caller photo",
                            modifier = Modifier
                                .fillMaxSize()
                                .clip(CircleShape),
                            contentScale = androidx.compose.ui.layout.ContentScale.Crop
                        )
                    } else {
                        // Show initials (first letter of first 2 words)
                        val initials = callerName.trim().split(" ")
                            .take(2)
                            .mapNotNull { it.firstOrNull()?.uppercase() }
                            .joinToString("")
                            .ifEmpty { "?" }
                        
                        Text(
                            text = initials,
                            fontSize = 56.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            
            // Caller name
            Text(
                text = callerName,
                fontSize = 28.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.TextLight
            )
            
            // "Incoming video call" text
            Text(
                text = "Incoming video call",
                fontSize = 16.sp,
                color = AppColors.TextLight.copy(alpha = 0.7f)
            )
            
            Spacer(modifier = Modifier.height(64.dp))
            
            // Accept and Reject buttons - Modern circular design
            Row(
                horizontalArrangement = Arrangement.spacedBy(64.dp),
                modifier = Modifier.padding(horizontal = 32.dp)
            ) {
                // Reject button - Red circular
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(80.dp)
                            .clip(CircleShape)
                            .background(Color(0xFFE53935))
                            .clickable(onClick = onReject),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_call_end),
                            contentDescription = "Reject call",
                            modifier = Modifier.size(40.dp),
                            tint = Color.White
                        )
                    }
                    Text(
                        text = "Decline",
                        color = AppColors.TextLight,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
                
                // Accept button - Green circular
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(80.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF43A047))
                            .clickable(onClick = onAccept),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_call_end),
                            contentDescription = "Accept call",
                            modifier = Modifier
                                .size(40.dp)
                                .rotate(135f), // Rotate to look like answer icon
                            tint = Color.White
                        )
                    }
                    Text(
                        text = "Accept",
                        color = AppColors.TextLight,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}
