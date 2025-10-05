package com.example.threevchat.webrtc

import org.webrtc.PeerConnection

object WebRtcConfig {
    val iceServers: List<PeerConnection.IceServer> = listOf(
        PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer()
    )

    const val TARGET_WIDTH = 1920
    const val TARGET_HEIGHT = 1080
    const val TARGET_FPS = 30

    const val BITRATE_DIRECT_BPS = 3_000_000
    const val BITRATE_RELAY_BPS = 1_800_000
}
