package com.tres3.videochat

import android.content.Context
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.NoiseSuppressor
import android.util.Log
import com.google.ai.edge.litert.Interpreter
import com.google.ai.edge.litert.gpu.GpuDelegate
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * LiteRT-backed audio processor.
 *
 * Provides two layers of audio enhancement for in-call audio:
 *
 *  1. Hardware-accelerated layer — Android AudioEffect APIs:
 *       - NoiseSuppressor  (DSP noise suppression on supported devices)
 *       - LoudnessEnhancer (boosts perceived volume without clipping)
 *
 *  2. LiteRT inference layer:
 *       - Voice Activity Detection (VAD) using yamnet_lite.tflite
 *         → can gate aggressive suppression so it only fires during speech silences
 *       - Audio quality scoring to surface stats to the Flutter layer
 *
 * Note: WebRTC's own NS/EC/AGC pipeline (configured in EnhancedAudioProcessor.dart)
 * runs independently of this class.  This class augments that pipeline at the
 * platform level using the Android AudioEffect framework.
 *
 * Usage:
 *   val processor = LiteRTAudioProcessor(context)
 *   processor.attach(audioSessionId)  // call after WebRTC audio session starts
 *   processor.setNoiseSuppression(true)
 *   processor.setLoudnessGain(500)    // mB, 0 = off, max ~900
 *   ...
 *   processor.detach()
 *   processor.dispose()
 */
class LiteRTAudioProcessor(private val context: Context) {

    companion object {
        private const val TAG = "LiteRTAudioProcessor"
        // Audio frame size for VAD: 16kHz, mono, 32ms window
        private const val VAD_FRAME_SAMPLES = 512
        private const val VAD_THRESHOLD = 0.6f
    }

    // ── Hardware AudioEffects ─────────────────────────────────────────────────
    private var noiseSuppressor: NoiseSuppressor? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var audioSessionId: Int = -1

    // ── LiteRT VAD ────────────────────────────────────────────────────────────
    private var vadInterpreter: Interpreter? = null
    private var gpuDelegate: GpuDelegate? = null

    // ── State ─────────────────────────────────────────────────────────────────
    var noiseSuppressorEnabled = false
        private set
    var loudnessEnhancerEnabled = false
        private set
    var loudnessGainMb = 0
        private set
    var vadEnabled = false
        private set

    init {
        loadVadModel()
    }

    // ── Model loading ─────────────────────────────────────────────────────────

    private fun loadVadModel() {
        gpuDelegate = try { GpuDelegate() } catch (e: Exception) { null }

        val opts = Interpreter.Options().apply {
            if (gpuDelegate != null) addDelegate(gpuDelegate!!)
            numThreads = 1
        }
        vadInterpreter = try {
            val afd = context.assets.openFd("models/vad_lite.tflite")
            val buf = FileInputStream(afd.fileDescriptor).channel.map(
                java.nio.channels.FileChannel.MapMode.READ_ONLY,
                afd.startOffset,
                afd.declaredLength,
            )
            Interpreter(buf, opts)
        } catch (e: Exception) {
            Log.d(TAG, "VAD model not found: ${e.message}")
            null
        }

        if (vadInterpreter == null) Log.w(TAG, "VAD model unavailable — VAD feature disabled")
    }

    // ── Session management ────────────────────────────────────────────────────

    /**
     * Attach AudioEffect processors to an active WebRTC audio session.
     * Call this once the WebRTC audio track is created and its session ID is known.
     */
    fun attach(sessionId: Int) {
        if (sessionId <= 0) {
            Log.w(TAG, "Invalid audio session ID $sessionId — skipping attachment")
            return
        }
        audioSessionId = sessionId
        Log.d(TAG, "Attaching audio processors to session $sessionId")

        if (NoiseSuppressor.isAvailable()) {
            noiseSuppressor = NoiseSuppressor.create(sessionId)
            Log.d(TAG, "NoiseSuppressor attached (hardware)")
        } else {
            Log.w(TAG, "NoiseSuppressor not available on this device")
        }

        loudnessEnhancer = LoudnessEnhancer(sessionId)
        Log.d(TAG, "LoudnessEnhancer attached")

        // Apply any pending settings
        applyNoiseSuppression()
        applyLoudnessGain()
    }

