package com.example.tres3.presence

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.tasks.await
import java.util.Date

/**
 * User presence states
 */
enum class UserStatus {
    ONLINE,      // Active and available
    OFFLINE,     // Not connected
    BUSY,        // In a call
    AWAY         // Inactive for > 5 minutes
}

/**
 * Manages user presence and status in Firestore
 * - Tracks online/offline/busy/away status
 * - Auto-updates on app lifecycle changes
 * - Syncs across all devices
 */
object UserPresenceManager {
    
    private val firestore = FirebaseFirestore.getInstance()
    private val auth = FirebaseAuth.getInstance()
    
    private var presenceListener: ListenerRegistration? = null
    private var lastActivityTime = System.currentTimeMillis()
    private const val AWAY_THRESHOLD_MS = 5 * 60 * 1000 // 5 minutes
    
    /**
     * Initialize presence tracking for current user
     */
    fun initialize(context: Context) {
        val currentUser = auth.currentUser ?: return
        
        Log.d("UserPresenceManager", "🟢 Initializing presence for user: ${currentUser.uid}")
        
        // Set initial status to ONLINE using sync method
        setStatusSync(UserStatus.ONLINE)
        
        // Setup disconnect cleanup (when app closes)
        setupDisconnectCleanup()
    }
    
    /**
     * Update user status
     */
    suspend fun setStatus(status: UserStatus) {
        val currentUser = auth.currentUser ?: return
        
        try {
            val userRef = firestore.collection("users").document(currentUser.uid)
            
            val statusData = hashMapOf(
                "status" to status.name,
                "lastSeen" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                "lastActivity" to Date()
            )
            
            userRef.set(statusData, SetOptions.merge()).await()
            
            Log.d("UserPresenceManager", "✅ Status updated to: $status")
        } catch (e: Exception) {
            Log.e("UserPresenceManager", "❌ Failed to update status: ${e.message}", e)
        }
    }
    
    /**
     * Set status synchronously (for lifecycle callbacks)
     */
    fun setStatusSync(status: UserStatus) {
        val currentUser = auth.currentUser ?: return
        
        try {
            val userRef = firestore.collection("users").document(currentUser.uid)
            
            val statusData = hashMapOf(
                "status" to status.name,
                "lastSeen" to com.google.firebase.firestore.FieldValue.serverTimestamp(),
                "lastActivity" to Date()
            )
            
            // Use non-blocking set (will complete eventually)
            userRef.set(statusData, SetOptions.merge())
            
            Log.d("UserPresenceManager", "✅ Status queued for update: $status")
        } catch (e: Exception) {
            Log.e("UserPresenceManager", "❌ Failed to queue status update: ${e.message}")
        }
    }
    
    /**
     * Mark user as in a call (BUSY)
     */
    suspend fun markInCall(callRoomName: String) {
        val currentUser = auth.currentUser ?: return
        
        try {
            val userRef = firestore.collection("users").document(currentUser.uid)
            
            userRef.set(
                hashMapOf(
                    "status" to UserStatus.BUSY.name,
                    "currentCall" to callRoomName,
                    "lastSeen" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                ),
                SetOptions.merge()
            ).await()
            
            Log.d("UserPresenceManager", "📞 Marked as BUSY in call: $callRoomName")
        } catch (e: Exception) {
            Log.e("UserPresenceManager", "❌ Failed to mark in call: ${e.message}", e)
        }
    }
    
    /**
     * Clear call status (back to ONLINE)
     */
    suspend fun clearCallStatus() {
        val currentUser = auth.currentUser ?: return
        
        try {
            val userRef = firestore.collection("users").document(currentUser.uid)
            
            userRef.set(
                hashMapOf(
                    "status" to UserStatus.ONLINE.name,
                    "currentCall" to com.google.firebase.firestore.FieldValue.delete(),
                    "lastSeen" to com.google.firebase.firestore.FieldValue.serverTimestamp()
                ),
                SetOptions.merge()
            ).await()
            
            Log.d("UserPresenceManager", "✅ Call status cleared, back to ONLINE")
        } catch (e: Exception) {
            Log.e("UserPresenceManager", "❌ Failed to clear call status: ${e.message}", e)
        }
    }
    
    /**
     * Listen to another user's presence
     */
    fun listenToUserPresence(
        userId: String,
        onStatusChange: (UserStatus, Date?) -> Unit
    ): ListenerRegistration {
        val userRef = firestore.collection("users").document(userId)
        
        return userRef.addSnapshotListener { snapshot, error ->
            if (error != null) {
                Log.e("UserPresenceManager", "Error listening to presence: ${error.message}")
                return@addSnapshotListener
            }
            
            if (snapshot != null && snapshot.exists()) {
                val statusString = snapshot.getString("status") ?: "OFFLINE"
                val lastSeen = snapshot.getDate("lastSeen")
                
                val status = try {
                    UserStatus.valueOf(statusString)
                } catch (e: Exception) {
                    UserStatus.OFFLINE
                }
                
                onStatusChange(status, lastSeen)
            } else {
                onStatusChange(UserStatus.OFFLINE, null)
            }
        }
    }
    
    /**
     * Get user status (one-time fetch)
     */
    suspend fun getUserStatus(userId: String): UserStatus {
        return try {
            val userDoc = firestore.collection("users").document(userId).get().await()
            
            if (userDoc.exists()) {
                val statusString = userDoc.getString("status") ?: "OFFLINE"
                val lastSeen = userDoc.getDate("lastSeen")
                
                // Check if user is away (no activity for 5+ minutes)
                if (lastSeen != null) {
                    val timeSinceActivity = System.currentTimeMillis() - lastSeen.time
                    if (timeSinceActivity > AWAY_THRESHOLD_MS && statusString == "ONLINE") {
                        return UserStatus.AWAY
                    }
                }
                
                try {
                    UserStatus.valueOf(statusString)
                } catch (e: Exception) {
                    UserStatus.OFFLINE
                }
            } else {
                UserStatus.OFFLINE
            }
        } catch (e: Exception) {
            Log.e("UserPresenceManager", "Failed to get user status: ${e.message}")
            UserStatus.OFFLINE
        }
    }
    
    /**
     * Update last activity timestamp (call this on user interaction)
     */
    fun updateActivity() {
        lastActivityTime = System.currentTimeMillis()
        
        val currentUser = auth.currentUser ?: return
        
        // Update in Firestore
        firestore.collection("users").document(currentUser.uid)
            .update(
                "lastActivity", com.google.firebase.firestore.FieldValue.serverTimestamp()
            )
    }
    
    /**
     * Check if user should be marked as AWAY
     */
    fun checkAwayStatus() {
        val timeSinceActivity = System.currentTimeMillis() - lastActivityTime
        
        if (timeSinceActivity > AWAY_THRESHOLD_MS) {
            setStatusSync(UserStatus.AWAY)
        }
    }
    
    /**
     * Setup disconnect cleanup (when app closes/crashes)
     * Note: Firestore doesn't have onDisconnect() like Realtime Database,
     * so we use app lifecycle to handle this
     */
    private fun setupDisconnectCleanup() {
        // This will be called when app is properly closed
        Runtime.getRuntime().addShutdownHook(Thread {
            setStatusSync(UserStatus.OFFLINE)
        })
    }
    
    /**
     * Cleanup presence listener
     */
    fun cleanup() {
        presenceListener?.remove()
        setStatusSync(UserStatus.OFFLINE)
        Log.d("UserPresenceManager", "🔴 Presence manager cleaned up")
    }
}
