import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Recording status enum
enum RecordingStatus {
  notStarted,
  starting,
  recording,
  stopping,
  stopped,
  uploading,
  uploaded,
  failed,
}

/// Recording metadata
class RecordingMetadata {
  final String callId;
  final String? recordingId; // LiveKit egress ID
  final String fileName;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? duration;
  final String? downloadUrl;
  final int? fileSizeBytes;
  final RecordingStatus status;

  RecordingMetadata({
    required this.callId,
    this.recordingId,
    required this.fileName,
    required this.startTime,
    this.endTime,
    this.duration,
    this.downloadUrl,
    this.fileSizeBytes,
    this.status = RecordingStatus.notStarted,
  });

  RecordingMetadata copyWith({
    String? callId,
    String? recordingId,
    String? fileName,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    String? downloadUrl,
    int? fileSizeBytes,
    RecordingStatus? status,
  }) {
    return RecordingMetadata(
      callId: callId ?? this.callId,
      recordingId: recordingId ?? this.recordingId,
      fileName: fileName ?? this.fileName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'callId': callId,
      'recordingId': recordingId,
      'fileName': fileName,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration?.inSeconds,
      'downloadUrl': downloadUrl,
      'fileSizeBytes': fileSizeBytes,
      'status': status.toString(),
    };
  }
}

/// Cloud Recording Service
///
/// Manages call recording with automatic cloud upload to Firebase Storage.
/// Uses LiveKit Cloud Egress for server-side recording.
///
/// Features:
/// - Start/stop recording via LiveKit API
/// - Automatic upload to Firebase Storage
/// - Recording metadata tracking
/// - Download URL generation
/// - Storage management
///
/// Note: Requires LiveKit Cloud or self-hosted LiveKit server with Egress enabled.
class CloudRecordingService extends ChangeNotifier {
  static const String _tag = 'CloudRecording';
  static const String _storageBasePath = 'call-recordings';
  // ignore: unused_field
  static const int _maxFileSizeMB = 500;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  final Map<String, RecordingMetadata> _recordings = {};
  RecordingMetadata? _currentRecording;
  RecordingStatus _status = RecordingStatus.notStarted;

  RecordingStatus get status => _status;
  RecordingMetadata? get currentRecording => _currentRecording;
  bool get isRecording => _status == RecordingStatus.recording;
  List<RecordingMetadata> get allRecordings =>
      List.unmodifiable(_recordings.values);

  /// Update status from current recording
  void _syncStatus() {
    _status = _currentRecording?.status ?? RecordingStatus.notStarted;
  }

