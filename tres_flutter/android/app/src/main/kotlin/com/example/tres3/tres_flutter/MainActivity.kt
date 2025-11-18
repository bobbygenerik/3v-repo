package com.example.tres3.tres_flutter

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Keep screen on during calls
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        // Handle incoming call intents
        handleIncomingCallIntent()
    }
    
    private fun handleIncomingCallIntent() {
        intent?.data?.let { uri ->
            if (uri.scheme == "tresvideo" && uri.host == "join") {
                // Pass deep link data to Flutter
                val roomId = uri.getQueryParameter("room")
                val token = uri.getQueryParameter("token")
                // Flutter will handle the actual call joining
            }
        }
    }
}
