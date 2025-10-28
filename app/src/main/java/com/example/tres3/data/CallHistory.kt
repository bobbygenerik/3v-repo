package com.example.tres3.data

import com.google.firebase.firestore.DocumentId
import com.google.firebase.firestore.ServerTimestamp
import java.util.Date

data class CallHistory(
    @DocumentId
    val id: String = "",
    val callerId: String = "",
    val callerName: String = "",
    val receiverId: String = "",
    val receiverName: String = "",
    val roomName: String = "",
    val callType: CallType = CallType.VIDEO,
    val callStatus: CallStatus = CallStatus.COMPLETED,
    val duration: Long = 0, // in seconds
    @ServerTimestamp
    val timestamp: Date? = null
)

enum class CallType {
    AUDIO,
    VIDEO,
    GROUP
}

enum class CallStatus {
    COMPLETED,
    MISSED,
    REJECTED,
    FAILED
}