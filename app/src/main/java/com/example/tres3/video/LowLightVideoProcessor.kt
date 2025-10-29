package com.example.tres3.video

import android.graphics.Bitmap
import android.util.Log
import com.example.tres3.opencv.OpenCVManager
import livekit.org.webrtc.VideoFrame
import livekit.org.webrtc.VideoProcessor
import livekit.org.webrtc.VideoSink

/**
 * Automatic low-light video enhancement processor
 * - Detects low-light conditions automatically (brightness < 80)
 * - Applies adaptive lighting enhancement using OpenCV
 * - Processes frames in real-time without manual intervention
 * - Gracefully falls back to original frame if processing fails
 */
class LowLightVideoProcessor : VideoProcessor {
    
    private val TAG = "LowLightVideoProcessor"
    private var frameCount = 0
    private var processedCount = 0
    private var sink: VideoSink? = null
    
    override fun onCapturerStarted(success: Boolean) {
        Log.d(TAG, "Capturer started: $success")
    }
    
    override fun onCapturerStopped() {
        Log.d(TAG, "Capturer stopped. Total frames: $frameCount, processed: $processedCount")
    }
    
    override fun onFrameCaptured(frame: VideoFrame) {
        frameCount++
        
        // Process every 5th frame to reduce CPU load (6fps at 30fps input)
        if (frameCount % 5 != 0) {
            sink?.onFrame(frame)
            return
        }
        
        processedCount++
        
        try {
            // Convert VideoFrame to Bitmap via I420
            val i420 = frame.buffer.toI420()
            if (i420 != null) {
                val width = i420.width
                val height = i420.height
                
                // Convert I420 to NV21 to Bitmap
                val nv21 = VideoFrameConverters.i420ToNV21(i420)
                val bitmap = VideoFrameConverters.nv21ToBitmap(nv21, width, height)
                
                // Apply low-light enhancement using OpenCV
                val result = OpenCVManager.enhanceLowLight(bitmap)
                val enhanced = result.processedBitmap
                
                if (enhanced != null && enhanced != bitmap && result.success) {
                    // Convert enhanced Bitmap back to VideoFrame
                    val i420Buffer = VideoFrameConverters.bitmapToI420(enhanced)
                    val processedFrame = VideoFrame(i420Buffer, frame.rotation, frame.timestampNs)
                    
                    // Send processed frame
                    sink?.onFrame(processedFrame)
                    
                    // Cleanup
                    if (enhanced != bitmap) enhanced.recycle()
                    bitmap.recycle()
                    i420.release()
                    processedFrame.release()
                    
                    return
                } else {
                    // Enhancement failed or returned same bitmap
                    bitmap.recycle()
                    i420.release()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing frame: ${e.message}", e)
        }
        
        // Fallback: pass through original frame if processing fails
        sink?.onFrame(frame)
    }
    
    override fun setSink(sink: VideoSink?) {
        this.sink = sink
    }
}

