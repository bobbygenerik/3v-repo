package com.tres3.videochat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import android.util.Log

class MyFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        android.util.Log.d("FCM", "Message received: ${remoteMessage.data}")
        
        val data = remoteMessage.data
        val type = data["type"] ?: ""
        
        if (type == "call_invite" || type == "guest_joining") {
            val invitationId = data["invitationId"] ?: ""
            val fromName = data["fromUserName"] ?: data["guestName"] ?: "Incoming call"

            val channelId = "call_channel"
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create high-priority notification channel
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val ch = NotificationChannel(
                    channelId, 
                    "Calls", 
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Incoming call notifications"
                    enableVibration(true)
                    enableLights(true)
                    setBypassDnd(true)
                    setShowBadge(true)
                }
                nm.createNotificationChannel(ch)
            }

            val fullScreenIntent = Intent(this, FullScreenCallActivity::class.java).apply {
                putExtra("invitationId", invitationId)
                putExtra("fromName", fromName)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            else
                PendingIntent.FLAG_UPDATE_CURRENT

            val fullScreenPendingIntent = PendingIntent.getActivity(this, 1001, fullScreenIntent, flags)

            val acceptIntent = Intent(this, CallActionReceiver::class.java).apply {
                action = "ACTION_ACCEPT"
                putExtra("invitationId", invitationId)
            }
            val declineIntent = Intent(this, CallActionReceiver::class.java).apply {
                action = "ACTION_DECLINE"
                putExtra("invitationId", invitationId)
            }
            val acceptPI = PendingIntent.getBroadcast(this, 1002, acceptIntent, flags)
            val declinePI = PendingIntent.getBroadcast(this, 1003, declineIntent, flags)

            val notification = NotificationCompat.Builder(this, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("$fromName is calling")
                .setContentText("Tap to answer or use buttons below")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setAutoCancel(false)
                .setOngoing(true)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setVibrate(longArrayOf(0, 1000, 500, 1000))
                .setTimeoutAfter(30000) // 30 seconds
                .addAction(R.drawable.ic_call_accept, "Accept", acceptPI)
                .addAction(R.drawable.ic_call_decline, "Decline", declinePI)
                .build()

            android.util.Log.d("FCM", "Showing notification for $fromName")
            nm.notify(1001, notification)
        }
    }
}
