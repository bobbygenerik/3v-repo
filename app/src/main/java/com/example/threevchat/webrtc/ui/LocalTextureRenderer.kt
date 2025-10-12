package com.example.threevchat.webrtc.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.util.AttributeSet
import android.view.TextureView
import org.webrtc.EglBase
import org.webrtc.VideoFrame
import org.webrtc.VideoSink

/**
 * TextureView-based local preview that accepts WebRTC frames (VideoSink) and renders via EglRenderer.
 * Uses reflection to support multiple EglRenderer API shapes across WebRTC builds.
 */
class LocalTextureRenderer @JvmOverloads constructor(
	context: Context,
	attrs: AttributeSet? = null
) : TextureView(context, attrs), TextureView.SurfaceTextureListener, VideoSink {

	private var eglContext: EglBase.Context? = null // kept for API parity; not used in software path
	private var mirror: Boolean = true
	@Volatile private var lastBitmap: Bitmap? = null
	@Volatile private var lastDrawTimeMs: Long = 0

	init {
		surfaceTextureListener = this
		isOpaque = false
	}

	fun init(eglContext: EglBase.Context) { this.eglContext = eglContext }

	fun setMirror(mirror: Boolean) {
		this.mirror = mirror
		scaleX = if (mirror) -1f else 1f
	}

	override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) { }

	private fun drawBitmap(bmp: Bitmap) {
		val st = surfaceTexture ?: return
		if (!isAvailable) return
		// Throttle to ~30fps
		val now = System.currentTimeMillis()
		if (now - lastDrawTimeMs < 33) return
		val w = width
		val h = height
		if (w <= 0 || h <= 0) return
		try {
			val canvas = lockCanvas() ?: return
			try {
				// Center-crop to fill container while preserving aspect ratio
				val bw = bmp.width
				val bh = bmp.height
				val viewAR = w.toFloat() / h.toFloat()
				val bmpAR = bw.toFloat() / bh.toFloat()
				val src: Rect = if (bmpAR > viewAR) {
					// Bitmap is wider than view: crop width
					val targetW = (bh * viewAR).toInt().coerceAtMost(bw)
					val left = ((bw - targetW) / 2).coerceAtLeast(0)
					Rect(left, 0, (left + targetW).coerceAtMost(bw), bh)
				} else {
					// Bitmap is taller than view: crop height
					val targetH = (bw / viewAR).toInt().coerceAtMost(bh)
					val top = ((bh - targetH) / 2).coerceAtLeast(0)
					Rect(0, top, bw, (top + targetH).coerceAtMost(bh))
				}
				val dst = Rect(0, 0, w, h)
				canvas.drawBitmap(bmp, src, dst, null)
			} finally {
				unlockCanvasAndPost(canvas)
				lastDrawTimeMs = now
			}
		} catch (_: Throwable) {
			// Surface may be destroyed or not ready; ignore draw
		}
	}

	override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) { }

	override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean { return true }

	override fun onSurfaceTextureUpdated(surface: SurfaceTexture) { }

	override fun onFrame(frame: VideoFrame) {
		// Never let exceptions escape this thread; WebRTC treats uncaught exceptions as fatal.
		try {
			// Apply frame rotation to the view itself to correct orientation (UI-thread safe)
			val rotRaw = frame.rotation
			val rot = ((rotRaw % 360) + 360) % 360 // normalize to [0,360)
			post {
				this.rotation = rot.toFloat()
				// Do not vertically flip; rely on rotation only to avoid upside-down output
				this.scaleY = 1f
			}
			val buf = frame.buffer
			val i420 = try { buf.toI420() } catch (_: Throwable) { buf as? VideoFrame.I420Buffer }
			if (i420 == null) return
			val w = i420.width
			val h = i420.height
			// Prepare bitmap backing store
			var bmp = lastBitmap
			if (bmp == null || bmp.width != w || bmp.height != h) {
				bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
				lastBitmap = bmp
			}
			// Convert I420 to ARGB into an IntArray (robust to strides/odd sizes)
			val out = IntArray(w * h)
			try {
				yuvToArgb(
					i420.dataY, i420.strideY,
					i420.dataU, i420.strideU,
					i420.dataV, i420.strideV,
					w, h,
					out
				)
			} catch (_: Throwable) {
				// Drop this frame on any conversion issue
				return
			}
			bmp!!.setPixels(out, 0, w, 0, 0, w, h)
			// Draw onto TextureView surface
			drawBitmap(bmp)
			// Release buffer if it was a copy
			try { i420.release() } catch (_: Throwable) {}
		} catch (_: Throwable) {
			// ignore
		}
	}

	private fun yuvToArgb(
		y: java.nio.ByteBuffer, yStride: Int,
		u: java.nio.ByteBuffer, uStride: Int,
		v: java.nio.ByteBuffer, vStride: Int,
		width: Int, height: Int,
		out: IntArray
	) {
		// Use absolute reads with bounds checks; handle odd sizes safely.
		val yLimit = y.limit()
		val uLimit = u.limit()
		val vLimit = v.limit()
		val chromaH = (height + 1) / 2
		var outIdx = 0
		for (row in 0 until height) {
			val yRow = row * yStride
			val uvRow = (row / 2)
			val uRow = uvRow * uStride
			val vRow = uvRow * vStride
			for (col in 0 until width) {
				val yOfs = yRow + col
				val cY = if (yOfs < yLimit) (y.get(yOfs).toInt() and 0xFF) else 0
				// For chroma, clamp index in case of inconsistent strides/limits
				val cIdx = (col / 2)
				val uOfs = uRow + cIdx
				val vOfs = vRow + cIdx
				val cU = if (uvRow < chromaH && uOfs < uLimit) (u.get(uOfs).toInt() and 0xFF) else 128
				val cV = if (uvRow < chromaH && vOfs < vLimit) (v.get(vOfs).toInt() and 0xFF) else 128
				val c = cY - 16
				val d = cU - 128
				val e = cV - 128
				var r = (298 * c + 409 * e + 128) shr 8
				var g = (298 * c - 100 * d - 208 * e + 128) shr 8
				var b = (298 * c + 516 * d + 128) shr 8
				if (r < 0) r = 0 else if (r > 255) r = 255
				if (g < 0) g = 0 else if (g > 255) g = 255
				if (b < 0) b = 0 else if (b > 255) b = 255
				out[outIdx++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
			}
		}
	}
}

