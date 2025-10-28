package com.example.tres3.effects

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import timber.log.Timber
import java.io.InputStream

/**
 * BackgroundEffectsLibrary - Pre-built virtual backgrounds and blur presets
 * 
 * Features:
 * - Blur presets (light, medium, heavy)
 * - Gradient backgrounds (multiple color schemes)
 * - Nature scene backgrounds
 * - Custom background upload support
 * - Background caching for performance
 * 
 * Usage:
 * ```kotlin
 * val library = BackgroundEffectsLibrary(context)
 * val blurBackground = library.getBlurPreset(BlurIntensity.MEDIUM)
 * val gradientBackground = library.getGradientBackground(GradientType.SUNSET)
 * virtualBackgroundProcessor.setCustomBackground(blurBackground)
 * ```
 */
class BackgroundEffectsLibrary(private val context: Context) {

    // Blur intensity levels
    enum class BlurIntensity(val radius: Int) {
        LIGHT(5),
        MEDIUM(15),
        HEAVY(25)
    }

    // Gradient types
    enum class GradientType {
        SUNSET,      // Orange to purple
        OCEAN,       // Blue to cyan
        FOREST,      // Green to dark green
        LAVENDER,    // Purple to pink
        PROFESSIONAL // Dark blue to light blue
    }

    // Nature scene types
    enum class NatureScene(val resourceName: String) {
        BEACH("beach"),
        MOUNTAINS("mountains"),
        FOREST("forest"),
        SUNSET("sunset"),
        OFFICE("office")
    }

    // Background cache
    private val backgroundCache = mutableMapOf<String, Bitmap>()

    companion object {
        private const val DEFAULT_WIDTH = 1920
        private const val DEFAULT_HEIGHT = 1080
        private const val CACHE_SIZE_LIMIT = 10
    }

    init {
        Timber.d("BackgroundEffectsLibrary initialized")
    }

    /**
     * Get blur preset background
     * Returns a simple solid color background with metadata for blur intensity
     */
    fun getBlurPreset(intensity: BlurIntensity): BlurPreset {
        val cacheKey = "blur_${intensity.name}"
        
        val background = backgroundCache.getOrPut(cacheKey) {
            createSolidColorBackground(0xFFE0E0E0.toInt()) // Light gray
        }

        Timber.d("Retrieved blur preset: ${intensity.name} (radius: ${intensity.radius})")
        return BlurPreset(background, intensity)
    }

    /**
     * Blur preset data class
     */
    data class BlurPreset(
        val background: Bitmap,
        val intensity: BlurIntensity
    )

    /**
     * Get gradient background
     */
    fun getGradientBackground(type: GradientType): Bitmap {
        val cacheKey = "gradient_${type.name}"
        
        return backgroundCache.getOrPut(cacheKey) {
            createGradientBackground(type)
        }
    }

