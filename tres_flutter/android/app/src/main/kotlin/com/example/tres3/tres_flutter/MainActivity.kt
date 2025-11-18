package com.example.tres3.tres_flutter

import android.os.Bundle
import android.view.WindowManager
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Keep screen on during calls
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        // Handle incoming call intents
        handleIncomingCallIntent()
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingCallIntent()
    }
    
    private fun handleIncomingCallIntent() {
        intent?.let { itIntent ->
            // If intent has data URI, keep existing behavior
            itIntent.data?.let { uri ->
                if (uri.scheme == "tresvideo" && uri.host == "join") {
                    // Flutter deep link (existing behavior)
                    return
                }
            }

            // If intent has extras from notification (invitationId/fromName/callAction), convert to URI
            val invitationId = itIntent.getStringExtra("invitationId")
            val fromName = itIntent.getStringExtra("fromName")
            val callAction = itIntent.getStringExtra("callAction")
            if (!invitationId.isNullOrEmpty()) {
                val uriStr = Uri.Builder()
                    .scheme("tresvideo")
                    .authority("incoming")
                    .appendQueryParameter("invitationId", invitationId)
                    .apply { if (!fromName.isNullOrEmpty()) appendQueryParameter("fromName", fromName) }
                    .apply { if (!callAction.isNullOrEmpty()) appendQueryParameter("action", callAction) }
                    .build()
                itIntent.data = Uri.parse(uriStr.toString())
            }
        }
    }
}
