package com.tres3.videochat

import android.content.Context
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.VideoFrame

/**
 * Minimal stub for MediaPipeVideoProcessor.
 *
 * MediaPipe native processing has been removed for stability. This stub keeps the
 * same class/API surface but performs no per-frame processing and avoids
 * referencing MediaPipe classes so the Android build succeeds.
 */
data class MediaPipeOptions(
  var backgroundBlur: Boolean = false,
  var beauty: Boolean = false,
  var faceMesh: Boolean = false,
  var faceDetection: Boolean = false,
  var blurIntensity: Double = 70.0,
)

class MediaPipeVideoProcessor(
  private val context: Context,
  private var options: MediaPipeOptions,
) : LocalVideoTrack.ExternalVideoFrameProcessing {

  fun updateOptions(newOptions: MediaPipeOptions) {
    options = newOptions
  }

  fun dispose() {
    // no-op stub
  }

  override fun onFrame(frame: VideoFrame): VideoFrame {
    // Pass-through: do not mutate or process frames.
    return frame
  }
}
