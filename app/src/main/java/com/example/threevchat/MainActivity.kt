package com.example.threevchat

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.toArgb
import com.example.threevchat.ui.screens.AppNav
import com.example.threevchat.viewmodel.MainViewModel
import com.google.accompanist.systemuicontroller.rememberSystemUiController
import com.example.threevchat.ui.theme.P2PTheme

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Request critical permissions (runtime)
        requestPermissions(arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        ), 100)

        setContent {
            P2PTheme {
                val systemUi = rememberSystemUiController()
                val bg = MaterialTheme.colorScheme.background
                LaunchedEffect(bg) {
                    systemUi.setSystemBarsColor(bg, darkIcons = true)
                }
                Surface(color = MaterialTheme.colorScheme.background) {
                    AppNav(vm = vm)
                }
            }
        }

        handleIntent(intent)
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
