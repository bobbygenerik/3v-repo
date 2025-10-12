package com.example.threevchat

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.core.view.WindowCompat
import com.example.threevchat.ui.Navigation.AppNav
import com.example.threevchat.viewmodel.MainViewModel
import com.example.threevchat.ui.theme.ThreeVChatTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.dp
import com.example.threevchat.viewmodel.BannerKind
import kotlinx.coroutines.launch
// import removed: RegisterScreen is not needed
import com.example.threevchat.ui.screens.SignInScreen
import com.example.threevchat.ui.screens.SignUpScreen

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request critical permissions (runtime)
        requestPermissions(arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        ), 100)

        // Enable edge-to-edge content
        WindowCompat.setDecorFitsSystemWindows(window, false)

        setContent {
            ThreeVChatTheme {
                val ui by vm.uiState.collectAsState()
                val snackbar = remember { SnackbarHostState() }
                val ctx = LocalContext.current
                val scope = rememberCoroutineScope()

                Surface(color = MaterialTheme.colorScheme.background) {
                    if (!ui.isLoggedIn) {
                        // Simple auth gate: show SignIn by default; allow navigating to Register
                        val showRegisterState = remember { mutableStateOf(false) }
                        val showRegister = showRegisterState.value
                        fun setShowRegister(v: Boolean) { showRegisterState.value = v }
                        Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
                            Box(Modifier.fillMaxSize().padding(padding)) {
                                if (showRegister) {
                                    // Replace legacy register with the new SignUpScreen
                                    SignUpScreen(
                                        onSignUp = { cred: String, pass: String, confirm: String ->
                                            if (cred.isBlank()) {
                                                scope.launch { snackbar.showSnackbar("Enter email, phone, or username") }
                                                return@SignUpScreen
                                            }
                                            if (pass.isBlank() && !cred.contains("@") && !(cred.startsWith("+") || cred.filter { ch -> ch.isDigit() }.length >= 7)) {
                                                // If it's a username-only sign-up with no password, ask for email or phone
                                                scope.launch { snackbar.showSnackbar("Use email+password to register, or enter a phone number to verify.") }
                                                vm.queueUsernameClaim(cred)
                                                return@SignUpScreen
                                            }
                                            if (pass != confirm) {
                                                scope.launch { snackbar.showSnackbar("Passwords do not match") }
                                            } else {
                                                val c = cred.trim()
                                                val phoneish = c.startsWith("+") || c.filter { ch -> ch.isDigit() }.length >= 7
                                                if (phoneish) {
                                                    vm.startPhoneVerification(this@MainActivity, c)
                                                    scope.launch { snackbar.showSnackbar("Verification code sent (if possible)") }
                                                    // If a username-like credential was provided, queue to claim after verification
                                                    if (!c.contains("@")) vm.queueUsernameClaim(c)
                                                } else if (c.contains("@")) {
                                                    // If the original text looked like a username but user switched to email, claim that username post-signup
                                                    // Here we assume they typed the email; to support username inline, consider a hint or a secondary field later
                                                    vm.signUpEmail(c, pass)
                                                } else {
                                                    // Username-only: queue claim and ask user to provide email/phone
                                                    vm.queueUsernameClaim(c)
                                                    scope.launch { snackbar.showSnackbar("We will try to claim that username after you sign up. Enter email+password or phone to continue.") }
                                                }
                                            }
                                        },
                                        onBackToSignIn = { setShowRegister(false) }
                                    )
                                } else {
                                    SignInScreen(
                                        onSignIn = { cred, pass ->
                                            val c = cred.trim()
                                            val phoneish = c.startsWith("+") || c.filter { it.isDigit() }.length >= 7
                                            if (!phoneish && !c.contains("@")) vm.queueUsernameClaim(c)
                                            vm.signInSmart(cred, pass)
                                        },
                                        onForgotPassword = { email -> vm.forgotPassword(email) },
                                        onSignUp = { setShowRegister(true) }
                                    )
                                }
                                // Inline banner for status and errors
                                val banner = ui.banner
                                androidx.compose.animation.AnimatedVisibility(
                                    visible = banner != null || !ui.error.isNullOrBlank(),
                                    modifier = Modifier
                                        .align(Alignment.TopCenter)
                                        .padding(top = WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 12.dp)
                                        .padding(horizontal = 16.dp)
                                ) {
                                    val isError = (banner?.kind == BannerKind.ERROR) || (!ui.error.isNullOrBlank())
                                    val msg = banner?.message ?: ui.error.orEmpty()
                                    // Auto-dismiss banner after 3 seconds (only for banner; errors remain until updated)
                                    if (banner != null) {
                                        LaunchedEffect(banner) {
                                            kotlinx.coroutines.delay(3000)
                                            vm.consumeBanner()
                                        }
                                    }
                                    Surface(
                                        color = if (isError) MaterialTheme.colorScheme.error.copy(alpha = 0.12f) else MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                                        tonalElevation = 0.dp,
                                        shadowElevation = 0.dp,
                                        shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp)
                                    ) {
                                        Text(
                                            text = msg,
                                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                                            color = if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                                            style = MaterialTheme.typography.bodyMedium
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        AppNav(vm)
                    }
                }
            }
        }

    // Background listeners resume when logged in via AppNav
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        vm.handleIncomingIntent(intent)
    }
}
