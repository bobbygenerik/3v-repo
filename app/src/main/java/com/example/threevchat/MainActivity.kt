package com.example.threevchat

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.core.view.WindowCompat
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.Modifier
import com.example.threevchat.ui.screens.AppNav
import com.example.threevchat.viewmodel.MainViewModel
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

        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContent {
            P2PTheme {
                // Surface adopts theme background; system bars are edge-to-edge by default
                Surface(color = MaterialTheme.colorScheme.background) {
                    Box(modifier = Modifier.windowInsetsPadding(WindowInsets.safeDrawing)) {
                        AppNav(vm = vm)
                    }
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
