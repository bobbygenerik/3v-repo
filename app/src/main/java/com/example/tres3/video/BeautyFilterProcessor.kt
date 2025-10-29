package com.example.tres3.video

import android.graphics.Bitmap
import android.graphics.Color
import livekit.org.webrtc.VideoFrame
import livekit.org.webrtc.VideoProcessor
import livekit.org.webrtc.VideoSink
import timber.log.Timber
import kotlin.math.min
import kotlin.math.pow

/**
 * Beauty filter video processor for skin smoothing and enhancement.
 * 
 * Applies real-time beauty effects to video frames:
 * - Skin smoothing (reduces blemishes and imperfections)
 * - Brightness adjustment (subtle brightening)
 * - Warm color tone (slight pink tint for healthy appearance)
 * - Edge preservation (maintains facial features)
 * 
 * Features:
 * - Lightweight processing suitable for real-time video
 * - Adjustable intensity levels (0.0 - 1.0)
 * - Processes every Nth frame for performance
 * - Preserves natural appearance
 * 
 * Integration:
 * ```
 * val beautyFilter = BeautyFilterProcessor(intensity = 0.6f)
 * compositeProcessor.addProcessor(beautyFilter)
 * ```
 */
class BeautyFilterProcessor(
    private var intensity: Float = 0.5f // 0.0 = disabled, 1.0 = maximum
) : VideoProcessor {
    
    private var videoSink: VideoSink? = null
    private var frameCount = 0
    private var processedCount = 0
    
    // Process every 3rd frame (10fps at 30fps input) for smooth effect
    private val processEveryNFrames = 3
    
    // Cached last processed frame
    private var lastProcessedBitmap: Bitmap? = null
    
    init {
        require(intensity in 0f..1f) { "Intensity must be between 0.0 and 1.0" }
    }
    
    override fun onCapturerStarted(success: Boolean) {
        Timber.d("BeautyFilterProcessor: Capturer started, intensity=$intensity")
        frameCount = 0
        processedCount = 0
        lastProcessedBitmap?.recycle()
        lastProcessedBitmap = null
    }
    
    override fun onCapturerStopped() {
        Timber.d("BeautyFilterProcessor: Capturer stopped. Processed $processedCount/$frameCount frames")
        frameCount = 0
        processedCount = 0
        lastProcessedBitmap?.recycle()
        lastProcessedBitmap = null
    }
    
    override fun onFrameCaptured(frame: VideoFrame) {
        frameCount++
        
        // If disabled, pass through
        if (intensity == 0f) {
            videoSink?.onFrame(frame)
            return
        }
        
        // Process only every Nth frame to reduce CPU load
        if (frameCount % processEveryNFrames != 0) {
            videoSink?.onFrame(frame)
            return
        }
        
        processedCount++
        
        try {
            // Convert VideoFrame to Bitmap
            val bitmap = videoFrameToBitmap(frame)
            if (bitmap != null) {
                // Apply beauty filter
                val filtered = applyBeautyFilter(bitmap)
                
                // Convert processed Bitmap back to VideoFrame
                val i420Buffer = VideoFrameConverters.bitmapToI420(filtered)
                val processedFrame = VideoFrame(i420Buffer, frame.rotation, frame.timestampNs)
                
                // Send processed frame
                videoSink?.onFrame(processedFrame)
                
                // Cache and cleanup
                lastProcessedBitmap?.recycle()
                lastProcessedBitmap = filtered
                bitmap.recycle()
                processedFrame.release()
                
                return
            }
        } catch (e: Exception) {
            Timber.e(e, "BeautyFilterProcessor: Error processing frame")
        }
        
        // Fallback: pass through original frame if processing fails
        videoSink?.onFrame(frame)
    }
    
    /**
     * Apply beauty filter to bitmap
     * 
     * Algorithm:
     * 1. Gaussian blur for skin smoothing
     * 2. Blend original with blurred (preserves edges)
     * 3. Brighten slightly
     * 4. Add warm tint
     */
    private fun applyBeautyFilter(input: Bitmap): Bitmap {
        val width = input.width
        val height = input.height
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        
        try {
            // Simple box blur approximation (lightweight)
            val radius = (3 * intensity).toInt().coerceIn(1, 5)
            val blurred = boxBlur(input, radius)
            
            // Blend original with blurred based on intensity
            for (y in 0 until height) {
                for (x in 0 until width) {
                    val originalPixel = input.getPixel(x, y)
                    val blurredPixel = blurred.getPixel(x, y)
                    
                    // Extract RGB channels
                    val origR = Color.red(originalPixel)
                    val origG = Color.green(originalPixel)
                    val origB = Color.blue(originalPixel)
                    
                    val blurR = Color.red(blurredPixel)
                    val blurG = Color.green(blurredPixel)
                    val blurB = Color.blue(blurredPixel)
                    
                    // Blend: preserve edges (high contrast), smooth skin (low contrast)
                    val contrast = (origR - blurR) * (origR - blurR) + (origG - blurG) * (origG - blurG) + (origB - blurB) * (origB - blurB)
                    val blendFactor = if (contrast > 1000) 0.2f else intensity
                    
                    var r = (origR * (1 - blendFactor) + blurR * blendFactor).toInt()
                    var g = (origG * (1 - blendFactor) + blurG * blendFactor).toInt()
                    var b = (origB * (1 - blendFactor) + blurB * blendFactor).toInt()
                    
                    // Subtle brightening (5-15%)
                    val brighten = 1.0f + (0.1f * intensity)
                    r = (r * brighten).toInt().coerceIn(0, 255)
                    g = (g * brighten).toInt().coerceIn(0, 255)
                    b = (b * brighten).toInt().coerceIn(0, 255)
                    
                    // Warm tint (add slight red)
                    r = (r + 5 * intensity).toInt().coerceIn(0, 255)
                    
                    output.setPixel(x, y, Color.argb(255, r, g, b))
                }
            }
            
            blurred.recycle()
        } catch (e: Exception) {
            Timber.e(e, "BeautyFilterProcessor: Error applying filter")
            return input
        }
        
        return output
    }
    
    /**
     * Simple box blur (faster than Gaussian for real-time)
     */
    private fun boxBlur(input: Bitmap, radius: Int): Bitmap {
        val width = input.width
        val height = input.height
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                var r = 0
                var g = 0
                var b = 0
                var count = 0
                
                // Average pixels in box
                for (dy in -radius..radius) {
                    for (dx in -radius..radius) {
                        val nx = (x + dx).coerceIn(0, width - 1)
                        val ny = (y + dy).coerceIn(0, height - 1)
                        val pixel = input.getPixel(nx, ny)
                        r += Color.red(pixel)
                        g += Color.green(pixel)
                        b += Color.blue(pixel)
                        count++
                    }
                }
                
                output.setPixel(
                    x, y,
                    Color.argb(255, r / count, g / count, b / count)
                )
            }
        }
        
        return output
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
            Timber.e(e, "BeautyFilterProcessor: Error converting frame to bitmap")
            null
        }
    }
    
    override fun setSink(sink: VideoSink?) {
        videoSink = sink
    }
    
    /**
     * Update filter intensity dynamically
     */
    fun setIntensity(newIntensity: Float) {
        require(newIntensity in 0f..1f) { "Intensity must be between 0.0 and 1.0" }
        intensity = newIntensity
        Timber.d("BeautyFilterProcessor: Intensity updated to $intensity")
    }
    
    fun cleanup() {
        lastProcessedBitmap?.recycle()
        lastProcessedBitmap = null
        Timber.d("BeautyFilterProcessor: Cleaned up resources")
    }
}
