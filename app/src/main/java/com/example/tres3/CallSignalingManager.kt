package com.example.tres3

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import kotlinx.coroutines.tasks.await

/**
 * Manages call signaling through Firestore
 * - Sends call invitations to other users
 * - Listens for incoming call invitations
 * - Handles call invitation lifecycle
 */
object CallSignalingManager {
    
    private const val TAG = "CallSignaling"
    private var callSignalListener: ListenerRegistration? = null
    
    /**
     * Send a call invitation to another user
     * @param recipientUserId The Firestore user ID of the person being called
     * @param roomName The LiveKit room name
     * @param roomUrl The LiveKit server URL  
     * @param token The LiveKit token for the recipient
     */
    suspend fun sendCallInvitation(
        recipientUserId: String,
        recipientName: String,
        roomName: String,
        roomUrl: String,
        token: String,
        callerAvatarUrl: String? = null
    ): Boolean {
        return try {
            val currentUser = FirebaseAuth.getInstance().currentUser
            if (currentUser == null) {
                Log.e(TAG, "Cannot send invitation: not authenticated")
                return false
            }
            
            val callerName = currentUser.displayName ?: currentUser.email ?: "Unknown"
            
            val inviteData = hashMapOf(
                "type" to "call_invite",
                "fromUserId" to currentUser.uid,
                "fromUserName" to callerName,
                "roomName" to roomName,
                "url" to roomUrl,
                "token" to token,
                "timestamp" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                "status" to "pending", // pending, accepted, rejected, missed
                "avatarUrl" to (callerAvatarUrl ?: "")
            )
            
            Log.d(TAG, "📤 Sending call invitation to $recipientName (ID: $recipientUserId)")
            Log.d(TAG, "   Room: $roomName")
            Log.d(TAG, "   Caller: $callerName")
            
            FirebaseFirestore.getInstance()
                .collection("users")
                .document(recipientUserId)
                .collection("callSignals")
                .add(inviteData)
                .await()
            
            Log.d(TAG, "✅ Call invitation sent successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send call invitation", e)
            false
        }
    }
    
    /**
     * Start listening for incoming call invitations
     * @param onCallReceived Callback when a new call invitation arrives
     */
    fun startListeningForCalls(
        context: Context,
        onCallReceived: (CallInvitation) -> Unit
    ) {
        val currentUser = FirebaseAuth.getInstance().currentUser
        if (currentUser == null) {
            Log.w(TAG, "Cannot listen for calls: not authenticated")
            return
        }
        
        // Remove any existing listener
        stopListeningForCalls()
        
        Log.d(TAG, "🎧 Starting to listen for call invitations for user: ${currentUser.uid}")
        Log.d(TAG, "   Listening path: users/${currentUser.uid}/callSignals")
        
        callSignalListener = FirebaseFirestore.getInstance()
            .collection("users")
            .document(currentUser.uid)
            .collection("callSignals")
            .whereEqualTo("status", "pending")
            .addSnapshotListener { snapshots, error ->
                if (error != null) {
                    Log.e(TAG, "❌ Error listening for call signals", error)
                    error.printStackTrace()
                    return@addSnapshotListener
                }
                
                Log.d(TAG, "🔔 Call signal listener triggered - snapshots: ${snapshots?.size() ?: 0} documents")
                
                if (snapshots == null) {
                    Log.w(TAG, "⚠️ Snapshots is null")
                    return@addSnapshotListener
                }
                
                if (snapshots.isEmpty) {
                    Log.d(TAG, "📭 No pending call signals")
                    return@addSnapshotListener
                }
                
                Log.d(TAG, "📬 Processing ${snapshots.size()} call signal documents")
                
                // Process new call invitations
                for (documentChange in snapshots.documentChanges) {
                    Log.d(TAG, "   Document change type: ${documentChange.type}")
                    if (documentChange.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                        val document = documentChange.document
                        Log.d(TAG, "   New call signal document ID: ${document.id}")
                        try {
                            val invitation = CallInvitation(
                                id = document.id,
                                fromUserId = document.getString("fromUserId") ?: "",
                                fromUserName = document.getString("fromUserName") ?: "Unknown",
                                roomName = document.getString("roomName") ?: "",
                                url = document.getString("url") ?: "",
                                token = document.getString("token") ?: "",
                                timestamp = document.getDate("timestamp"),
                                avatarUrl = document.getString("avatarUrl")
                            )
                            
                            Log.d(TAG, "📞 Incoming call from: ${invitation.fromUserName}")
                            Log.d(TAG, "   Room: ${invitation.roomName}")
                            
                            // Mark as received (not pending anymore)
                            document.reference.update("status", "ringing")
                            
                            onCallReceived(invitation)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing call invitation", e)
                        }
                    }
                }
            }
    }
    
    /**
     * Stop listening for call invitations
     */
    fun stopListeningForCalls() {
        callSignalListener?.remove()
        callSignalListener = null
        Log.d(TAG, "🔇 Stopped listening for call invitations")
    }
    
    /**
     * Mark a call invitation as accepted
     */
    suspend fun acceptCallInvitation(invitationId: String) {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser ?: return
            
            FirebaseFirestore.getInstance()
                .collection("users")
                .document(currentUser.uid)
                .collection("callSignals")
                .document(invitationId)
                .update("status", "accepted")
                .await()
            
            Log.d(TAG, "✅ Call invitation accepted")
        } catch (e: Exception) {
            Log.e(TAG, "Error accepting call invitation", e)
        }
    }
    
    /**
     * Mark a call invitation as rejected
     */
    suspend fun rejectCallInvitation(invitationId: String) {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser ?: return
            
            FirebaseFirestore.getInstance()
                .collection("users")
                .document(currentUser.uid)
                .collection("callSignals")
                .document(invitationId)
                .update("status", "rejected")
                .await()
            
            Log.d(TAG, "❌ Call invitation rejected")
        } catch (e: Exception) {
            Log.e(TAG, "Error rejecting call invitation", e)
        }
    }
    
    /**
     * Mark a call invitation as missed
     */
    suspend fun missCallInvitation(invitationId: String) {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser ?: return
            
            FirebaseFirestore.getInstance()
                .collection("users")
                .document(currentUser.uid)
                .collection("callSignals")
                .document(invitationId)
                .update("status", "missed")
                .await()
            
            Log.d(TAG, "📵 Call invitation marked as missed")
        } catch (e: Exception) {
            Log.e(TAG, "Error marking call as missed", e)
        }
    }
    
    /**
     * Clean up old call signals (older than 1 hour)
     */
    suspend fun cleanupOldCallSignals() {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser ?: return
            val oneHourAgo = System.currentTimeMillis() - (60 * 60 * 1000)
            
            val oldSignals = FirebaseFirestore.getInstance()
                .collection("users")
                .document(currentUser.uid)
                .collection("callSignals")
                .whereLessThan("timestamp", java.util.Date(oneHourAgo))
                .get()
                .await()
            
            for (document in oldSignals.documents) {
                document.reference.delete().await()
            }
            
            if (oldSignals.size() > 0) {
                Log.d(TAG, "🧹 Cleaned up ${oldSignals.size()} old call signals")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up old call signals", e)
        }
    }
}

/**
 * Data class representing an incoming call invitation
 */
data class CallInvitation(
    val id: String,
    val fromUserId: String,
    val fromUserName: String,
    val roomName: String,
    val url: String,
    val token: String,
    val timestamp: java.util.Date?,
    val avatarUrl: String? = null
)
