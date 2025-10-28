package com.example.tres3.performance

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.os.Debug
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import timber.log.Timber
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap

/**
 * Memory profiling and optimization tool for video call features.
 * Monitors memory usage, detects leaks, and provides optimization recommendations.
 */
class MemoryProfiler(private val context: Context) {
    
    private val scope = CoroutineScope(Dispatchers.Default + Job())
    private val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    
    // Memory tracking
    private val _memoryStats = MutableStateFlow(MemoryStats())
    val memoryStats: StateFlow<MemoryStats> = _memoryStats
    
    private val _alerts = MutableStateFlow<List<MemoryAlert>>(emptyList())
    val alerts: StateFlow<List<MemoryAlert>> = _alerts
    
    // Bitmap tracking for leak detection
    private val trackedBitmaps = ConcurrentHashMap<String, WeakReference<Bitmap>>()
    private val bitmapAllocationSizes = ConcurrentHashMap<String, Long>()
    
    // Object tracking for leak detection
    private val trackedObjects = ConcurrentHashMap<String, WeakReference<Any>>()
    
    private var monitoringJob: Job? = null
    private var isMonitoring = false
    
    data class MemoryStats(
        val usedMemoryMB: Double = 0.0,
        val availableMemoryMB: Double = 0.0,
        val totalMemoryMB: Double = 0.0,
        val memoryPercentage: Float = 0f,
        val nativeHeapAllocatedMB: Double = 0.0,
        val nativeHeapSizeMB: Double = 0.0,
        val trackedBitmapsCount: Int = 0,
        val trackedBitmapsSizeMB: Double = 0.0,
        val gcCount: Int = 0,
        val timestamp: Long = System.currentTimeMillis()
    )
    
    data class MemoryAlert(
        val severity: Severity,
        val message: String,
        val recommendation: String,
        val timestamp: Long = System.currentTimeMillis()
    ) {
        enum class Severity { INFO, WARNING, CRITICAL }
    }
    
    /**
     * Start continuous memory monitoring.
     */
    fun startMonitoring(intervalMs: Long = 2000) {
        if (isMonitoring) return
        
        isMonitoring = true
        monitoringJob = scope.launch {
            var previousGcCount = getGcCount()
            
            while (isActive) {
                val stats = collectMemoryStats()
                _memoryStats.value = stats
                
                // Check for memory alerts
                checkMemoryAlerts(stats, previousGcCount)
                
                // Update GC count
                val currentGcCount = getGcCount()
                previousGcCount = currentGcCount
                
                // Clean up dead references
                cleanupDeadReferences()
                
                delay(intervalMs)
            }
        }
        
        Timber.d("MemoryProfiler: Started monitoring (interval: ${intervalMs}ms)")
    }
    
    /**
     * Stop memory monitoring.
     */
    fun stopMonitoring() {
        isMonitoring = false
        monitoringJob?.cancel()
        monitoringJob = null
        Timber.d("MemoryProfiler: Stopped monitoring")
    }
    
    /**
     * Track a Bitmap to monitor its lifecycle and detect leaks.
     */
    fun trackBitmap(name: String, bitmap: Bitmap) {
        val size = bitmap.byteCount.toLong()
        trackedBitmaps[name] = WeakReference(bitmap)
        bitmapAllocationSizes[name] = size
        Timber.d("MemoryProfiler: Tracking bitmap '$name' (${size / 1024 / 1024}MB)")
    }
    
    /**
     * Untrack a Bitmap when it's explicitly released.
     */
    fun untrackBitmap(name: String) {
        trackedBitmaps.remove(name)
        bitmapAllocationSizes.remove(name)
        Timber.d("MemoryProfiler: Untracked bitmap '$name'")
    }
    
    /**
     * Track any object for leak detection.
     */
    fun trackObject(name: String, obj: Any) {
        trackedObjects[name] = WeakReference(obj)
        Timber.d("MemoryProfiler: Tracking object '$name' (${obj::class.simpleName})")
    }
    
    /**
     * Get list of potentially leaked bitmaps (still tracked but GC'd).
     */
    fun getLeakedBitmaps(): List<String> {
        return trackedBitmaps.entries
            .filter { it.value.get() == null }
            .map { it.key }
    }
    
    /**
     * Get list of potentially leaked objects.
     */
    fun getLeakedObjects(): List<String> {
        return trackedObjects.entries
            .filter { it.value.get() == null }
            .map { it.key }
    }
    
