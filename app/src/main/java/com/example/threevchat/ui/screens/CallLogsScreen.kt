package com.example.threevchat.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.example.threevchat.viewmodel.MainViewModel
import com.example.threevchat.ui.theme.AppColors

@Composable
fun CallLogsScreen(vm: MainViewModel, userId: String) {
    val callLogs by vm.callLogs.collectAsState()
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var lastStartedAt by remember { mutableStateOf<Long?>(null) }
    var canLoadMore by remember { mutableStateOf(true) }

    // Fetch logs when screen appears
    LaunchedEffect(userId) {
        loading = true
        error = null
        try {
            vm.fetchCallLogs(userId)
            lastStartedAt = callLogs.lastOrNull()?.get("startedAt") as? Long
            canLoadMore = callLogs.size >= 20
        } catch (e: Exception) {
            error = e.message
        }
        loading = false
    }

    Scaffold { padding ->
        val bgGradient = Brush.verticalGradient(
            listOf(
                Color(0xFF001F3F),
                Color(0xFF003F7F),
                Color(0xFF0074D9)
            )
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(bgGradient)
                .padding(padding)
                .padding(16.dp),
            contentAlignment = Alignment.TopCenter
        ) {
            Column(
                Modifier
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text("History", style = MaterialTheme.typography.headlineSmall, color = AppColors.TextPrimary)
                if (loading) {
                CircularProgressIndicator()
                } else if (error != null) {
                Text("Error: $error", color = MaterialTheme.colorScheme.error)
                } else if (callLogs.isEmpty()) {
                Text("No call logs found.", color = AppColors.TextSecondary)
                } else {
                callLogs.forEach { log ->
                    val startedAt = log["startedAt"]
                    val dateStr = startedAt?.let {
                        try {
                            val sdf = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss")
                            val date = java.util.Date((it as Number).toLong())
                            sdf.format(date)
                        } catch (e: Exception) { it.toString() }
                    } ?: "Unknown"
                    val direction = if (log["callerId"] == userId) "Outgoing" else "Incoming"
                    val duration = log["durationSeconds"] ?: "?"
                    val color = if (direction == "Outgoing") MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.secondary
                    val icon = if (direction == "Outgoing") "\u2197" else "\u2198" // Unicode arrows
                    Card(
                        Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
                        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.1f))
                    ) {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(icon, style = MaterialTheme.typography.headlineMedium, color = color)
                            Spacer(Modifier.width(12.dp))
                            Column {
                                Text("$direction call to ${log["calleeId"]}", style = MaterialTheme.typography.bodyLarge, color = AppColors.TextPrimary)
                                Text("Started: $dateStr", style = MaterialTheme.typography.bodySmall, color = AppColors.TextSecondary)
                                Text("Duration: $duration sec", style = MaterialTheme.typography.bodySmall, color = AppColors.TextSecondary)
                            }
                        }
                    }
                }
                if (canLoadMore) {
                    Button(onClick = {
                        loading = true
                        vm.fetchCallLogs(userId, startAfter = lastStartedAt)
                        loading = false
                    }) {
                        Text("Load More")
                    }
                }
                }
            }
        }
    }
}