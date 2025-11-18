package com.example.tres3.tres_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val invitationId = intent.getStringExtra("invitationId") ?: ""

        val i = Intent(context, MainActivity::class.java).apply {
            putExtra("invitationId", invitationId)
            putExtra("callAction", action)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(i)
    }
}
