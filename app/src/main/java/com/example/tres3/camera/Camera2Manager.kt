package com.example.tres3.camera

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.params.StreamConfigurationMap
import android.util.Log
import android.util.Range
import android.util.Size
import com.example.tres3.FeatureFlags

/**
 * Camera2Manager - Advanced camera control using Camera2 API
 * 
 * Provides enhanced camera features:
 * - Auto-focus optimization
 * - Video stabilization
 * - Low-light enhancement
 * - Manual exposure control
 * - Frame rate optimization
 * 
 * All features are disabled by default and controlled by FeatureFlags.
 */
object Camera2Manager {
    private const val TAG = "Camera2Manager"
    
    data class CameraCapabilities(
        val cameraId: String,
        val isBackCamera: Boolean,
        val supportedResolutions: List<Size>,
        val supportedFpsRanges: List<Range<Int>>,
        val supportsAutoFocus: Boolean,
        val supportsVideoStabilization: Boolean,
        val supportsOpticalStabilization: Boolean,
        val supportsManualExposure: Boolean,
        val supportsHDR: Boolean,
        val maxDigitalZoom: Float,
        val minFocusDistance: Float,
        val exposureRange: Range<Int>?
    )
    
    data class CameraSettings(
        val autoFocusMode: Int = CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO,
        val videoStabilizationEnabled: Boolean = false,
        val opticalStabilizationEnabled: Boolean = false,
        val targetFps: Int = 30,
        val lowLightBoostEnabled: Boolean = false,
        val hdrEnabled: Boolean = false,
        val exposureCompensation: Int = 0
    )
    
    /**
     * Get camera capabilities for a specific camera
     */
    fun getCameraCapabilities(context: Context, cameraId: String): CameraCapabilities? {
        return try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            
            val isBackCamera = characteristics.get(CameraCharacteristics.LENS_FACING) == 
                CameraCharacteristics.LENS_FACING_BACK
            
            val configMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val supportedResolutions = configMap?.getOutputSizes(android.graphics.ImageFormat.YUV_420_888)?.toList() ?: emptyList()
            
            val fpsRanges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.toList() ?: emptyList()
            
            val afModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES) ?: intArrayOf()
            val supportsAutoFocus = afModes.contains(CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
            
            val videoStabModes = characteristics.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES) ?: intArrayOf()
            val supportsVideoStab = videoStabModes.contains(CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON)
            
