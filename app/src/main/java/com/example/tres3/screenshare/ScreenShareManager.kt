package com.example.tres3.screenshare

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.util.DisplayMetrics
import android.util.Log
import io.livekit.android.room.Room
import io.livekit.android.room.track.LocalVideoTrack
import io.livekit.android.room.track.LocalVideoTrackOptions
import io.livekit.android.room.track.VideoCaptureParameter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Screen sharing manager for LiveKit.
 * 
 * Handles:
 * - Media projection permission requests
 * - Screen capture initialization
 * - Track publishing/unpublishing
 * - Resolution and FPS configuration
 * 
 * Usage:
 * ```
 * val screenShare = ScreenShareManager(context)
 * 
 * // Request permission (from Activity)
 * activity.startActivityForResult(
 *     screenShare.createScreenCaptureIntent(),
 *     SCREEN_SHARE_REQUEST_CODE
 * )
 * 
 * // In onActivityResult:
 * if (resultCode == Activity.RESULT_OK) {
 *     screenShare.startScreenShare(room, resultCode, data)
 * }
 * 
 * // Stop sharing
 * screenShare.stopScreenShare()
 * ```
 */
class ScreenShareManager(private val context: Context) {
    
    companion object {
        const val SCREEN_SHARE_REQUEST_CODE = 1001
        private const val TAG = "ScreenShareManager"
    }
    
    private var mediaProjection: MediaProjection? = null
    private var screenShareTrack: LocalVideoTrack? = null
    private var isSharing = false
    
    private val mediaProjectionManager by lazy {
        context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }
    
    /**
     * Create intent to request screen capture permission
     */
    fun createScreenCaptureIntent(): Intent {
        return mediaProjectionManager.createScreenCaptureIntent()
    }
    
    /**
     * Start screen sharing after permission granted
     */
    suspend fun startScreenShare(
        room: Room,
        resultCode: Int,
        data: Intent?,
        resolution: ScreenResolution = ScreenResolution.HD_720P,
        fps: Int = 15
    ): Boolean = withContext(Dispatchers.Main) {
        try {
            if (isSharing) {
                Log.w(TAG, "Screen share already active")
                return@withContext false
            }
            
            if (data == null) {
                Log.e(TAG, "Screen capture data is null")
                return@withContext false
            }
            
            // Get media projection
            mediaProjection = mediaProjectionManager.getMediaProjection(resultCode, data)
            if (mediaProjection == null) {
                Log.e(TAG, "Failed to get MediaProjection")
                return@withContext false
            }
            
            // Get display metrics
            val displayMetrics = context.resources.displayMetrics
            val screenWidth = resolution.width
            val screenHeight = resolution.height
            val screenDensity = displayMetrics.densityDpi
            
            Log.d(TAG, "Starting screen share: ${screenWidth}x${screenHeight} @ ${fps}fps, density=$screenDensity")
            
            // Create screen capture track options
            val options = LocalVideoTrackOptions(
                captureParams = VideoCaptureParameter(
                    width = screenWidth,
                    height = screenHeight,
                    maxFps = fps
                )
            )
            
            // Create screen capture track
            screenShareTrack = room.localParticipant.createScreencastTrack(
                name = "screen_share",
                mediaProjectionPermissionResultData = data,
                options = options,
                onStop = {
                    Log.d(TAG, "Screen capture stopped by system")
                    isSharing = false
                }
            )
            
            if (screenShareTrack == null) {
                Log.e(TAG, "Failed to create screen capture track")
                stopScreenShare()
                return@withContext false
            }
            
            // Publish screen share track
            room.localParticipant.publishVideoTrack(screenShareTrack!!)
            
            isSharing = true
            Log.d(TAG, "Screen share started successfully")
            return@withContext true
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting screen share: ${e.message}", e)
            stopScreenShare()
            return@withContext false
        }
    }
    
    /**
     * Stop screen sharing
     */
    suspend fun stopScreenShare() = withContext(Dispatchers.Main) {
        try {
            Log.d(TAG, "Stopping screen share")
            
            screenShareTrack?.let { track ->
                track.stop()
                screenShareTrack = null
            }
            
            mediaProjection?.stop()
            mediaProjection = null
            
            isSharing = false
            Log.d(TAG, "Screen share stopped")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping screen share: ${e.message}", e)
        }
    }
    
    /**
     * Check if currently sharing screen
     */
    fun isScreenSharing(): Boolean = isSharing
    
    /**
     * Get current screen share track
     */
    fun getScreenShareTrack(): LocalVideoTrack? = screenShareTrack
    
    /**
     * Cleanup resources
     */
    fun cleanup() {
        screenShareTrack?.stop()
        screenShareTrack = null
        mediaProjection?.stop()
        mediaProjection = null
        isSharing = false
        Log.d(TAG, "ScreenShareManager cleaned up")
    }
    
    /**
     * Predefined screen resolutions
     */
    enum class ScreenResolution(val width: Int, val height: Int) {
        HD_720P(1280, 720),
        FULL_HD_1080P(1920, 1080),
        QHD_1440P(2560, 1440),
        CUSTOM(0, 0); // Use device native resolution
        
        companion object {
            fun fromDisplayMetrics(metrics: DisplayMetrics): ScreenResolution {
                val width = metrics.widthPixels
                val height = metrics.heightPixels
                
                return when {
                    width <= 1280 -> HD_720P
                    width <= 1920 -> FULL_HD_1080P
                    else -> QHD_1440P
                }
            }
        }
    }
}
