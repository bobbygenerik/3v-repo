package com.tres3.videochat

import android.content.Context
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MediaPipeChannel(
  private val context: Context,
  messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
  private val channel = MethodChannel(messenger, "mediapipe_processor")
  private val processors = mutableMapOf<String, MediaPipeVideoProcessor>()

  init {
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "attachProcessor" -> {
        val trackId = call.argument<String>("trackId")
        if (trackId.isNullOrEmpty()) {
          result.error("ARG_ERROR", "trackId is required", null)
          return
        }

        val localTrack = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId)
        if (localTrack !is LocalVideoTrack) {
          result.error("TRACK_ERROR", "Local video track not found", null)
          return
        }

        val options = MediaPipeOptions(
          backgroundBlur = call.argument<Boolean>("backgroundBlur") ?: false,
          beauty = call.argument<Boolean>("beauty") ?: false,
          faceMesh = call.argument<Boolean>("faceMesh") ?: false,
          faceDetection = call.argument<Boolean>("faceDetection") ?: false,
          blurIntensity = call.argument<Double>("blurIntensity") ?: 70.0,
        )

        val processor = processors[trackId] ?: MediaPipeVideoProcessor(context, options).also {
          processors[trackId] = it
          localTrack.addProcessor(it)
        }
        processor.updateOptions(options)
        result.success(true)
      }
      "updateOptions" -> {
        val trackId = call.argument<String>("trackId")
        val processor = if (trackId != null) processors[trackId] else null
        if (processor == null) {
          result.success(false)
          return
        }
        val options = MediaPipeOptions(
          backgroundBlur = call.argument<Boolean>("backgroundBlur") ?: false,
          beauty = call.argument<Boolean>("beauty") ?: false,
          faceMesh = call.argument<Boolean>("faceMesh") ?: false,
          faceDetection = call.argument<Boolean>("faceDetection") ?: false,
          blurIntensity = call.argument<Double>("blurIntensity") ?: 70.0,
        )
        processor.updateOptions(options)
        result.success(true)
      }
      "detachProcessor" -> {
        val trackId = call.argument<String>("trackId")
        if (trackId.isNullOrEmpty()) {
          result.success(false)
          return
        }
        val processor = processors.remove(trackId)
        val localTrack = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId)
        if (processor != null && localTrack is LocalVideoTrack) {
          localTrack.removeProcessor(processor)
          processor.dispose()
        }
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  companion object {
    fun register(context: Context, messenger: BinaryMessenger) {
      Log.d("MediaPipeChannel", "Registering MediaPipe channel")
      MediaPipeChannel(context, messenger)
    }
  }
}
