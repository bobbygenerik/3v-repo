package com.example.tres3.video

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult
import livekit.org.webrtc.VideoFrame
import livekit.org.webrtc.VideoProcessor
import livekit.org.webrtc.VideoSink
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream

/**
 * Hand gesture recognition video processor using MediaPipe Hands.
 * 
 * Detects hand gestures (👍 👎 ✋) in video frames and maps them to reactions/controls.
 * Processes selective frames to minimize CPU/battery impact.
 * 
 * Supported gestures:
 * - Thumb_Up (👍) - Like/approve reaction
 * - Thumb_Down (👎) - Dislike/disapprove reaction
 * - Open_Palm (✋) - Stop/mute request
 * - Closed_Fist - End call or reject
 * - Victory (✌️) - Peace sign
 * - Pointing_Up (☝️) - Raise hand to speak
 * 
 * Features:
 * - Real-time gesture recognition with MediaPipe
 * - Callback-based gesture events (non-blocking)
 * - Processes every Nth frame to reduce CPU load
 * - Confidence threshold filtering
 * - Duplicate gesture suppression (cooldown)
 * 
 * Integration: 
 * ```
 * val gestureProcessor = HandGestureProcessor(context) { gesture ->
 *     when (gesture) {
 *         "Thumb_Up" -> showReaction("👍")
 *         "Thumb_Down" -> showReaction("👎")
 *         "Open_Palm" -> showReaction("✋")
 *     }
 * }
 * compositeProcessor.addProcessor(gestureProcessor)
 * ```
 */
