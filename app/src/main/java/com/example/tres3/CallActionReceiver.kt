package com.example.tres3

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore

class CallActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "DECLINE_CALL" -> {
                // Cancel the incoming call notification
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(1)

                // Send decline signal to caller via Firestore
                val callerId = intent.getStringExtra("callerId")
                val currentUser = FirebaseAuth.getInstance().currentUser
                
                if (callerId != null && currentUser != null) {
                    val db = FirebaseFirestore.getInstance()
                    
                    // Send a decline message to the caller
                    val declineData = hashMapOf(
                        "type" to "call_declined",
                        "declinedBy" to currentUser.uid,
                        "declinedByName" to (currentUser.displayName ?: currentUser.email),
                        "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                    )
                    
                    db.collection("users")
                        .document(callerId)
                        .collection("callSignals")
                        .add(declineData)
                        .addOnSuccessListener {
                            Log.d("CallActionReceiver", "Decline signal sent to caller: $callerId")
                        }
                        .addOnFailureListener { e ->
                            Log.e("CallActionReceiver", "Error sending decline signal", e)
                        }
                } else {
                    Log.w("CallActionReceiver", "Cannot send decline signal - missing caller ID or user not authenticated")
                }
            }
        }
    }
}