package com.example.tres3.utils

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

/**
 * Manages live captions using OpenAI Whisper API
 * - Captures audio chunks from microphone
 * - Sends to Whisper API for transcription
 * - Displays transcribed text in real-time
 * 
 * Note: Requires OPENAI_API_KEY to be configured in local.properties or environment
 */
class CaptionManager(
    private val context: Context,
    private val scope: CoroutineScope
) {
    private var captureJob: Job? = null
    private var audioRecord: AudioRecord? = null
    private val TAG = "CaptionManager"
    
    // Configuration
    private val sampleRate = 16000 // Whisper prefers 16kHz
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private val chunkDurationMs = 5000L // 5 seconds per chunk
    
    // API configuration
    private val apiKey: String? by lazy {
        // Try to get from BuildConfig or local.properties
        try {
            val properties = java.util.Properties()
            val localPropsFile = File(context.filesDir.parentFile?.parentFile?.parentFile, "local.properties")
            if (localPropsFile.exists()) {
                properties.load(localPropsFile.inputStream())
                properties.getProperty("OPENAI_API_KEY")
            } else {
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not load OPENAI_API_KEY: ${e.message}")
            null
        }
    }
    
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    
    // Callback for caption updates
    var onCaptionReceived: ((String) -> Unit)? = null
    
    /**
     * Start capturing audio and generating captions
     */
    fun startCaptions() {
        if (apiKey == null) {
            Log.w(TAG, "⚠️ OPENAI_API_KEY not configured. Captions disabled.")
            onCaptionReceived?.invoke("[Captions unavailable - API key not configured]")
            return
        }
        
        stopCaptions()
        
        captureJob = scope.launch(Dispatchers.IO) {
            try {
                val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
                
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize * 2
                )
                
                audioRecord?.startRecording()
                Log.d(TAG, "🎤 Started audio capture for captions")
                
                val chunkSize = (sampleRate * 2 * (chunkDurationMs / 1000.0)).toInt() // 16-bit = 2 bytes
                val buffer = ByteArray(chunkSize)
                
                while (isActive) {
                    // Read audio chunk
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    
                    if (read > 0) {
                        // Save to temporary WAV file
                        val audioFile = saveAudioChunk(buffer, read)
                        
                        // Transcribe with Whisper
                        val transcript = transcribeAudio(audioFile)
                        
                        if (transcript.isNotBlank()) {
                            withContext(Dispatchers.Main) {
                                onCaptionReceived?.invoke(transcript)
                            }
                        }
                        
                        // Clean up temp file
                        audioFile.delete()
                    }
                    
                    delay(100) // Small delay between chunks
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error capturing audio: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    onCaptionReceived?.invoke("[Caption error: ${e.message}]")
                }
            }
        }
        
        Log.d(TAG, "📝 Caption capture started")
    }
    
    /**
     * Stop capturing and generating captions
     */
    fun stopCaptions() {
        captureJob?.cancel()
        captureJob = null
        
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping audio record: ${e.message}")
        }
        
        Log.d(TAG, "📝 Caption capture stopped")
    }
    
    /**
     * Save audio chunk as WAV file
     */
    private fun saveAudioChunk(data: ByteArray, size: Int): File {
        val file = File(context.cacheDir, "audio_chunk_${System.currentTimeMillis()}.wav")
        
        FileOutputStream(file).use { fos ->
            // Write WAV header
            writeWavHeader(fos, size, sampleRate, 1) // Mono
            
            // Write audio data
            fos.write(data, 0, size)
        }
        
        return file
    }
    
    /**
     * Write WAV file header
     */
    private fun writeWavHeader(fos: FileOutputStream, dataSize: Int, sampleRate: Int, channels: Int) {
        val header = ByteArray(44)
        val byteRate = sampleRate * channels * 2 // 16-bit
        
        // RIFF header
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()
        
        // File size
        val fileSize = dataSize + 36
        header[4] = (fileSize and 0xff).toByte()
        header[5] = ((fileSize shr 8) and 0xff).toByte()
        header[6] = ((fileSize shr 16) and 0xff).toByte()
        header[7] = ((fileSize shr 24) and 0xff).toByte()
        
        // WAVE header
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()
        
        // fmt subchunk
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()
        header[16] = 16 // Subchunk1Size (16 for PCM)
        header[17] = 0
        header[18] = 0
        header[19] = 0
        header[20] = 1 // AudioFormat (1 for PCM)
        header[21] = 0
        header[22] = channels.toByte()
        header[23] = 0
        
        // Sample rate
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()
        
        // Byte rate
        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()
        
        // Block align
        header[32] = (channels * 2).toByte()
        header[33] = 0
        
        // Bits per sample
        header[34] = 16
        header[35] = 0
        
        // data subchunk
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()
        
        // Data size
        header[40] = (dataSize and 0xff).toByte()
        header[41] = ((dataSize shr 8) and 0xff).toByte()
        header[42] = ((dataSize shr 16) and 0xff).toByte()
        header[43] = ((dataSize shr 24) and 0xff).toByte()
        
        fos.write(header)
    }
    
    /**
     * Transcribe audio file using OpenAI Whisper API
     */
    private suspend fun transcribeAudio(audioFile: File): String = withContext(Dispatchers.IO) {
        try {
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "file",
                    audioFile.name,
                    audioFile.asRequestBody("audio/wav".toMediaType())
                )
                .addFormDataPart("model", "whisper-1")
                .addFormDataPart("language", "en") // Can be made configurable
                .build()
            
            val request = Request.Builder()
                .url("https://api.openai.com/v1/audio/transcriptions")
                .header("Authorization", "Bearer $apiKey")
                .post(requestBody)
                .build()
            
            val response = httpClient.newCall(request).execute()
            
            if (response.isSuccessful) {
                val responseBody = response.body?.string() ?: ""
                val json = JSONObject(responseBody)
                val text = json.optString("text", "")
                
                Log.d(TAG, "✅ Transcribed: $text")
                return@withContext text.trim()
            } else {
                val error = response.body?.string() ?: "Unknown error"
                Log.e(TAG, "❌ Whisper API error: ${response.code} - $error")
                return@withContext ""
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error transcribing audio: ${e.message}", e)
            return@withContext ""
        }
    }
}
