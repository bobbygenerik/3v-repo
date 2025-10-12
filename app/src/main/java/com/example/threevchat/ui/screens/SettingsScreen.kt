package com.example.threevchat.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.threevchat.ui.theme.AppColors
import kotlin.OptIn

import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun SettingsScreen(onBack: () -> Unit) {
    val notificationsEnabled = remember { mutableStateOf(true) }
    val speakerEnabled = remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White) }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Black,
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White
                )
            )
        },
        containerColor = Color.Black
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("Notifications", color = AppColors.TextPrimary, style = MaterialTheme.typography.titleMedium)
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Incoming call notifications", color = AppColors.TextSecondary)
                Switch(
                    checked = notificationsEnabled.value,
                    onCheckedChange = { notificationsEnabled.value = it }
                )
            }

            HorizontalDivider(color = Color.White.copy(alpha = 0.08f))

            Text("Audio/Video", color = AppColors.TextPrimary, style = MaterialTheme.typography.titleMedium)
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Use speaker by default", color = AppColors.TextSecondary)
                Switch(
                    checked = speakerEnabled.value,
                    onCheckedChange = { speakerEnabled.value = it }
                )
            }
        }
    }
}