class HandGestureProcessor(
    private val context: Context,
    private val onGestureDetected: (String) -> Unit
) : VideoProcessor {
    
    private var videoSink: VideoSink? = null
    private var frameCount = 0
    private var processedCount = 0
    private var detectedGestureCount = 0
    
    // Process every 30th frame (~1fps at 30fps input) to reduce CPU load
    private val processEveryNFrames = 30
    
    // Confidence threshold for gesture detection
    private val confidenceThreshold = 0.7f
    
    // Cooldown to prevent duplicate gesture triggers (milliseconds)
    private val gestureCooldownMs = 2000L
    private var lastGestureTime = 0L
    private var lastGesture: String? = null
    
    // MediaPipe gesture recognizer
    private var gestureRecognizer: GestureRecognizer? = null
    
    init {
        initializeGestureRecognizer()
    }
    
    private fun initializeGestureRecognizer() {
        try {
            // Copy model from assets to cache directory
            val modelFile = copyAssetToCache("gesture_recognizer.task")
            
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath(modelFile.absolutePath)
                .build()
            
            val options = GestureRecognizer.GestureRecognizerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumHands(2) // Support detecting both hands
                .setMinHandDetectionConfidence(0.5f)
                .setMinHandPresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .build()
            
            gestureRecognizer = GestureRecognizer.createFromOptions(context, options)
            Timber.d("HandGestureProcessor: Initialized MediaPipe gesture recognizer")
        } catch (e: Exception) {
            Timber.e(e, "HandGestureProcessor: Failed to initialize gesture recognizer")
        }
    }
    
    private fun copyAssetToCache(assetName: String): File {
        val cacheFile = File(context.cacheDir, assetName)
        if (!cacheFile.exists()) {
            context.assets.open(assetName).use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
        }
        return cacheFile
    }
    
    override fun onCapturerStarted(success: Boolean) {
        Timber.d("HandGestureProcessor: Capturer started, success=$success")
        frameCount = 0
        processedCount = 0
        detectedGestureCount = 0
        lastGestureTime = 0L
        lastGesture = null
    }
    
    override fun onCapturerStopped() {
        Timber.d("HandGestureProcessor: Capturer stopped. Processed $processedCount/$frameCount frames, detected $detectedGestureCount gestures")
        frameCount = 0
        processedCount = 0
        detectedGestureCount = 0
    }
    
    override fun onFrameCaptured(frame: VideoFrame) {
        frameCount++
        
        // Process only every Nth frame to reduce CPU load
        if (frameCount % processEveryNFrames != 0) {
            // Pass through unmodified
            videoSink?.onFrame(frame)
            return
        }
        
        processedCount++
        
        // Convert VideoFrame to Bitmap for MediaPipe
        val bitmap = videoFrameToBitmap(frame)
        if (bitmap != null) {
            detectGestures(bitmap)
            bitmap.recycle()
        }
        
        // Pass through original frame (we don't modify video)
        videoSink?.onFrame(frame)
    }
    
    private fun detectGestures(bitmap: Bitmap) {
        try {
            val recognizer = gestureRecognizer ?: return
            
            // Convert Bitmap to MediaPipe image
            val mpImage = BitmapImageBuilder(bitmap).build()
            
            // Run gesture recognition
            val result: GestureRecognizerResult = recognizer.recognize(mpImage)
            
            // Process detected gestures
            if (result.gestures().isNotEmpty()) {
                for (gestureList in result.gestures()) {
                    if (gestureList.isNotEmpty()) {
                        val gesture = gestureList[0]
                        val gestureName = gesture.categoryName()
                        val confidence = gesture.score()
                        
                        if (confidence >= confidenceThreshold) {
                            handleGestureDetected(gestureName, confidence)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Timber.e(e, "HandGestureProcessor: Error detecting gestures")
        }
    }
    
    private fun handleGestureDetected(gesture: String, confidence: Float) {
        val currentTime = System.currentTimeMillis()
        
        // Check cooldown - prevent duplicate triggers
        if (gesture == lastGesture && (currentTime - lastGestureTime) < gestureCooldownMs) {
            return
        }
        
        // Filter gestures we care about
        val recognizedGesture = when (gesture) {
            "Thumb_Up" -> "👍"
            "Thumb_Down" -> "👎"
            "Open_Palm" -> "✋"
            "Closed_Fist" -> "✊"
            "Victory" -> "✌️"
            "Pointing_Up" -> "☝️"
            else -> null
        }
        
        if (recognizedGesture != null) {
            detectedGestureCount++
            lastGesture = gesture
            lastGestureTime = currentTime
            
            Timber.d("HandGestureProcessor: Detected $gesture ($recognizedGesture) with confidence ${String.format("%.2f", confidence)}")
            
            // Trigger callback (on background thread - caller should handle UI thread)
            onGestureDetected(recognizedGesture)
        }
    }
    
    private fun videoFrameToBitmap(frame: VideoFrame): Bitmap? {
        return try {
            val buffer = frame.buffer
            val width = buffer.width
            val height = buffer.height
            
            // Convert to I420 buffer
            val i420Buffer = buffer.toI420() ?: return null
            
            // Create ARGB bitmap
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            
            // Use AndroidVideoFrameBuffer's toPixels method instead
            // This is a simpler approach that works with LiveKit's WebRTC implementation
            try {
                // Create IntArray for pixels
                val pixels = IntArray(width * height)
                
                // Convert YUV to RGB manually (simple approach)
                val yData = i420Buffer.dataY
                val uData = i420Buffer.dataU
                val vData = i420Buffer.dataV
                val yStride = i420Buffer.strideY
                val uvStride = i420Buffer.strideU
                
                // Simple YUV420 to RGB conversion
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        val yIndex = y * yStride + x
                        val uvIndex = (y / 2) * uvStride + (x / 2)
                        
                        val yVal = yData.get(yIndex).toInt() and 0xFF
                        val uVal = uData.get(uvIndex).toInt() and 0xFF
                        val vVal = vData.get(uvIndex).toInt() and 0xFF
                        
                        // YUV to RGB conversion
                        val r = (yVal + 1.370705 * (vVal - 128)).toInt().coerceIn(0, 255)
                        val g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).toInt().coerceIn(0, 255)
                        val b = (yVal + 1.732446 * (uVal - 128)).toInt().coerceIn(0, 255)
                        
                        pixels[y * width + x] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                    }
                }
                
                bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
                i420Buffer.release()
                bitmap
            } catch (e: Exception) {
                i420Buffer.release()
                bitmap.recycle()
                null
            }
        } catch (e: Exception) {
            Timber.e(e, "HandGestureProcessor: Error converting frame to bitmap")
            null
        }
    }
    
    override fun setSink(sink: VideoSink?) {
        videoSink = sink
    }
    
    fun cleanup() {
        try {
            gestureRecognizer?.close()
            gestureRecognizer = null
            Timber.d("HandGestureProcessor: Cleaned up resources")
        } catch (e: Exception) {
            Timber.e(e, "HandGestureProcessor: Error during cleanup")
        }
    }
}
