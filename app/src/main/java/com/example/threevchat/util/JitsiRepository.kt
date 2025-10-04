package com.example.threevchat.util

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import org.jitsi.meet.sdk.JitsiMeet
import org.jitsi.meet.sdk.JitsiMeetActivity
import org.jitsi.meet.sdk.JitsiMeetConferenceOptions
import java.net.URL

class JitsiRepository(private val app: Application) {

    init {
        try {
            val serverURL = URL("https://meet.jit.si")
            val defaultOptions = JitsiMeetConferenceOptions.Builder()
                .setServerURL(serverURL)
                .setFeatureFlag("welcomepage.enabled", false)
                .setFeatureFlag("add-people.enabled", false)
                .setFeatureFlag("invite.enabled", false)
                .setFeatureFlag("p2p.enabled", true)
                .build()
            JitsiMeet.setDefaultConferenceOptions(defaultOptions)
        } catch (e: Exception) {
            Log.e("Jitsi", "Error init", e)
        }
    }

    fun buildRoomNameForCallee(callee: String): String {
        // Simple normalization -> room name
        return "p2p_${callee.lowercase().replace("[^a-z0-9]".toRegex(), "") }"
    }

    fun launchJitsi(context: Context, room: String) {
        val options = JitsiMeetConferenceOptions.Builder()
            .setRoom(room)
            .setAudioOnly(false)
            .build()
        JitsiMeetActivity.launch(context, options)
    }

    fun parseCallIntent(intent: Intent): String? {
        val data: Uri? = intent.data
        if (data != null) {
            return when (data.scheme) {
                "p2pvideo" -> data.lastPathSegment
                "content" -> if (data.host == "com.example.threevchat") data.lastPathSegment else null
                "tel" -> data.schemeSpecificPart // phone number
                else -> null
            }?.let { buildRoomNameForCallee(it) }
        }
        intent.getStringExtra("callee")?.let { return buildRoomNameForCallee(it) }
        return null
    }
}
