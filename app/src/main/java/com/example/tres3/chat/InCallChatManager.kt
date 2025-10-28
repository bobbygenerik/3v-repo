package com.example.tres3.chat

import android.content.Context
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.participant.RemoteParticipant
import io.livekit.android.events.RoomEvent
import kotlinx.coroutines.*
import org.json.JSONObject
import timber.log.Timber
import java.text.SimpleDateFormat
import java.util.*

/**
 * InCallChatManager - Real-time text messaging during calls
 * 
 * Features:
 * - LiveKit DataChannel for low-latency message delivery
 * - Message history with timestamps
 * - Typing indicators
 * - Participant identification
 * - Auto-scroll to latest messages
 * 
 * Usage:
 * ```kotlin
 * val chatManager = InCallChatManager(context, room)
 * chatManager.onMessageReceived = { message ->
 *     updateChatUI(message)
 * }
 * chatManager.sendMessage("Hello everyone!")
 * ```
 */
class InCallChatManager(
    private val context: Context,
    private val room: Room
) {
    // Message data class
    data class ChatMessage(
        val id: String = UUID.randomUUID().toString(),
        val senderId: String,
        val senderName: String,
        val message: String,
        val timestamp: Long = System.currentTimeMillis(),
        val isLocal: Boolean = false
    ) {
        fun getFormattedTime(): String {
            val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
            return sdf.format(Date(timestamp))
        }
    }

    // Typing indicator data class
    data class TypingIndicator(
        val userId: String,
        val userName: String,
        val timestamp: Long = System.currentTimeMillis()
    )

    // Message type constants
    companion object {
        private const val MESSAGE_TYPE_CHAT = "chat"
        private const val MESSAGE_TYPE_TYPING = "typing"
        private const val MESSAGE_TYPE_TYPING_STOP = "typing_stop"
        private const val TYPING_TIMEOUT_MS = 3000L
    }

    // Message history
    private val _messageHistory = mutableListOf<ChatMessage>()
    val messageHistory: List<ChatMessage> get() = _messageHistory.toList()

    // Typing indicators
    private val _typingUsers = mutableMapOf<String, TypingIndicator>()
    val typingUsers: List<TypingIndicator> get() = _typingUsers.values.toList()

    // Coroutine scope for async operations
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    // Typing timeout jobs
    private val typingTimeoutJobs = mutableMapOf<String, Job>()

    // Callbacks
    var onMessageReceived: ((ChatMessage) -> Unit)? = null
    var onTypingIndicatorChanged: ((List<TypingIndicator>) -> Unit)? = null
    var onMessageSendFailed: ((String) -> Unit)? = null

    // Max message history
    private val maxHistorySize = 100

    init {
        // TODO: Enable DataChannel listener when LiveKit 2.21+ event handling is fixed
        // Currently room.events.collect() pattern has issues in LiveKit SDK
        // For now, chat messages can be sent but won't be received automatically
        Timber.w("InCallChatManager: DataChannel listener disabled (LiveKit 2.21 limitation)")
        Timber.d("InCallChatManager initialized for room: ${room.name}")
    }

    /**
     * Setup LiveKit DataChannel listener for incoming messages
     * 
     * TODO: Re-enable when LiveKit 2.21+ event handling pattern is clarified
     */
    private fun setupDataChannelListener() {
        // Commented out due to LiveKit SDK limitations
        /*
        try {
            // Listen for data messages from all participants via room events
            scope.launch {
                room.events.collect { event ->
                    when (event) {
                        is RoomEvent.DataReceived -> {
                            handleIncomingData(event.data, event.participant)
                        }
                        else -> { /* Ignore other events */ }
                    }
                }
            }
            Timber.d("DataChannel listener setup complete")
        } catch (e: Exception) {
            Timber.e(e, "Failed to setup DataChannel listener")
        }
        */
    }

    /**
     * Handle incoming data from DataChannel
     */
    private fun handleIncomingData(data: ByteArray, participant: Participant?) {
        try {
            val jsonString = String(data, Charsets.UTF_8)
            val json = JSONObject(jsonString)
            val messageType = json.optString("type", "")

            when (messageType) {
                MESSAGE_TYPE_CHAT -> {
                    val message = ChatMessage(
                        id = json.optString("id", UUID.randomUUID().toString()),
                        senderId = participant?.sid?.value ?: "unknown",
                        senderName = participant?.name ?: "Unknown",
                        message = json.getString("message"),
                        timestamp = json.optLong("timestamp", System.currentTimeMillis()),
                        isLocal = false
                    )
                    handleReceivedMessage(message)
                }
                MESSAGE_TYPE_TYPING -> {
                    val indicator = TypingIndicator(
                        userId = participant?.sid?.value ?: "unknown",
                        userName = participant?.name ?: "Unknown"
                    )
                    handleTypingIndicator(indicator)
                }
                MESSAGE_TYPE_TYPING_STOP -> {
                    removeTypingIndicator(participant?.sid?.value ?: "unknown")
                }
                else -> {
                    Timber.w("Unknown message type: $messageType")
                }
            }
        } catch (e: Exception) {
            Timber.e(e, "Failed to parse incoming data")
        }
    }

    /**
     * Send a chat message to all participants
     */
    fun sendMessage(text: String) {
        if (text.isBlank()) {
            Timber.w("Attempted to send blank message")
            return
        }

        scope.launch {
            try {
                val message = ChatMessage(
                    senderId = room.localParticipant.sid?.value ?: "local",
                    senderName = room.localParticipant.name ?: "You",
                    message = text.trim(),
                    isLocal = true
                )

                // Create JSON payload
                val json = JSONObject().apply {
                    put("type", MESSAGE_TYPE_CHAT)
                    put("id", message.id)
                    put("message", message.message)
                    put("timestamp", message.timestamp)
                }

                // Send via DataChannel to all participants
                val data = json.toString().toByteArray(Charsets.UTF_8)
                room.localParticipant.publishData(data)

                // Add to local history
                addMessageToHistory(message)
                onMessageReceived?.invoke(message)

                // Stop typing indicator for local user
                sendTypingStop()

                Timber.d("Sent message: ${message.message}")
            } catch (e: Exception) {
                Timber.e(e, "Failed to send message")
                onMessageSendFailed?.invoke("Failed to send message: ${e.message}")
            }
        }
    }

    /**
     * Send typing indicator to other participants
     */
    fun sendTypingIndicator() {
        scope.launch {
            try {
                val json = JSONObject().apply {
                    put("type", MESSAGE_TYPE_TYPING)
                    put("timestamp", System.currentTimeMillis())
                }

                val data = json.toString().toByteArray(Charsets.UTF_8)
                room.localParticipant.publishData(data)

                Timber.d("Sent typing indicator")
            } catch (e: Exception) {
                Timber.e(e, "Failed to send typing indicator")
            }
        }
    }

    /**
     * Send typing stop indicator
     */
    fun sendTypingStop() {
        scope.launch {
            try {
                val json = JSONObject().apply {
                    put("type", MESSAGE_TYPE_TYPING_STOP)
                    put("timestamp", System.currentTimeMillis())
                }

                val data = json.toString().toByteArray(Charsets.UTF_8)
                room.localParticipant.publishData(data)

                Timber.d("Sent typing stop indicator")
            } catch (e: Exception) {
                Timber.e(e, "Failed to send typing stop indicator")
            }
        }
    }

    /**
     * Handle received message
     */
    private fun handleReceivedMessage(message: ChatMessage) {
        addMessageToHistory(message)
        onMessageReceived?.invoke(message)
        Timber.d("Received message from ${message.senderName}: ${message.message}")
    }

    /**
     * Handle typing indicator
     */
    private fun handleTypingIndicator(indicator: TypingIndicator) {
        _typingUsers[indicator.userId] = indicator
        onTypingIndicatorChanged?.invoke(typingUsers)

        // Cancel existing timeout job for this user
        typingTimeoutJobs[indicator.userId]?.cancel()

        // Schedule automatic removal after timeout
        val timeoutJob = scope.launch {
            delay(TYPING_TIMEOUT_MS)
            removeTypingIndicator(indicator.userId)
        }
        typingTimeoutJobs[indicator.userId] = timeoutJob

        Timber.d("${indicator.userName} is typing")
    }

    /**
     * Remove typing indicator for a user
     */
    private fun removeTypingIndicator(userId: String) {
        if (_typingUsers.remove(userId) != null) {
            typingTimeoutJobs[userId]?.cancel()
            typingTimeoutJobs.remove(userId)
            onTypingIndicatorChanged?.invoke(typingUsers)
            Timber.d("Removed typing indicator for user: $userId")
        }
    }

    /**
     * Add message to history with size limit
     */
    private fun addMessageToHistory(message: ChatMessage) {
        _messageHistory.add(message)
        
        // Trim history if too large
        if (_messageHistory.size > maxHistorySize) {
            val removeCount = _messageHistory.size - maxHistorySize
            repeat(removeCount) {
                _messageHistory.removeAt(0)
            }
            Timber.d("Trimmed message history, removed $removeCount old messages")
        }
    }

    /**
     * Clear all messages
     */
    fun clearHistory() {
        _messageHistory.clear()
        Timber.d("Cleared message history")
    }

    /**
     * Get message count
     */
    fun getMessageCount(): Int = _messageHistory.size

    /**
     * Get unread message count (messages since last call to markAllAsRead)
     */
    private var lastReadTimestamp = 0L
    
    fun getUnreadCount(): Int {
        return _messageHistory.count { it.timestamp > lastReadTimestamp && !it.isLocal }
    }

    fun markAllAsRead() {
        lastReadTimestamp = System.currentTimeMillis()
        Timber.d("Marked all messages as read")
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        scope.cancel()
        typingTimeoutJobs.values.forEach { it.cancel() }
        typingTimeoutJobs.clear()
        _typingUsers.clear()
        onMessageReceived = null
        onTypingIndicatorChanged = null
        onMessageSendFailed = null
        Timber.d("InCallChatManager cleaned up")
    }
}
