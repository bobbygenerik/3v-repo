package com.example.threevchat.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.example.threevchat.viewmodel.MainViewModel
import androidx.compose.ui.platform.LocalContext
import com.example.threevchat.viewmodel.UiState

@Composable
fun CallScreen(vm: MainViewModel) {
    val uiState by vm.uiState.collectAsState()
    val ctx = LocalContext.current

    LaunchedEffect(uiState.currentRoom) {
        val sessionId = uiState.currentRoom
        if (!sessionId.isNullOrBlank()) {
            vm.launchCall(ctx, sessionId, role = "caller")
        }
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Preparing call... (native WebRTC)")
    }
}
