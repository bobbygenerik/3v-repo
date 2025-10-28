package com.example.tres3.performance

import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import timber.log.Timber
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * Performance monitoring for CPU usage, frame rates, and hot path detection.
 * Helps identify performance bottlenecks in video/audio processing.
 */
class PerformanceMonitor {
    
    private val scope = CoroutineScope(Dispatchers.Default + Job())
    
    // Performance metrics
    private val _performanceStats = MutableStateFlow(PerformanceStats())
    val performanceStats: StateFlow<PerformanceStats> = _performanceStats
    
    // Method timing tracking
    private val methodTimings = ConcurrentHashMap<String, MethodTiming>()
    private val activeTimers = ConcurrentHashMap<String, Long>()
    
    // Frame rate tracking
    private val frameTimestamps = mutableListOf<Long>()
    private val maxFrameHistory = 120 // 2 seconds at 60fps
    
    private var monitoringJob: Job? = null
    private var isMonitoring = false
    
    data class PerformanceStats(
        val currentFps: Float = 0f,
        val averageFps: Float = 0f,
        val frameDrops: Int = 0,
        val cpuUsagePercent: Float = 0f,
        val hotMethods: List<MethodStats> = emptyList(),
        val timestamp: Long = System.currentTimeMillis()
    )
    
    data class MethodStats(
        val name: String,
        val callCount: Long,
        val totalTimeMs: Long,
        val averageTimeMs: Float,
        val maxTimeMs: Long,
        val minTimeMs: Long
    )
    
    private data class MethodTiming(
        val callCount: AtomicLong = AtomicLong(0),
        val totalTimeMs: AtomicLong = AtomicLong(0),
        val maxTimeMs: AtomicLong = AtomicLong(0),
        val minTimeMs: AtomicLong = AtomicLong(Long.MAX_VALUE)
    )
    
    /**
     * Start performance monitoring.
     */
    fun startMonitoring(intervalMs: Long = 1000) {
        if (isMonitoring) return
        
        isMonitoring = true
        monitoringJob = scope.launch {
            while (isActive) {
                val stats = collectPerformanceStats()
                _performanceStats.value = stats
                delay(intervalMs)
            }
        }
        
        Timber.d("PerformanceMonitor: Started monitoring (interval: ${intervalMs}ms)")
    }
    
    /**
     * Stop performance monitoring.
     */
    fun stopMonitoring() {
        isMonitoring = false
        monitoringJob?.cancel()
        monitoringJob = null
        Timber.d("PerformanceMonitor: Stopped monitoring")
    }
    
    /**
     * Start timing a method execution.
     */
    fun startTimer(methodName: String): String {
        val timerId = "$methodName-${System.nanoTime()}"
        activeTimers[timerId] = SystemClock.elapsedRealtimeNanos()
        return timerId
    }
    
    /**
     * End timing a method execution.
     */
    fun endTimer(timerId: String) {
        val startTime = activeTimers.remove(timerId) ?: return
        val endTime = SystemClock.elapsedRealtimeNanos()
        val durationMs = (endTime - startTime) / 1_000_000
        
        val methodName = timerId.substringBeforeLast("-")
        recordMethodTiming(methodName, durationMs)
    }
    
    /**
     * Measure execution time of a block.
     */
    inline fun <T> measureTime(methodName: String, block: () -> T): T {
        val timerId = startTimer(methodName)
        try {
            return block()
        } finally {
            endTimer(timerId)
        }
    }
    
    /**
     * Record a frame timestamp for FPS calculation.
     */
    fun recordFrame() {
        synchronized(frameTimestamps) {
            val now = System.currentTimeMillis()
            frameTimestamps.add(now)
            
            // Remove old timestamps (older than 2 seconds)
            frameTimestamps.removeAll { now - it > 2000 }
        }
    }
    
    /**
     * Get current frame rate.
     */
    fun getCurrentFps(): Float {
        synchronized(frameTimestamps) {
            if (frameTimestamps.size < 2) return 0f
            
            val timeWindow = frameTimestamps.last() - frameTimestamps.first()
            if (timeWindow <= 0) return 0f
            
            return (frameTimestamps.size - 1) * 1000f / timeWindow
        }
    }
    
    /**
     * Get method statistics.
     */
    fun getMethodStats(methodName: String): MethodStats? {
        val timing = methodTimings[methodName] ?: return null
        
        val callCount = timing.callCount.get()
        val totalTime = timing.totalTimeMs.get()
        
        return MethodStats(
            name = methodName,
            callCount = callCount,
            totalTimeMs = totalTime,
            averageTimeMs = if (callCount > 0) totalTime.toFloat() / callCount else 0f,
            maxTimeMs = timing.maxTimeMs.get(),
            minTimeMs = if (timing.minTimeMs.get() == Long.MAX_VALUE) 0 else timing.minTimeMs.get()
        )
    }
    
    /**
     * Get all method statistics sorted by total time.
     */
    fun getAllMethodStats(): List<MethodStats> {
        return methodTimings.keys.mapNotNull { getMethodStats(it) }
            .sortedByDescending { it.totalTimeMs }
    }
    
