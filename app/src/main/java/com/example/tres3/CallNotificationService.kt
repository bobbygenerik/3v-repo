
package com.example.tres3

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import timber.log.Timber
import com.example.tres3.InCallActivity
import com.example.tres3.CallActionReceiver
import com.example.tres3.R

class CallNotificationService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "CallNotificationService"
        private const val CHANNEL_ID = "incoming_calls"
        private const val CHANNEL_NAME = "Incoming Calls"
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Timber.d("From: ${remoteMessage.from}")

        // Check if message contains a data payload
        if (remoteMessage.data.isNotEmpty()) {
            Timber.d("Message data payload: ${remoteMessage.data}")

            val callType = remoteMessage.data["callType"]
            val callerName = remoteMessage.data["callerName"] ?: "Unknown Caller"
            val callerId = remoteMessage.data["callerId"]

            when (callType) {
                "incoming_call" -> showIncomingCallNotification(callerName, callerId)
                "call_ended" -> cancelIncomingCallNotification()
            }
        }

        // Check if message contains a notification payload
        remoteMessage.notification?.let {
            Timber.d("Message Notification Body: ${it.body}")
        }
    }

    override fun onNewToken(token: String) {
        // Send token to your server (token logging removed for security)
        sendRegistrationToServer(token)
    }

    private fun showIncomingCallNotification(callerName: String, callerId: String?) {
        createNotificationChannel()

        // Create intent for accepting call
        val acceptIntent = Intent(this, InCallActivity::class.java).apply {
            action = "ACCEPT_CALL"
            putExtra("callerName", callerName)
            putExtra("callerId", callerId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val acceptPendingIntent = PendingIntent.getActivity(
            this, 0, acceptIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create intent for declining call
        val declineIntent = Intent(this, CallActionReceiver::class.java).apply {
            action = "DECLINE_CALL"
            putExtra("callerId", callerId)
        }

        val declinePendingIntent = PendingIntent.getBroadcast(
            this, 1, declineIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Incoming Call")
            .setContentText("$callerName is calling...")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(acceptPendingIntent, true)
            .addAction(R.drawable.ic_end_call, "Decline", declinePendingIntent)
            .addAction(R.drawable.ic_call_end, "Accept", acceptPendingIntent)
            .setOngoing(true)
            .build()

        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(1, notification)
    }

    private fun cancelIncomingCallNotification() {
        val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(1)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for incoming video calls"
                setShowBadge(true)
                enableVibration(true)
                enableLights(true)
            }

            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun sendRegistrationToServer(token: String) {
        // Send FCM token to Firestore to associate with current user
        val currentUser = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser
        if (currentUser != null) {
            val db = com.google.firebase.firestore.FirebaseFirestore.getInstance()
            val userRef = db.collection("users").document(currentUser.uid)
            
            userRef.update("fcmToken", token)
                .addOnSuccessListener {
                    Timber.d("FCM token successfully registered for user: ${currentUser.uid}")
                }
                .addOnFailureListener { e ->
                    Timber.e(e, "Error registering FCM token")
                    // Try to create the document if it doesn't exist
                    userRef.set(
                        hashMapOf(
                            "fcmToken" to token,
                            "email" to currentUser.email,
                            "lastUpdated" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                        ),
                        com.google.firebase.firestore.SetOptions.merge()
                    ).addOnSuccessListener {
                        Timber.d("FCM token registered with new user document")
                    }
                }
        } else {
            Timber.w("No authenticated user to register FCM token")
        }
    }
}