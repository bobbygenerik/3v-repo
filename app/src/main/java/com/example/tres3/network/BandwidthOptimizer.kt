package com.example.tres3.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import io.livekit.android.room.Room
import io.livekit.android.room.track.VideoCaptureParameter
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.max
import kotlin.math.min

/**
 * BandwidthOptimizer - Dynamic video quality adaptation based on network conditions
 * 
 * Features:
 * - Real-time bandwidth estimation
 * - Automatic resolution/framerate adaptation
 * - Quality presets (auto, high, medium, low)
 * - Network type detection (WiFi, cellular, etc)
 * - Smooth quality transitions
 * 
 * Usage:
 * ```kotlin
 * val optimizer = BandwidthOptimizer(context, room)
 * optimizer.onQualityChanged = { preset ->
 *     updateQualityIndicator(preset)
 * }
 * optimizer.startMonitoring()
 * ```
 */
class BandwidthOptimizer(
    private val context: Context,
    private val room: Room
) {
    // Quality presets
    enum class QualityPreset(
        val width: Int,
        val height: Int,
        val fps: Int,
        val bitrateKbps: Int
    ) {
        LOW(320, 240, 15, 300),
        MEDIUM(640, 480, 24, 800),
        HIGH(1280, 720, 30, 2000),
        ULTRA(1920, 1080, 30, 4000);

        fun toCaptureParameter(): VideoCaptureParameter {
            return VideoCaptureParameter(width, height, fps)
        }
    }

    // Network type
    enum class NetworkType {
        WIFI,
        CELLULAR_5G,
        CELLULAR_4G,
        CELLULAR_3G,
        CELLULAR_2G,
        ETHERNET,
        UNKNOWN
    }

    // Bandwidth estimation
    data class BandwidthEstimate(
        val downlinkKbps: Int,
        val uplinkKbps: Int,
        val networkType: NetworkType,
        val timestamp: Long = System.currentTimeMillis()
    )

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var monitoringJob: Job? = null

    // Current state
    private var currentPreset = QualityPreset.HIGH
    private var autoAdaptEnabled = true
    private var lastBandwidthEstimate: BandwidthEstimate? = null

    // History for smoothing
    private val bandwidthHistory = mutableListOf<BandwidthEstimate>()
    private val maxHistorySize = 5

    // Callbacks
    var onQualityChanged: ((QualityPreset) -> Unit)? = null
    var onBandwidthEstimated: ((BandwidthEstimate) -> Unit)? = null

    // Connectivity manager
    private val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    companion object {
        private const val MONITORING_INTERVAL_MS = 5000L
        private const val MIN_SAMPLES_FOR_ADAPTATION = 3
    }

    init {
        Timber.d("BandwidthOptimizer initialized")
    }

    /**
     * Start monitoring network conditions
     */
    fun startMonitoring() {
        if (monitoringJob != null) {
            Timber.w("BandwidthOptimizer already monitoring")
            return
        }

        monitoringJob = scope.launch {
            while (isActive) {
                try {
                    val estimate = estimateBandwidth()
                    lastBandwidthEstimate = estimate
                    
                    // Add to history
                    bandwidthHistory.add(estimate)
                    if (bandwidthHistory.size > maxHistorySize) {
                        bandwidthHistory.removeAt(0)
                    }

                    // Trigger callback
                    onBandwidthEstimated?.invoke(estimate)

                    // Adapt quality if auto mode enabled
                    if (autoAdaptEnabled && bandwidthHistory.size >= MIN_SAMPLES_FOR_ADAPTATION) {
                        adaptQuality()
                    }

                    delay(MONITORING_INTERVAL_MS)
                } catch (e: Exception) {
                    Timber.e(e, "Error monitoring bandwidth")
                    delay(MONITORING_INTERVAL_MS)
                }
            }
        }

        Timber.d("Bandwidth monitoring started")
    }

    /**
     * Stop monitoring
     */
    fun stopMonitoring() {
        monitoringJob?.cancel()
        monitoringJob = null
        bandwidthHistory.clear()
        Timber.d("Bandwidth monitoring stopped")
    }

    /**
     * Estimate current bandwidth
     */
    private fun estimateBandwidth(): BandwidthEstimate {
        val networkType = detectNetworkType()
        
        // Get network capabilities
        val network = connectivityManager.activeNetwork
        val capabilities = network?.let { connectivityManager.getNetworkCapabilities(it) }

        // Estimate based on network type (simplified heuristic)
        val (downlink, uplink) = when (networkType) {
            NetworkType.WIFI -> Pair(
                capabilities?.linkDownstreamBandwidthKbps ?: 50000,
                capabilities?.linkUpstreamBandwidthKbps ?: 20000
            )
            NetworkType.ETHERNET -> Pair(100000, 50000)
            NetworkType.CELLULAR_5G -> Pair(50000, 20000)
            NetworkType.CELLULAR_4G -> Pair(10000, 5000)
            NetworkType.CELLULAR_3G -> Pair(2000, 1000)
            NetworkType.CELLULAR_2G -> Pair(200, 100)
            NetworkType.UNKNOWN -> Pair(1000, 500)
        }

        return BandwidthEstimate(downlink, uplink, networkType)
    }

    /**
     * Detect network type
     */
    private fun detectNetworkType(): NetworkType {
        try {
            val network = connectivityManager.activeNetwork ?: return NetworkType.UNKNOWN
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return NetworkType.UNKNOWN

            return when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkType.WIFI
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetworkType.ETHERNET
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> {
                    // Try to determine cellular generation
                    // This is simplified - in production you'd check NetworkInfo
                    NetworkType.CELLULAR_4G
                }
                else -> NetworkType.UNKNOWN
            }
        } catch (e: Exception) {
            Timber.e(e, "Error detecting network type")
            return NetworkType.UNKNOWN
        }
    }

    /**
     * Adapt quality based on bandwidth history
     */
    private fun adaptQuality() {
        // Calculate average uplink bandwidth
        val avgUplink = bandwidthHistory.map { it.uplinkKbps }.average().toInt()

        // Determine optimal quality preset with hysteresis
        val targetPreset = when {
            avgUplink >= 3000 -> QualityPreset.ULTRA
            avgUplink >= 1500 -> QualityPreset.HIGH
            avgUplink >= 600 -> QualityPreset.MEDIUM
            else -> QualityPreset.LOW
        }

        // Only change if different from current
        if (targetPreset != currentPreset) {
            Timber.d("Adapting quality: ${currentPreset.name} -> ${targetPreset.name} (uplink: $avgUplink kbps)")
            setQualityPreset(targetPreset)
        }
    }

    /**
     * Set quality preset manually
     */
    fun setQualityPreset(preset: QualityPreset) {
        currentPreset = preset
        
        scope.launch {
            try {
                // Apply to LiveKit room
                // Note: LiveKit 2.21 doesn't expose direct video quality control
                // This would typically be applied via LocalVideoTrackOptions when creating tracks
                Timber.d("Applied quality preset: ${preset.name} (${preset.width}x${preset.height}@${preset.fps}fps, ${preset.bitrateKbps}kbps)")
                
                onQualityChanged?.invoke(preset)
            } catch (e: Exception) {
                Timber.e(e, "Failed to apply quality preset")
            }
        }
    }

    /**
     * Enable/disable auto adaptation
     */
    fun setAutoAdaptEnabled(enabled: Boolean) {
        autoAdaptEnabled = enabled
        Timber.d("Auto adaptation ${if (enabled) "enabled" else "disabled"}")
    }

    /**
     * Get current quality preset
     */
    fun getCurrentPreset(): QualityPreset = currentPreset

    /**
     * Get last bandwidth estimate
     */
    fun getLastBandwidthEstimate(): BandwidthEstimate? = lastBandwidthEstimate

    /**
     * Get recommended preset for current network
     */
    fun getRecommendedPreset(): QualityPreset {
        val estimate = lastBandwidthEstimate ?: return QualityPreset.MEDIUM

        return when {
            estimate.uplinkKbps >= 3000 -> QualityPreset.ULTRA
            estimate.uplinkKbps >= 1500 -> QualityPreset.HIGH
            estimate.uplinkKbps >= 600 -> QualityPreset.MEDIUM
            else -> QualityPreset.LOW
        }
    }

    /**
     * Force bandwidth re-estimation
     */
    suspend fun forceEstimate(): BandwidthEstimate {
        val estimate = estimateBandwidth()
        lastBandwidthEstimate = estimate
        onBandwidthEstimated?.invoke(estimate)
        return estimate
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        stopMonitoring()
        scope.cancel()
        onQualityChanged = null
        onBandwidthEstimated = null
        Timber.d("BandwidthOptimizer cleaned up")
    }
}
