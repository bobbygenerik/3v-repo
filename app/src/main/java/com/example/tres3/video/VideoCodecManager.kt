package com.example.tres3.video

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.util.Log

/**
 * Manages video codec selection and configuration for optimal video quality
 * 
 * Provides advanced codec support (H.265/HEVC, VP9, VP8) while maintaining
 * H.264 as the default fallback for maximum compatibility.
 * 
 * Features:
 * - Device codec capability detection
 * - Hardware vs software encoder selection
 * - Automatic fallback to compatible codecs
 * - Performance-optimized codec parameters
 * 
 * Usage:
 * ```
 * val availableCodecs = VideoCodecManager.getAvailableCodecs(context)
 * val codecInfo = VideoCodecManager.getCodecInfo(PreferredCodec.H265_HEVC)
 * ```
 */
object VideoCodecManager {
    private const val TAG = "VideoCodecManager"
    
    /**
     * Supported video codecs
     */
    enum class PreferredCodec(val displayName: String, val mimeType: String) {
        /**
         * H.264/AVC - Universal compatibility, hardware support on all devices
         * Best for: Maximum compatibility, older devices
         * Bitrate: ~1-2 Mbps for 720p
         */
        H264(
            displayName = "H.264 (AVC)",
            mimeType = "video/avc"
        ),
        
        /**
         * H.265/HEVC - 30-40% better compression than H.264
         * Best for: Newer devices (2017+), bandwidth-constrained networks
         * Bitrate: ~0.6-1.5 Mbps for 720p
         * Requires: Android 5.0+ with hardware encoder
         */
        H265_HEVC(
            displayName = "H.265 (HEVC)",
            mimeType = "video/hevc"
        ),
        
        /**
         * VP9 - Google's codec, optimized for WebRTC
         * Best for: WebRTC applications, similar quality to H.265
         * Bitrate: ~0.7-1.5 Mbps for 720p
         * Requires: Android 4.4+ (software), 5.0+ (hardware)
         */
        VP9(
            displayName = "VP9",
            mimeType = "video/x-vnd.on2.vp9"
        ),
        
        /**
         * VP8 - Older Google codec, good fallback
         * Best for: Compatibility with VP9, better than H.264 for some scenarios
         * Bitrate: ~1-2 Mbps for 720p
         * Requires: Android 4.3+
         */
        VP8(
            displayName = "VP8",
            mimeType = "video/x-vnd.on2.vp8"
        );
        
        companion object {
            fun fromString(value: String): PreferredCodec {
                return values().find { it.name.equals(value, ignoreCase = true) } ?: H264
            }
        }
    }
    
    /**
     * Codec capability information
     */
    data class CodecInfo(
        val codec: PreferredCodec,
        val isSupported: Boolean,
        val hasHardwareEncoder: Boolean,
        val hasSoftwareEncoder: Boolean,
        val encoderName: String?,
        val supportedResolutions: List<Resolution>,
        val recommendedBitrate: Int // kbps for 720p
    )
    
    /**
     * Video resolution
     */
    data class Resolution(val width: Int, val height: Int) {
        override fun toString() = "${width}x${height}"
    }
    
    /**
     * Get list of available codecs on this device
     * @param context Application context
     * @return List of supported codecs, ordered by preference (best first)
     */
    fun getAvailableCodecs(context: Context): List<PreferredCodec> {
        val available = mutableListOf<PreferredCodec>()
        
        // Check each codec
        PreferredCodec.values().forEach { codec ->
            if (isCodecSupported(codec)) {
                available.add(codec)
            }
        }
        
        Log.d(TAG, "Available codecs: ${available.map { it.displayName }}")
        return available
    }
    
    /**
     * Check if a specific codec is supported on this device
     * @param codec The codec to check
     * @return true if the codec has at least a software encoder
     */
    fun isCodecSupported(codec: PreferredCodec): Boolean {
        val info = getCodecInfo(codec)
        val isSupported = info.hasHardwareEncoder || info.hasSoftwareEncoder
        
        Log.d(TAG, "Codec ${codec.displayName}: supported=$isSupported, " +
                "hardware=${info.hasHardwareEncoder}, software=${info.hasSoftwareEncoder}")
        
        return isSupported
    }
    
