package com.example.threevchat.activities

import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import android.Manifest
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import com.example.threevchat.ui.theme.ThreeVChatTheme
import com.example.threevchat.webrtc.WebRtcRepository
import com.example.threevchat.ui.screens.InCallScreen
import org.webrtc.SurfaceViewRenderer

class CallActivity : ComponentActivity() {
    private lateinit var webRtcRepo: WebRtcRepository
    private var localVideoRenderer: SurfaceViewRenderer? = null
    
    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            initializeCamera()
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableImmersiveMode()
        
        webRtcRepo = WebRtcRepository(this, lifecycleScope)
        
        requestPermissions.launch(
            arrayOf(
                Manifest.permission.CAMERA,
                Manifest.permission.RECORD_AUDIO
            )
        )
        
        val contactName = intent.getStringExtra("CONTACT_NAME") ?: "Unknown"
        
        setContent {
            ThreeVChatTheme {
                var isMicMuted by remember { mutableStateOf(false) }
                
                InCallScreen(
                    contactName = contactName,
                    onMenu = {
                        Log.d("CallActivity", "onMenu clicked")
                        showSettingsDialog()
                    },
                    onToggleMic = {
                        Log.d("CallActivity", "onToggleMic clicked")
                        isMicMuted = !isMicMuted
                        webRtcRepo.setMicEnabled(!isMicMuted)
                    },
                    isMicMuted = isMicMuted,
                    onEndCall = {
                        Log.d("CallActivity", "onEndCall clicked")
                        cleanup()
                        finish()
                    },
                    onSwitchCamera = {
                        Log.d("CallActivity", "onSwitchCamera clicked")
                        webRtcRepo.switchCamera()
                    },
                    onAddPerson = {
                        Log.d("CallActivity", "onAddPerson clicked")
                        showAddPersonDialog()
                    },
                    transparentBackground = true,
                    showVideoPlaceholder = false,
                    showSelfPip = true,
                    selfPipContent = {
                        LocalCameraView()
                    },
                    showConnecting = false
                )
            }
        }
    }
    
    private fun showSettingsDialog() {
        runOnUiThread {
            try {
                AlertDialog.Builder(this)
                    .setTitle("Call Settings")
                    .setItems(arrayOf("Toggle Camera", "Audio Settings", "Video Quality")) { _, which ->
                        when (which) {
                            0 -> Toast.makeText(this, "Camera toggle", Toast.LENGTH_SHORT).show()
                            1 -> Toast.makeText(this, "Audio settings", Toast.LENGTH_SHORT).show()
                            2 -> Toast.makeText(this, "Video quality", Toast.LENGTH_SHORT).show()
                        }
                    }
                    .setNegativeButton("Cancel", null)
                    .show()
            } catch (e: Exception) {
                Log.e("CallActivity", "Error showing settings dialog", e)
            }
        }
    }
    
    private fun showAddPersonDialog() {
        runOnUiThread {
            try {
                val input = EditText(this).apply {
                    hint = "Enter username or phone number"
                    setPadding(50, 20, 50, 20)
                }
                
                AlertDialog.Builder(this)
                    .setTitle("Add Participant")
                    .setMessage("Enter the username or phone number of the person you want to add")
                    .setView(input)
                    .setPositiveButton("Add") { _, _ ->
                        val username = input.text.toString().trim()
                        if (username.isNotBlank()) {
                            Toast.makeText(this, "Adding $username...", Toast.LENGTH_SHORT).show()
                        } else {
                            Toast.makeText(this, "Please enter a valid username", Toast.LENGTH_SHORT).show()
                        }
                    }
                    .setNegativeButton("Cancel", null)
                    .show()
            } catch (e: Exception) {
                Log.e("CallActivity", "Error showing add person dialog", e)
            }
        }
    }
    
    private fun initializeCamera() {
        localVideoRenderer?.let { renderer ->
            try {
                webRtcRepo.startLocalMedia(renderer)
                Log.d("CallActivity", "Camera initialized")
            } catch (e: Exception) {
                Log.e("CallActivity", "Error initializing camera", e)
            }
        }
    }
    
    private fun cleanup() {
        try {
            webRtcRepo.dispose()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cleanup()
    }

    @Composable
    private fun LocalCameraView() {
        AndroidView(
            factory = { context ->
                Log.d("CallActivity", "Creating SurfaceViewRenderer")
                SurfaceViewRenderer(context).apply {
                    init(webRtcRepo.eglContext(), null)
                    setMirror(true)
                    setEnableHardwareScaler(true)
                    setZOrderMediaOverlay(true)
                    
                    localVideoRenderer = this
                    
                    try {
                        webRtcRepo.startLocalMedia(this)
                        Log.d("CallActivity", "Local media started in factory")
                    } catch (e: Exception) {
                        Log.e("CallActivity", "Error starting local media in factory", e)
                    }
                }
            },
            update = { view ->
                if (localVideoRenderer != view) {
                    localVideoRenderer = view
                }
            }
        )
    }

    private fun enableImmersiveMode() {
        try {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            val controller = WindowInsetsControllerCompat(window, window.decorView)
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } catch (_: Throwable) { }
    }
}