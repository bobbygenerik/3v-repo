package com.example.tres3.video

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.StreamConfigurationMap
import android.util.Log
import android.util.Size
import com.example.tres3.FeatureFlags

/**
 * CameraEnhancer - Advanced camera optimizations using Camera2 API
 * 
 * Features:
 * - Continuous auto-focus (CAF) for better focus tracking
 * - Auto-exposure optimization for varying lighting
 * - Video stabilization to reduce shake
 * - Low-light enhancement
 * - HDR video support
 * 
 * All enhancements work as middleware and are optional via FeatureFlags.
 * 
 * Usage:
 * ```
 * val enhancer = CameraEnhancer(context)
 * val capabilities = enhancer.getCameraCapabilities(cameraId)
 * if (capabilities.supportsContinuousAutoFocus) {
 *     enhancer.enableContinuousAutoFocus(cameraId)
 * }
 * ```
 */
class CameraEnhancer(private val context: Context) {
    
    companion object {
        private const val TAG = "CameraEnhancer"
    }
    
    private val cameraManager: CameraManager by lazy {
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }
    
    /**
     * Camera capability information
     */
    data class CameraCapabilities(
        val cameraId: String,
        val supportsContinuousAutoFocus: Boolean,
        val supportsAutoExposure: Boolean,
        val supportsVideoStabilization: Boolean,
        val supportsOpticalStabilization: Boolean,
        val supportsHDR: Boolean,
        val supportedVideoSizes: List<Size>,
        val maxFps: Int,
        val lensFacing: Int, // LENS_FACING_FRONT or LENS_FACING_BACK
        val sensorOrientation: Int
    )
    
    /**
     * Enhancement settings for a camera
     */
    data class EnhancementSettings(
        var continuousAutoFocus: Boolean = false,
        var autoExposure: Boolean = false,
        var videoStabilization: Boolean = false,
        var opticalStabilization: Boolean = false,
        var hdrMode: Boolean = false,
        var lowLightMode: Boolean = false,
        var noiseReduction: Int = CaptureRequest.NOISE_REDUCTION_MODE_FAST,
        var exposureCompensation: Int = 0,
        var whiteBalanceMode: Int = CaptureRequest.CONTROL_AWB_MODE_AUTO,
        var colorCorrectionMode: Int = CaptureRequest.COLOR_CORRECTION_MODE_FAST,
        var edgeEnhancement: Int = CaptureRequest.EDGE_MODE_FAST,
        var hotPixelMode: Int = CaptureRequest.HOT_PIXEL_MODE_FAST
    )
    
    private val enhancementSettings = mutableMapOf<String, EnhancementSettings>()
    
    /**
     * Get detailed camera capabilities
     */
    fun getCameraCapabilities(cameraId: String): CameraCapabilities? {
        return try {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            
            // Get AF modes
            val afModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
            val supportsContinuousAF = afModes.contains(CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO) ||
                                       afModes.contains(CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            
            // Get AE modes
            val aeModes = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_MODES) ?: intArrayOf()
            val supportsAutoAE = aeModes.contains(CameraMetadata.CONTROL_AE_MODE_ON)
            
            // Check stabilization support
            val videoStab = characteristics.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES) ?: intArrayOf()
            val supportsVideoStab = videoStab.contains(CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON)
            
            val opticalStab = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION) ?: intArrayOf()
            val supportsOpticalStab = opticalStab.contains(CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON)
            
            // Get supported video sizes
            val streamConfigMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val videoSizes = streamConfigMap?.getOutputSizes(android.media.MediaRecorder::class.java)?.toList() ?: emptyList()
            