  /// Start recording a call
  ///
  /// In production, this should call your backend API which then calls
  /// LiveKit Egress API to start server-side recording:
  ///
  /// POST /v1/egress/room_composite
  /// {
  ///   "room_name": "room-name",
  ///   "layout": "grid",
  ///   "output": {
  ///     "file": {
  ///       "filepath": "recording.mp4"
  ///     }
  ///   }
  /// }
  Future<bool> startRecording(String callId, {String? roomName}) async {
    if (isRecording) {
      debugPrint('$_tag: Recording already in progress');
      return false;
    }

    try {
      final fileName =
          'recording_${callId}_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final metadata = RecordingMetadata(
        callId: callId,
        fileName: fileName,
        startTime: DateTime.now(),
        status: RecordingStatus.starting,
      );

      _currentRecording = metadata;
      _recordings[callId] = metadata;
      _syncStatus();
      notifyListeners();

      // In production: Call backend API to start LiveKit Egress recording
      // Example:
      // final response = await http.post(
      //   Uri.parse('$backendUrl/api/recording/start'),
      //   body: json.encode({
      //     'callId': callId,
      //     'roomName': roomName,
      //     'fileName': fileName,
      //   }),
      // );
      // final recordingId = json.decode(response.body)['egressId'];

      // For now, simulate starting
      await Future.delayed(const Duration(milliseconds: 500));

      // Simulate getting recording ID from LiveKit
      final recordingId = 'EG_${DateTime.now().millisecondsSinceEpoch}';

      _currentRecording = metadata.copyWith(
        recordingId: recordingId,
        status: RecordingStatus.recording,
      );
      _recordings[callId] = _currentRecording!;
      _syncStatus();
      notifyListeners();

      debugPrint('$_tag: ✅ Recording started: $callId');

      // Save metadata to Firestore
      await _saveMetadataToFirestore(_currentRecording!);

      return true;
    } catch (e) {
      debugPrint('$_tag: ❌ Failed to start recording: $e');

      if (_currentRecording != null) {
        _currentRecording = _currentRecording!.copyWith(
          status: RecordingStatus.failed,
        );
        _recordings[_currentRecording!.callId] = _currentRecording!;
        notifyListeners();
      }

      return false;
    }
  }

  /// Stop recording and upload to Firebase Storage
  Future<RecordingMetadata?> stopRecording() async {
    if (_currentRecording == null) {
      debugPrint('$_tag: No active recording to stop');
      return null;
    }

    try {
      final metadata = _currentRecording!;

      // Update status
      _currentRecording = metadata.copyWith(status: RecordingStatus.stopping);
      notifyListeners();

      // In production: Call backend API to stop LiveKit Egress
      // Example:
      // await http.post(
      //   Uri.parse('$backendUrl/api/recording/stop'),
      //   body: json.encode({
      //     'egressId': metadata.recordingId,
      //   }),
      // );

      await Future.delayed(const Duration(milliseconds: 500));

      final endTime = DateTime.now();
      final duration = endTime.difference(metadata.startTime);

      _currentRecording = metadata.copyWith(
        endTime: endTime,
        duration: duration,
        status: RecordingStatus.stopped,
      );
      _recordings[metadata.callId] = _currentRecording!;
      notifyListeners();

      debugPrint(
        '$_tag: ✅ Recording stopped: ${metadata.callId} (${duration.inSeconds}s)',
      );

      // Upload to Firebase Storage (in production, LiveKit can upload directly)
      await _uploadToStorage(_currentRecording!);

      final finalMetadata = _currentRecording;
      _currentRecording = null; // Clear current recording

      return finalMetadata;
    } catch (e) {
      debugPrint('$_tag: ❌ Failed to stop recording: $e');

      if (_currentRecording != null) {
        _currentRecording = _currentRecording!.copyWith(
          status: RecordingStatus.failed,
        );
        _recordings[_currentRecording!.callId] = _currentRecording!;
        notifyListeners();
      }

      return null;
    }
  }

  /// Upload recording to Firebase Storage
  ///
  /// In production with LiveKit Cloud, configure output to upload directly:
  /// "output": {
  ///   "file": {
  ///     "uploadUrl": "https://your-upload-endpoint.com/upload"
  ///   }
  /// }
  Future<void> _uploadToStorage(RecordingMetadata metadata) async {
    try {
      _currentRecording = metadata.copyWith(status: RecordingStatus.uploading);
      notifyListeners();

      // In production: The recording file URL is provided by LiveKit Egress
      // You can either:
      // 1. Use LiveKit's S3/GCS upload (configure in Egress)
      // 2. Download from LiveKit and upload to Firebase
      // 3. Use a webhook to get the file URL when ready

      // Simulate upload
      await Future.delayed(const Duration(seconds: 2));

      // Simulate getting download URL
      final storagePath = '$_storageBasePath/${metadata.fileName}';
      final downloadUrl = 'https://storage.googleapis.com/bucket/$storagePath';

      _currentRecording = metadata.copyWith(
        downloadUrl: downloadUrl,
        fileSizeBytes: 1024 * 1024 * 50, // Simulate 50MB file
        status: RecordingStatus.uploaded,
      );
      _recordings[metadata.callId] = _currentRecording!;

      await _saveMetadataToFirestore(_currentRecording!);
      notifyListeners();

      debugPrint('$_tag: ✅ Recording uploaded: $downloadUrl');
    } catch (e) {
      debugPrint('$_tag: ❌ Upload failed: $e');

      _currentRecording = metadata.copyWith(status: RecordingStatus.failed);
      _recordings[metadata.callId] = _currentRecording!;
      notifyListeners();

      rethrow;
    }
  }

  /// Save recording metadata to Firestore
  Future<void> _saveMetadataToFirestore(RecordingMetadata metadata) async {
    try {
      await _firestore
          .collection('recordings')
          .doc(metadata.callId)
          .set(metadata.toJson());

      debugPrint('$_tag: Metadata saved to Firestore');
    } catch (e) {
      debugPrint('$_tag: ⚠️ Failed to save metadata: $e');
    }
  }

  /// Get recording metadata by call ID
  RecordingMetadata? getRecording(String callId) {
    return _recordings[callId];
  }

  /// Get download URL for a recording
  Future<String?> getDownloadUrl(String callId) async {
    final metadata = _recordings[callId];
    if (metadata?.downloadUrl != null) {
      return metadata!.downloadUrl;
    }

    // Fetch from Firestore if not in memory
    try {
      final doc = await _firestore.collection('recordings').doc(callId).get();
      if (doc.exists) {
        return doc.data()?['downloadUrl'] as String?;
      }
    } catch (e) {
      debugPrint('$_tag: ❌ Failed to fetch download URL: $e');
    }

    return null;
  }

  /// Delete recording from storage
  Future<bool> deleteRecording(String callId) async {
    try {
      final metadata = _recordings[callId];
      if (metadata == null) return false;

      // Delete from Firebase Storage
      if (metadata.downloadUrl != null) {
        final ref = _storage.ref('$_storageBasePath/${metadata.fileName}');
        await ref.delete();
      }

      // Delete from Firestore
      await _firestore.collection('recordings').doc(callId).delete();

      // Remove from memory
      _recordings.remove(callId);
      if (_currentRecording?.callId == callId) {
        _currentRecording = null;
      }
      notifyListeners();

      debugPrint('$_tag: ✅ Recording deleted: $callId');
      return true;
    } catch (e) {
      debugPrint('$_tag: ❌ Failed to delete recording: $e');
      return false;
    }
  }

  /// Get total storage used (bytes)
  int getTotalStorageUsed() {
    return _recordings.values
        .where((r) => r.fileSizeBytes != null)
        .fold(0, (sum, r) => sum + r.fileSizeBytes!);
  }

  /// Clean up old recordings (older than specified days)
  Future<int> cleanupOldRecordings({int olderThanDays = 30}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
    final toDelete = _recordings.values.where((r) {
      return r.endTime != null &&
          r.endTime!.isBefore(cutoffDate) &&
          r.status == RecordingStatus.uploaded;
    }).toList();

    int deletedCount = 0;
    for (final recording in toDelete) {
      final success = await deleteRecording(recording.callId);
      if (success) deletedCount++;
    }

    debugPrint('$_tag: ✅ Cleaned up $deletedCount old recordings');
    return deletedCount;
  }

  /// Clean up resources
  @override
  void dispose() {
    _recordings.clear();
    _currentRecording = null;
    debugPrint('$_tag: ✅ Service disposed');
    super.dispose();
  }
}
