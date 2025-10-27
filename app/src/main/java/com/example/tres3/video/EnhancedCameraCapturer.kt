package com.example.tres3.video

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.view.Surface
import livekit.org.webrtc.CapturerObserver
import livekit.org.webrtc.JavaI420Buffer
import livekit.org.webrtc.SurfaceTextureHelper
import livekit.org.webrtc.VideoCapturer
import livekit.org.webrtc.VideoFrame
import java.nio.ByteBuffer
import kotlin.math.max

/**
 * EnhancedCameraCapturer
 *
 * Custom Camera2-based VideoCapturer that applies CameraEnhancer settings (HDR, low-light,
 * CAF, stabilization) by building CaptureRequests directly, then forwards frames to WebRTC.
 * Frames are acquired via ImageReader in YUV_420_888 and converted to I420.
 */
class EnhancedCameraCapturer(
    private val context: Context,
    private val useFrontCamera: Boolean = true,
    private val targetFps: Int = 30,
    private val cameraEnhancer: CameraEnhancer = CameraEnhancer(context)
) : VideoCapturer {

    private val tag = "EnhancedCamCapturer"
    private var observer: CapturerObserver? = null
    private var surfaceTextureHelper: SurfaceTextureHelper? = null

    private val cameraManager: CameraManager by lazy {
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null

    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null

    private var currentCameraId: String? = null
    @Volatile private var started: Boolean = false

    override fun initialize(
        surfaceTextureHelper: SurfaceTextureHelper?,
        applicationContext: Context?,
        capturerObserver: CapturerObserver?
    ) {
        this.surfaceTextureHelper = surfaceTextureHelper
        this.observer = capturerObserver
    }

    @SuppressLint("MissingPermission")
    override fun startCapture(width: Int, height: Int, framerate: Int) {
        if (started) return
        started = true

        startBackgroundThread()

        val camId = selectCameraId(useFrontCamera) ?: run {
            Log.e(tag, "No suitable camera found")
            observer?.onCapturerStarted(false)
            return
        }
        currentCameraId = camId

        try {
            cameraManager.openCamera(camId, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    cameraDevice = device
                    try {
                        setupSession(device, width, height, framerate)
                        observer?.onCapturerStarted(true)
                    } catch (e: Exception) {
                        Log.e(tag, "Failed to start session: ${e.message}", e)
                        observer?.onCapturerStarted(false)
                    }
                }

                override fun onDisconnected(device: CameraDevice) {
                    Log.w(tag, "Camera disconnected")
                    device.close()
                    cameraDevice = null
                }

                override fun onError(device: CameraDevice, error: Int) {
                    Log.e(tag, "Camera error: $error")
                    device.close()
                    cameraDevice = null
                    observer?.onCapturerStarted(false)
                }
            }, bgHandler)
        } catch (e: Exception) {
            Log.e(tag, "openCamera failed: ${e.message}", e)
            observer?.onCapturerStarted(false)
        }
    }

    override fun stopCapture() {
        started = false
        try {
            captureSession?.stopRepeating()
        } catch (_: Exception) {}
        try { captureSession?.close() } catch (_: Exception) {}
        captureSession = null

        try { cameraDevice?.close() } catch (_: Exception) {}
        cameraDevice = null

        try { imageReader?.close() } catch (_: Exception) {}
        imageReader = null

        stopBackgroundThread()
        observer?.onCapturerStopped()
    }

    override fun changeCaptureFormat(width: Int, height: Int, framerate: Int) {
        // Recreate session with new format
        val device = cameraDevice ?: return
        try {
            captureSession?.stopRepeating()
        } catch (_: Exception) {}
        try { captureSession?.close() } catch (_: Exception) {}
        captureSession = null
        setupSession(device, width, height, framerate)
    }

    override fun dispose() {
        stopCapture()
        observer = null
        surfaceTextureHelper = null
    }

    override fun isScreencast(): Boolean = false

    // ==== Internals ==== //
    private fun selectCameraId(front: Boolean): String? {
        return try {
            cameraManager.cameraIdList.firstOrNull { id ->
                val facing = cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.LENS_FACING)
                if (front) facing == CameraCharacteristics.LENS_FACING_FRONT
                else facing == CameraCharacteristics.LENS_FACING_BACK
            } ?: cameraManager.cameraIdList.firstOrNull()
        } catch (e: Exception) {
            Log.e(tag, "selectCameraId failed: ${e.message}", e)
            null
        }
    }

    private fun setupSession(device: CameraDevice, width: Int, height: Int, framerate: Int) {
        val w = if (width <= 0) 1280 else width
        val h = if (height <= 0) 720 else height
        val fps = if (framerate <= 0) targetFps else framerate

        // ImageReader for YUV frames
        imageReader = ImageReader.newInstance(w, h, ImageFormat.YUV_420_888, 3).apply {
            setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    onImageAvailable(image)
                } catch (e: Exception) {
                    Log.e(tag, "onImageAvailable error: ${e.message}", e)
                } finally {
                    try { image.close() } catch (_: Exception) {}
                }
            }, bgHandler)
        }

        val surfaces = mutableListOf<Surface>()
        imageReader?.surface?.let { surfaces.add(it) }

        val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
            imageReader?.surface?.let { addTarget(it) }
            // FPS range if supported
            try {
                val chars = cameraManager.getCameraCharacteristics(device.id)
                val fpsRanges = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                val target = fpsRanges?.maxByOrNull { r -> scoreFpsRange(r, fps) }
                if (target != null) set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, target)
            } catch (_: Exception) {}

            // Apply CameraEnhancer settings
            try {
                cameraEnhancer.applyEnhancements(this, device.id)
            } catch (e: Exception) {
                Log.w(tag, "applyEnhancements failed: ${e.message}")
            }
        }

        device.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                captureSession = session
                try {
                    session.setRepeatingRequest(builder.build(), null, bgHandler)
                } catch (e: Exception) {
                    Log.e(tag, "setRepeatingRequest failed: ${e.message}", e)
                }
            }

            override fun onConfigureFailed(session: CameraCaptureSession) {
                Log.e(tag, "CaptureSession configuration failed")
            }
        }, bgHandler)
    }

    private fun scoreFpsRange(r: Range<Int>, target: Int): Int {
        // Prefer ranges covering target fps with minimal spread
        val covers = if (r.contains(target)) 1000 else 0
        val spreadPenalty = (r.upper - r.lower)
        return covers - spreadPenalty
    }

    private fun onImageAvailable(image: Image) {
        val w = image.width
        val h = image.height

        val buffer = convertYUV420ToI420(image) ?: return
        val frame = VideoFrame(buffer, /*rotation*/0, System.nanoTime())
        observer?.onFrameCaptured(frame)
        frame.release()
    }

    private fun convertYUV420ToI420(image: Image): JavaI420Buffer? {
        val w = image.width
        val h = image.height
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val out = JavaI420Buffer.allocate(w, h)

        try {
            // Copy Y
            copyPlane(
                src = yPlane.buffer,
                srcRowStride = yPlane.rowStride,
                srcPixelStride = yPlane.pixelStride,
                dst = out.dataY,
                dstRowStride = out.strideY,
                width = w,
                height = h
            )

            // Copy U (subsampled)
            copyPlane(
                src = uPlane.buffer,
                srcRowStride = uPlane.rowStride,
                srcPixelStride = uPlane.pixelStride,
                dst = out.dataU,
                dstRowStride = out.strideU,
                width = w / 2,
                height = h / 2
            )

            // Copy V (subsampled)
            copyPlane(
                src = vPlane.buffer,
                srcRowStride = vPlane.rowStride,
                srcPixelStride = vPlane.pixelStride,
                dst = out.dataV,
                dstRowStride = out.strideV,
                width = w / 2,
                height = h / 2
            )
        } catch (e: Exception) {
            Log.e(tag, "YUV->I420 conversion failed: ${e.message}", e)
            out.release()
            return null
        }

        return out
    }

    private fun copyPlane(
        src: ByteBuffer,
        srcRowStride: Int,
        srcPixelStride: Int,
        dst: ByteBuffer,
        dstRowStride: Int,
        width: Int,
        height: Int
    ) {
        var srcRowStart = 0
        var dstRowStart = 0

        for (row in 0 until height) {
            var srcIndex = srcRowStart
            var dstIndex = dstRowStart

            if (srcPixelStride == 1) {
                // Fast path: contiguous row
                val oldPos = src.position()
                src.position(srcIndex)
                val rowBytes = ByteArray(width)
                src.get(rowBytes, 0, width)
                val oldDstPos = dst.position()
                dst.position(dstIndex)
                dst.put(rowBytes)
                dst.position(oldDstPos)
                src.position(oldPos)
            } else {
                // Generic: sample every pixelStride
                for (col in 0 until width) {
                    val b = src.get(srcIndex)
                    val oldPosDst = dst.position()
                    dst.position(dstIndex)
                    dst.put(b)
                    dst.position(oldPosDst)
                    srcIndex += srcPixelStride
                    dstIndex += 1
                }
            }

            srcRowStart += srcRowStride
            dstRowStart += dstRowStride
        }
    }

    private fun startBackgroundThread() {
        if (bgThread != null) return
        bgThread = HandlerThread("EnhancedCamera2").apply { start() }
        bgHandler = Handler(bgThread!!.looper)
    }

    private fun stopBackgroundThread() {
        bgThread?.quitSafely()
        try { bgThread?.join() } catch (_: Exception) {}
        bgThread = null
        bgHandler = null
    }
}
