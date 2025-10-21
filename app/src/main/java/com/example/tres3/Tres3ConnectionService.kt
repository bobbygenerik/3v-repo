package com.example.tres3

import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log
import androidx.annotation.RequiresApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * ConnectionService integration for native Android call UI
 * Provides system-level call management with native animations
 */
class Tres3ConnectionService : ConnectionService() {
    
    companion object {
        private const val TAG = "Tres3ConnectionService"
        
        // Store active connections
        private val activeConnections = mutableMapOf<String, Tres3Connection>()
        
        fun getActiveConnection(callId: String): Tres3Connection? {
            return activeConnections[callId]
        }
        
        fun addConnection(callId: String, connection: Tres3Connection) {
            activeConnections[callId] = connection
        }
        
        fun removeConnection(callId: String) {
            activeConnections.remove(callId)
        }
    }
    
    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        Log.d(TAG, "📞 Creating outgoing connection")
        
        val extras = request?.extras
        val contactName = extras?.getString("contactName") ?: "Unknown"
        val contactId = extras?.getString("contactId") ?: ""
        val roomName = extras?.getString("roomName") ?: ""
        val url = extras?.getString("url") ?: ""
        val token = extras?.getString("token") ?: ""
        
        val connection = Tres3Connection(
            context = applicationContext,
            isIncoming = false,
            contactName = contactName,
            contactId = contactId,
            roomName = roomName,
            url = url,
            token = token
        )
        
        // Set up connection properties
        connection.setAddress(request?.address, TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(contactName, TelecomManager.PRESENTATION_ALLOWED)
        connection.setVideoState(VideoProfile.STATE_BIDIRECTIONAL)
        
        addConnection(roomName, connection)
        
        return connection
    }
    
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        Log.d(TAG, "📱 Creating incoming connection")
        
        val extras = request?.extras
        val callerName = extras?.getString("callerName") ?: "Unknown Caller"
        val callerId = extras?.getString("callerId") ?: ""
        val invitationId = extras?.getString("invitationId") ?: ""
        val roomName = extras?.getString("roomName") ?: ""
        val url = extras?.getString("url") ?: ""
        val token = extras?.getString("token") ?: ""
        
        val connection = Tres3Connection(
            context = applicationContext,
            isIncoming = true,
            contactName = callerName,
            contactId = callerId,
            roomName = roomName,
            url = url,
            token = token,
            invitationId = invitationId
        )
        
        // Set up connection properties
        connection.setAddress(request?.address, TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
        connection.setVideoState(VideoProfile.STATE_BIDIRECTIONAL)
        
        // Ring for incoming call
        connection.setRinging()
        
        addConnection(roomName, connection)
        
        return connection
    }
}

/**
 * Represents a single video call connection
 * Handles connection lifecycle and integrates with LiveKit
 */
class Tres3Connection(
    private val context: android.content.Context,
    private val isIncoming: Boolean,
    private val contactName: String,
    private val contactId: String,
    private val roomName: String,
    private val url: String,
    private val token: String,
    private val invitationId: String = ""
) : Connection() {
    
    private val TAG = "Tres3Connection"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    
    init {
        // Set connection capabilities
        connectionCapabilities = CAPABILITY_SUPPORT_HOLD or
                CAPABILITY_HOLD or
                CAPABILITY_MUTE or
                CAPABILITY_SUPPORTS_VT_LOCAL_BIDIRECTIONAL or
                CAPABILITY_SUPPORTS_VT_REMOTE_BIDIRECTIONAL
        
        // Set connection properties
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            connectionProperties = PROPERTY_SELF_MANAGED
        }
        
        // Set video state
        videoState = VideoProfile.STATE_BIDIRECTIONAL
        
        Log.d(TAG, "🔗 Connection created for: $contactName (incoming: $isIncoming)")
    }
    
    override fun onShowIncomingCallUi() {
        Log.d(TAG, "📲 Show incoming call UI for: $contactName")
        
        // Android will show native incoming call UI with animations
        // User will see system UI with Accept/Reject buttons
    }
    
    override fun onAnswer(videoState: Int) {
        Log.d(TAG, "✅ Call answered: $contactName")
        
        scope.launch {
            try {
                // Mark invitation as accepted if incoming
                if (isIncoming && invitationId.isNotEmpty()) {
                    CallSignalingManager.acceptCallInvitation(invitationId)
                }
                
                // Connect to LiveKit room
                val room = LiveKitManager.connectToRoom(
                    context,
                    url,
                    token
                )
                
                // Enable camera and microphone
                room.localParticipant.setCameraEnabled(true)
                room.localParticipant.setMicrophoneEnabled(true)
                
                // Set connection as active
                setActive()
                
                // Launch InCallActivity
                val intent = android.content.Intent(
                    context,
                    InCallActivity::class.java
                ).apply {
                    putExtra("recipient_name", contactName)
                    putExtra("contact_id", contactId)
                    putExtra("room_name", roomName)
                    flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                            android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                context.startActivity(intent)
                
                Log.d(TAG, "🎥 Video call started")
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error answering call", e)
                setDisconnected(DisconnectCause(DisconnectCause.ERROR))
                destroy()
            }
        }
    }
    
    override fun onReject() {
        Log.d(TAG, "❌ Call rejected: $contactName")
        
        scope.launch {
            try {
                if (isIncoming && invitationId.isNotEmpty()) {
                    CallSignalingManager.rejectCallInvitation(invitationId)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error rejecting call", e)
            }
        }
        
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
        Tres3ConnectionService.removeConnection(roomName)
    }
    
    override fun onDisconnect() {
        Log.d(TAG, "📴 Call disconnected: $contactName")
        
        scope.launch {
            try {
                LiveKitManager.disconnectFromRoom()
            } catch (e: Exception) {
                Log.e(TAG, "Error disconnecting", e)
            }
        }
        
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        Tres3ConnectionService.removeConnection(roomName)
    }
    
    override fun onAbort() {
        Log.d(TAG, "🚫 Call aborted: $contactName")
        
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        Tres3ConnectionService.removeConnection(roomName)
    }
    
    override fun onHold() {
        Log.d(TAG, "⏸️  Call on hold: $contactName")
        
        scope.launch {
            try {
                val room = LiveKitManager.currentRoom
                room?.localParticipant?.setCameraEnabled(false)
                room?.localParticipant?.setMicrophoneEnabled(false)
            } catch (e: Exception) {
                Log.e(TAG, "Error holding call", e)
            }
        }
        
        setOnHold()
    }
    
    override fun onUnhold() {
        Log.d(TAG, "▶️  Call resumed: $contactName")
        
        scope.launch {
            try {
                val room = LiveKitManager.currentRoom
                room?.localParticipant?.setCameraEnabled(true)
                room?.localParticipant?.setMicrophoneEnabled(true)
            } catch (e: Exception) {
                Log.e(TAG, "Error resuming call", e)
            }
        }
        
        setActive()
    }
    
    override fun onStateChanged(state: Int) {
        Log.d(TAG, "📊 Connection state changed to: $state")
        super.onStateChanged(state)
    }
}