    /**
     * Force garbage collection and measure impact.
     */
    fun forceGcAndMeasure(): MemoryImpact {
        val before = collectMemoryStats()
        
        System.gc()
        System.runFinalization()
        Thread.sleep(100) // Give GC time to complete
        
        val after = collectMemoryStats()
        
        return MemoryImpact(
            beforeMB = before.usedMemoryMB,
            afterMB = after.usedMemoryMB,
            freedMB = before.usedMemoryMB - after.usedMemoryMB
        )
    }
    
    data class MemoryImpact(
        val beforeMB: Double,
        val afterMB: Double,
        val freedMB: Double
    )
    
    /**
     * Get detailed memory report.
     */
    fun generateReport(): String = buildString {
        val stats = _memoryStats.value
        
        appendLine("=== Memory Profile Report ===")
        appendLine("Timestamp: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(stats.timestamp)}")
        appendLine()
        
        appendLine("Memory Usage:")
        appendLine("  Used: ${"%.2f".format(stats.usedMemoryMB)} MB (${stats.memoryPercentage.toInt()}%)")
        appendLine("  Available: ${"%.2f".format(stats.availableMemoryMB)} MB")
        appendLine("  Total: ${"%.2f".format(stats.totalMemoryMB)} MB")
        appendLine()
        
        appendLine("Native Heap:")
        appendLine("  Allocated: ${"%.2f".format(stats.nativeHeapAllocatedMB)} MB")
        appendLine("  Size: ${"%.2f".format(stats.nativeHeapSizeMB)} MB")
        appendLine()
        
        appendLine("Tracked Bitmaps:")
        appendLine("  Count: ${stats.trackedBitmapsCount}")
        appendLine("  Size: ${"%.2f".format(stats.trackedBitmapsSizeMB)} MB")
        appendLine()
        
        val leakedBitmaps = getLeakedBitmaps()
        if (leakedBitmaps.isNotEmpty()) {
            appendLine("Potential Bitmap Leaks:")
            leakedBitmaps.forEach { appendLine("  - $it") }
            appendLine()
        }
        
        val leakedObjects = getLeakedObjects()
        if (leakedObjects.isNotEmpty()) {
            appendLine("Potential Object Leaks:")
            leakedObjects.forEach { appendLine("  - $it") }
            appendLine()
        }
        
        val currentAlerts = _alerts.value
        if (currentAlerts.isNotEmpty()) {
            appendLine("Active Alerts:")
            currentAlerts.forEach { alert ->
                appendLine("  [${alert.severity}] ${alert.message}")
                appendLine("    Recommendation: ${alert.recommendation}")
            }
            appendLine()
        }
        
        appendLine("Recommendations:")
        val recommendations = generateRecommendations(stats)
        recommendations.forEach { appendLine("  - $it") }
    }
    
    /**
     * Collect current memory statistics.
     */
    private fun collectMemoryStats(): MemoryStats {
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        
        val runtime = Runtime.getRuntime()
        val usedMemory = (runtime.totalMemory() - runtime.freeMemory()) / 1024.0 / 1024.0
        val maxMemory = runtime.maxMemory() / 1024.0 / 1024.0
        val availableMemory = maxMemory - usedMemory
        
        val nativeHeapAllocated = Debug.getNativeHeapAllocatedSize() / 1024.0 / 1024.0
        val nativeHeapSize = Debug.getNativeHeapSize() / 1024.0 / 1024.0
        
        // Calculate tracked bitmaps size
        val aliveBitmaps = trackedBitmaps.values.mapNotNull { it.get() }
        val bitmapsSize = aliveBitmaps.sumOf { it.byteCount.toLong() } / 1024.0 / 1024.0
        
        return MemoryStats(
            usedMemoryMB = usedMemory,
            availableMemoryMB = availableMemory,
            totalMemoryMB = maxMemory,
            memoryPercentage = ((usedMemory / maxMemory) * 100).toFloat(),
            nativeHeapAllocatedMB = nativeHeapAllocated,
            nativeHeapSizeMB = nativeHeapSize,
            trackedBitmapsCount = aliveBitmaps.size,
            trackedBitmapsSizeMB = bitmapsSize,
            gcCount = getGcCount()
        )
    }
    
