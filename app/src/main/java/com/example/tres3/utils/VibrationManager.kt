package com.example.tres3.utils

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Manages haptic feedback patterns for call events
 * - Incoming call: Long repeating pattern
 * - Call connected: Double tap
 * - Call ended: Single long vibration
 */
object VibrationManager {
    
    private const val TAG = "VibrationManager"
    
    // Vibration patterns (timings in milliseconds: [delay, vibrate, delay, vibrate, ...])
    private val INCOMING_CALL_PATTERN = longArrayOf(0, 500, 200, 500, 200, 500) // Triple pulse
    private val CALL_CONNECTED_PATTERN = longArrayOf(0, 100, 50, 100) // Double tap
    private val CALL_ENDED_PATTERN = longArrayOf(0, 300) // Single pulse
    
    /**
     * Vibrate for incoming call (repeats until answered/rejected)
     */
    fun vibrateIncomingCall(context: Context) {
        try {
            val vibrator = getVibrator(context)
            if (vibrator?.hasVibrator() == true) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(
                        INCOMING_CALL_PATTERN,
                        0 // Repeat from index 0 (continuously)
                    )
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(INCOMING_CALL_PATTERN, 0)
                }
                Log.d(TAG, "📳 Incoming call vibration started")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to vibrate for incoming call: ${e.message}")
        }
    }
    
    /**
     * Vibrate when call connects (short double tap)
     */
    fun vibrateCallConnected(context: Context) {
        try {
            val vibrator = getVibrator(context)
            if (vibrator?.hasVibrator() == true) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(
                        CALL_CONNECTED_PATTERN,
                        -1 // Don't repeat
                    )
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(CALL_CONNECTED_PATTERN, -1)
                }
                Log.d(TAG, "📳 Call connected vibration")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to vibrate for call connected: ${e.message}")
        }
    }
    
    /**
     * Vibrate when call ends (single pulse)
     */
    fun vibrateCallEnded(context: Context) {
        try {
            val vibrator = getVibrator(context)
            if (vibrator?.hasVibrator() == true) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(
                        CALL_ENDED_PATTERN,
                        -1 // Don't repeat
                    )
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(CALL_ENDED_PATTERN, -1)
                }
                Log.d(TAG, "📳 Call ended vibration")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to vibrate for call ended: ${e.message}")
        }
    }
    
    /**
     * Cancel any ongoing vibration (e.g., when call is answered)
     */
    fun cancelVibration(context: Context) {
        try {
            val vibrator = getVibrator(context)
            vibrator?.cancel()
            Log.d(TAG, "🔇 Vibration cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel vibration: ${e.message}")
        }
    }
    
    /**
     * Get the vibrator service (handles both old and new API)
     */
    private fun getVibrator(context: Context): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }
}
