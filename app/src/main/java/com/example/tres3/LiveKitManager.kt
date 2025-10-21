package com.example.tres3

import android.content.Context
import android.util.Log
import io.livekit.android.LiveKit
import io.livekit.android.room.Room
import io.livekit.android.room.track.LocalVideoTrackOptions
import io.livekit.android.room.track.VideoCaptureParameter
import io.livekit.android.util.LoggingLevel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient

object LiveKitManager {
    private val roomMutex = Mutex()
    var currentRoom: Room? = null
    
    /**
     * Video quality presets
     * - HIGH: 720p @ 30fps, H.264 codec - Best quality (~1.5 Mbps)
     * - AUTO: Adaptive bitrate with simulcast - Adjusts to network conditions
     * - LOW: 360p @ 24fps - Works on poor networks (~300 Kbps)
     */
    enum class VideoQuality {
        HIGH, AUTO, LOW
    }
    
    private var currentQuality = VideoQuality.AUTO // Default to AUTO
    
    // Video optimization settings - can be changed dynamically
    private fun getVideoSettings(quality: VideoQuality = currentQuality): LocalVideoTrackOptions {
        val params = when (quality) {
            VideoQuality.HIGH -> VideoCaptureParameter(
                width = 1280,
                height = 720,
                maxFps = 30
            )
            VideoQuality.AUTO -> VideoCaptureParameter(
                width = 1280,
                height = 720,
                maxFps = 30
            )
            VideoQuality.LOW -> VideoCaptureParameter(
                width = 640,
                height = 360,
                maxFps = 24
            )
        }
        
        return LocalVideoTrackOptions(
            captureParams = params
        )
    }
    
    /**
     * Check if simulcast should be enabled for current quality
     */
    private fun shouldEnableSimulcast(): Boolean {
        return currentQuality == VideoQuality.AUTO
    }
    
    /**
     * Change video quality dynamically (call this if user has poor connection)
     * This is called from Settings or can be used to manually adjust quality
     */
    fun setVideoQuality(quality: VideoQuality) {
        currentQuality = quality
        Log.d("LiveKitManager", "📹 Video quality changed to: $quality")
    }
    
    /**
     * Load video quality from SharedPreferences
     */
    fun loadQualityFromSettings(context: Context) {
        val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        val qualityString = prefs.getString("call_quality", "Auto") ?: "Auto"
        
        currentQuality = when (qualityString.lowercase()) {
            "high" -> VideoQuality.HIGH
            "low" -> VideoQuality.LOW
            else -> VideoQuality.AUTO
        }
        
        Log.d("LiveKitManager", "📹 Loaded video quality from settings: $currentQuality")
    }

    suspend fun connectToRoom(context: Context, url: String, token: String): Room {
        // Load quality settings before connecting
        loadQualityFromSettings(context)
        
        return roomMutex.withLock {
            try {
                // Clean up any existing room INSIDE the lock
                val existingRoom = currentRoom
                if (existingRoom != null) {
                    Log.d("LiveKitManager", "connectToRoom: Found existing room, forcing cleanup")
                    currentRoom = null
                    
                    try {
                        // Quick cleanup without delays
                        withContext(Dispatchers.Main) {
                            try {
                                existingRoom.localParticipant.setCameraEnabled(false)
                                existingRoom.localParticipant.setMicrophoneEnabled(false)
                            } catch (e: Exception) {
                                Log.e("LiveKitManager", "Error disabling media: ${e.message}")
                            }
                            existingRoom.disconnect()
                        }
                        
                        existingRoom.release()
                        Log.d("LiveKitManager", "connectToRoom: Cleanup completed")
                    } catch (e: Exception) {
                        Log.e("LiveKitManager", "connectToRoom: Cleanup error: ${e.message}", e)
                    }
                    
                    // Minimal delay for hardware release
                    kotlinx.coroutines.delay(100)
                }
                
                io.livekit.android.LiveKit.loggingLevel = LoggingLevel.WARN // Reduce logging overhead

                Log.d("LiveKitManager", "connectToRoom: Creating new room instance with quality: $currentQuality")
                
                val room = LiveKit.create(
                    appContext = context.applicationContext
                )

                Log.d("LiveKitManager", "connectToRoom: Connecting to room")
                
                // Connect with timeout optimization
                withContext(Dispatchers.IO) {
                    room.connect(url, token)
                }

                currentRoom = room

                Log.d("LiveKitManager", "Successfully connected to room")
                room
            } catch (e: Exception) {
                Log.e("LiveKitManager", "Failed to connect to room: ${e.message}", e)
                throw e
            }
        }
    }
    
    suspend fun disconnectFromRoom() {
        disconnectRoomInternal(currentRoom, clearCurrent = true)
    }

    suspend fun disconnectSpecificRoom(target: Room?) {
        disconnectRoomInternal(target, clearCurrent = (target != null && currentRoom == target))
    }

    private suspend fun disconnectRoomInternal(target: Room?, clearCurrent: Boolean) {
        if (target == null) {
            return
        }

        roomMutex.withLock {
            val room = target

            Log.d("LiveKitManager", "disconnectRoomInternal: starting cleanup for room=${room.name}")

            muteLocalMedia(room)

            Log.d("LiveKitManager", "disconnectRoomInternal: local media muted, proceeding to disconnect")

            try {
                withContext(Dispatchers.Main) {
                    Log.d("LiveKitManager", "disconnectRoomInternal: calling room.disconnect() on thread=${Thread.currentThread().name}")
                    room.disconnect()
                    Log.d("LiveKitManager", "disconnectRoomInternal: room.disconnect() completed")
                }
            } catch (e: Exception) {
                Log.e("LiveKitManager", "Error disconnecting room: ${e.message}", e)
            } finally {
                try {
                    Log.d("LiveKitManager", "disconnectRoomInternal: releasing room resources")
                    room.release()
                    Log.d("LiveKitManager", "disconnectRoomInternal: room.release() completed")
                } catch (releaseError: Exception) {
                    Log.e("LiveKitManager", "Error releasing room: ${releaseError.message}", releaseError)
                }

                if (clearCurrent && currentRoom == room) {
                    currentRoom = null
                }

                Log.d("LiveKitManager", "disconnectRoomInternal: cleanup finished; currentRoomCleared=$clearCurrent")
            }
        }
    }

    private suspend fun muteLocalMedia(room: Room) {
        val participant = room.localParticipant
        try {
            withContext(Dispatchers.Main) {
                participant.setCameraEnabled(false)
            }
        } catch (e: Exception) {
            Log.e("LiveKitManager", "Error disabling camera: ${e.message}", e)
        }

        try {
            withContext(Dispatchers.Main) {
                participant.setMicrophoneEnabled(false)
            }
        } catch (e: Exception) {
            Log.e("LiveKitManager", "Error disabling microphone: ${e.message}", e)
        }
    }
}
