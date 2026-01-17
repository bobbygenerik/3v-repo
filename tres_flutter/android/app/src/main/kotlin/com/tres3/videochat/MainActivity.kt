package com.tres3.videochat

import android.os.Bundle
import android.os.Build
import android.view.WindowManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.app.PictureInPictureParams
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val PIP_CHANNEL = "tres3/pip"
    private val AUDIO_CHANNEL = "tres3/audio"

    private var pipMethodChannel: MethodChannel? = null
    private var audioMethodChannel: MethodChannel? = null

    private var autoPipEnabled: Boolean = false
    private var callActive: Boolean = false
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        handleIncomingCallIntent()
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // PiP Channel
        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipAvailable" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "enterPipMode" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(9, 16)) // Portrait video call
                                .build()
                            val entered = enterPictureInPictureMode(params)
                            result.success(entered)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "isInPipMode" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(isInPictureInPictureMode)
                    } else {
                        result.success(false)
                    }
                }
                "setAutoPipEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    autoPipEnabled = enabled
                    result.success(null)
                }
                "setCallActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    callActive = active
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Audio Channel
        audioMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
        audioMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSpatialAudioEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (Build.VERSION.SDK_INT >= 32) {
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val spatializer = audioManager.spatializer
                            // Check availability (read-only) to confirm device capability
                            val isAvailable = spatializer.isAvailable
                            // Note: Applications cannot force-enable spatial audio; it is a user preference.
                            // However, checking availability confirms we are interacting with the API.
                        } catch (e: Exception) {
                            // Ignore API access errors
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // MediaPipe bridge removed for Safari PWA stability; no native registration.
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingCallIntent()
    }
    
    private fun handleIncomingCallIntent() {
        intent?.let { itIntent ->
            itIntent.data?.let { uri ->
                if (uri.scheme == "tresvideo" && uri.host == "join") {
                    return
                }
            }

            val invitationId = itIntent.getStringExtra("invitationId")
            val fromName = itIntent.getStringExtra("fromName")
            val callAction = itIntent.getStringExtra("callAction")
            if (!invitationId.isNullOrEmpty()) {
                val uriStr = Uri.Builder()
                    .scheme("tresvideo")
                    .authority("incoming")
                    .appendQueryParameter("invitationId", invitationId)
                    .apply { if (!fromName.isNullOrEmpty()) appendQueryParameter("fromName", fromName) }
                    .apply { if (!callAction.isNullOrEmpty()) appendQueryParameter("action", callAction) }
                    .build()
                itIntent.data = Uri.parse(uriStr.toString())
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        maybeEnterPictureInPicture()
    }

    private fun maybeEnterPictureInPicture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!autoPipEnabled || !callActive || isInPictureInPictureMode) return
        try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16)) // Portrait video call
                .build()
            enterPictureInPictureMode(params)
        } catch (_: Exception) {
            // Ignore PiP errors when leaving app
        }
    }
}
