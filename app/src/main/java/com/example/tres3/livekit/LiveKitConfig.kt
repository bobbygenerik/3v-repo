package com.example.tres3.livekit

import android.util.Base64
import com.example.tres3.BuildConfig
import org.json.JSONObject
import java.util.*
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object LiveKitConfig {
    // LiveKit Cloud credentials - should be configured via BuildConfig
    // WARNING: These should NEVER be hardcoded in production!
    // Use environment variables or secure server-side token generation
    val LIVEKIT_URL: String = BuildConfig.LIVEKIT_URL
    val API_KEY: String = BuildConfig.LIVEKIT_API_KEY
    val API_SECRET: String = BuildConfig.LIVEKIT_API_SECRET

    // Token validity duration (24 hours)
    private const val TOKEN_VALIDITY_SECONDS = 24 * 60 * 60

    /**
     * Generates a JWT token for LiveKit room access
     * @param roomName The name of the room to join
     * @param participantName The name/identity of the participant
     * @return JWT token string
     * @throws IllegalStateException if API credentials are not configured
     */
    fun generateToken(roomName: String, participantName: String): String {
        if (API_KEY.isEmpty() || API_SECRET.isEmpty()) {
            throw IllegalStateException("LiveKit API credentials not configured. Set LIVEKIT_API_KEY and LIVEKIT_API_SECRET in BuildConfig.")
        }

        val now = System.currentTimeMillis() / 1000
        val expiry = now + TOKEN_VALIDITY_SECONDS

        val header = JSONObject().apply {
            put("alg", "HS256")
            put("typ", "JWT")
        }

        val payload = JSONObject().apply {
            put("iss", API_KEY)
            put("exp", expiry)
            put("nbf", now)
            put("sub", UUID.randomUUID().toString())
            put("name", participantName)
            put("room", roomName)
            put("video", JSONObject().apply {
                put("room", roomName)
                put("roomJoin", true)
                put("canPublish", true)
                put("canSubscribe", true)
            })
        }

        val headerEncoded = base64UrlEncode(header.toString().toByteArray())
        val payloadEncoded = base64UrlEncode(payload.toString().toByteArray())

        val message = "$headerEncoded.$payloadEncoded"
        val signature = hmacSha256(message, API_SECRET)

        return "$message.$signature"
    }

    private fun base64UrlEncode(data: ByteArray): String {
        return Base64.encodeToString(data, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun hmacSha256(message: String, secret: String): String {
        val algorithm = "HmacSHA256"
        val key = SecretKeySpec(secret.toByteArray(), algorithm)
        val mac = Mac.getInstance(algorithm)
        mac.init(key)
        return base64UrlEncode(mac.doFinal(message.toByteArray()))
    }
}