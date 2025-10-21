package com.example.tres3

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class CallNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        val invitationId = intent.getStringExtra("invitationId") ?: return
        
        Log.d("CallNotificationReceiver", "Action received: $action for invitation: $invitationId")
        
        when (action) {
            "ACCEPT_CALL" -> {
                // Cancel notification
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                notificationManager.cancel(invitationId.hashCode())
                
                // Mark as accepted
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        CallSignalingManager.acceptCallInvitation(invitationId)
                    } catch (e: Exception) {
                        Log.e("CallNotificationReceiver", "Error accepting call", e)
                    }
                }
                
                // Launch IncomingCallActivity to handle the connection
                val fullScreenIntent = Intent(context, IncomingCallActivity::class.java).apply {
                    putExtra("invitationId", invitationId)
                    putExtra("fromUserName", intent.getStringExtra("fromUserName"))
                    putExtra("fromUserId", intent.getStringExtra("fromUserId"))
                    putExtra("roomName", intent.getStringExtra("roomName"))
                    putExtra("url", intent.getStringExtra("url"))
                    putExtra("token", intent.getStringExtra("token"))
                    putExtra("callerPhotoUrl", intent.getStringExtra("callerPhotoUrl"))
                    putExtra("autoAccept", true) // Auto-accept since user clicked Accept
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                context.startActivity(fullScreenIntent)
            }
            
            "DECLINE_CALL" -> {
                // Cancel notification
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                notificationManager.cancel(invitationId.hashCode())
                
                // Mark as rejected
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        CallSignalingManager.rejectCallInvitation(invitationId)
                    } catch (e: Exception) {
                        Log.e("CallNotificationReceiver", "Error rejecting call", e)
                    }
                }
            }
        }
    }
}
