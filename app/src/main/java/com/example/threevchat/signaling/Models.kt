package com.example.threevchat.signaling

data class CallSession(
    val id: String = "",
    val caller: String = "",
    val callee: String = "",
    val status: String = "ringing",
    val offerSdp: String? = null,
    val answerSdp: String? = null
)

data class IceCandidateDTO(
    val sdpMid: String = "",
    val sdpMLineIndex: Int = 0,
    val candidate: String = "",
    val from: String = ""
)

data class Participant(
    val id: String = "",
    val active: Boolean = true,
    val joinedAt: Long = System.currentTimeMillis()
)

data class SignalDTO(
    val type: String = "", // offer, answer, ice
    val from: String = "",
    val to: String = "",
    val sdp: String? = null,
    val sdpType: String? = null, // OFFER/ANSWER
    val sdpMid: String? = null,
    val sdpMLineIndex: Int? = null,
    val candidate: String? = null,
    val timestamp: Long = System.currentTimeMillis()
)
