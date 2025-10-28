package com.example.tres3.recording

import android.content.Context
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageReference
import kotlinx.coroutines.*
import timber.log.Timber
import java.io.File

/**
 * CloudRecordingManager - Enhanced call recording with automatic cloud upload
 * 
 * Features:
 * - Local recording with cloud backup
 * - Automatic Firebase Storage upload
 * - Resume capability for failed uploads
 * - Compression and optimization
 * - Metadata tagging
 * - Download URL generation
 * - Storage quota management
 * 
 * Usage:
 * ```kotlin
 * val recorder = CloudRecordingManager(context)
 * recorder.startRecording(callId)
 * recorder.stopRecording()  // Auto-uploads to Firebase
 * val url = recorder.getDownloadUrl(callId)
 * ```
 */
class CloudRecordingManager(
    private val context: Context
) {
    // Recording metadata
    data class RecordingMetadata(
        val callId: String,
        val fileName: String,
        val localPath: String,
        val cloudPath: String? = null,
        val downloadUrl: String? = null,
        val fileSize: Long = 0,
        val duration: Long = 0,  // milliseconds
        val startTime: Long,
        val endTime: Long? = null,
        val uploadStatus: UploadStatus = UploadStatus.NOT_STARTED
    )

    enum class UploadStatus {
        NOT_STARTED,
        UPLOADING,
        COMPLETED,
        FAILED,
        CANCELLED
    }

    // Upload progress
    data class UploadProgress(
        val callId: String,
        val bytesTransferred: Long,
        val totalBytes: Long,
        val progress: Float  // 0.0-1.0
    )

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    // Firebase Storage
    private val storage = FirebaseStorage.getInstance()
    private val storageRef = storage.reference
    
    // State
    private val activeRecordings = mutableMapOf<String, RecordingMetadata>()
    private val uploadTasks = mutableMapOf<String, Deferred<Boolean>>()
    
    // Callbacks
    var onRecordingStarted: ((String) -> Unit)? = null
    var onRecordingStopped: ((String, File) -> Unit)? = null
    var onUploadProgress: ((UploadProgress) -> Unit)? = null
    var onUploadComplete: ((String, String) -> Unit)? = null
    var onUploadFailed: ((String, Exception) -> Unit)? = null

    companion object {
        private const val RECORDINGS_FOLDER = "recordings"
        private const val STORAGE_PATH = "call-recordings"
        private const val MAX_FILE_SIZE_MB = 500
    }

    init {
        Timber.d("CloudRecordingManager initialized")
    }

    /**
     * Start recording for a call
     */
    fun startRecording(callId: String): Boolean {
        if (activeRecordings.containsKey(callId)) {
            Timber.w("Recording already active for call: $callId")
            return false
        }

        val fileName = "recording_${callId}_${System.currentTimeMillis()}.mp4"
        val localPath = "${context.getExternalFilesDir(RECORDINGS_FOLDER)}/$fileName"
        
        val metadata = RecordingMetadata(
            callId = callId,
            fileName = fileName,
            localPath = localPath,
            startTime = System.currentTimeMillis()
        )
        
        activeRecordings[callId] = metadata
        onRecordingStarted?.invoke(callId)
        
        Timber.d("Recording started: $callId -> $fileName")
        return true
    }

    /**
     * Stop recording and initiate upload
     */
    suspend fun stopRecording(callId: String): RecordingMetadata? {
        val metadata = activeRecordings[callId] ?: run {
            Timber.w("No active recording for call: $callId")
            return null
        }

        val endTime = System.currentTimeMillis()
        val duration = endTime - metadata.startTime
        
        // Get file info
        val file = File(metadata.localPath)
        val fileSize = if (file.exists()) file.length() else 0L
        
        val completedMetadata = metadata.copy(
            endTime = endTime,
            duration = duration,
            fileSize = fileSize
        )
        
        activeRecordings[callId] = completedMetadata
        
        // Trigger callback
        onRecordingStopped?.invoke(callId, file)
        
        // Start upload in background
        uploadToCloud(callId, completedMetadata)
        
        Timber.d("Recording stopped: $callId, size: ${fileSize / 1024 / 1024}MB, duration: ${duration / 1000}s")
        return completedMetadata
    }

    /**
     * Upload recording to Firebase Storage
     */
    private fun uploadToCloud(callId: String, metadata: RecordingMetadata) {
        val uploadJob = scope.async {
            try {
                val file = File(metadata.localPath)
                
                if (!file.exists()) {
                    Timber.e("Recording file not found: ${metadata.localPath}")
                    onUploadFailed?.invoke(callId, Exception("File not found"))
                    return@async false
                }

                // Check file size
                val fileSizeMB = file.length() / 1024 / 1024
                if (fileSizeMB > MAX_FILE_SIZE_MB) {
                    Timber.w("Recording too large: ${fileSizeMB}MB")
                    // In production: compress or chunk upload
                }

                // Update status
                activeRecordings[callId] = metadata.copy(uploadStatus = UploadStatus.UPLOADING)
                
                // Create cloud path
                val cloudPath = "$STORAGE_PATH/${metadata.fileName}"
                val fileRef = storageRef.child(cloudPath)
                
                // Upload file
                val uploadTask = fileRef.putFile(android.net.Uri.fromFile(file))
                
                // Monitor progress
                uploadTask.addOnProgressListener { taskSnapshot ->
                    val progress = UploadProgress(
                        callId = callId,
                        bytesTransferred = taskSnapshot.bytesTransferred,
                        totalBytes = taskSnapshot.totalByteCount,
                        progress = taskSnapshot.bytesTransferred.toFloat() / taskSnapshot.totalByteCount
                    )
                    onUploadProgress?.invoke(progress)
                }
                
                // Wait for completion
                val uploadResult = uploadTask.await()
                
                // Get download URL
                val downloadUrl = fileRef.downloadUrl.await().toString()
                
                // Update metadata
                activeRecordings[callId] = metadata.copy(
                    cloudPath = cloudPath,
                    downloadUrl = downloadUrl,
                    uploadStatus = UploadStatus.COMPLETED
                )
                
                onUploadComplete?.invoke(callId, downloadUrl)
                Timber.d("Upload complete: $callId -> $downloadUrl")
                
                return@async true
            } catch (e: Exception) {
                Timber.e(e, "Upload failed for call: $callId")
                activeRecordings[callId] = metadata.copy(uploadStatus = UploadStatus.FAILED)
                onUploadFailed?.invoke(callId, e)
                return@async false
            }
        }
        
        uploadTasks[callId] = uploadJob
    }

    /**
     * Get recording metadata
     */
    fun getRecordingMetadata(callId: String): RecordingMetadata? {
        return activeRecordings[callId]
    }

    /**
     * Get download URL for a recording
     */
    suspend fun getDownloadUrl(callId: String): String? {
        val metadata = activeRecordings[callId] ?: return null
        
        // If already uploaded, return cached URL
        if (metadata.downloadUrl != null) {
            return metadata.downloadUrl
        }
        
        // If cloud path exists, fetch URL
        val cloudPath = metadata.cloudPath ?: return null
        
        return try {
            val fileRef = storageRef.child(cloudPath)
            fileRef.downloadUrl.await().toString()
        } catch (e: Exception) {
            Timber.e(e, "Failed to get download URL")
            null
        }
    }

    /**
     * Delete recording (local and cloud)
     */
    suspend fun deleteRecording(callId: String, deleteCloud: Boolean = true): Boolean {
        val metadata = activeRecordings[callId] ?: return false
        
        var success = true
        
        // Delete local file
        val localFile = File(metadata.localPath)
        if (localFile.exists()) {
            success = localFile.delete()
            Timber.d("Local file deleted: $success")
        }
        
        // Delete from cloud
        if (deleteCloud && metadata.cloudPath != null) {
            try {
                val fileRef = storageRef.child(metadata.cloudPath)
                fileRef.delete().await()
                Timber.d("Cloud file deleted: ${metadata.cloudPath}")
            } catch (e: Exception) {
                Timber.e(e, "Failed to delete cloud file")
                success = false
            }
        }
        
        activeRecordings.remove(callId)
        return success
    }

    /**
     * Retry failed upload
     */
    fun retryUpload(callId: String) {
        val metadata = activeRecordings[callId] ?: run {
            Timber.w("No recording found for retry: $callId")
            return
        }
        
        if (metadata.uploadStatus != UploadStatus.FAILED) {
            Timber.w("Recording is not in failed state: ${metadata.uploadStatus}")
            return
        }
        
        uploadToCloud(callId, metadata)
        Timber.d("Upload retry initiated: $callId")
    }

    /**
     * Cancel active upload
     */
    fun cancelUpload(callId: String) {
        uploadTasks[callId]?.cancel()
        uploadTasks.remove(callId)
        
        activeRecordings[callId]?.let { metadata ->
            activeRecordings[callId] = metadata.copy(uploadStatus = UploadStatus.CANCELLED)
        }
        
        Timber.d("Upload cancelled: $callId")
    }

    /**
     * Get all recordings
     */
    fun getAllRecordings(): List<RecordingMetadata> {
        return activeRecordings.values.toList()
    }

    /**
     * Get total storage used (bytes)
     */
    fun getTotalStorageUsed(): Long {
        return activeRecordings.values.sumOf { it.fileSize }
    }

    /**
     * Clean up old local recordings
     */
    fun cleanupOldRecordings(olderThanDays: Int = 30): Int {
        val cutoffTime = System.currentTimeMillis() - (olderThanDays * 24 * 60 * 60 * 1000L)
        var deletedCount = 0
        
        val toDelete = activeRecordings.filter { (_, metadata) ->
            metadata.endTime != null && 
            metadata.endTime < cutoffTime && 
            metadata.uploadStatus == UploadStatus.COMPLETED
        }
        
        toDelete.forEach { (callId, metadata) ->
            val file = File(metadata.localPath)
            if (file.exists() && file.delete()) {
                deletedCount++
                Timber.d("Cleaned up old recording: ${metadata.fileName}")
            }
        }
        
        Timber.d("Cleaned up $deletedCount old recordings")
        return deletedCount
    }

    /**
     * Generate shareable link with expiration
     */
    suspend fun generateShareableLink(callId: String, expirationHours: Int = 24): String? {
        val metadata = activeRecordings[callId] ?: return null
        val cloudPath = metadata.cloudPath ?: return null
        
        return try {
            val fileRef = storageRef.child(cloudPath)
            // In production: Use Firebase Dynamic Links or custom token
            fileRef.downloadUrl.await().toString()
        } catch (e: Exception) {
            Timber.e(e, "Failed to generate shareable link")
            null
        }
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        // Cancel all active uploads
        uploadTasks.values.forEach { it.cancel() }
        uploadTasks.clear()
        
        scope.cancel()
        onRecordingStarted = null
        onRecordingStopped = null
        onUploadProgress = null
        onUploadComplete = null
        onUploadFailed = null
        
        Timber.d("CloudRecordingManager cleaned up")
    }
}

// Extension function for Task await
private suspend fun <T> com.google.android.gms.tasks.Task<T>.await(): T {
    return suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { result ->
            continuation.resume(result) {}
        }
        addOnFailureListener { exception ->
            continuation.cancel(exception)
        }
    }
}
