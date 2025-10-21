package com.example.tres3

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * Full-screen incoming call activity
 * Shows caller information and accept/reject buttons
 */
class IncomingCallActivity : ComponentActivity() {
    
    private lateinit var invitation: CallInvitation
    
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
        
        invitation = CallInvitation(
            id = invitationId,
            fromUserId = fromUserId,
            fromUserName = fromUserName,
            roomName = roomName,
            url = url,
            token = token,
            timestamp = null
        )
        
        setContent {
            IncomingCallScreen(
                callerName = fromUserName,
                callerPhotoUrl = callerPhotoUrl,
                onAccept = { acceptCall() },
                onReject = { rejectCall() }
            )
        }
    }
    
    private fun acceptCall() {
        lifecycleScope.launch {
            try {
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
            } catch (e: Exception) {
                e.printStackTrace()
                finish()
            }
        }
    }
    
    private fun rejectCall() {
        lifecycleScope.launch {
            try {
                CallSignalingManager.rejectCallInvitation(invitation.id)
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
        rejectCall()
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
            // Pulsing animation for incoming call
            val infiniteTransition = rememberInfiniteTransition(label = "pulse")
            val scale by infiniteTransition.animateFloat(
                initialValue = 1f,
                targetValue = 1.15f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1000, easing = FastOutSlowInEasing),
                    repeatMode = RepeatMode.Reverse
                ),
                label = "scale"
            )
            
            // Caller avatar/photo with pulsing effect and blue outline
            Box(
                modifier = Modifier
                    .size(150.dp)
                    .clip(CircleShape)
                    .background(AppColors.PrimaryBlue) // Blue outline/border
                    .graphicsLayer(scaleX = scale, scaleY = scale),
                contentAlignment = Alignment.Center
            ) {
                if (!callerPhotoUrl.isNullOrEmpty()) {
                    // Show profile picture
                    coil.compose.AsyncImage(
                        model = callerPhotoUrl,
                        contentDescription = "Caller photo",
                        modifier = Modifier
                            .size(140.dp)
                            .clip(CircleShape),
                        contentScale = androidx.compose.ui.layout.ContentScale.Crop
                    )
                } else {
                    // Show initial
                    Box(
                        modifier = Modifier
                            .size(140.dp)
                            .clip(CircleShape)
                            .background(AppColors.PrimaryBlue),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = callerName.firstOrNull()?.uppercase() ?: "?",
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
