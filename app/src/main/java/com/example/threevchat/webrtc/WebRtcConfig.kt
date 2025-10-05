package com.example.threevchat.webrtc

import com.example.threevchat.BuildConfig
import com.google.firebase.auth.FirebaseAuth
import org.webrtc.PeerConnection

object WebRtcConfig {
    fun iceServers(): List<PeerConnection.IceServer> {
        val list = mutableListOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer()
        )

        val host = BuildConfig.TURN_HOST?.trim().orEmpty()
        val port = BuildConfig.TURN_PORT
        val transport = BuildConfig.TURN_TRANSPORT?.trim().orEmpty().lowercase()
        if (host.isNotEmpty()) {
            val scheme = if (transport == "tls" || transport == "tcp-tls" || transport == "tls-tcp") "turns" else "turn"
            val url = "$scheme:$host:$port?transport=${if (transport == "tls") "tcp" else transport}"

            val mode = BuildConfig.TURN_USERNAME_MODE.uppercase()
            val password = BuildConfig.TURN_PASSWORD
            val username = when (mode) {
                "PHONE" -> FirebaseAuth.getInstance().currentUser?.phoneNumber ?: FirebaseAuth.getInstance().currentUser?.uid ?: ""
                else -> BuildConfig.TURN_STATIC_USERNAME
            }

            if (username.isNotBlank() && password.isNotBlank()) {
                list += PeerConnection.IceServer.builder(url)
                    .setUsername(username)
                    .setPassword(password)
                    .createIceServer()
            } else {
                // If no creds, still add as anonymous (some servers allow it), else omit
                list += PeerConnection.IceServer.builder(url).createIceServer()
            }
        }
        return list
    }

    const val TARGET_WIDTH = 1920
    const val TARGET_HEIGHT = 1080
    const val TARGET_FPS = 30

    const val BITRATE_DIRECT_BPS = 3_000_000
    const val BITRATE_RELAY_BPS = 1_800_000
}