    /**
     * Check for memory-related issues and generate alerts.
     */
    private fun checkMemoryAlerts(stats: MemoryStats, previousGcCount: Int) {
        val newAlerts = mutableListOf<MemoryAlert>()
        
        // High memory usage
        if (stats.memoryPercentage > 90) {
            newAlerts.add(MemoryAlert(
                severity = MemoryAlert.Severity.CRITICAL,
                message = "Critical memory usage: ${stats.memoryPercentage.toInt()}%",
                recommendation = "Reduce video quality, clear caches, or recycle unused bitmaps"
            ))
        } else if (stats.memoryPercentage > 75) {
            newAlerts.add(MemoryAlert(
                severity = MemoryAlert.Severity.WARNING,
                message = "High memory usage: ${stats.memoryPercentage.toInt()}%",
                recommendation = "Consider reducing video quality or number of active streams"
            ))
        }
        
        // Large native heap
        if (stats.nativeHeapAllocatedMB > 200) {
            newAlerts.add(MemoryAlert(
                severity = MemoryAlert.Severity.WARNING,
                message = "Large native heap: ${"%.2f".format(stats.nativeHeapAllocatedMB)} MB",
                recommendation = "Check for native memory leaks in video/audio processing"
            ))
        }
        
        // Many tracked bitmaps
        if (stats.trackedBitmapsCount > 20) {
            newAlerts.add(MemoryAlert(
                severity = MemoryAlert.Severity.WARNING,
                message = "Many tracked bitmaps: ${stats.trackedBitmapsCount}",
                recommendation = "Implement bitmap pooling or recycle unused bitmaps"
            ))
        }
        
        // Large bitmap memory
        if (stats.trackedBitmapsSizeMB > 50) {
            newAlerts.add(MemoryAlert(
                severity = MemoryAlert.Severity.WARNING,
                message = "Large bitmap memory: ${"%.2f".format(stats.trackedBitmapsSizeMB)} MB",
                recommendation = "Use lower resolution bitmaps or implement caching strategy"
            ))
        }
        
        // Frequent GC
        val gcDelta = stats.gcCount - previousGcCount
        if (gcDelta > 5) {
            newAlerts.add(MemoryAlert(
                severity = MemoryAlert.Severity.INFO,
                message = "Frequent garbage collection detected ($gcDelta GCs)",
                recommendation = "Reduce object allocations in hot paths"
            ))
        }
        
        // Potential leaks
        val leakedBitmaps = getLeakedBitmaps()
        if (leakedBitmaps.size > 5) {
            newAlerts.add(MemoryAlert(
                severity = MemoryAlert.Severity.WARNING,
                message = "Potential bitmap leaks detected: ${leakedBitmaps.size}",
                recommendation = "Review bitmap lifecycle management"
            ))
        }
        
        _alerts.value = newAlerts
    }
    
    /**
     * Get current GC count (approximation).
     */
    private fun getGcCount(): Int {
        // Note: Android doesn't provide direct GC count API
        // This is an approximation based on debug info
        return 0 // Placeholder - would need native implementation
    }
    
    /**
     * Clean up dead weak references.
     */
    private fun cleanupDeadReferences() {
        trackedBitmaps.entries.removeIf { it.value.get() == null }
        trackedObjects.entries.removeIf { it.value.get() == null }
    }
    
    /**
     * Generate optimization recommendations based on current stats.
     */
    private fun generateRecommendations(stats: MemoryStats): List<String> {
        val recommendations = mutableListOf<String>()
        
        if (stats.trackedBitmapsCount > 10) {
            recommendations.add("Implement bitmap pooling to reuse bitmap memory")
        }
        
        if (stats.memoryPercentage > 70) {
            recommendations.add("Enable aggressive caching policies")
            recommendations.add("Consider downscaling video resolutions")
        }
        
        if (stats.nativeHeapAllocatedMB > 100) {
            recommendations.add("Review native library usage for memory leaks")
        }
        
        val leakedBitmaps = getLeakedBitmaps()
        if (leakedBitmaps.isNotEmpty()) {
            recommendations.add("Fix bitmap leaks: ${leakedBitmaps.joinToString()}")
        }
        
        return recommendations
    }
    
    /**
     * Clean up profiler resources.
     */
    fun cleanup() {
        stopMonitoring()
        trackedBitmaps.clear()
        bitmapAllocationSizes.clear()
        trackedObjects.clear()
        Timber.d("MemoryProfiler: Cleaned up")
    }
}
