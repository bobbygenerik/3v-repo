package com.example.tres3.video

import android.content.Context
import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.*
import timber.log.Timber
import kotlin.math.max

/**
 * HighlightMomentDetector - Automatically detect exciting moments in calls
 * 
 * Features:
 * - Emotion-based moment detection (laughter, excitement, surprise)
 * - Audio level spike detection
 * - Multi-participant reaction clustering
 * - Automatic highlight reel creation
 * - Timestamp marking for key moments
 * - Post-call highlight compilation
 * 
 * Detected Moments:
 * - 😂 Laughter: High smile probability + rapid changes
 * - 🎉 Excitement: Multiple participants excited simultaneously
 * - 😮 Surprise: Sudden emotion changes across participants
 * - 👏 Agreement: Multiple positive reactions together
 * - 💡 Insights: Extended focused attention periods
 * 
 * Usage:
 * ```kotlin
 * val detector = HighlightMomentDetector(context)
 * detector.startRecording(callId)
 * detector.processFrame(bitmap, participantId)
 * detector.addAudioLevel(level)
 * val highlights = detector.generateHighlightReel()
 * ```
 */
class HighlightMomentDetector(
    private val context: Context
) {
    // Moment types
    enum class MomentType {
        LAUGHTER,      // Group laughter
        EXCITEMENT,    // High energy moment
        SURPRISE,      // Unexpected reaction
        AGREEMENT,     // Multiple positive reactions
        INSIGHT,       // Extended attention
        CELEBRATION,   // Victory/achievement moment
        DRAMATIC       // Emotional peak
    }

    // Detected highlight moment
    data class HighlightMoment(
        val type: MomentType,
        val timestamp: Long,
        val duration: Long = 5000L,  // Default 5 seconds
        val intensity: Float,  // 0.0-1.0
        val participantIds: List<String>,
        val description: String,
        val audioLevel: Float = 0f,
        val emotionScores: Map<String, Float> = emptyMap()
    )

    // Participant emotion state
    data class ParticipantEmotion(
        val participantId: String,
        val smileProbability: Float,
        val emotionIntensity: Float,
        val timestamp: Long,
        val faceDetected: Boolean = true
    )

    // Highlight reel
    data class HighlightReel(
        val callId: String,
        val moments: List<HighlightMoment>,
        val totalDuration: Long,
        val createdAt: Long = System.currentTimeMillis()
    )

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // ML Kit face detector with emotion classification
    private val faceDetector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
            .setMinFaceSize(0.15f)
            .build()
        FaceDetection.getClient(options)
    }

    // State
    private var currentCallId: String? = null
    private val detectedMoments = mutableListOf<HighlightMoment>()
    private val participantEmotions = mutableMapOf<String, ParticipantEmotion>()
    private val emotionHistory = mutableMapOf<String, MutableList<Float>>()
    private val audioLevels = ArrayDeque<Float>()
    
    private var isRecording = false
    private var recordingStartTime = 0L

    // Callbacks
    var onHighlightDetected: ((HighlightMoment) -> Unit)? = null
    var onIntensityUpdate: ((Float) -> Unit)? = null

    companion object {
        private const val HISTORY_SIZE = 30
        private const val LAUGHTER_THRESHOLD = 0.8f
        private const val EXCITEMENT_THRESHOLD = 0.7f
        private const val AUDIO_SPIKE_THRESHOLD = 0.6f
        private const val MIN_MOMENT_INTERVAL_MS = 10000L  // 10 seconds between moments
        private const val GROUP_REACTION_THRESHOLD = 2  // Min participants for group moment
    }

    init {
        Timber.d("HighlightMomentDetector initialized")
    }

    /**
     * Start recording highlights for a call
     */
    fun startRecording(callId: String) {
        if (isRecording) {
            Timber.w("Already recording, stopping previous session")
            stopRecording()
        }

        currentCallId = callId
        isRecording = true
        recordingStartTime = System.currentTimeMillis()
        
        detectedMoments.clear()
        participantEmotions.clear()
        emotionHistory.clear()
        audioLevels.clear()

        Timber.d("Highlight recording started: $callId")
    }

    /**
     * Stop recording highlights
     */
    fun stopRecording() {
        isRecording = false
        Timber.d("Highlight recording stopped: $currentCallId, moments: ${detectedMoments.size}")
    }

    /**
     * Process video frame for emotion detection
     */
    suspend fun processFrame(frame: Bitmap, participantId: String) = withContext(Dispatchers.Default) {
        if (!isRecording) return@withContext

        try {
            val inputImage = InputImage.fromBitmap(frame, 0)
            
            faceDetector.process(inputImage)
                .addOnSuccessListener { faces ->
                    if (faces.isNotEmpty()) {
                        handleFaceDetection(faces[0], participantId)
                    }
                }
                .addOnFailureListener { e ->
                    Timber.w(e, "Face detection failed for $participantId")
                }
        } catch (e: Exception) {
            Timber.e(e, "Error processing frame")
        }
    }

    /**
     * Handle detected face and emotions
     */
    private fun handleFaceDetection(face: Face, participantId: String) {
        val smileProb = face.smilingProbability ?: 0f
        val leftEyeOpen = face.leftEyeOpenProbability ?: 0.5f
        val rightEyeOpen = face.rightEyeOpenProbability ?: 0.5f

        // Calculate emotion intensity
        val intensity = when {
            smileProb > 0.7f -> smileProb
            leftEyeOpen > 0.9f && rightEyeOpen > 0.9f -> 0.6f  // Surprise
            else -> 0.3f
        }

        val emotion = ParticipantEmotion(
            participantId = participantId,
            smileProbability = smileProb,
            emotionIntensity = intensity,
            timestamp = System.currentTimeMillis()
        )

        participantEmotions[participantId] = emotion

        // Track emotion history
        val history = emotionHistory.getOrPut(participantId) { mutableListOf() }
        history.add(intensity)
        if (history.size > HISTORY_SIZE) {
            history.removeAt(0)
        }

        // Check for moments
        checkForMoments()
    }

    /**
     * Add audio level reading
     */
    fun addAudioLevel(level: Float) {
        if (!isRecording) return

        synchronized(audioLevels) {
            audioLevels.addLast(level)
            if (audioLevels.size > 100) {
                audioLevels.removeFirst()
            }
        }

        // Check for audio spikes
        checkAudioSpike()
    }

    /**
     * Check for highlight moments
     */
    private fun checkForMoments() {
        val currentTime = System.currentTimeMillis()

        // Don't detect moments too frequently
        val lastMoment = detectedMoments.lastOrNull()
        if (lastMoment != null && currentTime - lastMoment.timestamp < MIN_MOMENT_INTERVAL_MS) {
            return
        }

        // Check for laughter (high smile probability across participants)
        checkLaughterMoment(currentTime)

        // Check for excitement (high intensity for multiple participants)
        checkExcitementMoment(currentTime)

        // Check for surprise (sudden emotion spike)
        checkSurpriseMoment(currentTime)
    }

    /**
     * Check for group laughter
     */
    private fun checkLaughterMoment(currentTime: Long) {
        val laughingParticipants = participantEmotions.filter { (_, emotion) ->
            emotion.smileProbability > LAUGHTER_THRESHOLD &&
            currentTime - emotion.timestamp < 2000  // Within last 2 seconds
        }

        if (laughingParticipants.size >= GROUP_REACTION_THRESHOLD) {
            val avgIntensity = laughingParticipants.values.map { it.smileProbability }.average().toFloat()
            val avgAudio = synchronized(audioLevels) { audioLevels.average().toFloat() }

            val moment = HighlightMoment(
                type = MomentType.LAUGHTER,
                timestamp = currentTime,
                duration = 5000L,
                intensity = avgIntensity,
                participantIds = laughingParticipants.keys.toList(),
                description = "Group laughter - ${laughingParticipants.size} participants",
                audioLevel = avgAudio,
                emotionScores = laughingParticipants.mapValues { it.value.smileProbability }
            )

            addMoment(moment)
        }
    }

    /**
     * Check for excitement moment
     */
    private fun checkExcitementMoment(currentTime: Long) {
        val excitedParticipants = participantEmotions.filter { (_, emotion) ->
            emotion.emotionIntensity > EXCITEMENT_THRESHOLD &&
            currentTime - emotion.timestamp < 2000
        }

        if (excitedParticipants.size >= GROUP_REACTION_THRESHOLD) {
            val avgIntensity = excitedParticipants.values.map { it.emotionIntensity }.average().toFloat()

            val moment = HighlightMoment(
                type = MomentType.EXCITEMENT,
                timestamp = currentTime,
                duration = 7000L,
                intensity = avgIntensity,
                participantIds = excitedParticipants.keys.toList(),
                description = "High energy moment - ${excitedParticipants.size} participants excited",
                emotionScores = excitedParticipants.mapValues { it.value.emotionIntensity }
            )

            addMoment(moment)
        }
    }

    /**
     * Check for surprise moment
     */
    private fun checkSurpriseMoment(currentTime: Long) {
        // Detect sudden emotion spikes
        emotionHistory.forEach { (participantId, history) ->
            if (history.size < 10) return@forEach

            val recentAvg = history.takeLast(5).average().toFloat()
            val previousAvg = history.dropLast(5).takeLast(5).average().toFloat()
            val spike = recentAvg - previousAvg

            if (spike > 0.3f) {  // 30% sudden increase
                val moment = HighlightMoment(
                    type = MomentType.SURPRISE,
                    timestamp = currentTime,
                    duration = 4000L,
                    intensity = spike,
                    participantIds = listOf(participantId),
                    description = "Surprise reaction from $participantId",
                    emotionScores = mapOf(participantId to recentAvg)
                )

                addMoment(moment)
            }
        }
    }

    /**
     * Check for audio spike (loud moment)
     */
    private fun checkAudioSpike() {
        val levels = synchronized(audioLevels) { audioLevels.toList() }
        if (levels.size < 20) return

        val recentAvg = levels.takeLast(10).average()
        val previousAvg = levels.dropLast(10).takeLast(10).average()
        val spike = recentAvg - previousAvg

        if (spike > 0.3 && recentAvg > AUDIO_SPIKE_THRESHOLD) {
            val currentTime = System.currentTimeMillis()
            
            val moment = HighlightMoment(
                type = MomentType.DRAMATIC,
                timestamp = currentTime,
                duration = 3000L,
                intensity = recentAvg.toFloat(),
                participantIds = participantEmotions.keys.toList(),
                description = "Loud moment detected (${recentAvg.toFloat()})",
                audioLevel = recentAvg.toFloat()
            )

            addMoment(moment)
        }
    }

    /**
     * Add detected moment
     */
    private fun addMoment(moment: HighlightMoment) {
        detectedMoments.add(moment)
        onHighlightDetected?.invoke(moment)
        
        Timber.d("Highlight detected: ${moment.type} - ${moment.description} (intensity: ${"%.2f".format(moment.intensity)})")
    }

    /**
     * Manually add a moment
     */
    fun addManualMoment(type: MomentType, description: String, duration: Long = 5000L) {
        if (!isRecording) return

        val moment = HighlightMoment(
            type = type,
            timestamp = System.currentTimeMillis(),
            duration = duration,
            intensity = 1.0f,
            participantIds = participantEmotions.keys.toList(),
            description = description
        )

        addMoment(moment)
    }

    /**
     * Generate highlight reel
     */
    fun generateHighlightReel(): HighlightReel? {
        val callId = currentCallId ?: return null

        // Sort moments by intensity
        val topMoments = detectedMoments
            .sortedByDescending { it.intensity }
            .take(10)  // Top 10 moments
            .sortedBy { it.timestamp }  // Chronological order

        val totalDuration = topMoments.sumOf { it.duration }

        return HighlightReel(
            callId = callId,
            moments = topMoments,
            totalDuration = totalDuration
        )
    }

    /**
     * Get moments by type
     */
    fun getMomentsByType(type: MomentType): List<HighlightMoment> {
        return detectedMoments.filter { it.type == type }
    }

    /**
     * Get top moments
     */
    fun getTopMoments(count: Int = 5): List<HighlightMoment> {
        return detectedMoments
            .sortedByDescending { it.intensity }
            .take(count)
    }

    /**
     * Generate highlight summary
     */
    fun generateSummary(): String {
        val reel = generateHighlightReel() ?: return "No highlights recorded"

        return buildString {
            appendLine("═══════════════════════════════════════")
            appendLine("  HIGHLIGHT REEL SUMMARY")
            appendLine("═══════════════════════════════════════")
            appendLine()
            appendLine("Call ID: ${reel.callId}")
            appendLine("Total Highlights: ${reel.moments.size}")
            appendLine("Total Duration: ${reel.totalDuration / 1000}s")
            appendLine()
            appendLine("MOMENTS")
            appendLine("────────────────────────────────────────")
            
            reel.moments.forEachIndexed { index, moment ->
                val timestamp = (moment.timestamp - recordingStartTime) / 1000
                appendLine("${index + 1}. [${timestamp}s] ${moment.type}: ${moment.description}")
                appendLine("   Intensity: ${"%.2f".format(moment.intensity)}, Duration: ${moment.duration / 1000}s")
                appendLine("   Participants: ${moment.participantIds.size}")
            }
            
            appendLine()
            appendLine("BREAKDOWN BY TYPE")
            appendLine("────────────────────────────────────────")
            MomentType.values().forEach { type ->
                val count = getMomentsByType(type).size
                if (count > 0) {
                    appendLine("${type}: $count moments")
                }
            }
        }
    }

    /**
     * Get statistics
     */
    fun getStatistics(): Statistics {
        return Statistics(
            totalMoments = detectedMoments.size,
            laughterMoments = getMomentsByType(MomentType.LAUGHTER).size,
            excitementMoments = getMomentsByType(MomentType.EXCITEMENT).size,
            surpriseMoments = getMomentsByType(MomentType.SURPRISE).size,
            isRecording = isRecording,
            avgIntensity = if (detectedMoments.isNotEmpty()) {
                detectedMoments.map { it.intensity }.average().toFloat()
            } else 0f
        )
    }

    data class Statistics(
        val totalMoments: Int,
        val laughterMoments: Int,
        val excitementMoments: Int,
        val surpriseMoments: Int,
        val isRecording: Boolean,
        val avgIntensity: Float
    )

    /**
     * Export timestamps for video editing
     */
    fun exportTimestamps(): String {
        val reel = generateHighlightReel() ?: return ""

        return buildString {
            appendLine("# Highlight Timestamps for ${reel.callId}")
            appendLine("# Format: timestamp_ms,duration_ms,type,intensity,description")
            appendLine()
            
            reel.moments.forEach { moment ->
                val relativeTimestamp = moment.timestamp - recordingStartTime
                appendLine("${relativeTimestamp},${moment.duration},${moment.type},${"%.2f".format(moment.intensity)},${moment.description}")
            }
        }
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        stopRecording()
        scope.cancel()
        detectedMoments.clear()
        participantEmotions.clear()
        emotionHistory.clear()
        audioLevels.clear()
        onHighlightDetected = null
        onIntensityUpdate = null
        Timber.d("HighlightMomentDetector cleaned up")
    }
}
