package com.example.threevchat.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.threevchat.viewmodel.MainViewModel

@Composable
fun HomeScreen(vm: MainViewModel, onStartCall: () -> Unit, onViewCallLogs: () -> Unit) {
    var callee by remember { mutableStateOf("") }

    Scaffold { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("Home", style = MaterialTheme.typography.headlineSmall)
            OutlinedTextField(
                value = callee,
                onValueChange = { callee = it },
                label = { Text("Callee phone number") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Button(onClick = {
                vm.startCallTo(callee)
                onStartCall()
            }) { Text("Start Call") }

            Spacer(Modifier.height(12.dp))
            Button(onClick = { onViewCallLogs() }) {
                Text("View Call Logs")
            }
        }
    }
}
