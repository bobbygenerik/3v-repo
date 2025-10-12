
package com.example.threevchat.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.threevchat.viewmodel.MainViewModel
import com.example.threevchat.viewmodel.UiState

@Composable
fun CallScreen(vm: MainViewModel, onLaunched: () -> Unit) {
    val uiState by vm.uiState.collectAsState()
    val ctx = LocalContext.current

    // Show spinner and auto-dismiss after 1.5 seconds
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(1500)
        onLaunched()
    }

    // In-call UI with menu and add person button
    Box(Modifier.fillMaxSize()) {
        // Top right menu button
    var showMenu by remember { mutableStateOf(false) }
        IconButton(
            onClick = { showMenu = true },
            modifier = Modifier.align(Alignment.TopEnd).padding(16.dp)
        ) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = "Menu",
                tint = androidx.compose.ui.graphics.Color.White
            )
        }
        DropdownMenu(
            expanded = showMenu,
            onDismissRequest = { showMenu = false },
            modifier = Modifier.align(Alignment.TopEnd)
        ) {
            DropdownMenuItem(
                text = { Text("Settings") },
                onClick = {
                    showMenu = false
                    vm.openSettings() // UI layer should navigate to settings
                }
            )
            DropdownMenuItem(
                text = { Text("Participants") },
                onClick = {
                    showMenu = false
                    // TODO: Implement navigation to participants screen
                }
            )
        }

        // Add person button (bottom right)
    var showAddDialog by remember { mutableStateOf(false) }
    var newParticipant by remember { mutableStateOf("") }
        FloatingActionButton(
            onClick = { showAddDialog = true },
            modifier = Modifier.align(Alignment.BottomEnd).padding(24.dp),
            containerColor = androidx.compose.ui.graphics.Color(0xFF3CB371)
        ) {
            Icon(
                imageVector = Icons.Filled.PersonAdd,
                contentDescription = "Add Person",
                tint = androidx.compose.ui.graphics.Color.White
            )
        }

        if (showAddDialog) {
            AlertDialog(
                onDismissRequest = { showAddDialog = false },
                confirmButton = {
                    TextButton(onClick = {
                        showAddDialog = false
                        if (newParticipant.isNotBlank()) {
                            // Invite via phone or email
                            if (android.util.Patterns.PHONE.matcher(newParticipant).matches()) {
                                vm.inviteViaMessages(ctx, newParticipant)
                            } else {
                                // TODO: Implement email invite logic if needed
                                android.widget.Toast.makeText(ctx, "Email invite not implemented", android.widget.Toast.LENGTH_SHORT).show()
                            }
                            newParticipant = ""
                        }
                    }) {
                        Text("Invite")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showAddDialog = false }) {
                        Text("Cancel")
                    }
                },
                title = { Text("Add Person to Call") },
                text = {
                    OutlinedTextField(
                        value = newParticipant,
                        onValueChange = { newParticipant = it },
                        label = { Text("Phone or Email") },
                        singleLine = true
                    )
                }
            )
        }

        // Center spinner and message
        Box(Modifier.align(Alignment.Center)) {
            androidx.compose.material3.CircularProgressIndicator()
            androidx.compose.material3.Text(
                "Preparing call... (native WebRTC)",
                modifier = Modifier.align(Alignment.BottomCenter),
                color = androidx.compose.ui.graphics.Color.White
            )
        }
    }
}
