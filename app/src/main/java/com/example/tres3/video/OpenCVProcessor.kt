package com.example.tres3.video

import android.graphics.Bitmap
import android.util.Log
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc

/**
 * OpenCV-based video processor for low-light enhancement
 * - Applies adaptive histogram equalization (CLAHE)
 * - Enhances brightness and contrast in dark conditions
 * - Preserves natural colors
 */
object OpenCVProcessor {
    private val TAG = "OpenCVProcessor"
    private var isInitialized = false
    
    /**
     * Initialize OpenCV library
     */
    fun initialize(): Boolean {
        if (isInitialized) return true
        
        return try {
            if (OpenCVLoader.initLocal()) {
                isInitialized = true
                Log.d(TAG, "✅ OpenCV initialized successfully")
                true
            } else {
                Log.e(TAG, "❌ OpenCV initialization failed")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ OpenCV initialization error: ${e.message}", e)
            false
        }
    }
    
    /**
     * Apply low-light enhancement to a bitmap
     * Uses CLAHE (Contrast Limited Adaptive Histogram Equalization)
     */
    fun enhanceLowLight(inputBitmap: Bitmap): Bitmap {
        if (!isInitialized) {
            Log.w(TAG, "OpenCV not initialized, returning original bitmap")
            return inputBitmap
        }
        
        return try {
            // Convert Bitmap to Mat
            val srcMat = Mat()
            Utils.bitmapToMat(inputBitmap, srcMat)
            
            // Convert to LAB color space (better for brightness adjustments)
            val labMat = Mat()
            Imgproc.cvtColor(srcMat, labMat, Imgproc.COLOR_RGB2Lab)
            
            // Split LAB channels
            val channels = mutableListOf<Mat>()
            Core.split(labMat, channels)
            
            // Apply CLAHE to L channel (lightness)
            val clahe = Imgproc.createCLAHE().apply {
                clipLimit = 3.0  // Higher = more contrast enhancement
                tilesGridSize = Size(8.0, 8.0)  // Grid size for local enhancement
            }
            
            val lChannel = channels[0]
            clahe.apply(lChannel, lChannel)
            
            // Merge channels back
            Core.merge(channels, labMat)
            
            // Convert back to RGB
            val resultMat = Mat()
            Imgproc.cvtColor(labMat, resultMat, Imgproc.COLOR_Lab2RGB)
            
            // Convert Mat back to Bitmap
            val resultBitmap = Bitmap.createBitmap(
                resultMat.cols(),
                resultMat.rows(),
                Bitmap.Config.ARGB_8888
            )
            Utils.matToBitmap(resultMat, resultBitmap)
            
            // Cleanup
            srcMat.release()
            labMat.release()
            resultMat.release()
            channels.forEach { it.release() }
            
            resultBitmap
        } catch (e: Exception) {
            Log.e(TAG, "Error enhancing low-light: ${e.message}", e)
            inputBitmap
        }
    }
    
    /**
     * Check if frame needs enhancement based on brightness
     * @return true if frame is dark and needs enhancement
     */
    fun needsEnhancement(bitmap: Bitmap, brightnessThreshold: Double = 50.0): Boolean {
        if (!isInitialized) return false
        
        return try {
            val mat = Mat()
            Utils.bitmapToMat(bitmap, mat)
            
            // Convert to grayscale
            val grayMat = Mat()
            Imgproc.cvtColor(mat, grayMat, Imgproc.COLOR_RGB2GRAY)
            
            // Calculate mean brightness
            val mean = Core.mean(grayMat)
            val brightness = mean.`val`[0]
            
            // Cleanup
            mat.release()
            grayMat.release()
            
            // Return true if darker than threshold
            brightness < brightnessThreshold
        } catch (e: Exception) {
            Log.e(TAG, "Error checking brightness: ${e.message}", e)
            false
        }
    }
    
    /**
     * Apply adaptive enhancement based on scene brightness
     */
    fun adaptiveEnhance(inputBitmap: Bitmap): Bitmap {
        if (!isInitialized) return inputBitmap
        
        return try {
            // Check if enhancement needed
            val mat = Mat()
            Utils.bitmapToMat(inputBitmap, mat)
            
            val grayMat = Mat()
            Imgproc.cvtColor(mat, grayMat, Imgproc.COLOR_RGB2GRAY)
            val brightness = Core.mean(grayMat).`val`[0]
            
            grayMat.release()
            
            // Determine enhancement strength based on brightness
            val clipLimit = when {
                brightness < 30 -> 4.0  // Very dark - strong enhancement
                brightness < 50 -> 3.0  // Dark - moderate enhancement
                brightness < 70 -> 2.0  // Dim - light enhancement
                else -> {
                    mat.release()
                    return inputBitmap  // Bright enough - no enhancement
                }
            }
            
            // Convert to LAB
            val labMat = Mat()
            Imgproc.cvtColor(mat, labMat, Imgproc.COLOR_RGB2Lab)
            
            // Split and enhance L channel
            val channels = mutableListOf<Mat>()
            Core.split(labMat, channels)
            
            val clahe = Imgproc.createCLAHE().apply {
                this.clipLimit = clipLimit
                tilesGridSize = Size(8.0, 8.0)
            }
            
            clahe.apply(channels[0], channels[0])
            
            // Merge and convert back
            Core.merge(channels, labMat)
            val resultMat = Mat()
            Imgproc.cvtColor(labMat, resultMat, Imgproc.COLOR_Lab2RGB)
            
            // Create result bitmap
            val resultBitmap = Bitmap.createBitmap(
                resultMat.cols(),
                resultMat.rows(),
                Bitmap.Config.ARGB_8888
            )
            Utils.matToBitmap(resultMat, resultBitmap)
            
            // Cleanup
            mat.release()
            labMat.release()
            resultMat.release()
            channels.forEach { it.release() }
            
            Log.d(TAG, "✨ Enhanced frame (brightness: $brightness, clipLimit: $clipLimit)")
            resultBitmap
        } catch (e: Exception) {
            Log.e(TAG, "Error in adaptive enhance: ${e.message}", e)
            inputBitmap
        }
    }
}
