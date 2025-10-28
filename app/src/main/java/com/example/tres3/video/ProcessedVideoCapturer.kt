package com.example.tres3.video

import android.content.Context
import android.app.ActivityManager
import android.graphics.Bitmap
import android.util.Log
import com.example.tres3.FeatureFlags
import com.example.tres3.ml.MLKitManager
import livekit.org.webrtc.Camera2Enumerator
import livekit.org.webrtc.CameraVideoCapturer
import livekit.org.webrtc.CapturerObserver
import livekit.org.webrtc.SurfaceTextureHelper
import livekit.org.webrtc.VideoCapturer
import livekit.org.webrtc.VideoFrame
import livekit.org.webrtc.JavaI420Buffer
import livekit.org.webrtc.VideoFrame.I420Buffer
import kotlinx.coroutines.launch

/**
 * ProcessedVideoCapturer - wrapper around Camera2 capturer that intercepts frames
 *
 * Current behavior: pass-through (no processing). This scaffolds the hook needed
 * to apply MLKit background blur before forwarding frames upstream. Once stable,
 * we will gate processing by a feature flag and device capabilities.
 */
class ProcessedVideoCapturer(
    private val context: Context,
    private val useFrontCamera: Boolean = true
) : VideoCapturer {

    private val tag = "ProcessedCapturer"
    private var inner: CameraVideoCapturer? = null
    private var upstreamObserver: CapturerObserver? = null
    private val processingScope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Default + kotlinx.coroutines.SupervisorJob())
    @Volatile private var processingJob: kotlinx.coroutines.Job? = null
    
    // Performance and safety guards
    @Volatile private var processingEnabled: Boolean = false
    @Volatile private var targetFpsWhenProcessing: Int = 24
    private var lastForwardNanos: Long = 0L
    private var droppedFramesWindow: Int = 0
    private var windowStartNanos: Long = 0L
    private val dropWindowNanos: Long = 2_000_000_000L // 2 seconds
    private val maxDropsPerWindow: Int = 30
    private val minMemFreeMb: Long = 200 // if free RAM lower than this, disable processing

    override fun initialize(
        surfaceTextureHelper: SurfaceTextureHelper?,
        applicationContext: Context?,
        capturerObserver: CapturerObserver?
    ) {
        upstreamObserver = capturerObserver

        // Pick a camera
    val enumerator = Camera2Enumerator(context)
        val deviceNames = enumerator.deviceNames
        val cameraName = deviceNames.firstOrNull { name ->
            val isFront = enumerator.isFrontFacing(name)
            if (useFrontCamera) isFront else !isFront
        } ?: deviceNames.firstOrNull()

        if (cameraName == null) {
            Log.e(tag, "No camera device found")
            return
        }

        val events = object : CameraVideoCapturer.CameraEventsHandler {
            override fun onCameraError(p0: String?) {
                Log.e(tag, "onCameraError: $p0")
            }

            override fun onCameraDisconnected() {
                Log.w(tag, "onCameraDisconnected")
            }

            override fun onCameraFreezed(p0: String?) {
                Log.w(tag, "onCameraFreezed: $p0")
            }

            override fun onCameraOpening(p0: String?) {
                Log.d(tag, "onCameraOpening: $p0")
            }

            override fun onFirstFrameAvailable() {
                Log.d(tag, "onFirstFrameAvailable")
            }

            override fun onCameraClosed() {
                Log.d(tag, "onCameraClosed")
            }
        }

        inner = enumerator.createCapturer(cameraName, events)

        // Initialize processing gate based on current flags
        processingEnabled = FeatureFlags.isMLKitEnabled() && FeatureFlags.isBackgroundBlurEnabled()
        targetFpsWhenProcessing = 24 // safer default for lower-end devices

        // Proxy the observer to intercept frames in the future
        val proxyObserver = object : CapturerObserver {
            override fun onCapturerStarted(success: Boolean) {
                capturerObserver?.onCapturerStarted(success)
            }

            override fun onCapturerStopped() {
                capturerObserver?.onCapturerStopped()
            }

            override fun onFrameCaptured(frame: VideoFrame) {
                // Safety: memory pressure check
                if (processingEnabled && isUnderMemoryPressure()) {
                    Log.w(tag, "Memory pressure detected; temporarily disabling processing/throttle")
                    processingEnabled = false
                }

                if (!processingEnabled) {
                    capturerObserver?.onFrameCaptured(frame)
                    return
                }

                // FPS throttle by dropping excess frames
                val now = System.nanoTime()
                val minIntervalNanos = 1_000_000_000L / targetFpsWhenProcessing.coerceAtLeast(1)
                if (now - lastForwardNanos < minIntervalNanos) {
                    trackDroppedFrame()
                    return // drop
                }
                lastForwardNanos = now

                // Ensure only one processing job at a time; drop if busy
                val currentJob = processingJob
                if (currentJob != null && currentJob.isActive) {
                    trackDroppedFrame()
                    return
                }

                processingJob = processingScope.launch {
                    try {
                        val processed = processFrameWithMLKit(frame)
                        if (processed != null) {
                            upstreamObserver?.onFrameCaptured(processed)
                            processed.release()
                        } else {
                            // Fallback: forward original if processing failed
                            upstreamObserver?.onFrameCaptured(frame)
                        }
                    } catch (e: Exception) {
                        Log.e(tag, "Error processing frame: ${e.message}", e)
                        upstreamObserver?.onFrameCaptured(frame)
                    }
                }
            }
        }

        inner?.initialize(surfaceTextureHelper, applicationContext, proxyObserver)
    }

    override fun startCapture(width: Int, height: Int, framerate: Int) {
        inner?.startCapture(width, height, framerate)
    }

    override fun stopCapture() {
        try {
            inner?.stopCapture()
        } catch (e: InterruptedException) {
            Log.e(tag, "stopCapture interrupted", e)
        }
    }

    override fun changeCaptureFormat(width: Int, height: Int, framerate: Int) {
        inner?.changeCaptureFormat(width, height, framerate)
    }

    override fun dispose() {
        inner?.dispose()
        inner = null
        upstreamObserver = null
    }

    override fun isScreencast(): Boolean = false

    // ========= Performance guard helpers =========
    private fun trackDroppedFrame() {
        val now = System.nanoTime()
        if (windowStartNanos == 0L || now - windowStartNanos > dropWindowNanos) {
            windowStartNanos = now
            droppedFramesWindow = 0
        }
        droppedFramesWindow++
        if (droppedFramesWindow >= maxDropsPerWindow) {
            // Too many drops; disable processing to recover
            processingEnabled = false
            Log.w(tag, "Excessive frame drops detected; disabling processing/throttle for stability")
            // reset window
            windowStartNanos = now
            droppedFramesWindow = 0
        }
    }

    private fun isUnderMemoryPressure(): Boolean {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val mi = ActivityManager.MemoryInfo()
            am?.getMemoryInfo(mi)
            val availMb = (mi.availMem / (1024L * 1024L))
            mi.lowMemory || availMb < minMemFreeMb
        } catch (e: Exception) {
            false
        }
    }

    // Public knobs for future wiring
    fun setProcessingEnabled(enabled: Boolean) {
        processingEnabled = enabled
    }

    fun setTargetFps(fps: Int) {
        targetFpsWhenProcessing = fps.coerceIn(10, 60)
    }

    // ========= ML/Conversion pipeline =========
    private suspend fun processFrameWithMLKit(frame: VideoFrame): VideoFrame? {
        return try {
            val i420 = frame.buffer.toI420()
            if (i420 == null) {
                Log.w(tag, "toI420() returned null; forwarding original frame")
                return null
            }
            val width = i420.width
            val height = i420.height

            // Convert I420 -> NV21 -> Bitmap (downscale for perf)
            val nv21 = VideoFrameConverters.i420ToNV21(i420)
            val bmp = VideoFrameConverters.nv21ToBitmap(nv21, width, height)

            // Downscale for processing to ~640p max dimension
            val scaledBmp = downscaleBitmapIfNeeded(bmp, 640)

            // Run MLKit processing (background blur only for now)
            val result = com.example.tres3.ml.MLKitManager.processFrame(
                context = context,
                bitmap = scaledBmp,
                applyBackgroundBlur = true,
                detectFaces = FeatureFlags.isFaceEnhancementEnabled(),
                detectObjects = false,
                enhanceQuality = FeatureFlags.isCameraLowLightEnabled()
            )

            val processedBmp = (result.processedBitmap ?: scaledBmp)

            // If we downscaled, upscale back to original to keep encoder sizes consistent
            val outBmp = if (processedBmp.width != width || processedBmp.height != height) {
                Bitmap.createScaledBitmap(processedBmp, width, height, true)
            } else processedBmp

            // Convert Bitmap -> I420 -> VideoFrame
            val outI420: JavaI420Buffer = VideoFrameConverters.bitmapToI420(outBmp)
            val outFrame = VideoFrame(outI420, frame.rotation, frame.timestampNs)

            // Clean up
            i420.release()

            outFrame
        } catch (e: Exception) {
            Log.e(tag, "processFrameWithMLKit failed: ${e.message}", e)
            null
        }
    }

    private fun downscaleBitmapIfNeeded(bmp: Bitmap, maxDim: Int): Bitmap {
        val w = bmp.width
        val h = bmp.height
        val max = maxOf(w, h)
        if (max <= maxDim) return bmp
        val scale = maxDim.toFloat() / max
        val nw = (w * scale).toInt().coerceAtLeast(1)
        val nh = (h * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bmp, nw, nh, true)
    }
}
