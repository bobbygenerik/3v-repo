package com.tres3.videochat

import android.content.Context
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge: Flutter ↔ LiteRT on-device ML processors.
 *
 * Channel name: "tres3/liteRT"
 *
 * Exposed methods (all called from Dart):
 *
 *  Video:
 *    registerVideoTrack(trackId: String)        — must be called after local track is created
 *    setBackgroundBlur(enabled: bool, [blurRadius: double])
 *    setLowLightEnhancement(enabled: bool)
 *    setSharpening(enabled: bool)
 *
 *  Audio:
 *    setNoiseSuppression(enabled: bool)
 *    setLoudnessGain(gainMb: int)          // 0 = off, 100–900 recommended
 *    setVadEnabled(enabled: bool)
 *    attachAudio(audioSessionId: int)
 *    detachAudio()
 *    getAudioStats() → Map
 *
 *  General:
 *    getCapabilities() → Map<String, bool>
 *    dispose()
 *
 * Video processor registration:
 *   Dart calls registerVideoTrack(trackId) after obtaining the local video
 *   track ID from flutter_webrtc. This method looks up the LocalVideoTrack
 *   via FlutterWebRTCPlugin.sharedSingleton and attaches the processor using
 *   the instance-level addProcessor() API.
 */
class LiteRTChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textureRegistry: io.flutter.view.TextureRegistry,
) {

    companion object {
        const val CHANNEL = "tres3/liteRT"
        private const val TAG = "LiteRTChannel"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val videoProcessor = LiteRTVideoProcessor(context)
    private val audioProcessor = LiteRTAudioProcessor(context)
    private var videoProcessorRegistered = false
    private val remoteSinks = mutableMapOf<String, Pair<io.flutter.view.TextureRegistry.SurfaceTextureEntry, LiteRTRemoteVideoSink>>()

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {

                    // ── Track registration ──────────────────────────────────
                    "registerVideoTrack" -> {
                        val trackId = call.argument<String>("trackId")
                        if (trackId == null) {
                            result.error("INVALID_ARG", "trackId is required", null)
                            return@setMethodCallHandler
                        }
                        registerVideoTrack(trackId, result)
                    }

                    // ── Video controls ──────────────────────────────────────
                    "setBackgroundBlur" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val radius = call.argument<Double>("blurRadius")?.toFloat()
                            ?: videoProcessor.blurRadius
                        videoProcessor.backgroundBlurEnabled = enabled
                        videoProcessor.blurRadius = radius
                        Log.d(TAG, "Background blur → $enabled (radius $radius)")
                        result.success(null)
                    }

                    "setLowLightEnhancement" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        videoProcessor.lowLightEnabled = enabled
                        Log.d(TAG, "Low-light enhancement → $enabled")
                        result.success(null)
                    }

                    "setSharpening" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        videoProcessor.sharpeningEnabled = enabled
                        Log.d(TAG, "Sharpening → $enabled")
                        result.success(null)
                    }

                    "attachRemoteProcessing" -> {
                        val trackId = call.argument<String>("trackId")
                        if (trackId == null) {
                            result.error("INVALID_ARG", "trackId is required", null)
                            return@setMethodCallHandler
                        }
                        attachRemoteProcessing(trackId, result)
                    }

                    "detachRemoteProcessing" -> {
                        val trackId = call.argument<String>("trackId") ?: ""
                        detachRemoteProcessing(trackId)
                        result.success(null)
                    }

                    // ── Audio controls ──────────────────────────────────────
                    "setNoiseSuppression" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        audioProcessor.setNoiseSuppression(enabled)
                        Log.d(TAG, "Noise suppression → $enabled")
                        result.success(null)
                    }

                    "setLoudnessGain" -> {
                        val gainMb = call.argument<Int>("gainMb") ?: 0
                        audioProcessor.setLoudnessGain(gainMb)
                        Log.d(TAG, "Loudness gain → ${gainMb}mB")
                        result.success(null)
                    }

                    "setVadEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        audioProcessor.setVadEnabled(enabled)
                        result.success(null)
                    }

                    "attachAudio" -> {
                        val sessionId = call.argument<Int>("audioSessionId") ?: -1
                        audioProcessor.attach(sessionId)
                        result.success(null)
                    }

                    "detachAudio" -> {
                        audioProcessor.detach()
                        result.success(null)
                    }

                    "getAudioStats" -> {
                        result.success(audioProcessor.getStats())
                    }

                    // ── General ─────────────────────────────────────────────
                    "getCapabilities" -> {
                        val caps = mutableMapOf<String, Boolean>()
                        caps.putAll(videoProcessor.capabilities())
                        caps.putAll(audioProcessor.capabilities())
                        caps["videoProcessorRegistered"] = videoProcessorRegistered
                        result.success(caps)
                    }

                    "dispose" -> {
                        disposeProcessors()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "MethodChannel error [${call.method}]: ${e.message}")
                result.error("LITEDT_ERROR", e.message, null)
            }
        }
    }

    /**
     * Looks up the LocalVideoTrack by [trackId] from the flutter_webrtc plugin
     * registry and attaches [videoProcessor] to it. Must be called after the
     * local video track is created (i.e. after getUserMedia succeeds).
     */
    private fun registerVideoTrack(trackId: String, result: MethodChannel.Result) {
        try {
            val plugin = FlutterWebRTCPlugin.sharedSingleton
            if (plugin == null) {
                Log.e(TAG, "FlutterWebRTCPlugin.sharedSingleton is null — plugin not yet initialized")
                result.error("PLUGIN_UNAVAILABLE", "FlutterWebRTCPlugin not initialized", null)
                return
            }
            val localTrack = plugin.getLocalTrack(trackId)
            if (localTrack == null) {
                Log.e(TAG, "No local track found for id=$trackId")
                result.error("TRACK_NOT_FOUND", "Local video track '$trackId' not found", null)
                return
            }
            if (localTrack !is LocalVideoTrack) {
                Log.e(TAG, "Track $trackId is not a LocalVideoTrack")
                result.error("WRONG_TRACK_TYPE", "Track '$trackId' is not a video track", null)
                return
            }
            localTrack.addProcessor(videoProcessor)
            videoProcessorRegistered = true
            Log.d(TAG, "LiteRT video processor attached to track $trackId")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "registerVideoTrack failed: ${e.message}")
            result.error("REGISTRATION_FAILED", e.message, null)
        }
    }

    private fun attachRemoteProcessing(trackId: String, result: MethodChannel.Result) {
        try {
            remoteSinks.remove(trackId)?.let { (entry, sink) ->
                try {
                    FlutterWebRTCPlugin.sharedSingleton
                        ?.getLocalTrack(trackId)
                        ?.let { (it as? org.webrtc.VideoTrack)?.removeSink(sink) }
                } catch (_: Exception) {
                }
                sink.dispose()
                entry.release()
            }

            val plugin = FlutterWebRTCPlugin.sharedSingleton
            if (plugin == null) {
                result.error("PLUGIN_UNAVAILABLE", "FlutterWebRTCPlugin not initialized", null)
                return
            }

            val track = plugin.getLocalTrack(trackId)
            if (track == null) {
                result.error("TRACK_NOT_FOUND", "Track '$trackId' not found", null)
                return
            }

            val entry = textureRegistry.createSurfaceTexture()
            val surface = android.view.Surface(entry.surfaceTexture())
            val sink = LiteRTRemoteVideoSink(videoProcessor, surface)

            val videoTrack = track as? org.webrtc.VideoTrack
            if (videoTrack == null) {
                sink.dispose()
                entry.release()
                result.error("WRONG_TRACK_TYPE", "Track '$trackId' is not a video track", null)
                return
            }

            videoTrack.addSink(sink)
            remoteSinks[trackId] = entry to sink
            Log.d(TAG, "Remote LiteRT attached: $trackId -> textureId ${entry.id()}")
            result.success(entry.id())
        } catch (e: Exception) {
            Log.e(TAG, "attachRemoteProcessing failed: ${e.message}", e)
            result.error("ATTACH_FAILED", e.message, null)
        }
    }

    private fun detachRemoteProcessing(trackId: String) {
        remoteSinks.remove(trackId)?.let { (entry, sink) ->
            try {
                FlutterWebRTCPlugin.sharedSingleton
                    ?.getLocalTrack(trackId)
                    ?.let { (it as? org.webrtc.VideoTrack)?.removeSink(sink) }
            } catch (_: Exception) {
            }
            sink.dispose()
            entry.release()
            Log.d(TAG, "Remote LiteRT detached: $trackId")
        }
    }

    private fun disposeProcessors() {
        remoteSinks.keys.toList().forEach { detachRemoteProcessing(it) }
        remoteSinks.clear()
        videoProcessor.dispose()
        audioProcessor.dispose()
        Log.d(TAG, "LiteRT processors disposed")
    }

    fun dispose() {
        disposeProcessors()
        channel.setMethodCallHandler(null)
    }
}