            val opticalStabModes = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION) ?: intArrayOf()
            val supportsOpticalStab = opticalStabModes.contains(CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON)
            
            val aeMode = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_MODES) ?: intArrayOf()
            val supportsManualExposure = aeMode.contains(CameraMetadata.CONTROL_AE_MODE_OFF)
            
            val sceneModes = characteristics.get(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES) ?: intArrayOf()
            val supportsHDR = sceneModes.contains(CameraMetadata.CONTROL_SCENE_MODE_HDR)
            
            val maxZoom = characteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
            val minFocusDist = characteristics.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
            val exposureRange = characteristics.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
            
            CameraCapabilities(
                cameraId = cameraId,
                isBackCamera = isBackCamera,
                supportedResolutions = supportedResolutions,
                supportedFpsRanges = fpsRanges,
                supportsAutoFocus = supportsAutoFocus,
                supportsVideoStabilization = supportsVideoStab,
                supportsOpticalStabilization = supportsOpticalStab,
                supportsManualExposure = supportsManualExposure,
                supportsHDR = supportsHDR,
                maxDigitalZoom = maxZoom,
                minFocusDistance = minFocusDist,
                exposureRange = exposureRange
            )
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Failed to get camera capabilities", e)
            null
        }
    }
    
    /**
     * Get capabilities for all available cameras
     */
    fun getAllCameraCapabilities(context: Context): Map<String, CameraCapabilities> {
        val capabilities = mutableMapOf<String, CameraCapabilities>()
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIds = cameraManager.cameraIdList
            
            for (cameraId in cameraIds) {
                getCameraCapabilities(context, cameraId)?.let {
                    capabilities[cameraId] = it
                }
            }
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Failed to enumerate cameras", e)
        }
        return capabilities
    }
    
    /**
     * Get optimal camera settings based on device capabilities and feature flags
     */
    fun getOptimalSettings(context: Context, cameraId: String): CameraSettings {
        val capabilities = getCameraCapabilities(context, cameraId) ?: return CameraSettings()
        
        return CameraSettings(
            autoFocusMode = if (capabilities.supportsAutoFocus && FeatureFlags.isCameraAutofocusEnhanced()) {
                CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO
            } else {
                CameraMetadata.CONTROL_AF_MODE_AUTO
            },
            videoStabilizationEnabled = capabilities.supportsVideoStabilization && 
                FeatureFlags.isCameraStabilizationEnabled(),
            opticalStabilizationEnabled = capabilities.supportsOpticalStabilization && 
                FeatureFlags.isCameraStabilizationEnabled(),
            targetFps = 30,
            lowLightBoostEnabled = FeatureFlags.isCameraLowLightEnabled(),
            hdrEnabled = capabilities.supportsHDR && FeatureFlags.isCameraLowLightEnabled(),
            exposureCompensation = 0
        )
    }
    
    /**
     * Get recommended resolution for video calling based on network conditions
     */
    fun getRecommendedResolution(
        capabilities: CameraCapabilities,
        networkQuality: NetworkQuality = NetworkQuality.GOOD
    ): Size {
        val resolutions = capabilities.supportedResolutions.sortedByDescending { it.width * it.height }
        
        return when (networkQuality) {
            NetworkQuality.EXCELLENT -> {
                // 1080p or best available
                resolutions.firstOrNull { it.width >= 1920 } ?: resolutions.firstOrNull()
            }
            NetworkQuality.GOOD -> {
                // 720p
                resolutions.firstOrNull { it.width >= 1280 && it.width < 1920 }
            }
            NetworkQuality.FAIR -> {
                // 480p
                resolutions.firstOrNull { it.width >= 640 && it.width < 1280 }
            }
            NetworkQuality.POOR -> {
                // 360p or lower
                resolutions.lastOrNull { it.width >= 480 }
            }
        } ?: Size(640, 480) // Fallback
    }
    
    /**
     * Check if camera enhancements are available and enabled
     */
    fun areCameraEnhancementsAvailable(context: Context): Boolean {
        if (!FeatureFlags.isCameraEnhancementsEnabled()) {
            return false
        }
        
        val capabilities = getAllCameraCapabilities(context)
        return capabilities.values.any { 
            it.supportsAutoFocus || 
            it.supportsVideoStabilization || 
            it.supportsOpticalStabilization 
        }
    }
    
    /**
     * Get camera enhancement status for diagnostics
     */
    fun getCameraEnhancementStatus(context: Context): Map<String, Any> {
        val allCapabilities = getAllCameraCapabilities(context)
        val backCamera = allCapabilities.values.firstOrNull { it.isBackCamera }
        
        return mapOf(
            "enhancementsEnabled" to FeatureFlags.isCameraEnhancementsEnabled(),
            "autofocusEnhanced" to FeatureFlags.isCameraAutofocusEnhanced(),
            "stabilizationEnabled" to FeatureFlags.isCameraStabilizationEnabled(),
            "lowLightEnabled" to FeatureFlags.isCameraLowLightEnabled(),
            "camerasAvailable" to allCapabilities.size,
            "backCameraSupportsStabilization" to (backCamera?.supportsVideoStabilization ?: false),
            "backCameraSupportsOpticalStabilization" to (backCamera?.supportsOpticalStabilization ?: false),
            "backCameraSupportsHDR" to (backCamera?.supportsHDR ?: false)
        )
    }
    
    enum class NetworkQuality {
        EXCELLENT,
        GOOD,
        FAIR,
        POOR
    }
}
