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
import androidx.compose.foundation.text.KeyboardOptions

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RegisterScreen(vm: MainViewModel, onRegistered: () -> Unit) {
    val uiState by vm.uiState.collectAsState()
    val activity = LocalContext.current as android.app.Activity
    val snackbarHostState = remember { SnackbarHostState() }

    var phone by remember { mutableStateOf("") }
    var smsCode by remember { mutableStateOf("") }

    fun proceedIfLoggedIn() {
        if (uiState.isLoggedIn) onRegistered()
    }

    LaunchedEffect(uiState.isLoggedIn) { proceedIfLoggedIn() }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("Sign in with your phone", style = MaterialTheme.typography.headlineSmall)

            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("Phone number (+1...) for SMS") },
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

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val canResend = uiState.canResendInSec == 0
                Button(onClick = { vm.resendCode(activity, phone) }, enabled = canResend) {
                    val label = if (canResend) "Resend Code" else "Resend in ${uiState.canResendInSec}s"
                    Text(label)
                }
            }

            if (uiState.error != null) {
                // Also surface error in snackbar for visibility
                LaunchedEffect(uiState.error) {
                    snackbarHostState.showSnackbar(uiState.error!!)
                }
                Text(uiState.error!!, color = MaterialTheme.colorScheme.error)
            }
            if (uiState.loading) {
                CircularProgressIndicator()
            }
        }
    }

    // Show a one-time message when code is sent
    if (uiState.codeSent) {
        LaunchedEffect(uiState.codeSent) {
            snackbarHostState.showSnackbar("Verification code sent")
            vm.consumeCodeSent()
        }
    }
}
