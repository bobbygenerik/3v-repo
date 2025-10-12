package com.example.threevchat.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.app.PendingIntent
import android.content.Intent
import com.example.threevchat.MainActivity
import com.example.threevchat.activities.CallActivity
import com.example.threevchat.activities.IncomingCallActivity
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.threevchat.R
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class AppMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // TODO: send token to your backend so it can target this device for call invites
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        // Handle incoming call invites or other push events
    val title = message.data["title"] ?: message.notification?.title ?: "Incoming call"
    val body = message.data["body"] ?: message.notification?.body ?: "Tap to join"
    val sessionId = message.data["sessionId"]
    val role = message.data["role"] ?: "callee"
    val from = message.data["from"] ?: message.data["caller"] ?: message.data["sender"]
    val showRinging = message.data["ringing"]?.equals("true", ignoreCase = true) == true

    createChannelIfNeeded()

        val tapIntent = if (!sessionId.isNullOrBlank()) {
            if (showRinging) {
                Intent(this, IncomingCallActivity::class.java).apply {
                    putExtra("role", role)
                    putExtra("sessionId", sessionId)
                    if (!from.isNullOrBlank()) putExtra("from", from)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
            } else {
                Intent(this, CallActivity::class.java).apply {
                    putExtra("role", role)
                    putExtra("sessionId", sessionId)
                    if (!from.isNullOrBlank()) putExtra("recipientName", from)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
            }
        } else {
            Intent(this, MainActivity::class.java)
        }
        val pending = PendingIntent.getActivity(this, 0, tapIntent, PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0))

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_person)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)

        if (androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            NotificationManagerCompat.from(this).notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
        } else {
            // Optionally, request permission or handle lack of permission gracefully
        }
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Calls", NotificationManager.IMPORTANCE_HIGH)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    companion object {
        private const val CHANNEL_ID = "calls"
    }
}
