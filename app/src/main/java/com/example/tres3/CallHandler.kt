package com.example.tres3

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

object CallHandler {

    fun startCall(context: Context, url: String, token: String, callerName: String = "Unknown") {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                Log.d("CallHandler", "Connecting to room...")
                LiveKitManager.connectToRoom(context, url, token)
                val intent = Intent(context, InCallActivity::class.java).apply {
                    putExtra("caller_name", callerName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                ContextCompat.startActivity(context, intent, null)
            } catch (e: Exception) {
                Log.e("CallHandler", "Error starting call: ${e.message}", e)
            }
        }
    }
}
