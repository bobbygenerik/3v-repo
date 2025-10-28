package com.example.tres3.performance

import android.graphics.Bitmap
import timber.log.Timber
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Bitmap pooling system to reduce memory allocations and GC pressure.
 * Reuses bitmap memory for video frame processing and effects.
 */
class BitmapPool(
    private val maxPoolSizeMB: Int = 50
) {
    
    // Pool organized by size buckets for efficient retrieval
    private val pools = ConcurrentHashMap<BitmapSize, ConcurrentLinkedQueue<Bitmap>>()
    private var currentPoolSizeMB = 0
    
    data class BitmapSize(
        val width: Int,
        val height: Int,
        val config: Bitmap.Config
    ) {
        override fun equals(other: Any?): Boolean {
            if (other !is BitmapSize) return false
            return width == other.width && height == other.height && config == other.config
        }
        
        override fun hashCode(): Int {
            var result = width
            result = 31 * result + height
            result = 31 * result + config.hashCode()
            return result
        }
    }
    
    /**
     * Get a bitmap from pool or create a new one.
     */
    fun getBitmap(width: Int, height: Int, config: Bitmap.Config = Bitmap.Config.ARGB_8888): Bitmap {
        val size = BitmapSize(width, height, config)
        
        // Try to get from pool
        val pool = pools[size]
        val bitmap = pool?.poll()
        
        if (bitmap != null && !bitmap.isRecycled) {
            bitmap.eraseColor(0) // Clear previous content
            Timber.v("BitmapPool: Retrieved bitmap from pool ($width x $height)")
            return bitmap
        }
        
        // Create new bitmap
        val newBitmap = Bitmap.createBitmap(width, height, config)
        Timber.v("BitmapPool: Created new bitmap ($width x $height)")
        return newBitmap
    }
    
    /**
     * Return a bitmap to the pool for reuse.
     */
    fun returnBitmap(bitmap: Bitmap) {
        if (bitmap.isRecycled) {
            Timber.w("BitmapPool: Attempted to return recycled bitmap")
            return
        }
        
        val bitmapSizeMB = bitmap.byteCount / 1024 / 1024
        
        // Check if pool is full
        if (currentPoolSizeMB + bitmapSizeMB > maxPoolSizeMB) {
            // Pool is full, recycle oldest bitmaps
            evictOldestBitmaps(bitmapSizeMB)
        }
        
        val size = BitmapSize(bitmap.width, bitmap.height, bitmap.config ?: Bitmap.Config.ARGB_8888)
        val pool = pools.computeIfAbsent(size) { ConcurrentLinkedQueue() }
        
        pool.offer(bitmap)
        currentPoolSizeMB += bitmapSizeMB
        
        Timber.v("BitmapPool: Returned bitmap to pool (pool size: ${currentPoolSizeMB}MB)")
    }
    
    /**
     * Get or create a mutable bitmap with the same dimensions as source.
     */
    fun getMutableCopy(source: Bitmap): Bitmap {
        val config = source.config ?: Bitmap.Config.ARGB_8888
        val bitmap = getBitmap(source.width, source.height, config)
        
        // Copy source content
        val canvas = android.graphics.Canvas(bitmap)
        canvas.drawBitmap(source, 0f, 0f, null)
        
        return bitmap
    }
    
    /**
     * Clear all bitmaps from pool.
     */
    fun clear() {
        pools.values.forEach { pool ->
            pool.forEach { bitmap ->
                if (!bitmap.isRecycled) {
                    bitmap.recycle()
                }
            }
            pool.clear()
        }
        pools.clear()
        currentPoolSizeMB = 0
        Timber.d("BitmapPool: Cleared all bitmaps")
    }
    
    /**
     * Trim pool to specified size.
     */
    fun trimToSize(maxSizeMB: Int) {
        while (currentPoolSizeMB > maxSizeMB) {
            evictOldestBitmap()
        }
        Timber.d("BitmapPool: Trimmed to ${currentPoolSizeMB}MB")
    }
    
    /**
     * Get pool statistics.
     */
    fun getStats(): PoolStats {
        val bitmapCount = pools.values.sumOf { it.size }
        val sizeStats = pools.entries.associate { (size, pool) ->
            "${size.width}x${size.height}" to pool.size
        }
        
        return PoolStats(
            totalBitmaps = bitmapCount,
            totalSizeMB = currentPoolSizeMB,
            sizeDistribution = sizeStats,
            maxSizeMB = maxPoolSizeMB
        )
    }
    
    data class PoolStats(
        val totalBitmaps: Int,
        val totalSizeMB: Int,
        val sizeDistribution: Map<String, Int>,
        val maxSizeMB: Int
    )
    
    /**
     * Evict oldest bitmaps to free up space.
     */
    private fun evictOldestBitmaps(requiredSizeMB: Int) {
        var freedSizeMB = 0
        
        while (freedSizeMB < requiredSizeMB && currentPoolSizeMB > 0) {
            freedSizeMB += evictOldestBitmap()
        }
        
        Timber.d("BitmapPool: Evicted ${freedSizeMB}MB")
    }
    
    /**
     * Evict a single oldest bitmap.
     */
    private fun evictOldestBitmap(): Int {
        // Find first non-empty pool
        for ((_, pool) in pools) {
            val bitmap = pool.poll()
            if (bitmap != null) {
                val sizeMB = bitmap.byteCount / 1024 / 1024
                if (!bitmap.isRecycled) {
                    bitmap.recycle()
                }
                currentPoolSizeMB -= sizeMB
                return sizeMB
            }
        }
        return 0
    }
}
