package com.example.tres3

import android.content.Context
import android.content.SharedPreferences

/**
 * Centralized feature flag management system
 * 
 * Allows gradual rollout of new features and A/B testing
 * All enhancements are disabled by default to ensure backward compatibility
 * 
 * Usage:
 * ```
 * FeatureFlags.init(context)
 * if (FeatureFlags.isAdvancedCodecsEnabled()) {
 *     // Use advanced codec features
 * }
 * ```
 */
object FeatureFlags {
    private lateinit var prefs: SharedPreferences
    
    /**
     * Initialize feature flags system
     * Should be called in Application.onCreate()
     */
    fun init(context: Context) {
        prefs = context.getSharedPreferences("feature_flags", Context.MODE_PRIVATE)
    }
    
    // ========================================
    // Codec Enhancement Features
    // ========================================
    
    /**
     * Enable advanced video codecs (H.265/HEVC, VP9, VP8)
     * Default: false (uses H.264 only)
     */
    fun isAdvancedCodecsEnabled(): Boolean = 
        prefs.getBoolean("enable_advanced_codecs", false)
    
    fun setAdvancedCodecsEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("enable_advanced_codecs", enabled).apply()
    }
    
    // ========================================
    // Camera Enhancement Features
    // ========================================
    
    /**
     * Enable Camera2 API enhancements
     * Includes auto-focus, exposure optimization, and stabilization
     * Default: false
     */
    fun isCameraEnhancementsEnabled(): Boolean = 
        prefs.getBoolean("enable_camera_enhancements", false)
    
    fun setCameraEnhancementsEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("enable_camera_enhancements", enabled).apply()
    }
    
    /**
     * Enable auto-focus enhancement
     * Requires isCameraEnhancementsEnabled() to be true
     */
    fun isAutoFocusEnhancementEnabled(): Boolean =
        isCameraEnhancementsEnabled() && prefs.getBoolean("camera_autofocus_enhanced", true)
    
    /**
     * Enable video stabilization
     * Requires isCameraEnhancementsEnabled() to be true
     */
    fun isVideoStabilizationEnabled(): Boolean =
        isCameraEnhancementsEnabled() && prefs.getBoolean("camera_stabilization", true)
    
    /**
     * Enable low-light mode
     * Requires isCameraEnhancementsEnabled() to be true
     */
    fun isLowLightModeEnabled(): Boolean =
        isCameraEnhancementsEnabled() && prefs.getBoolean("camera_lowlight", false)
    
    // ========================================
    // ML Kit Features
    // ========================================
    
    /**
     * Enable Google ML Kit features
     * Master switch for all ML-powered enhancements
     * Default: false
     */
    fun isMLKitEnabled(): Boolean = 
        prefs.getBoolean("enable_ml_features", false)
    
    fun setMLKitEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("enable_ml_features", enabled).apply()
    }
    
    /**
     * Enable background blur during video calls
     * Requires isMLKitEnabled() to be true
     */
    fun isBackgroundBlurEnabled(): Boolean = 
        isMLKitEnabled() && prefs.getBoolean("ml_background_blur", false)
    
    fun setBackgroundBlurEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("ml_background_blur", enabled).apply()
    }
    
    /**
     * Get background blur intensity (0-100)
     * Default: 70
     */
    fun getBackgroundBlurIntensity(): Int =
        prefs.getInt("ml_blur_intensity", 70)
    
    fun setBackgroundBlurIntensity(intensity: Int) {
        prefs.edit().putInt("ml_blur_intensity", intensity.coerceIn(0, 100)).apply()
    }
    
    /**
     * Enable virtual background feature
     * Requires isMLKitEnabled() to be true
     */
    fun isVirtualBackgroundEnabled(): Boolean =
        isMLKitEnabled() && prefs.getBoolean("ml_virtual_background", false)
    
    /**
     * Enable face detection and enhancement
     * Auto-adjusts focus and exposure for detected faces
     * Requires isMLKitEnabled() to be true
     */
    fun isFaceEnhancementEnabled(): Boolean =
        isMLKitEnabled() && prefs.getBoolean("ml_face_enhancement", false)
    
    // ========================================
    // Developer & Debug Features
    // ========================================
    
    /**
     * Enable developer mode
     * Shows additional debugging information and experimental features
     * Default: false
     */
    fun isDeveloperModeEnabled(): Boolean = 
        prefs.getBoolean("developer_mode", false)
    
    fun setDeveloperModeEnabled(enabled: Boolean) {
        prefs.edit().putBoolean("developer_mode", enabled).apply()
    }
    
    /**
     * Enable performance metrics overlay
     * Shows FPS, bitrate, codec info during calls
     * Requires isDeveloperModeEnabled() to be true
     */
    fun isPerformanceOverlayEnabled(): Boolean =
        isDeveloperModeEnabled() && prefs.getBoolean("show_performance_overlay", false)
    
    /**
     * Enable verbose logging for debugging
     * Requires isDeveloperModeEnabled() to be true
     */
    fun isVerboseLoggingEnabled(): Boolean =
        isDeveloperModeEnabled() && prefs.getBoolean("verbose_logging", false)
    
    // ========================================
    // Utility Methods
    // ========================================
    
    /**
     * Reset all feature flags to default values
     * Useful for troubleshooting
     */
    fun resetToDefaults() {
        prefs.edit().clear().apply()
    }
    
    /**
     * Get all feature flags as a map for debugging
     */
    fun getAllFlags(): Map<String, Boolean> {
        return mapOf(
            "advanced_codecs" to isAdvancedCodecsEnabled(),
            "camera_enhancements" to isCameraEnhancementsEnabled(),
            "autofocus_enhanced" to isAutoFocusEnhancementEnabled(),
            "video_stabilization" to isVideoStabilizationEnabled(),
            "low_light_mode" to isLowLightModeEnabled(),
            "ml_kit" to isMLKitEnabled(),
            "background_blur" to isBackgroundBlurEnabled(),
            "virtual_background" to isVirtualBackgroundEnabled(),
            "face_enhancement" to isFaceEnhancementEnabled(),
            "developer_mode" to isDeveloperModeEnabled(),
            "performance_overlay" to isPerformanceOverlayEnabled(),
            "verbose_logging" to isVerboseLoggingEnabled()
        )
    }
}
