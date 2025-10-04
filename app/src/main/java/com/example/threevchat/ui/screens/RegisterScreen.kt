package com.example.threevchat.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.example.threevchat.viewmodel.MainViewModel
import androidx.compose.ui.text.input.KeyboardOptions

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RegisterScreen(vm: MainViewModel, onRegistered: () -> Unit) {
    val uiState by vm.uiState.collectAsState()
    val activity = LocalContext.current as android.app.Activity

    var username by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var smsCode by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    fun proceedIfLoggedIn() {
        if (uiState.isLoggedIn) onRegistered()
    }

    LaunchedEffect(uiState.isLoggedIn) { proceedIfLoggedIn() }

    Scaffold { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("Register / Login", style = MaterialTheme.typography.headlineSmall)
            OutlinedTextField(
                value = username,
                onValueChange = { username = it },
                label = { Text("Username (email-like)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth()
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = { vm.registerWithUsername(username, password) }) { Text("Register Username") }
                OutlinedButton(onClick = { vm.loginWithUsername(username, password) }) { Text("Login") }
            }

            Divider()

            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("Phone (+1...) for SMS") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                modifier = Modifier.fillMaxWidth()
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = { vm.startPhoneVerification(activity, phone) }) { Text("Send Code") }
                OutlinedTextField(
                    value = smsCode,
                    onValueChange = { smsCode = it },
                    label = { Text("SMS Code") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                Button(onClick = { vm.verifySmsCode(smsCode) }) { Text("Verify") }
            }

            if (uiState.error != null) {
                Text(uiState.error!!, color = MaterialTheme.colorScheme.error)
            }
            if (uiState.loading) {
                CircularProgressIndicator()
            }
        }
    }
}