    /**
     * Get detailed information about a codec
     * @param codec The codec to query
     * @return CodecInfo with support details
     */
    fun getCodecInfo(codec: PreferredCodec): CodecInfo {
        var hasHardware = false
        var hasSoftware = false
        var encoderName: String? = null
        val supportedResolutions = mutableListOf<Resolution>()
        
        try {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            val codecInfos = codecList.codecInfos
            
            for (info in codecInfos) {
                // Skip decoders, we only care about encoders
                if (!info.isEncoder) continue
                
                // Check if this codec supports our MIME type
                val types = info.supportedTypes
                if (!types.contains(codec.mimeType)) continue
                
                // Found an encoder for this codec
                val isHardware = isHardwareAccelerated(info)
                
                if (isHardware) {
                    hasHardware = true
                    encoderName = info.name
                    Log.d(TAG, "Found hardware encoder for ${codec.displayName}: ${info.name}")
                } else {
                    hasSoftware = true
                    if (encoderName == null) {
                        encoderName = info.name
                    }
                    Log.d(TAG, "Found software encoder for ${codec.displayName}: ${info.name}")
                }
                
                // Get supported resolutions
                try {
                    val capabilities = info.getCapabilitiesForType(codec.mimeType)
                    val videoCapabilities = capabilities.videoCapabilities
                    
                    // Add common video call resolutions that are supported
                    val commonResolutions = listOf(
                        Resolution(1920, 1080), // 1080p
                        Resolution(1280, 720),  // 720p
                        Resolution(960, 540),   // 540p
                        Resolution(640, 480),   // VGA
                        Resolution(640, 360),   // 360p
                        Resolution(320, 240)    // QVGA
                    )
                    
                    commonResolutions.forEach { res ->
                        if (videoCapabilities.isSizeSupported(res.width, res.height)) {
                            if (!supportedResolutions.contains(res)) {
                                supportedResolutions.add(res)
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Could not query capabilities for ${codec.displayName}: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking codec support for ${codec.displayName}", e)
        }
        
        // If no specific resolutions found, add safe defaults
        if (supportedResolutions.isEmpty() && (hasHardware || hasSoftware)) {
            supportedResolutions.addAll(listOf(
                Resolution(1280, 720),
                Resolution(640, 360)
            ))
        }
        
        // Recommended bitrates for 720p
        val recommendedBitrate = when (codec) {
            PreferredCodec.H264 -> 1500      // 1.5 Mbps
            PreferredCodec.H265_HEVC -> 1000 // 1.0 Mbps (better compression)
            PreferredCodec.VP9 -> 1000       // 1.0 Mbps
            PreferredCodec.VP8 -> 1500       // 1.5 Mbps
        }
        
        return CodecInfo(
            codec = codec,
            isSupported = hasHardware || hasSoftware,
            hasHardwareEncoder = hasHardware,
            hasSoftwareEncoder = hasSoftware,
            encoderName = encoderName,
            supportedResolutions = supportedResolutions,
            recommendedBitrate = recommendedBitrate
        )
    }
    
    /**
     * Determine if a codec is hardware accelerated
     */
    private fun isHardwareAccelerated(codecInfo: MediaCodecInfo): Boolean {
        // On Android 10+, we can check this directly
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return codecInfo.isHardwareAccelerated
        }
        
        // On older versions, use heuristics
        val name = codecInfo.name.lowercase()
        
        // Software codecs typically have these in their names
        val softwareKeywords = listOf("omx.google.", "c2.android.", "software")
        if (softwareKeywords.any { name.contains(it) }) {
            return false
        }
        
        // Hardware codecs typically have vendor names
        val hardwareKeywords = listOf(
            "qcom", "qualcomm",    // Qualcomm
            "mtk", "mediatek",      // MediaTek
            "exynos", "samsung",    // Samsung
            "hisi", "kirin",        // Huawei
            "nvidia", "tegra",      // Nvidia
            "intel",                // Intel
            "omx.",                 // Generic hardware
            "c2.qti", "c2.mtk"      // Codec2 hardware
        )
        
        return hardwareKeywords.any { name.contains(it) }
    }
    
    /**
     * Get the best available codec for the device
     * Preference order: H.265 (hardware) > VP9 (hardware) > H.264 (hardware) > H.264 (software)
     * 
     * @param preferQuality If true, prefer quality (H.265/VP9). If false, prefer compatibility (H.264)
     * @return The recommended codec
     */
    fun getBestCodec(preferQuality: Boolean = false): PreferredCodec {
        if (preferQuality) {
            // Try H.265 hardware first (best quality/compression)
            val h265Info = getCodecInfo(PreferredCodec.H265_HEVC)
            if (h265Info.hasHardwareEncoder) {
                Log.d(TAG, "Selected H.265 (hardware) for best quality")
                return PreferredCodec.H265_HEVC
            }
            
            // Try VP9 hardware (good quality, WebRTC optimized)
            val vp9Info = getCodecInfo(PreferredCodec.VP9)
            if (vp9Info.hasHardwareEncoder) {
                Log.d(TAG, "Selected VP9 (hardware) for good quality")
                return PreferredCodec.VP9
            }
        }
        
        // Fall back to H.264 (universal compatibility)
        Log.d(TAG, "Selected H.264 for maximum compatibility")
        return PreferredCodec.H264
    }
    
    /**
     * Load preferred codec from settings
     * @param context Application context
     * @return The user's preferred codec, or H.264 if not set
     */
    fun loadPreferredCodec(context: Context): PreferredCodec {
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val codecString = prefs.getString("preferred_codec", PreferredCodec.H264.name)
            ?: PreferredCodec.H264.name
        
        val codec = PreferredCodec.fromString(codecString)
        
        // Validate that the codec is actually supported
        if (!isCodecSupported(codec)) {
            Log.w(TAG, "Preferred codec ${codec.displayName} not supported, falling back to H.264")
            return PreferredCodec.H264
        }
        
        Log.d(TAG, "Loaded preferred codec: ${codec.displayName}")
        return codec
    }
    
    /**
     * Save preferred codec to settings
     * @param context Application context
     * @param codec The codec to save as preferred
     */
    fun savePreferredCodec(context: Context, codec: PreferredCodec) {
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        prefs.edit().putString("preferred_codec", codec.name).apply()
        Log.d(TAG, "Saved preferred codec: ${codec.displayName}")
    }
    
    /**
     * Get a human-readable description of codec capabilities for the device
     * Useful for displaying in settings or diagnostics
     */
    fun getDeviceCodecSummary(context: Context): String {
        val summary = StringBuilder()
        summary.append("Video Codec Support:\n\n")
        
        PreferredCodec.values().forEach { codec ->
            val info = getCodecInfo(codec)
            summary.append("${codec.displayName}:\n")
            
            when {
                info.hasHardwareEncoder -> {
                    summary.append("  ✓ Hardware accelerated\n")
                    summary.append("  Encoder: ${info.encoderName}\n")
                }
                info.hasSoftwareEncoder -> {
                    summary.append("  ⚠ Software only (slower)\n")
                    summary.append("  Encoder: ${info.encoderName}\n")
                }
                else -> {
                    summary.append("  ✗ Not supported\n")
                }
            }
            
            if (info.supportedResolutions.isNotEmpty()) {
                summary.append("  Resolutions: ${info.supportedResolutions.take(3).joinToString(", ")}\n")
            }
            summary.append("  Recommended bitrate: ${info.recommendedBitrate} kbps\n")
            summary.append("\n")
        }
        
        return summary.toString()
    }
}