            // Get max FPS
            val fpsRanges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES) ?: arrayOf()
            val maxFps = fpsRanges.maxOfOrNull { it.upper } ?: 30
            
            // Get lens facing and orientation
            val lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING) ?: CameraMetadata.LENS_FACING_FRONT
            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            
            // Check HDR support
            val sceneModes = characteristics.get(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES) ?: intArrayOf()
            val supportsHDR = sceneModes.contains(CameraMetadata.CONTROL_SCENE_MODE_HDR)
            
            CameraCapabilities(
                cameraId = cameraId,
                supportsContinuousAutoFocus = supportsContinuousAF,
                supportsAutoExposure = supportsAutoAE,
                supportsVideoStabilization = supportsVideoStab,
                supportsOpticalStabilization = supportsOpticalStab,
                supportsHDR = supportsHDR,
                supportedVideoSizes = videoSizes,
                maxFps = maxFps,
                lensFacing = lensFacing,
                sensorOrientation = sensorOrientation
            )
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Failed to get camera capabilities for $cameraId", e)
            null
        }
    }
    
    /**
     * Get all available cameras and their capabilities
     */
    fun getAllCameraCapabilities(): List<CameraCapabilities> {
        return try {
            cameraManager.cameraIdList.mapNotNull { cameraId ->
                getCameraCapabilities(cameraId)
            }
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Failed to enumerate cameras", e)
            emptyList()
        }
    }
    
    /**
     * Enable continuous auto-focus for video
     * Best for: Video calls, moving subjects
     */
    fun enableContinuousAutoFocus(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraAutofocusEnhanced()) {
            Log.d(TAG, "Auto-focus enhancement disabled by feature flag")
            return false
        }
        
        val capabilities = getCameraCapabilities(cameraId) ?: return false
        
        if (!capabilities.supportsContinuousAutoFocus) {
            Log.w(TAG, "Camera $cameraId does not support continuous auto-focus")
            return false
        }
        
        getOrCreateSettings(cameraId).continuousAutoFocus = true
        Log.i(TAG, "Continuous auto-focus enabled for camera $cameraId")
        return true
    }
    
    /**
     * Enable auto-exposure optimization
     * Best for: Varying lighting conditions
     */
    fun enableAutoExposure(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val capabilities = getCameraCapabilities(cameraId) ?: return false
        
        if (!capabilities.supportsAutoExposure) {
            Log.w(TAG, "Camera $cameraId does not support auto-exposure")
            return false
        }
        
        getOrCreateSettings(cameraId).autoExposure = true
        Log.i(TAG, "Auto-exposure enabled for camera $cameraId")
        return true
    }
    
    /**
     * Enable video stabilization
     * Best for: Handheld video, reducing shake
     */
    fun enableVideoStabilization(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraStabilizationEnabled()) {
            Log.d(TAG, "Video stabilization disabled by feature flag")
            return false
        }
        
        val capabilities = getCameraCapabilities(cameraId) ?: return false
        
        if (!capabilities.supportsVideoStabilization) {
            Log.w(TAG, "Camera $cameraId does not support video stabilization")
            return false
        }
        
        getOrCreateSettings(cameraId).videoStabilization = true
        Log.i(TAG, "Video stabilization enabled for camera $cameraId")
        return true
    }
    
    /**
     * Enable optical image stabilization (OIS)
     * Best for: Low light, reducing motion blur
     */
    fun enableOpticalStabilization(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraStabilizationEnabled()) {
            return false
        }
        
        val capabilities = getCameraCapabilities(cameraId) ?: return false
        
        if (!capabilities.supportsOpticalStabilization) {
            Log.w(TAG, "Camera $cameraId does not support optical stabilization")
            return false
        }
        
        getOrCreateSettings(cameraId).opticalStabilization = true
        Log.i(TAG, "Optical stabilization enabled for camera $cameraId")
        return true
    }
    
    /**
     * Enable HDR mode for better dynamic range
     * Best for: High contrast scenes
     */
    fun enableHDRMode(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val capabilities = getCameraCapabilities(cameraId) ?: return false
        
        if (!capabilities.supportsHDR) {
            Log.w(TAG, "Camera $cameraId does not support HDR")
            return false
        }
        
        getOrCreateSettings(cameraId).hdrMode = true
        Log.i(TAG, "HDR mode enabled for camera $cameraId")
        return true
    }
    
    /**
     * Enable low-light optimization
     * Best for: Dark environments
     */
    fun enableLowLightMode(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraLowLightEnabled()) {
            Log.d(TAG, "Low-light mode disabled by feature flag")
            return false
        }
        
        val settings = getOrCreateSettings(cameraId)
        settings.lowLightMode = true
        settings.noiseReduction = CaptureRequest.NOISE_REDUCTION_MODE_HIGH_QUALITY
        
        Log.i(TAG, "Low-light mode enabled for camera $cameraId")
        return true
    }
    
    /**
     * Set exposure compensation
     * @param cameraId Camera ID
     * @param compensation Exposure compensation value (-2 to +2 typically)
     */
    fun setExposureCompensation(cameraId: String, compensation: Int): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val capabilities = getCameraCapabilities(cameraId) ?: return false
        val settings = getOrCreateSettings(cameraId)
        settings.exposureCompensation = compensation
        
        Log.i(TAG, "Exposure compensation set to $compensation for camera $cameraId")
        return true
    }
    
    /**
     * Set white balance mode
     * @param cameraId Camera ID
     * @param mode White balance mode (AUTO, DAYLIGHT, CLOUDY, etc.)
     */
    fun setWhiteBalanceMode(cameraId: String, mode: Int = CaptureRequest.CONTROL_AWB_MODE_AUTO): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val settings = getOrCreateSettings(cameraId)
        settings.whiteBalanceMode = mode
        
        Log.i(TAG, "White balance mode set to $mode for camera $cameraId")
        return true
    }
    
    /**
     * Enable color correction for better color accuracy
     */
    fun enableColorCorrection(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val settings = getOrCreateSettings(cameraId)
        settings.colorCorrectionMode = CaptureRequest.COLOR_CORRECTION_MODE_HIGH_QUALITY
        
        Log.i(TAG, "Color correction enabled for camera $cameraId")
        return true
    }
    
    /**
     * Enable edge enhancement for sharper images
     */
    fun enableEdgeEnhancement(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val settings = getOrCreateSettings(cameraId)
        settings.edgeEnhancement = CaptureRequest.EDGE_MODE_HIGH_QUALITY
        
        Log.i(TAG, "Edge enhancement enabled for camera $cameraId")
        return true
    }
    
    /**
     * Enable hot pixel correction for better image quality
     */
    fun enableHotPixelCorrection(cameraId: String): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val settings = getOrCreateSettings(cameraId)
        settings.hotPixelMode = CaptureRequest.HOT_PIXEL_MODE_HIGH_QUALITY
        
        Log.i(TAG, "Hot pixel correction enabled for camera $cameraId")
        return true
    }
    
    /**
     * Apply all enabled enhancements to a CaptureRequest.Builder
     * This should be called by the video capture implementation
     */
    fun applyEnhancements(builder: CaptureRequest.Builder, cameraId: String) {
        val settings = enhancementSettings[cameraId] ?: return
        
        try {
            // Auto-focus
            if (settings.continuousAutoFocus) {
                builder.set(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO
                )
            }
            
            // Auto-exposure
            if (settings.autoExposure) {
                builder.set(
                    CaptureRequest.CONTROL_AE_MODE,
                    CaptureRequest.CONTROL_AE_MODE_ON
                )
            }
            
            // Exposure compensation
            if (settings.exposureCompensation != 0) {
                builder.set(
                    CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION,
                    settings.exposureCompensation
                )
            }
            
            // White balance
            builder.set(
                CaptureRequest.CONTROL_AWB_MODE,
                settings.whiteBalanceMode
            )
            
            // Color correction
            builder.set(
                CaptureRequest.COLOR_CORRECTION_MODE,
                settings.colorCorrectionMode
            )
            
            // Edge enhancement
            builder.set(
                CaptureRequest.EDGE_MODE,
                settings.edgeEnhancement
            )
            
            // Hot pixel correction
            builder.set(
                CaptureRequest.HOT_PIXEL_MODE,
                settings.hotPixelMode
            )
            
            // Video stabilization
            if (settings.videoStabilization) {
                builder.set(
                    CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
                    CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_ON
                )
            }
            
            // Optical stabilization
            if (settings.opticalStabilization) {
                builder.set(
                    CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
                    CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_ON
                )
            }
            
            // HDR mode
            if (settings.hdrMode) {
                builder.set(
                    CaptureRequest.CONTROL_SCENE_MODE,
                    CaptureRequest.CONTROL_SCENE_MODE_HDR
                )
            }
            
            // Low-light optimizations
            if (settings.lowLightMode) {
                builder.set(
                    CaptureRequest.NOISE_REDUCTION_MODE,
                    settings.noiseReduction
                )
                builder.set(
                    CaptureRequest.TONEMAP_MODE,
                    CaptureRequest.TONEMAP_MODE_HIGH_QUALITY
                )
            }
            
            Log.d(TAG, "Applied enhancements to camera $cameraId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to apply camera enhancements", e)
        }
    }
    
    /**
     * Get current enhancement settings for a camera
     */
    fun getEnhancementSettings(cameraId: String): EnhancementSettings {
        return enhancementSettings[cameraId] ?: EnhancementSettings()
    }
    
    /**
     * Reset all enhancements for a camera
     */
    fun resetEnhancements(cameraId: String) {
        enhancementSettings.remove(cameraId)
        Log.i(TAG, "Reset enhancements for camera $cameraId")
    }
    
    /**
     * Get recommended video size based on quality setting
     */
    fun getRecommendedVideoSize(
        cameraId: String,
        preferredWidth: Int = 1280,
        preferredHeight: Int = 720
    ): Size? {
        val capabilities = getCameraCapabilities(cameraId) ?: return null
        
        // Find closest matching size
        return capabilities.supportedVideoSizes.minByOrNull { size ->
            Math.abs(size.width - preferredWidth) + Math.abs(size.height - preferredHeight)
        }
    }
    
    /**
     * Check if camera enhancements are available
     */
    fun areEnhancementsAvailable(): Boolean {
        return FeatureFlags.isCameraEnhancementsEnabled()
    }
    
    /**
     * Get diagnostic information about camera enhancements
     */
    fun getDiagnostics(cameraId: String): Map<String, Any> {
        val capabilities = getCameraCapabilities(cameraId)
        val settings = getEnhancementSettings(cameraId)
        
        return mapOf(
            "enhancementsEnabled" to FeatureFlags.isCameraEnhancementsEnabled(),
            "cameraId" to cameraId,
            "capabilities" to mapOf(
                "continuousAutoFocus" to (capabilities?.supportsContinuousAutoFocus ?: false),
                "autoExposure" to (capabilities?.supportsAutoExposure ?: false),
                "videoStabilization" to (capabilities?.supportsVideoStabilization ?: false),
                "opticalStabilization" to (capabilities?.supportsOpticalStabilization ?: false),
                "hdr" to (capabilities?.supportsHDR ?: false),
                "maxFps" to (capabilities?.maxFps ?: 0)
            ),
            "activeSettings" to mapOf(
                "continuousAutoFocus" to settings.continuousAutoFocus,
                "autoExposure" to settings.autoExposure,
                "videoStabilization" to settings.videoStabilization,
                "opticalStabilization" to settings.opticalStabilization,
                "hdrMode" to settings.hdrMode,
                "lowLightMode" to settings.lowLightMode
            )
        )
    }
    
    private fun getOrCreateSettings(cameraId: String): EnhancementSettings {
        return enhancementSettings.getOrPut(cameraId) { EnhancementSettings() }
    }
}
