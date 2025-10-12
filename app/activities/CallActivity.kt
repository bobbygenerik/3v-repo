package com.example.threevchat.activities

import android.Manifest
import android.os.Bundle
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
import org.webrtc.SurfaceViewRenderer

class CallActivity : ComponentActivity() {
    private lateinit var webRtcRepo: WebRtcRepository
    private var localVideoRenderer: SurfaceViewRenderer? = null
    
    // Permission launcher
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
        
        // Initialize WebRTC repository with lifecycle scope
        webRtcRepo = WebRtcRepository(this, lifecycleScope)
        
        // Request camera and audio permissions
        requestPermissions.launch(
            arrayOf(
                Manifest.permission.CAMERA,
                Manifest.permission.RECORD_AUDIO
            )
        )
        
        // Get the contact name from intent
        val contactName = intent.getStringExtra("CONTACT_NAME") ?: "Unknown"
        
        setContent {
            ThreeVChatTheme {
                var isMicMuted by remember { mutableStateOf(false) }
                var showConnecting by remember { mutableStateOf(true) }
                
                // Simulate connection delay
                LaunchedEffect(Unit) {
                    kotlinx.coroutines.delay(2000)
                    showConnecting = false
                }
                
                InCallScreen(
                    contactName = contactName,
                    onMenu = {
                        // TODO: Show menu options
                    },
                    onToggleMic = {
                        isMicMuted = !isMicMuted
                        webRtcRepo.setMicEnabled(!isMicMuted)
                    },
                    isMicMuted = isMicMuted,
                    onEndCall = {
                        cleanup()
                        finish()
                    },
                    onSwitchCamera = {
                        webRtcRepo.switchCamera()
                    },
                    onAddPerson = {
                        // TODO: Add person to call
                    },
                    transparentBackground = true,
                    showVideoPlaceholder = false,
                    showSelfPip = true,
                    selfPipContent = {
                        LocalCameraView()
                    },
                    showConnecting = showConnecting
                )
            }
        }
    }
    
    private fun initializeCamera() {
        // Start local media once renderer is ready
        localVideoRenderer?.let { renderer ->
            try {
                webRtcRepo.startLocalMedia(renderer)
            } catch (e: Exception) {
                e.printStackTrace()
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
                SurfaceViewRenderer(context).apply {
                    // Initialize with EGL context from repository
                    init(webRtcRepo.eglContext(), null)
                    setMirror(true)
                    setEnableHardwareScaler(true)
                    setZOrderMediaOverlay(true)
                    
                    localVideoRenderer = this
                    
                    // Start media if permissions already granted
                    try {
                        webRtcRepo.startLocalMedia(this)
                    } catch (e: Exception) {
                        // Will be initialized after permission grant
                    }
                }
            },
            update = { view ->
                // Ensure renderer reference is up to date
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