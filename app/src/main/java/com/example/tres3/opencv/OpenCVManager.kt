package com.example.tres3.opencv

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import com.example.tres3.FeatureFlags
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.MatOfRect
import org.opencv.core.Point
import org.opencv.core.Scalar
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.CascadeClassifier
import java.io.File
import java.io.FileOutputStream

/**
 * OpenCVManager - Advanced image processing using OpenCV
 * 
 * Features:
 * - Advanced filters and effects
 * - Real-time image enhancement
 * - Color correction and adjustment
 * - Edge detection and processing
 * - Custom video filters
 * 
 * All features are disabled by default and controlled by FeatureFlags.
 */
object OpenCVManager {
    private const val TAG = "OpenCVManager"
    
    private var initialized = false
    private var faceClassifier: CascadeClassifier? = null
    
    data class ProcessingResult(
        val processedBitmap: Bitmap?,
        val processingTimeMs: Long,
        val success: Boolean,
        val error: String? = null
    )
    
    /**
     * Initialize OpenCV library
     */
    fun initialize(context: Context): Boolean {
        if (initialized) {
            return true
        }
        
        return try {
            if (OpenCVLoader.initLocal()) {
                Log.d(TAG, "OpenCV loaded successfully")
                initialized = true
                
                // Load face detection classifier if needed
                loadFaceClassifier(context)
                
                true
            } else {
                Log.e(TAG, "OpenCV initialization failed")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing OpenCV", e)
            false
        }
    }
    
    /**
     * Load face detection classifier
     */
    private fun loadFaceClassifier(context: Context) {
        try {
            val cascadeDir = context.getDir("cascade", Context.MODE_PRIVATE)
            val cascadeFile = File(cascadeDir, "haarcascade_frontalface_default.xml")
            
            // Copy from assets if not exists
            if (!cascadeFile.exists()) {
                context.assets.open("haarcascade_frontalface_default.xml").use { input ->
                    FileOutputStream(cascadeFile).use { output ->
                        input.copyTo(output)
                    }
                }
            }
            
            faceClassifier = CascadeClassifier(cascadeFile.absolutePath)
            if (faceClassifier?.empty() == true) {
                Log.w(TAG, "Failed to load face classifier")
                faceClassifier = null
            } else {
                Log.d(TAG, "Face classifier loaded successfully")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading face classifier", e)
        }
    }
    
    /**
     * Apply enhancement filter to a bitmap
     */
    fun applyEnhancement(
        bitmap: Bitmap,
        filter: ImageFilter
    ): ProcessingResult {
        if (!initialized) {
            return ProcessingResult(
                processedBitmap = bitmap,
                processingTimeMs = 0,
                success = false,
                error = "OpenCV not initialized"
            )
        }
        
        val startTime = System.currentTimeMillis()
        
        return try {
            val src = Mat()
            val dst = Mat()
            Utils.bitmapToMat(bitmap, src)
            
            when (filter) {
                ImageFilter.BRIGHTNESS_BOOST -> {
                    // Increase brightness
                    Core.add(src, Scalar(30.0, 30.0, 30.0), dst)
                }
                ImageFilter.CONTRAST_ENHANCE -> {
                    // Enhance contrast
                    src.convertTo(dst, -1, 1.3, 0.0)
                }
                ImageFilter.SHARPEN -> {
                    // Sharpen image
                    val kernel = Mat.zeros(3, 3, org.opencv.core.CvType.CV_32F)
                    kernel.put(0, 0, 
                        0.0, -1.0, 0.0,
                        -1.0, 5.0, -1.0,
                        0.0, -1.0, 0.0
                    )
                    Imgproc.filter2D(src, dst, -1, kernel)
                }
                ImageFilter.SMOOTH -> {
                    // Bilateral filter for smoothing while preserving edges
                    Imgproc.bilateralFilter(src, dst, 9, 75.0, 75.0)
                }
                ImageFilter.EDGE_ENHANCE -> {
                    // Edge enhancement
                    Imgproc.Laplacian(src, dst, org.opencv.core.CvType.CV_8U, 1, 1.0, 0.0)
                }
                ImageFilter.COLOR_BALANCE -> {
                    // Auto color balance
                    val channels = ArrayList<Mat>()
                    Core.split(src, channels)
                    
                    for (channel in channels) {
                        Core.normalize(channel, channel, 0.0, 255.0, Core.NORM_MINMAX)
                    }
                    
                    Core.merge(channels, dst)
                }
                ImageFilter.WARM_TONE -> {
                    // Add warm tone
                    Core.add(src, Scalar(0.0, 15.0, 30.0), dst)
                }
                ImageFilter.COOL_TONE -> {
                    // Add cool tone
                    Core.add(src, Scalar(30.0, 15.0, 0.0), dst)
                }
                ImageFilter.DENOISE -> {
                    // Noise reduction - using simple blur as fallback
                    Imgproc.GaussianBlur(src, dst, Size(5.0, 5.0), 0.0)
                }
                ImageFilter.HDR_EFFECT -> {
                    // HDR-like effect using contrast enhancement
                    src.convertTo(dst, -1, 1.5, 0.0)
                }
            }
            
            val resultBitmap = Bitmap.createBitmap(dst.cols(), dst.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(dst, resultBitmap)
            
            src.release()
            dst.release()
            
            val processingTime = System.currentTimeMillis() - startTime
            Log.d(TAG, "Filter ${filter.name} took ${processingTime}ms")
            
            ProcessingResult(
                processedBitmap = resultBitmap,
                processingTimeMs = processingTime,
                success = true
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error applying filter", e)
            ProcessingResult(
                processedBitmap = null,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = false,
                error = e.message
            )
        }
    }
    
    /**
     * Apply multiple filters in sequence
     */
    fun applyFilters(
        bitmap: Bitmap,
        filters: List<ImageFilter>
    ): ProcessingResult {
        var currentBitmap = bitmap
        val startTime = System.currentTimeMillis()
        
        for (filter in filters) {
            val result = applyEnhancement(currentBitmap, filter)
            if (!result.success || result.processedBitmap == null) {
                return result
            }
            currentBitmap = result.processedBitmap
        }
        
        return ProcessingResult(
            processedBitmap = currentBitmap,
            processingTimeMs = System.currentTimeMillis() - startTime,
            success = true
        )
    }
    
    /**
     * Detect faces using OpenCV
     */
    fun detectFaces(bitmap: Bitmap): List<org.opencv.core.Rect> {
        if (faceClassifier == null) {
            return emptyList()
        }
        
        return try {
            val mat = Mat()
            val grayMat = Mat()
            Utils.bitmapToMat(bitmap, mat)
            Imgproc.cvtColor(mat, grayMat, Imgproc.COLOR_RGBA2GRAY)
            
            val faces = MatOfRect()
            faceClassifier?.detectMultiScale(grayMat, faces)
            
            mat.release()
            grayMat.release()
            
            faces.toList()
        } catch (e: Exception) {
            Log.e(TAG, "Face detection failed", e)
            emptyList()
        }
    }
    
    /**
     * Auto-enhance image (combines multiple adjustments)
     */
    fun autoEnhance(bitmap: Bitmap): ProcessingResult {
        return applyFilters(
            bitmap,
            listOf(
                ImageFilter.COLOR_BALANCE,
                ImageFilter.CONTRAST_ENHANCE,
                ImageFilter.SHARPEN,
                ImageFilter.DENOISE
            )
        )
    }
    
    /**
     * Low-light enhancement
     */
    fun enhanceLowLight(bitmap: Bitmap): ProcessingResult {
        return applyFilters(
            bitmap,
            listOf(
                ImageFilter.BRIGHTNESS_BOOST,
                ImageFilter.DENOISE,
                ImageFilter.CONTRAST_ENHANCE
            )
        )
    }
    
    /**
     * Check if OpenCV is available
     */
    fun isAvailable(): Boolean {
        return initialized
    }
    
    /**
     * Get OpenCV status
     */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "initialized" to initialized,
            "faceClassifierLoaded" to (faceClassifier != null && faceClassifier?.empty() == false),
            "openCVVersion" to if (initialized) Core.VERSION else "Not initialized"
        )
    }
    
    /**
     * Advanced white balance correction
     */
    fun correctWhiteBalance(bitmap: Bitmap): ProcessingResult {
        if (!initialized) {
            return ProcessingResult(
                processedBitmap = bitmap,
                processingTimeMs = 0,
                success = false,
                error = "OpenCV not initialized"
            )
        }
        
        val startTime = System.currentTimeMillis()
        
        return try {
            val src = Mat()
            val dst = Mat()
            Utils.bitmapToMat(bitmap, src)
            
            // Gray world assumption for white balance
            val channels = ArrayList<Mat>()
            Core.split(src, channels)
            
            val avgB = Core.mean(channels[0]).`val`[0]
            val avgG = Core.mean(channels[1]).`val`[0]
            val avgR = Core.mean(channels[2]).`val`[0]
            
            val avg = (avgB + avgG + avgR) / 3.0
            
            val scaleB = avg / avgB
            val scaleG = avg / avgG
            val scaleR = avg / avgR
            
            channels[0].convertTo(channels[0], -1, scaleB, 0.0)
            channels[1].convertTo(channels[1], -1, scaleG, 0.0)
            channels[2].convertTo(channels[2], -1, scaleR, 0.0)
            
            Core.merge(channels, dst)
            
            val resultBitmap = Bitmap.createBitmap(dst.cols(), dst.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(dst, resultBitmap)
            
            src.release()
            dst.release()
            channels.forEach { it.release() }
            
            ProcessingResult(
                processedBitmap = resultBitmap,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = true
            )
        } catch (e: Exception) {
            Log.e(TAG, "White balance correction failed", e)
            ProcessingResult(
                processedBitmap = null,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = false,
                error = e.message
            )
        }
    }
    
    /**
     * Skin tone enhancement for video calls
     */
    fun enhanceSkinTone(bitmap: Bitmap): ProcessingResult {
        if (!initialized) {
            return ProcessingResult(
                processedBitmap = bitmap,
                processingTimeMs = 0,
                success = false,
                error = "OpenCV not initialized"
            )
        }
        
        val startTime = System.currentTimeMillis()
        
        return try {
            val src = Mat()
            val dst = Mat()
            Utils.bitmapToMat(bitmap, src)
            
            // Convert to HSV for skin tone detection
            val hsv = Mat()
            Imgproc.cvtColor(src, hsv, Imgproc.COLOR_RGB2HSV)
            
            // Skin tone range (approximate)
            val lowerSkin = Scalar(0.0, 20.0, 70.0)
            val upperSkin = Scalar(20.0, 150.0, 255.0)
            
            // Create mask for skin pixels
            val mask = Mat()
            Core.inRange(hsv, lowerSkin, upperSkin, mask)
            
            // Enhance skin regions: slight warmth and smoothing
            val enhanced = Mat()
            Imgproc.bilateralFilter(src, enhanced, 9, 75.0, 75.0)
            
            // Add slight warm tone to skin areas
            Core.add(enhanced, Scalar(0.0, 5.0, 10.0), enhanced, mask)
            
            // Copy enhanced skin regions to destination
            src.copyTo(dst)
            enhanced.copyTo(dst, mask)
            
            val resultBitmap = Bitmap.createBitmap(dst.cols(), dst.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(dst, resultBitmap)
            
            src.release()
            dst.release()
            hsv.release()
            mask.release()
            enhanced.release()
            
            ProcessingResult(
                processedBitmap = resultBitmap,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = true
            )
        } catch (e: Exception) {
            Log.e(TAG, "Skin tone enhancement failed", e)
            ProcessingResult(
                processedBitmap = null,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = false,
                error = e.message
            )
        }
    }
    
    /**
     * Dynamic range optimization (tone mapping)
     */
    fun optimizeDynamicRange(bitmap: Bitmap): ProcessingResult {
        if (!initialized) {
            return ProcessingResult(
                processedBitmap = bitmap,
                processingTimeMs = 0,
                success = false,
                error = "OpenCV not initialized"
            )
        }
        
        val startTime = System.currentTimeMillis()
        
        return try {
            val src = Mat()
            val dst = Mat()
            Utils.bitmapToMat(bitmap, src)
            
            // Apply CLAHE (Contrast Limited Adaptive Histogram Equalization)
            val lab = Mat()
            Imgproc.cvtColor(src, lab, Imgproc.COLOR_RGB2Lab)
            
            val channels = ArrayList<Mat>()
            Core.split(lab, channels)
            
            // Apply CLAHE to L channel
            val clahe = Imgproc.createCLAHE()
            clahe.clipLimit = 2.0
            clahe.tilesGridSize = Size(8.0, 8.0)
            clahe.apply(channels[0], channels[0])
            
            Core.merge(channels, lab)
            Imgproc.cvtColor(lab, dst, Imgproc.COLOR_Lab2RGB)
            
            val resultBitmap = Bitmap.createBitmap(dst.cols(), dst.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(dst, resultBitmap)
            
            src.release()
            dst.release()
            lab.release()
            channels.forEach { it.release() }
            
            ProcessingResult(
                processedBitmap = resultBitmap,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = true
            )
        } catch (e: Exception) {
            Log.e(TAG, "Dynamic range optimization failed", e)
            ProcessingResult(
                processedBitmap = null,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = false,
                error = e.message
            )
        }
    }
    
    /**
     * Intelligent lighting adaptation based on image brightness
     */
    fun adaptLighting(bitmap: Bitmap): ProcessingResult {
        if (!initialized) {
            return ProcessingResult(
                processedBitmap = bitmap,
                processingTimeMs = 0,
                success = false,
                error = "OpenCV not initialized"
            )
        }
        
        val startTime = System.currentTimeMillis()
        
        return try {
            val src = Mat()
            val gray = Mat()
            Utils.bitmapToMat(bitmap, src)
            
            // Convert to grayscale to analyze brightness
            Imgproc.cvtColor(src, gray, Imgproc.COLOR_RGB2GRAY)
            
            // Calculate average brightness
            val meanBrightness = Core.mean(gray).`val`[0]
            
            val dst = Mat()
            
            when {
                meanBrightness < 80 -> {
                    // Dark image - boost brightness and reduce noise
                    Log.d(TAG, "Low light detected (brightness: $meanBrightness), applying enhancement")
                    Imgproc.GaussianBlur(src, dst, Size(3.0, 3.0), 0.0)
                    dst.convertTo(dst, -1, 1.4, 40.0) // Increase brightness and contrast
                }
                meanBrightness > 180 -> {
                    // Bright image - reduce highlights
                    Log.d(TAG, "High light detected (brightness: $meanBrightness), applying reduction")
                    src.convertTo(dst, -1, 0.9, -20.0) // Reduce brightness slightly
                }
                else -> {
                    // Normal lighting - slight enhancement
                    Log.d(TAG, "Normal lighting (brightness: $meanBrightness), applying slight enhancement")
                    src.convertTo(dst, -1, 1.1, 5.0)
                }
            }
            
            val resultBitmap = Bitmap.createBitmap(dst.cols(), dst.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(dst, resultBitmap)
            
            src.release()
            dst.release()
            gray.release()
            
            ProcessingResult(
                processedBitmap = resultBitmap,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = true
            )
        } catch (e: Exception) {
            Log.e(TAG, "Lighting adaptation failed", e)
            ProcessingResult(
                processedBitmap = null,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = false,
                error = e.message
            )
        }
    }
    
    /**
     * Advanced noise reduction using Non-local Means Denoising
     */
    fun reduceNoise(bitmap: Bitmap, strength: Int = 10): ProcessingResult {
        if (!initialized) {
            return ProcessingResult(
                processedBitmap = bitmap,
                processingTimeMs = 0,
                success = false,
                error = "OpenCV not initialized"
            )
        }
        
        val startTime = System.currentTimeMillis()
        
        return try {
            val src = Mat()
            val dst = Mat()
            Utils.bitmapToMat(bitmap, src)
            
            // Fast denoising for real-time processing
            org.opencv.photo.Photo.fastNlMeansDenoisingColored(src, dst, strength.toFloat(), strength.toFloat(), 7, 21)
            
            val resultBitmap = Bitmap.createBitmap(dst.cols(), dst.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(dst, resultBitmap)
            
            src.release()
            dst.release()
            
            ProcessingResult(
                processedBitmap = resultBitmap,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = true
            )
        } catch (e: Exception) {
            Log.e(TAG, "Noise reduction failed", e)
            ProcessingResult(
                processedBitmap = null,
                processingTimeMs = System.currentTimeMillis() - startTime,
                success = false,
                error = e.message
            )
        }
    }
    
    /**
     * Comprehensive video enhancement for calls
     * Combines multiple enhancements intelligently
     */
    fun enhanceForVideoCall(bitmap: Bitmap): ProcessingResult {
        val startTime = System.currentTimeMillis()
        
        // Step 1: White balance correction
        var result = correctWhiteBalance(bitmap)
        if (!result.success || result.processedBitmap == null) {
            return result
        }
        
        // Step 2: Lighting adaptation
        result = adaptLighting(result.processedBitmap)
        if (!result.success || result.processedBitmap == null) {
            return result
        }
        
        // Step 3: Noise reduction
        result = reduceNoise(result.processedBitmap, strength = 5)
        if (!result.success || result.processedBitmap == null) {
            return result
        }
        
        // Step 4: Skin tone enhancement
        result = enhanceSkinTone(result.processedBitmap)
        if (!result.success || result.processedBitmap == null) {
            return result
        }
        
        // Step 5: Slight sharpening
        result = applyEnhancement(result.processedBitmap, ImageFilter.SHARPEN)
        
        return ProcessingResult(
            processedBitmap = result.processedBitmap,
            processingTimeMs = System.currentTimeMillis() - startTime,
            success = result.success,
            error = result.error
        )
    }
    
    enum class ImageFilter {
        BRIGHTNESS_BOOST,
        CONTRAST_ENHANCE,
        SHARPEN,
        SMOOTH,
        EDGE_ENHANCE,
        COLOR_BALANCE,
        WARM_TONE,
        COOL_TONE,
        DENOISE,
        HDR_EFFECT
    }
}