    /**
     * Reset all performance metrics.
     */
    fun reset() {
        methodTimings.clear()
        activeTimers.clear()
        synchronized(frameTimestamps) {
            frameTimestamps.clear()
        }
        Timber.d("PerformanceMonitor: Reset all metrics")
    }
    
    /**
     * Generate performance report.
     */
    fun generateReport(): String = buildString {
        val stats = _performanceStats.value
        
        appendLine("=== Performance Report ===")
        appendLine("Timestamp: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(stats.timestamp)}")
        appendLine()
        
        appendLine("Frame Rate:")
        appendLine("  Current: ${"%.1f".format(stats.currentFps)} fps")
        appendLine("  Average: ${"%.1f".format(stats.averageFps)} fps")
        appendLine("  Frame Drops: ${stats.frameDrops}")
        appendLine()
        
        appendLine("CPU Usage:")
        appendLine("  Current: ${"%.1f".format(stats.cpuUsagePercent)}%")
        appendLine()
        
        appendLine("Hot Methods (Top 10):")
        stats.hotMethods.take(10).forEach { method ->
            appendLine("  ${method.name}:")
            appendLine("    Calls: ${method.callCount}")
            appendLine("    Total: ${method.totalTimeMs}ms")
            appendLine("    Avg: ${"%.2f".format(method.averageTimeMs)}ms")
            appendLine("    Max: ${method.maxTimeMs}ms")
        }
        appendLine()
        
        appendLine("Recommendations:")
        val recommendations = generateRecommendations(stats)
        recommendations.forEach { appendLine("  - $it") }
    }
    
    /**
     * Record method timing.
     */
    private fun recordMethodTiming(methodName: String, durationMs: Long) {
        val timing = methodTimings.computeIfAbsent(methodName) { MethodTiming() }
        
        timing.callCount.incrementAndGet()
        timing.totalTimeMs.addAndGet(durationMs)
        
        // Update max
        var currentMax = timing.maxTimeMs.get()
        while (durationMs > currentMax) {
            if (timing.maxTimeMs.compareAndSet(currentMax, durationMs)) break
            currentMax = timing.maxTimeMs.get()
        }
        
        // Update min
        var currentMin = timing.minTimeMs.get()
        while (durationMs < currentMin) {
            if (timing.minTimeMs.compareAndSet(currentMin, durationMs)) break
            currentMin = timing.minTimeMs.get()
        }
    }
    
    /**
     * Collect current performance statistics.
     */
    private fun collectPerformanceStats(): PerformanceStats {
        val currentFps = getCurrentFps()
        val allMethods = getAllMethodStats()
        
        // Calculate average FPS (last 2 seconds)
        val averageFps = currentFps // Same as current for now
        
        // Detect frame drops (fps < 55 when targeting 60)
        val frameDrops = if (currentFps < 55 && currentFps > 0) 1 else 0
        
        return PerformanceStats(
            currentFps = currentFps,
            averageFps = averageFps,
            frameDrops = frameDrops,
            cpuUsagePercent = estimateCpuUsage(),
            hotMethods = allMethods.take(20),
            timestamp = System.currentTimeMillis()
        )
    }
    
    /**
     * Estimate CPU usage based on method timings.
     */
    private fun estimateCpuUsage(): Float {
        // Simple estimation based on total time spent in monitored methods
        val totalTimeMs = methodTimings.values.sumOf { it.totalTimeMs.get() }
        val monitoringDurationMs = 1000L // 1 second window
        
        return (totalTimeMs.toFloat() / monitoringDurationMs) * 100
    }
    
    /**
     * Generate optimization recommendations.
     */
    private fun generateRecommendations(stats: PerformanceStats): List<String> {
        val recommendations = mutableListOf<String>()
        
        if (stats.currentFps < 30) {
            recommendations.add("Critical: FPS is very low (${stats.currentFps.toInt()}). Reduce video quality or disable effects.")
        } else if (stats.currentFps < 55) {
            recommendations.add("Warning: FPS below target. Consider optimizing video processing.")
        }
        
        if (stats.cpuUsagePercent > 80) {
            recommendations.add("High CPU usage detected. Profile hot methods for optimization opportunities.")
        }
        
        // Check for slow methods
        stats.hotMethods.take(5).forEach { method ->
            if (method.averageTimeMs > 16) { // > 1 frame at 60fps
                recommendations.add("Method '${method.name}' is slow (${method.averageTimeMs.toInt()}ms avg). Consider optimization.")
            }
        }
        
        if (stats.frameDrops > 0) {
            recommendations.add("Frame drops detected. Check for blocking operations on main thread.")
        }
        
        return recommendations
    }
    
    /**
     * Clean up monitor resources.
     */
    fun cleanup() {
        stopMonitoring()
        reset()
        Timber.d("PerformanceMonitor: Cleaned up")
    }
}

/**
 * Extension function for easy method timing.
 */
inline fun <T> PerformanceMonitor.measure(methodName: String, block: () -> T): T {
    return measureTime(methodName, block)
}
