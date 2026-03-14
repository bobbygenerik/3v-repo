package com.tres3.videochat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.util.Log
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import com.google.ai.edge.litert.Interpreter
import com.google.ai.edge.litert.gpu.GpuDelegate
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * LiteRT (on-device ML) video frame processor.
 *
 * Implements LocalVideoTrack.ExternalVideoFrameProcessing so it hooks directly
 * into the flutter_webrtc capture pipeline for both the LiveKit SFU path and
 * the direct P2P WebRTC path.
 *
 * Features:
 *  - Background blur  (selfie_segmentation.tflite)
 *  - Low-light enhancement  (low_light_enhance.tflite)
 *  - Sharpening / super-resolution pre-encode  (sharpening via convolution kernel)
 *
 * Models must be placed under:
 *   android/app/src/main/assets/models/
 * See that directory's README.md for download links.
 */
class LiteRTVideoProcessor(
    private val context: Context,
) : LocalVideoTrack.ExternalVideoFrameProcessing {

    // ── Runtime options (thread-safe via @Volatile) ───────────────────────────
    @Volatile var backgroundBlurEnabled = false
    @Volatile var lowLightEnabled = false
    @Volatile var sharpeningEnabled = false
    @Volatile var blurRadius = 20f      // pixels, applied to background
    @Volatile var blurIntensity = 0.7f  // 0–1 mask threshold for soft edges

    // ── LiteRT state ─────────────────────────────────────────────────────────
    private var segInterpreter: Interpreter? = null
    private var lowLightInterpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null
    private var gpuAvailable = false

    // Prevent concurrent frame processing (skip frame if previous still running)
    private val processing = AtomicBoolean(false)

    companion object {
        private const val TAG = "LiteRTVideoProcessor"

        // Segmentation model I/O size: input [1, 256, 256, 3], output [1, 256, 256, 1]
        private const val SEG_W = 256
        private const val SEG_H = 256

        // Zero-DCE model I/O size: input [1, 400, 600, 3], output [1, 400, 600, 24]
        private const val LL_H = 400
        private const val LL_W = 600
        // Number of DCE curve iterations encoded in the 24-channel output (8 × 3 channels)
        private const val DCE_ITERS = 8

        // Sharpening kernel (unsharp-mask approximation)
        private val SHARPEN_KERNEL = floatArrayOf(
             0f, -1f,  0f,
            -1f,  5f, -1f,
             0f, -1f,  0f,
        )
    }

    init {
        loadModels()
    }

    // ── Model loading ─────────────────────────────────────────────────────────

    private fun loadModels() {
        gpuDelegate = try {
            GpuDelegate().also { gpuAvailable = true }
        } catch (e: Exception) {
            Log.w(TAG, "GPU delegate unavailable, falling back to CPU: ${e.message}")
            null
        }

        val opts = Interpreter.Options().apply {
            if (gpuAvailable && gpuDelegate != null) addDelegate(gpuDelegate!!)
            numThreads = if (gpuAvailable) 1 else 2
        }

        segInterpreter = loadInterpreter("models/selfie_segmentation.tflite", opts)
        lowLightInterpreter = loadInterpreter("models/low_light_enhance.tflite", opts)

        if (segInterpreter == null) Log.w(TAG, "Segmentation model not found — background blur disabled")
        if (lowLightInterpreter == null) Log.w(TAG, "Low-light model not found — low-light enhancement disabled")
    }

    private fun loadInterpreter(assetPath: String, opts: Interpreter.Options): Interpreter? {
        return try {
            val afd = context.assets.openFd(assetPath)
            val buffer = FileInputStream(afd.fileDescriptor).channel.map(
                java.nio.channels.FileChannel.MapMode.READ_ONLY,
                afd.startOffset,
                afd.declaredLength,
            )
            Interpreter(buffer, opts)
        } catch (e: Exception) {
            Log.d(TAG, "Could not load $assetPath: ${e.message}")
            null
        }
    }

    // ── ExternalVideoFrameProcessing ──────────────────────────────────────────

    override fun onFrame(frame: VideoFrame): VideoFrame {
        val doBlur = backgroundBlurEnabled && segInterpreter != null
        val doLowLight = lowLightEnabled && lowLightInterpreter != null
        val doSharpen = sharpeningEnabled

        if (!doBlur && !doLowLight && !doSharpen) return frame

        // Skip this frame if processing is still running from last frame
        if (!processing.compareAndSet(false, true)) return frame

        val i420 = frame.buffer.toI420() ?: run {
            processing.set(false)
            return frame
        }

        return try {
            val bitmap = i420ToBitmap(i420)
            val processed = processFrame(bitmap, doBlur, doLowLight, doSharpen)
            val newBuffer = bitmapToI420(processed, i420.width, i420.height)
            if (processed !== bitmap) bitmap.recycle()
            VideoFrame(newBuffer, frame.rotation, frame.timestampNs)
        } catch (e: Exception) {
            Log.e(TAG, "Frame processing error: ${e.message}")
            frame
        } finally {
            i420.release()
            processing.set(false)
        }
    }

    // ── Pipeline ──────────────────────────────────────────────────────────────

    private fun processFrame(
        src: Bitmap,
        doBlur: Boolean,
        doLowLight: Boolean,
        doSharpen: Boolean,
    ): Bitmap {
        var result = src

        // 1. Low-light enhancement (before blur so the model sees the raw signal)
        if (doLowLight && isLowLight(result)) {
            result = runLowLight(result) ?: result
        }

        // 2. Background blur using segmentation mask
        if (doBlur) {
            result = runBackgroundBlur(result) ?: result
        }

        // 3. Sharpening / super-resolution convolution
        if (doSharpen) {
            result = applySharpen(result)
        }

        return result
    }

    /**
     * Process a remote video frame: apply low-light enhancement and sharpening.
     * Background blur is intentionally excluded for received video.
     */
    fun processRemoteFrame(src: Bitmap): Bitmap {
        var result = src
        if (lowLightEnabled && isLowLight(result)) {
            result = runLowLight(result) ?: result
        }
        if (sharpeningEnabled) {
            val sharpened = applySharpen(result)
            if (result !== src) result.recycle()
            result = sharpened
        }
        return result
    }

    fun i420ToBitmapPublic(i420: VideoFrame.I420Buffer): Bitmap = i420ToBitmap(i420)

    // ── Background blur ───────────────────────────────────────────────────────

    private fun runBackgroundBlur(src: Bitmap): Bitmap? {
        val interp = segInterpreter ?: return null

        // Scale to model input
        val scaled = Bitmap.createScaledBitmap(src, SEG_W, SEG_H, true)

        // Build float input [1, H, W, 3]
        val inputBuf = ByteBuffer.allocateDirect(1 * SEG_H * SEG_W * 3 * 4)
            .apply { order(ByteOrder.nativeOrder()) }
        val pixels = IntArray(SEG_W * SEG_H)
        scaled.getPixels(pixels, 0, SEG_W, 0, 0, SEG_W, SEG_H)
        for (px in pixels) {
            inputBuf.putFloat(Color.red(px) / 255f)
            inputBuf.putFloat(Color.green(px) / 255f)
            inputBuf.putFloat(Color.blue(px) / 255f)
        }
        inputBuf.rewind()
        scaled.recycle()

        // Output: [1, H, W, 1] confidence (person = 1, background = 0)
        val outputBuf = ByteBuffer.allocateDirect(1 * SEG_H * SEG_W * 1 * 4)
            .apply { order(ByteOrder.nativeOrder()) }
        interp.run(inputBuf, outputBuf)
        outputBuf.rewind()

        // Build alpha mask at model size
        val maskPixels = IntArray(SEG_W * SEG_H)
        for (i in maskPixels.indices) {
            val confidence = outputBuf.float.coerceIn(0f, 1f)
            maskPixels[i] = Color.argb((confidence * 255).toInt(), 255, 255, 255)
        }
        val maskSmall = Bitmap.createBitmap(SEG_W, SEG_H, Bitmap.Config.ARGB_8888)
            .apply { setPixels(maskPixels, 0, SEG_W, 0, 0, SEG_W, SEG_H) }

        // Scale mask back to frame dimensions
        val mask = Bitmap.createScaledBitmap(maskSmall, src.width, src.height, true)
        maskSmall.recycle()

        // Blurred background
        val blurredBg = boxBlur(src, blurRadius.toInt().coerceIn(1, 40))

        // Composite: blurred background + person foreground using mask
        val result = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)

        // Draw blurred background
        canvas.drawBitmap(blurredBg, 0f, 0f, null)
        blurredBg.recycle()

        // Draw person pixels via mask (DST_IN keeps only pixels where mask alpha > 0)
        val fg = src.copy(Bitmap.Config.ARGB_8888, true)
        Canvas(fg).drawBitmap(mask, 0f, 0f, Paint().apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        })
        mask.recycle()
        canvas.drawBitmap(fg, 0f, 0f, null)
        fg.recycle()

        return result
    }

    // ── Low-light enhancement ─────────────────────────────────────────────────

    private fun isLowLight(bitmap: Bitmap): Boolean {
        val thumb = Bitmap.createScaledBitmap(bitmap, 32, 32, false)
        val pixels = IntArray(32 * 32)
        thumb.getPixels(pixels, 0, 32, 0, 0, 32, 32)
        thumb.recycle()
        val avgLuma = pixels.fold(0f) { acc, px ->
            acc + (0.299f * Color.red(px) + 0.587f * Color.green(px) + 0.114f * Color.blue(px))
        } / pixels.size
        return avgLuma < 85f  // threshold: ~1/3 of full range
    }

    // Uses Zero-DCE TFLite (fully-convolutional — any input size).
    // Falls back to adaptive gamma correction when the model is absent.
    private fun runLowLight(src: Bitmap): Bitmap? {
        val interp = lowLightInterpreter
        return if (interp != null) runLowLightModel(src, interp) else gammaCorrect(src)
    }

    private fun runLowLightModel(src: Bitmap, interp: Interpreter): Bitmap? {
        // Zero-DCE model: fixed input [1, 400, 600, 3], output [1, 400, 600, 24]
        // The 24-channel output encodes 8 sets of 3-channel alpha (A) curve maps.
        // Enhancement formula applied 8 times: x = x + A * x * (1 - x)
        val scaled = Bitmap.createScaledBitmap(src, LL_W, LL_H, true)

        val pixelCount = LL_H * LL_W
        val inputBuf = ByteBuffer.allocateDirect(pixelCount * 3 * 4)
            .apply { order(ByteOrder.nativeOrder()) }
        val pixels = IntArray(pixelCount)
        scaled.getPixels(pixels, 0, LL_W, 0, 0, LL_W, LL_H)
        for (px in pixels) {
            inputBuf.putFloat(Color.red(px) / 255f)
            inputBuf.putFloat(Color.green(px) / 255f)
            inputBuf.putFloat(Color.blue(px) / 255f)
        }
        inputBuf.rewind()
        scaled.recycle()

        return try {
            // Output: [1, LL_H, LL_W, 24] — 8 iterations × 3 alpha channels
            val outputBuf = ByteBuffer.allocateDirect(pixelCount * 24 * 4)
                .apply { order(ByteOrder.nativeOrder()) }
            interp.run(inputBuf, outputBuf)
            outputBuf.rewind()

            // Read all 24 alpha channels: alpha[pixel][iteration][channel]
            // Layout is row-major: [H, W, 24] → iterate pixel by pixel, 24 floats each
            val alphas = Array(pixelCount) { FloatArray(24) }
            for (i in 0 until pixelCount) {
                for (c in 0 until 24) alphas[i][c] = outputBuf.float
            }

            // Apply DCE curve formula to the original normalized input pixels
            val outPixels = IntArray(pixelCount)
            for (i in outPixels.indices) {
                val px = pixels[i]
                var r = Color.red(px) / 255f
                var g = Color.green(px) / 255f
                var b = Color.blue(px) / 255f
                // 8 iterations, each using the next set of 3 alpha channels
                for (iter in 0 until DCE_ITERS) {
                    val ar = alphas[i][iter * 3]
                    val ag = alphas[i][iter * 3 + 1]
                    val ab = alphas[i][iter * 3 + 2]
                    r = (r + ar * r * (1f - r)).coerceIn(0f, 1f)
                    g = (g + ag * g * (1f - g)).coerceIn(0f, 1f)
                    b = (b + ab * b * (1f - b)).coerceIn(0f, 1f)
                }
                outPixels[i] = Color.rgb(
                    (r * 255).toInt(),
                    (g * 255).toInt(),
                    (b * 255).toInt(),
                )
            }

            val enhanced = Bitmap.createBitmap(LL_W, LL_H, Bitmap.Config.ARGB_8888)
                .apply { setPixels(outPixels, 0, LL_W, 0, 0, LL_W, LL_H) }
            Bitmap.createScaledBitmap(enhanced, src.width, src.height, true)
                .also { enhanced.recycle() }
        } catch (e: Exception) {
            Log.e(TAG, "Low-light model error: ${e.message} — falling back to gamma")
            gammaCorrect(src)
        }
    }

    /**
     * Model-free low-light enhancement: adaptive gamma correction.
     * Always available regardless of whether the TFLite model is loaded.
     * Computes gamma from scene luminance so dark frames are lifted proportionally.
     */
    private fun gammaCorrect(src: Bitmap): Bitmap {
        val w = src.width; val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        // Sample luminance on a tiny thumbnail for speed
        val thumb = Bitmap.createScaledBitmap(src, 32, 32, false)
        val thumbPx = IntArray(32 * 32)
        thumb.getPixels(thumbPx, 0, 32, 0, 0, 32, 32)
        thumb.recycle()
        val avgLuma = thumbPx.fold(0f) { acc, px ->
            acc + (0.299f * Color.red(px) + 0.587f * Color.green(px) + 0.114f * Color.blue(px))
        } / thumbPx.size

        // gamma < 1 brightens; scale with scene darkness so barely-dark frames get gentle lift
        val gamma = (0.5f + (avgLuma / 255f) * 0.5f).coerceIn(0.35f, 0.95f)
        val lut = IntArray(256) { i ->
            (255.0 * Math.pow(i / 255.0, gamma.toDouble())).toInt().coerceIn(0, 255)
        }

        for (i in pixels.indices) {
            val px = pixels[i]
            pixels[i] = Color.rgb(lut[Color.red(px)], lut[Color.green(px)], lut[Color.blue(px)])
        }
        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            .apply { setPixels(pixels, 0, w, 0, 0, w, h) }
    }

    // ── Sharpening (unsharp-mask convolution) ─────────────────────────────────

    private fun applySharpen(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)

        val out = IntArray(w * h)
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                var r = 0f; var g = 0f; var b = 0f
                for (ky in -1..1) {
                    for (kx in -1..1) {
                        val k = SHARPEN_KERNEL[(ky + 1) * 3 + (kx + 1)]
                        val px = pixels[(y + ky) * w + (x + kx)]
                        r += k * Color.red(px)
                        g += k * Color.green(px)
                        b += k * Color.blue(px)
                    }
                }
                out[y * w + x] = Color.rgb(
                    r.toInt().coerceIn(0, 255),
                    g.toInt().coerceIn(0, 255),
                    b.toInt().coerceIn(0, 255),
                )
            }
        }
        // Copy edge pixels unchanged
        for (x in 0 until w) { out[x] = pixels[x]; out[(h - 1) * w + x] = pixels[(h - 1) * w + x] }
        for (y in 0 until h) { out[y * w] = pixels[y * w]; out[y * w + w - 1] = pixels[y * w + w - 1] }

        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            .apply { setPixels(out, 0, w, 0, 0, w, h) }
    }

    // ── Box blur (3-pass approximates Gaussian) ───────────────────────────────

    private fun boxBlur(src: Bitmap, radius: Int): Bitmap {
        if (radius < 1) return src.copy(src.config, false)
        val w = src.width
        val h = src.height

        // Downsample → blur → upsample for speed on large frames
        val scale = 4
        val sw = (w / scale).coerceAtLeast(1)
        val sh = (h / scale).coerceAtLeast(1)
        val small = Bitmap.createScaledBitmap(src, sw, sh, true)

        val pixels = IntArray(sw * sh)
        small.getPixels(pixels, 0, sw, 0, 0, sw, sh)
        small.recycle()

        val scaledRadius = (radius / scale).coerceAtLeast(1)
        repeat(3) {
            boxBlurH(pixels, sw, sh, scaledRadius)
            boxBlurV(pixels, sw, sh, scaledRadius)
        }

        val blurred = Bitmap.createBitmap(sw, sh, Bitmap.Config.ARGB_8888)
            .apply { setPixels(pixels, 0, sw, 0, 0, sw, sh) }
        return Bitmap.createScaledBitmap(blurred, w, h, true).also { blurred.recycle() }
    }

    private fun boxBlurH(pixels: IntArray, w: Int, h: Int, r: Int) {
        val tmp = IntArray(w)
        for (y in 0 until h) {
            var rSum = 0; var gSum = 0; var bSum = 0
            val base = y * w
            val count = r + 1
            for (x in 0..r) {
                val px = pixels[base + x.coerceAtMost(w - 1)]
                rSum += Color.red(px); gSum += Color.green(px); bSum += Color.blue(px)
            }
            for (x in 0 until w) {
                tmp[x] = Color.rgb(rSum / count, gSum / count, bSum / count)
                val add = pixels[base + (x + r + 1).coerceAtMost(w - 1)]
                val rem = pixels[base + (x - r).coerceAtLeast(0)]
                rSum += Color.red(add) - Color.red(rem)
                gSum += Color.green(add) - Color.green(rem)
                bSum += Color.blue(add) - Color.blue(rem)
            }
            tmp.copyInto(pixels, base, 0, w)
        }
    }

    private fun boxBlurV(pixels: IntArray, w: Int, h: Int, r: Int) {
        val tmp = IntArray(h)
        for (x in 0 until w) {
            var rSum = 0; var gSum = 0; var bSum = 0
            val count = r + 1
            for (y in 0..r) {
                val px = pixels[y.coerceAtMost(h - 1) * w + x]
                rSum += Color.red(px); gSum += Color.green(px); bSum += Color.blue(px)
            }
            for (y in 0 until h) {
                tmp[y] = Color.rgb(rSum / count, gSum / count, bSum / count)
                val add = pixels[(y + r + 1).coerceAtMost(h - 1) * w + x]
                val rem = pixels[(y - r).coerceAtLeast(0) * w + x]
                rSum += Color.red(add) - Color.red(rem)
                gSum += Color.green(add) - Color.green(rem)
                bSum += Color.blue(add) - Color.blue(rem)
            }
            for (y in 0 until h) pixels[y * w + x] = tmp[y]
        }
    }

    // ── I420 ↔ Bitmap conversions ─────────────────────────────────────────────

    private fun i420ToBitmap(i420: VideoFrame.I420Buffer): Bitmap {
        val w = i420.width
        val h = i420.height
        val pixels = IntArray(w * h)

        val yBuf = i420.dataY
        val uBuf = i420.dataU
        val vBuf = i420.dataV
        val yStride = i420.strideY
        val uStride = i420.strideU
        val vStride = i420.strideV

        for (row in 0 until h) {
            for (col in 0 until w) {
                val yVal = yBuf.get(row * yStride + col).toInt() and 0xFF
                val uVal = (uBuf.get((row shr 1) * uStride + (col shr 1)).toInt() and 0xFF) - 128
                val vVal = (vBuf.get((row shr 1) * vStride + (col shr 1)).toInt() and 0xFF) - 128

                // BT.601 full range
                val r = (yVal + 1.402 * vVal).toInt().coerceIn(0, 255)
                val g = (yVal - 0.344136 * uVal - 0.714136 * vVal).toInt().coerceIn(0, 255)
                val b = (yVal + 1.772 * uVal).toInt().coerceIn(0, 255)
                pixels[row * w + col] = Color.rgb(r, g, b)
            }
        }

        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            .apply { setPixels(pixels, 0, w, 0, 0, w, h) }
    }

    private fun bitmapToI420(bitmap: Bitmap, outW: Int, outH: Int): VideoFrame.I420Buffer {
        val scaled = if (bitmap.width != outW || bitmap.height != outH)
            Bitmap.createScaledBitmap(bitmap, outW, outH, true)
        else bitmap

        val pixels = IntArray(outW * outH)
        scaled.getPixels(pixels, 0, outW, 0, 0, outW, outH)
        if (scaled !== bitmap) scaled.recycle()

        val yBuf = ByteBuffer.allocateDirect(outW * outH)
        val uBuf = ByteBuffer.allocateDirect((outW / 2) * (outH / 2))
        val vBuf = ByteBuffer.allocateDirect((outW / 2) * (outH / 2))

        for (row in 0 until outH) {
            for (col in 0 until outW) {
                val px = pixels[row * outW + col]
                val r = Color.red(px).toFloat()
                val g = Color.green(px).toFloat()
                val b = Color.blue(px).toFloat()

                // BT.601 limited range
                val y = ((77 * r + 150 * g + 29 * b + 128) / 256 + 16).toInt().coerceIn(16, 235)
                yBuf.put(y.toByte())

                if (row % 2 == 0 && col % 2 == 0) {
                    val u = ((-43 * r - 85 * g + 128 * b + 128) / 256 + 128).toInt().coerceIn(16, 240)
                    val v = ((128 * r - 107 * g - 21 * b + 128) / 256 + 128).toInt().coerceIn(16, 240)
                    uBuf.put(u.toByte())
                    vBuf.put(v.toByte())
                }
            }
        }

        yBuf.rewind(); uBuf.rewind(); vBuf.rewind()
        return JavaI420Buffer.wrap(outW, outH, yBuf, outW, uBuf, outW / 2, vBuf, outW / 2) {}
    }

    // ── Public API ────────────────────────────────────────────────────────────

    fun updateOptions(
        backgroundBlur: Boolean = backgroundBlurEnabled,
        lowLight: Boolean = lowLightEnabled,
        sharpening: Boolean = sharpeningEnabled,
        blur: Float = blurRadius,
    ) {
        backgroundBlurEnabled = backgroundBlur
        lowLightEnabled = lowLight
        sharpeningEnabled = sharpening
        blurRadius = blur
    }

    /** Returns which features have their models loaded and are ready to use. */
    fun capabilities(): Map<String, Boolean> = mapOf(
        "backgroundBlur" to (segInterpreter != null),
        "lowLight" to true,     // gamma fallback always available; model gives better results
        "lowLightModelLoaded" to (lowLightInterpreter != null),
        "sharpening" to true,   // kernel-based, always available
        "gpuDelegate" to gpuAvailable,
    )

    fun dispose() {
        segInterpreter?.close()
        lowLightInterpreter?.close()
        gpuDelegate?.close()
        segInterpreter = null
        lowLightInterpreter = null
        gpuDelegate = null
    }
}
