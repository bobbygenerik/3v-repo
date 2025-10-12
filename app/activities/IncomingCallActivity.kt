package com.example.threevchat.activities

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

class IncomingCallActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sessionId = intent.getStringExtra("sessionId").orEmpty()
        val role = intent.getStringExtra("role") ?: "callee"
        val from = intent.getStringExtra("from") ?: "Unknown"
        setContent {
            MaterialTheme {
                IncomingCallScreen(
                    from = from,
                    onAccept = {
                        val i = android.content.Intent(this, CallActivity::class.java)
                            .putExtra("sessionId", sessionId)
                            .putExtra("role", role)
                            .putExtra("recipientName", from)
                        startActivity(i)
                        finish()
                    },
                    onDecline = { finish() }
                )
            }
        }
    }
}

@Composable
private fun IncomingCallScreen(from: String, onAccept: () -> Unit, onDecline: () -> Unit) {
    Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    brush = Brush.verticalGradient(
                        listOf(
                            Color(0xFF001F3F),
                            Color(0xFF003F7F),
                            Color(0xFF0074D9)
                        )
                    )
                )
                .padding(24.dp),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(text = "Incoming call", color = Color.White, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text(text = from, color = Color.White, style = MaterialTheme.typography.titleLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(onClick = onDecline) { Text("Decline") }
                    Button(onClick = onAccept) { Text("Accept") }
                }
            }
        }
    }
}
