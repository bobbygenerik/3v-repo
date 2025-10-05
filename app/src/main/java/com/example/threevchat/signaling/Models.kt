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
