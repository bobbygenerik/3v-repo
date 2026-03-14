package com.tres3.videochat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Log
import android.view.Surface
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import java.util.concurrent.atomic.AtomicBoolean

/**
 * VideoSink that intercepts remote video frames, applies LiteRT low-light and
 * sharpening, then renders the result to a Flutter SurfaceTextureEntry surface.
 */
class LiteRTRemoteVideoSink(
    private val processor: LiteRTVideoProcessor,
    private val surface: Surface,
) : VideoSink {

    private val processing = AtomicBoolean(false)

    companion object {
        private const val TAG = "LiteRTRemoteSink"
    }

    override fun onFrame(frame: VideoFrame) {
        if (!processing.compareAndSet(false, true)) return

        val i420 = frame.buffer.toI420()
        try {
            val bitmap = processor.i420ToBitmapPublic(i420)
            val processed = processor.processRemoteFrame(bitmap)
            renderToSurface(processed, frame.rotation)

            if (processed !== bitmap) processed.recycle()
            bitmap.recycle()
        } catch (e: Exception) {
            Log.e(TAG, "Remote frame processing error: ${e.message}", e)
        } finally {
            i420.release()
            processing.set(false)
        }
    }

    private fun renderToSurface(bitmap: Bitmap, rotation: Int) {
        if (!surface.isValid) return

        var canvas: Canvas? = null
        try {
            canvas = surface.lockCanvas(null)
            if (canvas == null || canvas.width <= 0 || canvas.height <= 0) return

            if (rotation != 0) {
                canvas.save()
                canvas.rotate(rotation.toFloat(), canvas.width / 2f, canvas.height / 2f)
            }

            val drawBitmap =
                if (bitmap.width != canvas.width || bitmap.height != canvas.height) {
                    Bitmap.createScaledBitmap(bitmap, canvas.width, canvas.height, true)
                } else {
                    bitmap
                }

            canvas.drawBitmap(drawBitmap, 0f, 0f, null)

            if (drawBitmap !== bitmap) drawBitmap.recycle()
            if (rotation != 0) canvas.restore()
        } catch (e: Exception) {
            Log.e(TAG, "renderToSurface error: ${e.message}", e)
        } finally {
            if (canvas != null) {
                try {
                    surface.unlockCanvasAndPost(canvas)
                } catch (_: Exception) {
                }
            }
        }
    }

    fun dispose() {
        try {
            surface.release()
        } catch (_: Exception) {
        }
    }
}