    /**
     * Create gradient background
     */
    private fun createGradientBackground(type: GradientType): Bitmap {
        val bitmap = Bitmap.createBitmap(DEFAULT_WIDTH, DEFAULT_HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val (startColor, endColor) = when (type) {
            GradientType.SUNSET -> Pair(0xFFFF6B6B.toInt(), 0xFF4ECDC4.toInt())
            GradientType.OCEAN -> Pair(0xFF1A2980.toInt(), 0xFF26D0CE.toInt())
            GradientType.FOREST -> Pair(0xFF134E5E.toInt(), 0xFF71B280.toInt())
            GradientType.LAVENDER -> Pair(0xFFDA4453.toInt(), 0xFF89216B.toInt())
            GradientType.PROFESSIONAL -> Pair(0xFF2C3E50.toInt(), 0xFF4CA1AF.toInt())
        }

        val gradient = LinearGradient(
            0f, 0f,
            0f, DEFAULT_HEIGHT.toFloat(),
            startColor,
            endColor,
            Shader.TileMode.CLAMP
        )

        val paint = Paint().apply {
            shader = gradient
        }

        canvas.drawRect(0f, 0f, DEFAULT_WIDTH.toFloat(), DEFAULT_HEIGHT.toFloat(), paint)

        Timber.d("Created gradient background: ${type.name}")
        return bitmap
    }

    /**
     * Get nature scene background
     * For now, creates placeholder colored backgrounds
     * In production, these would load actual image assets
     */
    fun getNatureScene(scene: NatureScene): Bitmap {
        val cacheKey = "nature_${scene.name}"
        
        return backgroundCache.getOrPut(cacheKey) {
            createNatureScenePlaceholder(scene)
        }
    }

    /**
     * Create nature scene placeholder
     * In production, replace with: BitmapFactory.decodeResource(context.resources, resourceId)
     */
    private fun createNatureScenePlaceholder(scene: NatureScene): Bitmap {
        val color = when (scene) {
            NatureScene.BEACH -> 0xFFFFE5B4.toInt() // Sandy beach color
            NatureScene.MOUNTAINS -> 0xFF708090.toInt() // Slate gray
            NatureScene.FOREST -> 0xFF228B22.toInt() // Forest green
            NatureScene.SUNSET -> 0xFFFF4500.toInt() // Orange red
            NatureScene.OFFICE -> 0xFFF5F5F5.toInt() // White smoke
        }

        val bitmap = createSolidColorBackground(color)
        Timber.d("Created nature scene placeholder: ${scene.name}")
        return bitmap
    }

    /**
     * Load custom background from URI or file path
     */
    fun loadCustomBackground(inputStream: InputStream): Bitmap? {
        return try {
            val bitmap = BitmapFactory.decodeStream(inputStream)
            
            // Scale to standard size if needed
            val scaledBitmap = if (bitmap.width != DEFAULT_WIDTH || bitmap.height != DEFAULT_HEIGHT) {
                Bitmap.createScaledBitmap(bitmap, DEFAULT_WIDTH, DEFAULT_HEIGHT, true).also {
                    if (it != bitmap) bitmap.recycle()
                }
            } else {
                bitmap
            }

            // Add to cache
            val cacheKey = "custom_${System.currentTimeMillis()}"
            addToCache(cacheKey, scaledBitmap)

            Timber.d("Loaded custom background: ${scaledBitmap.width}x${scaledBitmap.height}")
            scaledBitmap
        } catch (e: Exception) {
            Timber.e(e, "Failed to load custom background")
            null
        }
    }

    /**
     * Create solid color background
     */
    fun createSolidColorBackground(color: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(DEFAULT_WIDTH, DEFAULT_HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(color)
        return bitmap
    }

    /**
     * Get all available blur presets
     */
    fun getAllBlurPresets(): List<BlurPreset> {
        return BlurIntensity.values().map { getBlurPreset(it) }
    }

    /**
     * Get all available gradient types
     */
    fun getAllGradientBackgrounds(): Map<GradientType, Bitmap> {
        return GradientType.values().associateWith { getGradientBackground(it) }
    }

    /**
     * Get all available nature scenes
     */
    fun getAllNatureScenes(): Map<NatureScene, Bitmap> {
        return NatureScene.values().associateWith { getNatureScene(it) }
    }

    /**
     * Get all backgrounds (blur, gradient, nature)
     */
    fun getAllBackgrounds(): Map<String, Bitmap> {
        val allBackgrounds = mutableMapOf<String, Bitmap>()
        
        // Add blur presets
        BlurIntensity.values().forEach { intensity ->
            allBackgrounds["blur_${intensity.name}"] = getBlurPreset(intensity).background
        }
        
        // Add gradients
        GradientType.values().forEach { gradient ->
            allBackgrounds["gradient_${gradient.name}"] = getGradientBackground(gradient)
        }
        
        // Add nature scenes
        NatureScene.values().forEach { scene ->
            allBackgrounds["nature_${scene.name}"] = getNatureScene(scene)
        }
        
        return allBackgrounds
    }

    /**
     * Add background to cache with size limit
     */
    private fun addToCache(key: String, bitmap: Bitmap) {
        // Remove oldest entry if cache is full
        if (backgroundCache.size >= CACHE_SIZE_LIMIT) {
            val oldestKey = backgroundCache.keys.firstOrNull()
            if (oldestKey != null) {
                backgroundCache[oldestKey]?.recycle()
                backgroundCache.remove(oldestKey)
                Timber.d("Removed oldest cached background: $oldestKey")
            }
        }
        
        backgroundCache[key] = bitmap
    }

    /**
     * Clear specific background from cache
     */
    fun clearFromCache(key: String) {
        backgroundCache[key]?.recycle()
        backgroundCache.remove(key)
        Timber.d("Cleared background from cache: $key")
    }

    /**
     * Clear all cached backgrounds
     */
    fun clearCache() {
        backgroundCache.values.forEach { it.recycle() }
        backgroundCache.clear()
        Timber.d("Cleared all background cache")
    }

    /**
     * Get cache size
     */
    fun getCacheSize(): Int = backgroundCache.size

    /**
     * Get memory usage of cache (approximate)
     */
    fun getCacheMemoryUsage(): Long {
        return backgroundCache.values.sumOf { bitmap ->
            (bitmap.byteCount).toLong()
        }
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        clearCache()
        Timber.d("BackgroundEffectsLibrary cleaned up")
    }
}
