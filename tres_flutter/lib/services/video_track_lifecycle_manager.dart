import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:livekit_client/livekit_client.dart';

class VideoTrackLifecycleManager extends ChangeNotifier {
  final Map<String, VideoTrack> _activeTracks = {};
  final Set<String> _recentlyUsedTracks = {};
  final Map<String, Timer> _cleanupTimers = {};
  
  // Lifecycle settings
  Duration _inactiveCleanupDelay = const Duration(minutes: 2);
  Duration _trackUsageWindow = const Duration(minutes: 5);
  int _maxActiveTracks = 8;
  
  // Track usage statistics
  final Map<String, DateTime> _lastUsedTimes = {};
  final Map<String, int> _usageCount = {};
  
  Map<String, VideoTrack> get activeTracks => Map.unmodifiable(_activeTracks);
  int get activeTrackCount => _activeTracks.length;
  bool get isAtCapacity => _activeTracks.length >= _maxActiveTracks;

  void registerTrack(String participantId, VideoTrack track) {
    try {
      // Cancel any existing cleanup timer
      _cleanupTimers[participantId]?.cancel();
      _cleanupTimers.remove(participantId);
      
      // Register the track
      _activeTracks[participantId] = track;
      _recentlyUsedTracks.add(participantId);
      _lastUsedTimes[participantId] = DateTime.now();
      _usageCount[participantId] = (_usageCount[participantId] ?? 0) + 1;
      
      debugPrint('📹 Registered video track for participant: $participantId');
      debugPrint('   - Track SID: ${track.sid}');
      debugPrint('   - Active tracks: ${_activeTracks.length}');
      debugPrint('   - Usage count: ${_usageCount[participantId]}');
      
      // Check if we need to cleanup old tracks due to capacity
      if (isAtCapacity) {
        _cleanupLeastUsedTracks();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error registering video track: $e');
    }
  }

  void markTrackAsUsed(String participantId) {
    if (_activeTracks.containsKey(participantId)) {
      _recentlyUsedTracks.add(participantId);
      _lastUsedTimes[participantId] = DateTime.now();
      _usageCount[participantId] = (_usageCount[participantId] ?? 0) + 1;
      
      // Cancel cleanup timer if it exists
      _cleanupTimers[participantId]?.cancel();
      _cleanupTimers.remove(participantId);
      
      debugPrint('👁️ Marked track as used: $participantId');
    }
  }

  void scheduleTrackCleanup(String participantId) {
    if (!_activeTracks.containsKey(participantId)) return;
    
    // Cancel existing timer
    _cleanupTimers[participantId]?.cancel();
    
    // Schedule cleanup
    _cleanupTimers[participantId] = Timer(_inactiveCleanupDelay, () {
      _cleanupTrack(participantId);
    });
    
    debugPrint('⏰ Scheduled cleanup for track: $participantId in ${_inactiveCleanupDelay.inMinutes} minutes');
  }

  Future<void> _cleanupTrack(String participantId) async {
    try {
      final track = _activeTracks[participantId];
      if (track == null) return;
      
      debugPrint('🧹 Cleaning up video track for participant: $participantId');
      
      // Remove from active tracks
      _activeTracks.remove(participantId);
      _recentlyUsedTracks.remove(participantId);
      _cleanupTimers.remove(participantId);
      
      // Stop the track if it's a local track
      if (track is LocalVideoTrack) {
        await track.stop();
        debugPrint('   - Stopped local video track');
      }
      
      debugPrint('   - Track cleaned up successfully');
      debugPrint('   - Remaining active tracks: ${_activeTracks.length}');
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error cleaning up video track: $e');
    }
  }

  Future<void> _cleanupLeastUsedTracks() async {
    if (_activeTracks.length <= _maxActiveTracks) return;
    
    debugPrint('🧹 Cleaning up least used tracks (capacity: $_maxActiveTracks)');
    
    // Sort participants by usage score (last used time + usage count)
    final participants = _activeTracks.keys.toList();
    participants.sort((a, b) {
      final aScore = _calculateUsageScore(a);
      final bScore = _calculateUsageScore(b);
      return aScore.compareTo(bScore); // Ascending order (least used first)
    });
    
    // Cleanup tracks until we're under capacity
    final tracksToCleanup = _activeTracks.length - _maxActiveTracks + 1;
    for (int i = 0; i < tracksToCleanup && i < participants.length; i++) {
      await _cleanupTrack(participants[i]);
    }
  }

  double _calculateUsageScore(String participantId) {
    final lastUsed = _lastUsedTimes[participantId] ?? DateTime.now();
    final usageCount = _usageCount[participantId] ?? 0;
    
    // Score based on recency (higher = more recent) and usage count
    final recencyScore = DateTime.now().difference(lastUsed).inMinutes;
    final usageScore = usageCount * 10; // Weight usage count heavily
    
    // Lower score = less used (will be cleaned up first)
    return (usageScore - recencyScore).toDouble();
  }

  Future<void> cleanupInactiveTracks() async {
    debugPrint('🧹 Cleaning up inactive tracks');
    
    final now = DateTime.now();
    final inactiveParticipants = <String>[];
    
    for (final participantId in _activeTracks.keys) {
      final lastUsed = _lastUsedTimes[participantId] ?? now;
      final inactiveDuration = now.difference(lastUsed);
      
      if (inactiveDuration > _trackUsageWindow && 
          !_recentlyUsedTracks.contains(participantId)) {
        inactiveParticipants.add(participantId);
      }
    }
    
    debugPrint('   - Found ${inactiveParticipants.length} inactive tracks');
    
    for (final participantId in inactiveParticipants) {
      await _cleanupTrack(participantId);
    }
    
    // Clear recently used set for next cycle
    _recentlyUsedTracks.clear();
  }

  Future<void> cleanupAllTracks() async {
    debugPrint('🧹 Cleaning up all video tracks');
    
    final participantIds = _activeTracks.keys.toList();
    for (final participantId in participantIds) {
      await _cleanupTrack(participantId);
    }
    
    // Cancel all timers
    for (final timer in _cleanupTimers.values) {
      timer.cancel();
    }
    _cleanupTimers.clear();
    
    // Clear all data
    _recentlyUsedTracks.clear();
    _lastUsedTimes.clear();
    _usageCount.clear();
    
    debugPrint('✅ All video tracks cleaned up');
  }

  void setMaxActiveTracks(int maxTracks) {
    if (_maxActiveTracks != maxTracks) {
      _maxActiveTracks = maxTracks;
      debugPrint('📊 Max active tracks set to: $maxTracks');
      
      // Cleanup excess tracks if needed
      if (_activeTracks.length > maxTracks) {
        _cleanupLeastUsedTracks();
      }
    }
  }

  void setInactiveCleanupDelay(Duration delay) {
    if (_inactiveCleanupDelay != delay) {
      _inactiveCleanupDelay = delay;
      debugPrint('⏰ Inactive cleanup delay set to: ${delay.inMinutes} minutes');
    }
  }

  void setTrackUsageWindow(Duration window) {
    if (_trackUsageWindow != window) {
      _trackUsageWindow = window;
      debugPrint('📊 Track usage window set to: ${window.inMinutes} minutes');
    }
  }

  Map<String, dynamic> getLifecycleMetrics() {
    return {
      'activeTrackCount': _activeTracks.length,
      'maxActiveTracks': _maxActiveTracks,
      'isAtCapacity': isAtCapacity,
      'recentlyUsedCount': _recentlyUsedTracks.length,
      'scheduledCleanupCount': _cleanupTimers.length,
      'totalUsageCount': _usageCount.values.fold(0, (sum, count) => sum + count),
      'averageUsagePerTrack': _usageCount.isNotEmpty 
          ? _usageCount.values.reduce((a, b) => a + b) / _usageCount.length 
          : 0.0,
    };
  }

  List<Map<String, dynamic>> getTrackUsageStats() {
    return _activeTracks.keys.map((participantId) {
      final track = _activeTracks[participantId]!;
      final lastUsed = _lastUsedTimes[participantId];
      final usageCount = _usageCount[participantId] ?? 0;
      final usageScore = _calculateUsageScore(participantId);
      
      return {
        'participantId': participantId,
        'trackSid': track.sid,
        'trackKind': track.kind.name,
        'lastUsed': lastUsed?.toIso8601String(),
        'usageCount': usageCount,
        'usageScore': usageScore,
        'isRecentlyUsed': _recentlyUsedTracks.contains(participantId),
        'hasScheduledCleanup': _cleanupTimers.containsKey(participantId),
      };
    }).toList();
  }

  @override
  void dispose() {
    // Cancel all cleanup timers
    for (final timer in _cleanupTimers.values) {
      timer.cancel();
    }
    
    // Clean up all tracks
    cleanupAllTracks();
    
    super.dispose();
  }
}