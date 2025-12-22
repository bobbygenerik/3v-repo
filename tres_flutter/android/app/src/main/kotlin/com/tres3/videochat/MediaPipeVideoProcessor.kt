package com.tres3.videochat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.Log
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenterResult
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min

data class MediaPipeOptions(
  var backgroundBlur: Boolean = false,
  var beauty: Boolean = false,
  var faceMesh: Boolean = false,
  var faceDetection: Boolean = false,
  var blurIntensity: Double = 70.0,
)

class MediaPipeVideoProcessor(
  private val context: Context,
  private var options: MediaPipeOptions,
) : LocalVideoTrack.ExternalVideoFrameProcessing {

  private var segmenter: ImageSegmenter? = null
  private var faceLandmarker: FaceLandmarker? = null

  private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
  private var lastCropRect: RectF? = null

  init {
    initializeModels()
  }

  fun updateOptions(newOptions: MediaPipeOptions) {
    options = newOptions
  }

  fun dispose() {
    segmenter?.close()
    faceLandmarker?.close()
  }

  override fun onFrame(frame: VideoFrame): VideoFrame {
    if (!options.backgroundBlur && !options.beauty && !options.faceMesh && !options.faceDetection) {
      return frame
    }

    return try {
      val i420 = frame.buffer.toI420() ?: return frame
      try {
        val bitmap = i420ToBitmap(i420)
        val processed = processBitmap(bitmap, frame.timestampNs / 1000000)
        val outI420 = bitmapToI420(processed)
        VideoFrame(outI420, frame.rotation, frame.timestampNs)
      } finally {
        i420.release()
      }
    } catch (e: Exception) {
      Log.e("MediaPipe", "Frame processing failed, passing through frame: ${e.message}")
      frame
    }
  }

  private fun processBitmap(bitmap: Bitmap, timestampMs: Long): Bitmap {
    val width = bitmap.width
    val height = bitmap.height
    var output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(output)

    var maskBitmap: Bitmap? = null
    if (options.backgroundBlur) {
      val result = segmenter?.segmentForVideo(buildMpImage(bitmap), timestampMs)
      maskBitmap = result?.let { buildMaskBitmap(it, width, height) }
    }

    val blurRadius = computeBlurRadius(options.blurIntensity)
    val blurred = if (options.backgroundBlur && blurRadius > 0) fastBlur(bitmap, blurRadius) else null

    if (blurred != null && maskBitmap != null) {
      canvas.drawBitmap(blurred, 0f, 0f, paint)
      val subject = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      val subjectCanvas = Canvas(subject)
      subjectCanvas.drawBitmap(bitmap, 0f, 0f, paint)
      subjectCanvas.drawBitmap(maskBitmap, 0f, 0f, Paint().apply {
        xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.DST_IN)
      })
      canvas.drawBitmap(subject, 0f, 0f, paint)
    } else if (options.backgroundBlur && blurred != null) {
      canvas.drawBitmap(blurred, 0f, 0f, paint)
    } else {
      canvas.drawBitmap(bitmap, 0f, 0f, paint)
    }

    val faceResult = if (options.beauty || options.faceDetection || options.faceMesh) {
      faceLandmarker?.detectForVideo(buildMpImage(bitmap), timestampMs)
    } else {
      null
    }

    if (options.beauty && faceResult != null) {
      applyBeauty(canvas, bitmap, faceResult)
    }

    if (options.faceDetection && faceResult != null) {
      val rect = computeFaceRect(faceResult, width, height)
      val smoothed = rect?.let { smoothRect(it) }
      if (smoothed != null) {
        val baseOutput = output
        val left = smoothed.left.toInt().coerceIn(0, width - 1)
        val top = smoothed.top.toInt().coerceIn(0, height - 1)
        val cropWidth = smoothed.width().toInt().coerceAtLeast(1)
          .coerceAtMost(width - left)
        val cropHeight = smoothed.height().toInt().coerceAtLeast(1)
          .coerceAtMost(height - top)
        val cropped = Bitmap.createBitmap(baseOutput, left, top, cropWidth, cropHeight)
        output = Bitmap.createScaledBitmap(cropped, width, height, true)
        if (cropped != output) {
          cropped.recycle()
        }
        if (baseOutput != output) {
          baseOutput.recycle()
        }
      }
    } else {
      lastCropRect = null
    }

    return output
  }

  private fun applyBeauty(canvas: Canvas, source: Bitmap, result: FaceLandmarkerResult) {
    if (result.faceLandmarks().isEmpty()) return
    val blurredFace = fastBlur(source, 4)

    for (landmarks in result.faceLandmarks()) {
      var minX = 1f
      var minY = 1f
      var maxX = 0f
      var maxY = 0f
      for (point in landmarks) {
        minX = min(minX, point.x())
        minY = min(minY, point.y())
        maxX = max(maxX, point.x())
        maxY = max(maxY, point.y())
      }
      val x = max((minX * source.width).toInt() - 10, 0)
      val y = max((minY * source.height).toInt() - 10, 0)
      val w = min(((maxX - minX) * source.width).toInt() + 20, source.width - x)
      val h = min(((maxY - minY) * source.height).toInt() + 20, source.height - y)

      val srcRect = android.graphics.Rect(x, y, x + w, y + h)
      canvas.drawBitmap(blurredFace, srcRect, srcRect, paint)
    }
  }

  private fun computeFaceRect(
    result: FaceLandmarkerResult,
    width: Int,
    height: Int,
  ): RectF? {
    val landmarks = result.faceLandmarks().firstOrNull() ?: return null
    var minX = 1f
    var minY = 1f
    var maxX = 0f
    var maxY = 0f

    for (point in landmarks) {
      minX = min(minX, point.x())
      minY = min(minY, point.y())
      maxX = max(maxX, point.x())
      maxY = max(maxY, point.y())
    }

    if (maxX <= minX || maxY <= minY) return null

    val centerX = (minX + maxX) * 0.5f * width
    val centerY = (minY + maxY) * 0.5f * height
    val faceWidth = (maxX - minX) * width
    val faceHeight = (maxY - minY) * height
    val targetScale = 1.9f
    var cropWidth = faceWidth * targetScale
    var cropHeight = faceHeight * targetScale

    val aspect = width.toFloat() / height.toFloat()
    if (cropWidth / cropHeight > aspect) {
      cropHeight = cropWidth / aspect
    } else {
      cropWidth = cropHeight * aspect
    }

    var left = centerX - cropWidth / 2f
    var top = centerY - cropHeight / 2f
    if (left < 0f) left = 0f
    if (top < 0f) top = 0f
    if (left + cropWidth > width) left = max(0f, width - cropWidth)
    if (top + cropHeight > height) top = max(0f, height - cropHeight)

    return RectF(left, top, left + cropWidth, top + cropHeight)
  }

  private fun smoothRect(next: RectF): RectF {
    val previous = lastCropRect
    if (previous == null) {
      lastCropRect = next
      return next
    }
    val alpha = 0.2f
    val smoothed = RectF(
      previous.left + (next.left - previous.left) * alpha,
      previous.top + (next.top - previous.top) * alpha,
      previous.right + (next.right - previous.right) * alpha,
      previous.bottom + (next.bottom - previous.bottom) * alpha,
    )
    lastCropRect = smoothed
    return smoothed
  }

  private fun buildMpImage(bitmap: Bitmap): MPImage {
    return BitmapImageBuilder(bitmap).build()
  }

  private fun buildMaskBitmap(result: ImageSegmenterResult, width: Int, height: Int): Bitmap? {
    val mask = result.categoryMask().orElse(null) ?: return null
    val maskWidth = mask.width
    val maskHeight = mask.height
    val maskBuffer = extractMaskBuffer(mask) ?: return null
    val maskPixels = IntArray(maskWidth * maskHeight)
    val floatBuffer = FloatArray(maskWidth * maskHeight)
    maskBuffer.rewind()
    val useFloat = maskBuffer.remaining() >= maskWidth * maskHeight * 4
    if (useFloat) {
      maskBuffer.asFloatBuffer().get(floatBuffer)
    }

    for (i in floatBuffer.indices) {
      val alpha = if (useFloat) {
        (floatBuffer[i] * 255).toInt().coerceIn(0, 255)
      } else {
        (maskBuffer.get(i).toInt() and 0xFF)
      }
      maskPixels[i] = (alpha shl 24)
    }

    val maskBitmap = Bitmap.createBitmap(maskWidth, maskHeight, Bitmap.Config.ARGB_8888)
    maskBitmap.setPixels(maskPixels, 0, maskWidth, 0, 0, maskWidth, maskHeight)
    return Bitmap.createScaledBitmap(maskBitmap, width, height, true)
  }

  private fun initializeModels() {
    segmenter = createSegmenter(Delegate.GPU) ?: createSegmenter(Delegate.CPU)
    faceLandmarker = createFaceLandmarker(Delegate.GPU) ?: createFaceLandmarker(Delegate.CPU)
  }

  private fun createSegmenter(delegate: Delegate): ImageSegmenter? {
    return try {
      val baseOptions = BaseOptions.builder()
        .setModelAssetPath("flutter_assets/assets/mediapipe/selfie_segmenter.tflite")
        .setDelegate(delegate)
        .build()
      val segmenterOptions = ImageSegmenter.ImageSegmenterOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.VIDEO)
        .setOutputCategoryMask(true)
        .build()
      val result = ImageSegmenter.createFromOptions(context, segmenterOptions)
      Log.d("MediaPipe", "ImageSegmenter initialized with ${delegate.name}")
      result
    } catch (e: Exception) {
      Log.w("MediaPipe", "ImageSegmenter ${delegate.name} init failed: ${e.message}")
      null
    }
  }

  private fun createFaceLandmarker(delegate: Delegate): FaceLandmarker? {
    return try {
      val baseOptions = BaseOptions.builder()
        .setModelAssetPath("flutter_assets/assets/mediapipe/face_landmarker.task")
        .setDelegate(delegate)
        .build()
      val faceOptions = FaceLandmarker.FaceLandmarkerOptions.builder()
        .setBaseOptions(baseOptions)
        .setRunningMode(RunningMode.VIDEO)
        .setOutputFaceBlendshapes(false)
        .setOutputFacialTransformationMatrixes(false)
        .build()
      val result = FaceLandmarker.createFromOptions(context, faceOptions)
      Log.d("MediaPipe", "FaceLandmarker initialized with ${delegate.name}")
      result
    } catch (e: Exception) {
      Log.w("MediaPipe", "FaceLandmarker ${delegate.name} init failed: ${e.message}")
      null
    }
  }

  private fun extractMaskBuffer(mask: MPImage): ByteBuffer? {
    return try {
      val getContainer = mask.javaClass.getDeclaredMethod("getContainer")
      getContainer.isAccessible = true
      val container = getContainer.invoke(mask)
      val method = container.javaClass.getMethod("getByteBuffer")
      method.isAccessible = true
      method.invoke(container) as? ByteBuffer
    } catch (e: Exception) {
      Log.e("MediaPipe", "Failed to extract mask buffer: ${e.message}")
      null
    }
  }

  private fun fastBlur(source: Bitmap, radius: Int): Bitmap {
    if (radius < 1) return source
    val bitmap = source.copy(source.config ?: Bitmap.Config.ARGB_8888, true)
    val w = bitmap.width
    val h = bitmap.height
    val pixels = IntArray(w * h)
    bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

    var rsum: Int
    var gsum: Int
    var bsum: Int
    val div = radius + radius + 1
    val wMinus = w - 1
    val hMinus = h - 1
    val vmin = IntArray(max(w, h))
    var yi = 0
    var yw = 0
    val dv = IntArray(256 * div)
    for (i in dv.indices) {
      dv[i] = i / div
    }

    var stackPointer: Int
    var stackStart: Int
    var sir: IntArray
    val stack = Array(div) { IntArray(3) }
    var rbs: Int
    val r1 = radius + 1

    var x = 0
    while (x < w) {
      rsum = 0
      gsum = 0
      bsum = 0
      var rinsum = 0
      var ginsum = 0
      var binsum = 0
      var routsum = 0
      var goutsum = 0
      var boutsum = 0
      var y = -radius
      while (y <= radius) {
        val p = pixels[yi + min(wMinus, max(y, 0))]
        sir = stack[y + radius]
        sir[0] = (p and 0xff0000) shr 16
        sir[1] = (p and 0x00ff00) shr 8
        sir[2] = (p and 0x0000ff)
        rbs = r1 - kotlin.math.abs(y)
        rsum += sir[0] * rbs
        gsum += sir[1] * rbs
        bsum += sir[2] * rbs
        if (y > 0) {
          rinsum += sir[0]
          ginsum += sir[1]
          binsum += sir[2]
        } else {
          routsum += sir[0]
          goutsum += sir[1]
          boutsum += sir[2]
        }
        y++
      }
      stackPointer = radius
      y = 0
      while (y < h) {
        pixels[yi] = (0xff000000.toInt() or (dv[rsum] shl 16) or (dv[gsum] shl 8) or dv[bsum])
        rsum -= routsum
        gsum -= goutsum
        bsum -= boutsum
        stackStart = stackPointer - radius + div
        sir = stack[stackStart % div]
        routsum -= sir[0]
        goutsum -= sir[1]
        boutsum -= sir[2]
        if (x == 0) {
          vmin[y] = min(y + r1, hMinus) * w
        }
        val p = x + vmin[y]
        sir[0] = (pixels[p] and 0xff0000) shr 16
        sir[1] = (pixels[p] and 0x00ff00) shr 8
        sir[2] = (pixels[p] and 0x0000ff)
        rinsum += sir[0]
        ginsum += sir[1]
        binsum += sir[2]
        rsum += rinsum
        gsum += ginsum
        bsum += binsum
        stackPointer = (stackPointer + 1) % div
        sir = stack[stackPointer]
        routsum += sir[0]
        goutsum += sir[1]
        boutsum += sir[2]
        rinsum -= sir[0]
        ginsum -= sir[1]
        binsum -= sir[2]
        yi += w
        y++
      }
      x++
      yi = ++x
    }

    x = 0
    while (x < w) {
      rsum = 0
      gsum = 0
      bsum = 0
      var rinsum = 0
      var ginsum = 0
      var binsum = 0
      var routsum = 0
      var goutsum = 0
      var boutsum = 0
      var y = -radius
      yi = -radius * w
      while (y <= radius) {
        val p = x + max(0, yi)
        sir = stack[y + radius]
        sir[0] = (pixels[p] and 0xff0000) shr 16
        sir[1] = (pixels[p] and 0x00ff00) shr 8
        sir[2] = (pixels[p] and 0x0000ff)
        rbs = r1 - kotlin.math.abs(y)
        rsum += sir[0] * rbs
        gsum += sir[1] * rbs
        bsum += sir[2] * rbs
        if (y > 0) {
          rinsum += sir[0]
          ginsum += sir[1]
          binsum += sir[2]
        } else {
          routsum += sir[0]
          goutsum += sir[1]
          boutsum += sir[2]
        }
        if (y < hMinus) {
          yi += w
        }
        y++
      }
      stackPointer = radius
      y = 0
      while (y < h) {
        val pos = x + y * w
        pixels[pos] = (0xff000000.toInt() or (dv[rsum] shl 16) or (dv[gsum] shl 8) or dv[bsum])
        rsum -= routsum
        gsum -= goutsum
        bsum -= boutsum
        stackStart = stackPointer - radius + div
        sir = stack[stackStart % div]
        routsum -= sir[0]
        goutsum -= sir[1]
        boutsum -= sir[2]
        if (x == 0) {
          vmin[y] = min(y + r1, hMinus) * w
        }
        val p = x + vmin[y]
        sir[0] = (pixels[p] and 0xff0000) shr 16
        sir[1] = (pixels[p] and 0x00ff00) shr 8
        sir[2] = (pixels[p] and 0x0000ff)
        rinsum += sir[0]
        ginsum += sir[1]
        binsum += sir[2]
        rsum += rinsum
        gsum += ginsum
        bsum += binsum
        stackPointer = (stackPointer + 1) % div
        sir = stack[stackPointer]
        routsum += sir[0]
        goutsum += sir[1]
        boutsum += sir[2]
        rinsum -= sir[0]
        ginsum -= sir[1]
        binsum -= sir[2]
        y++
      }
      x++
    }

    bitmap.setPixels(pixels, 0, w, 0, 0, w, h)
    return bitmap
  }

  private fun i420ToBitmap(buffer: VideoFrame.I420Buffer): Bitmap {
    val width = buffer.width
    val height = buffer.height
    val argb = IntArray(width * height)
    val yBuffer = buffer.dataY
    val uBuffer = buffer.dataU
    val vBuffer = buffer.dataV
    val yStride = buffer.strideY
    val uStride = buffer.strideU
    val vStride = buffer.strideV

    var index = 0
    for (y in 0 until height) {
      val yRow = yStride * y
      val uRow = uStride * (y / 2)
      val vRow = vStride * (y / 2)
      for (x in 0 until width) {
        val yValue = (yBuffer.get(yRow + x).toInt() and 0xFF) - 16
        val uValue = (uBuffer.get(uRow + (x / 2)).toInt() and 0xFF) - 128
        val vValue = (vBuffer.get(vRow + (x / 2)).toInt() and 0xFF) - 128

        val yClamped = if (yValue < 0) 0 else yValue
        var r = (298 * yClamped + 409 * vValue + 128) shr 8
        var g = (298 * yClamped - 100 * uValue - 208 * vValue + 128) shr 8
        var b = (298 * yClamped + 516 * uValue + 128) shr 8

        if (r < 0) r = 0 else if (r > 255) r = 255
        if (g < 0) g = 0 else if (g > 255) g = 255
        if (b < 0) b = 0 else if (b > 255) b = 255

        argb[index++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
      }
    }

    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    bitmap.setPixels(argb, 0, width, 0, 0, width, height)
    return bitmap
  }

  private fun bitmapToI420(bitmap: Bitmap): VideoFrame.I420Buffer {
    val width = bitmap.width
    val height = bitmap.height
    val argb = IntArray(width * height)
    bitmap.getPixels(argb, 0, width, 0, 0, width, height)

    val buffer = JavaI420Buffer.allocate(width, height)
    val yBuffer = buffer.dataY
    val uBuffer = buffer.dataU
    val vBuffer = buffer.dataV
    val yStride = buffer.strideY
    val uStride = buffer.strideU
    val vStride = buffer.strideV

    for (y in 0 until height) {
      val yIndex = y * yStride
      val argbIndex = y * width
      for (x in 0 until width) {
        val color = argb[argbIndex + x]
        val r = (color shr 16) and 0xFF
        val g = (color shr 8) and 0xFF
        val b = color and 0xFF
        var yValue = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
        if (yValue < 0) yValue = 0 else if (yValue > 255) yValue = 255
        yBuffer.put(yIndex + x, yValue.toByte())
      }
    }

    var y = 0
    while (y < height) {
      val uRow = (y / 2) * uStride
      val vRow = (y / 2) * vStride
      var x = 0
      while (x < width) {
        var rSum = 0
        var gSum = 0
        var bSum = 0
        var count = 0
        for (dy in 0..1) {
          if (y + dy >= height) continue
          val rowIndex = (y + dy) * width
          for (dx in 0..1) {
            if (x + dx >= width) continue
            val color = argb[rowIndex + x + dx]
            rSum += (color shr 16) and 0xFF
            gSum += (color shr 8) and 0xFF
            bSum += color and 0xFF
            count++
          }
        }
        val rAvg = rSum / count
        val gAvg = gSum / count
        val bAvg = bSum / count
        var uValue = ((-38 * rAvg - 74 * gAvg + 112 * bAvg + 128) shr 8) + 128
        var vValue = ((112 * rAvg - 94 * gAvg - 18 * bAvg + 128) shr 8) + 128
        if (uValue < 0) uValue = 0 else if (uValue > 255) uValue = 255
        if (vValue < 0) vValue = 0 else if (vValue > 255) vValue = 255
        uBuffer.put(uRow + (x / 2), uValue.toByte())
        vBuffer.put(vRow + (x / 2), vValue.toByte())
        x += 2
      }
      y += 2
    }

    return buffer
  }

  private fun computeBlurRadius(intensity: Double): Int {
    val clamped = intensity.coerceIn(0.0, 100.0)
    if (clamped <= 0.0) return 0
    return (2.0 + (clamped / 100.0) * 18.0).toInt().coerceAtLeast(1)
  }
}
