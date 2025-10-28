package com.example.tres3.utils

import android.util.Log
import io.livekit.android.room.Room
import io.livekit.android.room.track.LocalAudioTrack
import io.livekit.android.room.track.LocalVideoTrack
import io.livekit.android.room.track.RemoteAudioTrack
import io.livekit.android.room.track.RemoteVideoTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Manages call quality statistics and metrics
 */
class CallStatsManager(
    private val room: Room,
    private val scope: CoroutineScope
) {
    private var statsJob: Job? = null
    private val TAG = "CallStatsManager"
    
    var videoSendBitrate: Double = 0.0
        private set
    var videoRecvBitrate: Double = 0.0
        private set
    var audioSendBitrate: Double = 0.0
        private set
    var audioRecvBitrate: Double = 0.0
        private set
    var videoPacketLoss: Double = 0.0
        private set
    var audioPacketLoss: Double = 0.0
        private set
    var roundTripTime: Double = 0.0
        private set
    var jitter: Double = 0.0
        private set
    var videoResolution: String = "N/A"
        private set
    var videoFps: Int = 0
        private set
    
    var onStatsUpdate: (() -> Unit)? = null
    
    fun startCollecting() {
        stopCollecting()
        statsJob = scope.launch {
            while (isActive) {
                try {
                    collectStats()
                    onStatsUpdate?.invoke()
                    delay(1000)
                } catch (e: Exception) {
                    Log.e(TAG, "Error collecting stats: ${e.message}")
                }
            }
        }
        Log.d(TAG, "Stats collection started")
    }
    
    fun stopCollecting() {
        statsJob?.cancel()
        statsJob = null
        Log.d(TAG, "Stats collection stopped")
    }
    
    private suspend fun collectStats() {
        try {
            val localParticipant = room.localParticipant
            
            val localVideoTrack = localParticipant.getTrackPublication(io.livekit.android.room.track.Track.Source.CAMERA)
                ?.track as? LocalVideoTrack
            
            if (localVideoTrack != null) {
                try {
                    val rtcStats = localVideoTrack.getRTCStats()
                    parseStats(rtcStats) { statsMap ->
                        val type = statsMap["type"] as? String
                        val mediaType = statsMap["mediaType"] as? String
                        if (type == "outbound-rtp" && mediaType == "video") {
                            videoSendBitrate = (statsMap["bytesSent"] as? Number)?.toDouble() ?: 0.0
                            videoResolution = "${statsMap["frameWidth"] ?: "?"}x${statsMap["frameHeight"] ?: "?"}"
                            videoFps = (statsMap["framesPerSecond"] as? Number)?.toInt() ?: 0
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting local video stats: ${e.message}")
                }
            }
            
            val localAudioTrack = localParticipant.getTrackPublication(io.livekit.android.room.track.Track.Source.MICROPHONE)
                ?.track as? LocalAudioTrack
            
            if (localAudioTrack != null) {
                try {
                    val rtcStats = localAudioTrack.getRTCStats()
                    parseStats(rtcStats) { statsMap ->
                        val type = statsMap["type"] as? String
                        val mediaType = statsMap["mediaType"] as? String
                        if (type == "outbound-rtp" && mediaType == "audio") {
                            audioSendBitrate = (statsMap["bytesSent"] as? Number)?.toDouble() ?: 0.0
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting local audio stats: ${e.message}")
                }
            }
            
            val remoteParticipant = room.remoteParticipants.values.firstOrNull()
            if (remoteParticipant != null) {
                val remoteVideoTrack = remoteParticipant.getTrackPublication(io.livekit.android.room.track.Track.Source.CAMERA)
                    ?.track as? RemoteVideoTrack
                
                if (remoteVideoTrack != null) {
                    try {
                        val rtcStats = remoteVideoTrack.getRTCStats()
                        parseStats(rtcStats) { statsMap ->
                            val type = statsMap["type"] as? String
                            val mediaType = statsMap["mediaType"] as? String
                            if (type == "inbound-rtp" && mediaType == "video") {
                                videoRecvBitrate = (statsMap["bytesReceived"] as? Number)?.toDouble() ?: 0.0
                                videoPacketLoss = (statsMap["packetsLost"] as? Number)?.toDouble() ?: 0.0
                                jitter = (statsMap["jitter"] as? Number)?.toDouble() ?: 0.0
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting remote video stats: ${e.message}")
                    }
                }
                
                val remoteAudioTrack = remoteParticipant.getTrackPublication(io.livekit.android.room.track.Track.Source.MICROPHONE)
                    ?.track as? RemoteAudioTrack
                
                if (remoteAudioTrack != null) {
                    try {
                        val rtcStats = remoteAudioTrack.getRTCStats()
                        parseStats(rtcStats) { statsMap ->
                            val type = statsMap["type"] as? String
                            val mediaType = statsMap["mediaType"] as? String
                            if (type == "inbound-rtp" && mediaType == "audio") {
                                audioRecvBitrate = (statsMap["bytesReceived"] as? Number)?.toDouble() ?: 0.0
                                audioPacketLoss = (statsMap["packetsLost"] as? Number)?.toDouble() ?: 0.0
                            }
                            val state = statsMap["state"] as? String
                            if (type == "candidate-pair" && state == "succeeded") {
                                roundTripTime = (statsMap["currentRoundTripTime"] as? Number)?.toDouble() ?: 0.0
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting remote audio stats: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in collectStats: ${e.message}", e)
        }
    }
    
    private fun parseStats(rtcStats: Any?, block: (Map<*, *>) -> Unit) {
        when (rtcStats) {
            is Map<*, *> -> {
                for (value in rtcStats.values) {
                    if (value is Map<*, *>) {
                        block(value)
                    }
                }
            }
            is Iterable<*> -> {
                for (item in rtcStats) {
                    when (item) {
                        is Map<*, *> -> block(item)
                        is Map.Entry<*, *> -> {
                            val value = item.value
                            if (value is Map<*, *>) {
                                block(value)
                            }
                        }
                        is Pair<*, *> -> {
                            val value = item.second
                            if (value is Map<*, *>) {
                                block(value)
                            }
                        }
                    }
                }
            }
        }
    }
    
    fun formatBitrate(bytes: Double): String {
        val kbps = (bytes * 8) / 1000
        return if (kbps > 1000) {
            String.format("%.1f Mbps", kbps / 1000)
        } else {
            String.format("%.0f kbps", kbps)
        }
    }
    
    fun formatLatency(seconds: Double): String {
        return String.format("%.0f ms", seconds * 1000)
    }
    
    fun formatJitter(seconds: Double): String {
        return String.format("%.1f ms", seconds * 1000)
    }
    
    fun formatPacketLoss(packets: Double): String {
        return String.format("%.1f%%", packets)
    }
    
    fun getConnectionQuality(): ConnectionQuality {
        val rttMs = roundTripTime * 1000
        val totalPacketLoss = (videoPacketLoss + audioPacketLoss) / 2
        
        return when {
            rttMs < 50 && totalPacketLoss < 1 -> ConnectionQuality.EXCELLENT
            rttMs < 100 && totalPacketLoss < 2 -> ConnectionQuality.GOOD
            rttMs < 200 && totalPacketLoss < 5 -> ConnectionQuality.FAIR
            else -> ConnectionQuality.POOR
        }
    }
    
    enum class ConnectionQuality {
        EXCELLENT,
        GOOD,
        FAIR,
        POOR
    }
}