    fun detach() {
        noiseSuppressor?.release()
        loudnessEnhancer?.release()
        noiseSuppressor = null
        loudnessEnhancer = null
        audioSessionId = -1
    }

    // ── Noise suppression ─────────────────────────────────────────────────────

    fun setNoiseSuppression(enabled: Boolean) {
        noiseSuppressorEnabled = enabled
        applyNoiseSuppression()
    }

    private fun applyNoiseSuppression() {
        try {
            noiseSuppressor?.enabled = noiseSuppressorEnabled
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set NoiseSuppressor: ${e.message}")
        }
    }

    // ── Loudness enhancement ──────────────────────────────────────────────────

    fun setLoudnessGain(gainMb: Int) {
        loudnessGainMb = gainMb.coerceIn(0, 900)
        loudnessEnhancerEnabled = loudnessGainMb > 0
        applyLoudnessGain()
    }

    private fun applyLoudnessGain() {
        try {
            val le = loudnessEnhancer ?: return
            le.setTargetGain(loudnessGainMb)
            le.enabled = loudnessEnhancerEnabled
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set LoudnessEnhancer: ${e.message}")
        }
    }

    // ── VAD ───────────────────────────────────────────────────────────────────

    fun setVadEnabled(enabled: Boolean) {
        vadEnabled = enabled && (vadInterpreter != null)
    }

    /**
     * Run VAD inference on a single audio frame (float PCM, 16 kHz mono).
     * Returns true if speech is detected.
     * Call from audio thread; frame must be [VAD_FRAME_SAMPLES] samples.
     */
    fun detectVoiceActivity(pcmFrame: FloatArray): Boolean {
        val interp = vadInterpreter ?: return true  // default: assume speech
        if (!vadEnabled) return true

        val inputBuf = ByteBuffer.allocateDirect(VAD_FRAME_SAMPLES * 4)
            .apply { order(ByteOrder.nativeOrder()) }
        for (sample in pcmFrame.take(VAD_FRAME_SAMPLES)) inputBuf.putFloat(sample)
        inputBuf.rewind()

        val outputBuf = ByteBuffer.allocateDirect(4)
            .apply { order(ByteOrder.nativeOrder()) }

        return try {
            interp.run(inputBuf, outputBuf)
            outputBuf.rewind()
            outputBuf.float >= VAD_THRESHOLD
        } catch (e: Exception) {
            Log.e(TAG, "VAD inference error: ${e.message}")
            true
        }
    }

    // ── Quality metrics ───────────────────────────────────────────────────────

    /** Returns a snapshot of current processor state for Flutter-side reporting. */
    fun getStats(): Map<String, Any> = mapOf(
        "noiseSuppressorAvailable" to (NoiseSuppressor.isAvailable()),
        "noiseSuppressorEnabled" to noiseSuppressorEnabled,
        "loudnessEnhancerEnabled" to loudnessEnhancerEnabled,
        "loudnessGainMb" to loudnessGainMb,
        "vadAvailable" to (vadInterpreter != null),
        "vadEnabled" to vadEnabled,
        "audioSessionAttached" to (audioSessionId > 0),
    )

    // ── Capabilities ─────────────────────────────────────────────────────────

    fun capabilities(): Map<String, Boolean> = mapOf(
        "hardwareNoiseSuppressor" to NoiseSuppressor.isAvailable(),
        "loudnessEnhancer" to true,
        "vad" to (vadInterpreter != null),
    )

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    fun dispose() {
        detach()
        vadInterpreter?.close()
        gpuDelegate?.close()
        vadInterpreter = null
        gpuDelegate = null
    }
}
