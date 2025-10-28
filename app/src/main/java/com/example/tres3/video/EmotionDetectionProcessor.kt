package com.example.tres3.video

import android.content.Context
import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import livekit.org.webrtc.VideoFrame
import livekit.org.webrtc.VideoProcessor
import livekit.org.webrtc.VideoSink
import timber.log.Timber
import kotlin.math.abs

/**
 * Emotion detection video processor using ML Kit Face Detection.
 * 
 * Analyzes facial expressions to detect emotions:
 * - 😊 Happy (smiling probability > 0.7)
 * - 😐 Neutral (no strong expression)
 * - 😮 Surprised (eyes wide open)
 * - 😢 Sad (mouth corners down, eyes narrow)
 * 
 * Features:
 * - Real-time emotion detection with ML Kit
 * - Processes every Nth frame to reduce CPU load
 * - Callback-based emotion events (non-blocking)
 * - Smoothing to prevent jitter
 * - Confidence threshold filtering
 * 
 * Integration:
 * ```
 * val emotionProcessor = EmotionDetectionProcessor(context) { emotion, confidence ->
 *     Log.d("Emotion", "Detected: $emotion (${confidence}%)")
 *     updateEmotionIndicator(emotion)
 * }
 * compositeProcessor.addProcessor(emotionProcessor)
 * ```
 */
class EmotionDetectionProcessor(
    private val context: Context,
    private val onEmotionDetected: (String, Float) -> Unit
) : VideoProcessor {
    
    private var videoSink: VideoSink? = null
    private var frameCount = 0
    private var processedCount = 0
    private var detectedEmotionCount = 0
    
    // Process every 45th frame (~0.67fps at 30fps input) for less aggressive polling
    private val processEveryNFrames = 45
    
    // Confidence thresholds
    private val smilingThreshold = 0.7f
    private val eyesOpenThreshold = 0.8f
    
    // Smoothing - track last N emotions
    private val emotionHistory = mutableListOf<String>()
    private val historySize = 3
    private var lastEmotionTime = 0L
    private val emotionCooldownMs = 3000L // 3 seconds between emotion changes
    
    // ML Kit face detector with classification
    private val faceDetector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
            .setContourMode(FaceDetectorOptions.CONTOUR_MODE_NONE)
            .setMinFaceSize(0.15f)
            .build()
        FaceDetection.getClient(options)
    }
    
    override fun onCapturerStarted(success: Boolean) {
        Timber.d("EmotionDetectionProcessor: Capturer started, success=$success")
        frameCount = 0
        processedCount = 0
        detectedEmotionCount = 0
        emotionHistory.clear()
        lastEmotionTime = 0L
    }
    
    override fun onCapturerStopped() {
        Timber.d("EmotionDetectionProcessor: Capturer stopped. Processed $processedCount/$frameCount frames, detected $detectedEmotionCount emotions")
        frameCount = 0
        processedCount = 0
        detectedEmotionCount = 0
    }
    
    override fun onFrameCaptured(frame: VideoFrame) {
        frameCount++
        
        // Process only every Nth frame
        if (frameCount % processEveryNFrames != 0) {
            videoSink?.onFrame(frame)
            return
        }
        
        processedCount++
        
        // Convert VideoFrame to Bitmap
        val bitmap = videoFrameToBitmap(frame)
        if (bitmap != null) {
            detectEmotion(bitmap)
            bitmap.recycle()
        }
        
        // Pass through original frame
        videoSink?.onFrame(frame)
    }
    
    private fun detectEmotion(bitmap: Bitmap) {
        try {
            val image = InputImage.fromBitmap(bitmap, 0)
            
            faceDetector.process(image)
                .addOnSuccessListener { faces ->
                    if (faces.isNotEmpty()) {
                        analyzeFace(faces[0])
                    }
                }
                .addOnFailureListener { e ->
                    Timber.e(e, "EmotionDetectionProcessor: Face detection failed")
                }
        } catch (e: Exception) {
            Timber.e(e, "EmotionDetectionProcessor: Error detecting emotion")
        }
    }
    
    private fun analyzeFace(face: Face) {
        val smilingProb = face.smilingProbability ?: 0f
        val leftEyeOpen = face.leftEyeOpenProbability ?: 0.5f
        val rightEyeOpen = face.rightEyeOpenProbability ?: 0.5f
        
        // Determine emotion based on face classification
        val emotion = when {
            smilingProb > smilingThreshold -> "😊 Happy"
            smilingProb < 0.2f && leftEyeOpen < 0.3f -> "😢 Sad"
            leftEyeOpen > eyesOpenThreshold && rightEyeOpen > eyesOpenThreshold -> "😮 Surprised"
            else -> "😐 Neutral"
        }
        
        // Add to history for smoothing
        emotionHistory.add(emotion)
        if (emotionHistory.size > historySize) {
            emotionHistory.removeAt(0)
        }
        
        // Use majority vote from history
        val dominantEmotion = emotionHistory.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key ?: emotion
        
        // Check cooldown
        val currentTime = System.currentTimeMillis()
        if ((currentTime - lastEmotionTime) >= emotionCooldownMs) {
            handleEmotionDetected(dominantEmotion, smilingProb)
            lastEmotionTime = currentTime
        }
    }
    
    private fun handleEmotionDetected(emotion: String, confidence: Float) {
        detectedEmotionCount++
        
        Timber.d("EmotionDetectionProcessor: Detected $emotion with confidence ${String.format("%.2f", confidence)}")
        
        // Trigger callback
        onEmotionDetected(emotion, confidence)
    }
    
    private fun videoFrameToBitmap(frame: VideoFrame): Bitmap? {
        return try {
            val buffer = frame.buffer
            val width = buffer.width
            val height = buffer.height
            
            val i420Buffer = buffer.toI420() ?: return null
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            
            try {
                val pixels = IntArray(width * height)
                val yData = i420Buffer.dataY
                val uData = i420Buffer.dataU
                val vData = i420Buffer.dataV
                val yStride = i420Buffer.strideY
                val uvStride = i420Buffer.strideU
                
                // YUV420 to RGB conversion
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        val yIndex = y * yStride + x
                        val uvIndex = (y / 2) * uvStride + (x / 2)
                        
                        val yVal = yData.get(yIndex).toInt() and 0xFF
                        val uVal = uData.get(uvIndex).toInt() and 0xFF
                        val vVal = vData.get(uvIndex).toInt() and 0xFF
                        
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
            Timber.e(e, "EmotionDetectionProcessor: Error converting frame to bitmap")
            null
        }
    }
    
    override fun setSink(sink: VideoSink?) {
        videoSink = sink
    }
    
    fun cleanup() {
        try {
            // ML Kit face detector doesn't need explicit cleanup
            emotionHistory.clear()
            Timber.d("EmotionDetectionProcessor: Cleaned up resources")
        } catch (e: Exception) {
            Timber.e(e, "EmotionDetectionProcessor: Error during cleanup")
        }
    }
}
