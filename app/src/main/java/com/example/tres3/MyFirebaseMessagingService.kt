package com.example.tres3

import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class MyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        Log.e("FCM", "════════════════════════════════════════")
        Log.e("FCM", "📨 MESSAGE RECEIVED!!!")
        Log.e("FCM", "   From: ${message.from}")
        Log.e("FCM", "   Message ID: ${message.messageId}")
        Log.e("FCM", "   Data: ${message.data}")
        Log.e("FCM", "   Notification: ${message.notification?.title}")
        Log.e("FCM", "   Data keys: ${message.data.keys}")
        Log.e("FCM", "════════════════════════════════════════")

        val data = message.data
        val type = data["type"]

        Log.e("FCM", "Message type: $type")

        if (type == "call_invite") {
            Log.e("FCM", "✅ This is a call invite! Handling...")
            handleCallInvite(data)
        } else {
            Log.w("FCM", "⚠️ Message type is not 'call_invite': $type")
        }
    }

    private fun handleCallInvite(data: Map<String, String>) {
        Log.e("FCM", "════════════════════════════════════════")
        Log.e("FCM", "📞 HANDLING CALL INVITE")
        Log.e("FCM", "════════════════════════════════════════")
        
        val invitationId = data["invitationId"] ?: run {
            Log.e("FCM", "❌ Missing invitationId in payload")
            return
        }
        val fromUserId = data["fromUserId"] ?: run {
            Log.e("FCM", "❌ Missing fromUserId in payload")
            return
        }
        val fromUserName = data["fromUserName"] ?: "Unknown"
        val roomName = data["roomName"] ?: run {
            Log.e("FCM", "❌ Missing roomName in payload")
            return
        }
        val url = data["url"] ?: ""
        val token = data["token"] ?: ""

        Log.e("FCM", "   InvitationId: $invitationId")
        Log.e("FCM", "   From: $fromUserName ($fromUserId)")
        Log.e("FCM", "   Room: $roomName")
        Log.e("FCM", "   URL: ${if (url.isNotBlank()) "present" else "MISSING"}")
        Log.e("FCM", "   Token: ${if (token.isNotBlank()) "present" else "MISSING"}")
        
        // Get caller's photo URL from Firestore
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val callerDoc = FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(fromUserId)
                    .get()
                    .await()
                
                val callerPhotoUrl = callerDoc.getString("photoUrl") 
                    ?: callerDoc.getString("avatarUrl")
                
                Log.e("FCM", "   Caller photo URL: ${if (callerPhotoUrl != null) "present" else "none"}")
                
                // Check user preference for notification style
                val prefs = getSharedPreferences("settings", Context.MODE_PRIVATE)
                val useHeadsUpOnly = prefs.getBoolean("heads_up_notifications", false)
                
                if (useHeadsUpOnly) {
                    // Show heads-up notification only
                    Log.e("FCM", "📳 Showing heads-up notification (user preference)")
                    showCallNotification(invitationId, fromUserName, fromUserId, roomName, url, token, callerPhotoUrl)
                } else {
                    // Launch full-screen IncomingCallActivity
                    Log.e("FCM", "🚀 Launching full-screen IncomingCallActivity...")
                    val intent = Intent(this@MyFirebaseMessagingService, IncomingCallActivity::class.java).apply {
                        putExtra("invitationId", invitationId)
                        putExtra("fromUserName", fromUserName)
                        putExtra("fromUserId", fromUserId)
                        putExtra("roomName", roomName)
                        putExtra("url", url)
                        putExtra("token", token)
                        putExtra("callerPhotoUrl", callerPhotoUrl)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    startActivity(intent)
                    Log.e("FCM", "✅ IncomingCallActivity launched!")
                }
            } catch (e: Exception) {
                Log.e("FCM", "❌ Error fetching caller info: ${e.message}", e)
                // Fallback to full screen without photo
                val intent = Intent(this@MyFirebaseMessagingService, IncomingCallActivity::class.java).apply {
                    putExtra("invitationId", invitationId)
                    putExtra("fromUserName", fromUserName)
                    putExtra("fromUserId", fromUserId)
                    putExtra("roomName", roomName)
                    putExtra("url", url)
                    putExtra("token", token)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                startActivity(intent)
            }
        }
        
        Log.e("FCM", "════════════════════════════════════════")
    }
    
    private fun showCallNotification(
        invitationId: String,
        fromUserName: String,
        fromUserId: String,
        roomName: String,
        url: String,
        token: String,
        callerPhotoUrl: String?
    ) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        
        // Create notification channel for Android O+
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                "incoming_calls",
                "Incoming Calls",
                android.app.NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for incoming video calls"
                enableVibration(true)
                setSound(
                    android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE),
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
            notificationManager.createNotificationChannel(channel)
        }
        
        // Intent for Accept action
        val acceptIntent = Intent(this, CallNotificationReceiver::class.java).apply {
            action = "ACCEPT_CALL"
            putExtra("invitationId", invitationId)
            putExtra("fromUserName", fromUserName)
            putExtra("fromUserId", fromUserId)
            putExtra("roomName", roomName)
            putExtra("url", url)
            putExtra("token", token)
            putExtra("callerPhotoUrl", callerPhotoUrl)
        }
        val acceptPendingIntent = android.app.PendingIntent.getBroadcast(
            this,
            invitationId.hashCode(),
            acceptIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent for Decline action
        val declineIntent = Intent(this, CallNotificationReceiver::class.java).apply {
            action = "DECLINE_CALL"
            putExtra("invitationId", invitationId)
        }
        val declinePendingIntent = android.app.PendingIntent.getBroadcast(
            this,
            invitationId.hashCode() + 1,
            declineIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent for tapping the notification (opens full-screen UI)
        val fullScreenIntent = Intent(this, IncomingCallActivity::class.java).apply {
            putExtra("invitationId", invitationId)
            putExtra("fromUserName", fromUserName)
            putExtra("fromUserId", fromUserId)
            putExtra("roomName", roomName)
            putExtra("url", url)
            putExtra("token", token)
            putExtra("callerPhotoUrl", callerPhotoUrl)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val fullScreenPendingIntent = android.app.PendingIntent.getActivity(
            this,
            invitationId.hashCode() + 2,
            fullScreenIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        
        // Load caller photo if available
        val largeIcon: android.graphics.Bitmap? = if (!callerPhotoUrl.isNullOrEmpty()) {
            try {
                // You'll need to add Coil or Glide to load the image synchronously
                // For now, use default icon
                null
            } catch (e: Exception) {
                null
            }
        } else null
        
        // Build notification
        val notificationBuilder = androidx.core.app.NotificationCompat.Builder(this, "incoming_calls")
            .setSmallIcon(R.drawable.ic_call_end)
        
        // Only set large icon if we have a bitmap
        if (largeIcon != null) {
            notificationBuilder.setLargeIcon(largeIcon)
        }
        
        val notification = notificationBuilder
            .setContentTitle("$fromUserName is calling")
            .setContentText("Incoming video call")
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setCategory(androidx.core.app.NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setOngoing(true)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_call,
                "Decline",
                declinePendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_call,
                "Accept",
                acceptPendingIntent
            )
            .setColor(0xFF1E88E5.toInt())
            .setVibrate(longArrayOf(0, 1000, 500, 1000))
            .setSound(android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE))
            .build()
        
        notificationManager.notify(invitationId.hashCode(), notification)
        Log.e("FCM", "✅ Heads-up notification shown")
    }

    override fun onNewToken(token: String) {
        Log.e("FCM", "════════════════════════════════════════")
        Log.e("FCM", "🔄 FCM TOKEN REFRESHED")
        Log.e("FCM", "   New token: ${token.take(20)}...")
        Log.e("FCM", "════════════════════════════════════════")
        
        // Save token to Firestore so Cloud Functions can send notifications
        val currentUser = FirebaseAuth.getInstance().currentUser
        if (currentUser != null) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    FirebaseFirestore.getInstance()
                        .collection("users")
                        .document(currentUser.uid)
                        .set(mapOf("fcmToken" to token), SetOptions.merge())
                        .await()
                    
                    Log.e("FCM", "✅ FCM token saved to Firestore for user: ${currentUser.uid}")
                } catch (e: Exception) {
                    Log.e("FCM", "❌ Failed to save FCM token", e)
                }
            }
        } else {
            Log.w("FCM", "⚠️ No user signed in, token not saved")
        }
    }
}
