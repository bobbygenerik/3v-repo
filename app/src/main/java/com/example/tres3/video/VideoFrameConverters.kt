package com.example.tres3.video

import android.graphics.*
import android.graphics.ImageFormat
import android.graphics.YuvImage
import android.util.Log
import livekit.org.webrtc.JavaI420Buffer
import livekit.org.webrtc.VideoFrame.I420Buffer
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * VideoFrameConverters - utility conversions between WebRTC I420 buffers and Bitmaps.
 * NOTE: This is CPU-heavy and intended as a pragmatic bridge to enable MLKit processing.
 * We throttle FPS when processing to mitigate overhead on mid-range devices.
 */
object VideoFrameConverters {
    private const val TAG = "VideoFrameConv"

    // Convert I420 planar buffer to NV21 (Y + VU interleaved)
    fun i420ToNV21(i420: I420Buffer): ByteArray {
        val width = i420.width
        val height = i420.height
        val ySize = width * height
        val uvSize = ySize / 4
        val nv21 = ByteArray(ySize + 2 * uvSize)

        val y = i420.dataY
        val u = i420.dataU
        val v = i420.dataV
        val yStride = i420.strideY
        val uStride = i420.strideU
        val vStride = i420.strideV

        var pos = 0
        // Copy Y plane
        for (row in 0 until height) {
            y.position(row * yStride)
            y.get(nv21, pos, width)
            pos += width
        }

        // Interleave VU for NV21
        val chromaHeight = height / 2
        val chromaWidth = width / 2
        var uvPos = ySize
        for (row in 0 until chromaHeight) {
            val uRowStart = row * uStride
            val vRowStart = row * vStride
            for (col in 0 until chromaWidth) {
                v.position(vRowStart + col)
                u.position(uRowStart + col)
                // NV21 is V then U
                nv21[uvPos++] = v.get()
                nv21[uvPos++] = u.get()
            }
        }

        return nv21
    }

    // Convert NV21 bytes to ARGB Bitmap (via YuvImage JPEG roundtrip for simplicity)
    fun nv21ToBitmap(nv21: ByteArray, width: Int, height: Int): Bitmap {
        return try {
            val yuv = YuvImage(nv21, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuv.compressToJpeg(Rect(0, 0, width, height), 90, out)
            val jpegBytes = out.toByteArray()
            BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
        } catch (e: Exception) {
            Log.e(TAG, "nv21ToBitmap failed: ${e.message}", e)
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        }
    }

    // Convert ARGB Bitmap to I420
    fun bitmapToI420(bitmap: Bitmap): JavaI420Buffer {
        val width = bitmap.width
        val height = bitmap.height

        val out = JavaI420Buffer.allocate(width, height)
        val y = out.dataY
        val u = out.dataU
        val v = out.dataV
        val yStride = out.strideY
        val uStride = out.strideU
        val vStride = out.strideV

        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // ARGB -> I420 conversion
        var yp = 0
        for (j in 0 until height) {
            var yIndex = j * yStride
            for (i in 0 until width) {
                val c = pixels[yp++]
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF

                // BT.601 conversion
                val yVal = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                y.put(yIndex + i, yVal.toByte())
            }
        }

        // U/V planes (2x2 subsampling)
        for (j in 0 until height step 2) {
            var uIndex = (j / 2) * uStride
            var vIndex = (j / 2) * vStride
            var pIndex = j * width
            for (i in 0 until width step 2) {
                val c00 = pixels[pIndex + i]
                val c01 = if (i + 1 < width) pixels[pIndex + i + 1] else c00
                val c10 = if (j + 1 < height) pixels[pIndex + width + i] else c00
                val c11 = if (j + 1 < height && i + 1 < width) pixels[pIndex + width + i + 1] else c00

                val rAvg = ( ((c00 shr 16) and 0xFF) + ((c01 shr 16) and 0xFF) + ((c10 shr 16) and 0xFF) + ((c11 shr 16) and 0xFF) ) / 4
                val gAvg = ( ((c00 shr 8) and 0xFF) + ((c01 shr 8) and 0xFF) + ((c10 shr 8) and 0xFF) + ((c11 shr 8) and 0xFF) ) / 4
                val bAvg = ( (c00 and 0xFF) + (c01 and 0xFF) + (c10 and 0xFF) + (c11 and 0xFF) ) / 4

                val uVal = ((-38 * rAvg - 74 * gAvg + 112 * bAvg + 128) shr 8) + 128
                val vVal = ((112 * rAvg - 94 * gAvg - 18 * bAvg + 128) shr 8) + 128

                u.put(uIndex, uVal.toByte())
                v.put(vIndex, vVal.toByte())

                uIndex += 1
                vIndex += 1
            }
            pIndex += width * 2
        }

        return out
    }
}
