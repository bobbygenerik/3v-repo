import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_capability_service.dart';
import 'package:livekit_client/livekit_client.dart';
import 'chat_service.dart' as chat;
import 'reaction_service.dart';
import 'cloud_recording_service.dart';
import 'e2e_encryption_service.dart';
import 'screen_share_service.dart';
import 'call_stats_service.dart';
import '../config/environment.dart';
import 'grid_layout_manager.dart';
import 'mediapipe_settings.dart';
import '../config/environment.dart';

export 'grid_layout_manager.dart' show LayoutMode;

/// Call Features Coordinator
/// Manages all in-call features and provides unified state management
/// Mirrors functionality from Android InCallManagerCoordinator.kt
class CallFeaturesCoordinator extends ChangeNotifier {
  // Services
  final chat.ChatService chatService = chat.ChatService();
  final ReactionService reactionService = ReactionService();
  final CloudRecordingService recordingService = CloudRecordingService();
  final E2EEncryptionService encryptionService = E2EEncryptionService();
  final ScreenShareService screenShareService = ScreenShareService();
  final CallStatsService statsService = CallStatsService();
  final GridLayoutManager layoutManager = GridLayoutManager();

  final MediaPipeSettings? _mediaPipeSettings;

  // Feature states
  bool _isChatOpen = false;
  bool _isRecording = false;
  bool _isEncrypted = false;
  bool _isScreenSharing = false;
  bool _isSpatialAudioEnabled = false;
  bool _isBackgroundBlurEnabled = false;
  bool _isBeautyFilterEnabled = false;
  bool _isArFilterEnabled = false;
  bool _isAiNoiseCancellationEnabled = false;

  String _activeArFilter = 'none';
  LayoutMode _layoutMode = LayoutMode.grid;
  int _qualityScore = 100;

  // Getters for feature states
  bool get isChatOpen => _isChatOpen;
  bool get isRecording => _isRecording;
  bool get isEncrypted => _isEncrypted;
  bool get isScreenSharing => _isScreenSharing;
  bool get isSpatialAudioEnabled => _isSpatialAudioEnabled;
  bool get isBackgroundBlurEnabled => _isBackgroundBlurEnabled;
  bool get isBeautyFilterEnabled => _isBeautyFilterEnabled;
  bool get isArFilterEnabled => _isArFilterEnabled;
  bool get isAiNoiseCancellationEnabled => _isAiNoiseCancellationEnabled;

  // AI features
  bool _isFaceAutoFramingEnabled = false;
  bool get isFaceAutoFramingEnabled => _isFaceAutoFramingEnabled;

  String get activeArFilter => _activeArFilter;
  LayoutMode get layoutMode => _layoutMode;
  int get qualityScore => _qualityScore;

  // Chat & Reactions
  List<chat.ChatMessage> get chatMessages => chatService.messageHistory;
  List<Reaction> get activeReactions => reactionService.activeReactions;
  int get unreadMessageCount => chatService.getUnreadCount();

  // ML Services status (stubs)
  bool get isBlurProcessing => false;
  bool get isBeautyProcessing => false;
  bool get isArProcessing => false;
  double get beautyIntensity => 0.0;

  // Recording & Encryption status
  RecordingStatus get recordingStatus => recordingService.status;
  EncryptionStatus get encryptionStatus => encryptionService.status;
  RecordingMetadata? get currentRecording => recordingService.currentRecording;

  // Phase 5 status
  ScreenShareStatus get screenShareStatus => screenShareService.status;
  CallStats get currentCallStats => statsService.currentStats;
  CallConnectionQuality get connectionQuality => statsService.currentQuality;
  List<ParticipantTile> get participantTiles => layoutManager.participants.isEmpty
      ? []
      : layoutManager.getTiles(containerWidth: 1920, containerHeight: 1080);
  Participant? get pinnedParticipant => layoutManager.pinnedParticipant;
  bool get isStatsCollecting => statsService.isCollecting;

  /// Initialize coordinator with LiveKit room
  CallFeaturesCoordinator({MediaPipeSettings? mediaPipeSettings})
      : _mediaPipeSettings = mediaPipeSettings;

  Future<void> initialize(Room room) async {
    debugPrint('🎯 CallFeaturesCoordinator initializing...');

    // Initialize services
    chatService.initialize(room);
    reactionService.initialize(room);

    if (_mediaPipeSettings != null && Environment.enableMLFeatures) {
      debugPrint('✅ MediaPipe services ready');
    } else {
      debugPrint('⚠️ MediaPipe settings not provided; ML features disabled');
    }

    // Apply user preferences (if present) so features the user enabled in Settings
    try {
      final prefs = await SharedPreferences.getInstance();
      if (Environment.enableMLFeatures) {
        final bgBlur = prefs.getBool('background_blur') ?? false;
        _isBackgroundBlurEnabled = bgBlur;
        _mediaPipeSettings?.update(backgroundBlur: bgBlur);

        final beauty = prefs.getBool('beauty_filter') ?? false;
        _isBeautyFilterEnabled = beauty;
        _mediaPipeSettings?.update(beauty: beauty, faceMesh: beauty);

        final faceAuto = prefs.getBool('face_auto_framing') ?? false;
        _isFaceAutoFramingEnabled = faceAuto;
        _mediaPipeSettings?.update(faceDetection: faceAuto);

        final blurIntensity = prefs.getDouble('portrait_blur_intensity') ?? 70.0;
        _mediaPipeSettings?.update(blurIntensity: blurIntensity);
      } else {
        _isBackgroundBlurEnabled = false;
        _isBeautyFilterEnabled = false;
        _isFaceAutoFramingEnabled = false;
        _mediaPipeSettings?.update(
          backgroundBlur: false,
          beauty: false,
          faceMesh: false,
          faceDetection: false,
        );
      }
      
      // If device is low-end, disable expensive ML features regardless of saved prefs
      try {
        if (DeviceCapabilityService.capability == DeviceCapability.lowEnd) {
          debugPrint('⚠️ Low-end device detected — disabling ML-heavy features for performance');
          if (_isBackgroundBlurEnabled) {
            _isBackgroundBlurEnabled = false;
          }
          if (_isBeautyFilterEnabled) {
            _isBeautyFilterEnabled = false;
          }
          if (_isFaceAutoFramingEnabled) {
            _isFaceAutoFramingEnabled = false;
          }
          _mediaPipeSettings?.update(
            backgroundBlur: _isBackgroundBlurEnabled,
            beauty: _isBeautyFilterEnabled,
            faceMesh: _isBeautyFilterEnabled,
            faceDetection: _isFaceAutoFramingEnabled,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Error applying low-end device ML fallback: $e');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to apply saved preferences: $e');
    }

    // Initialize Phase 4 services
    try {
      await encryptionService.initialize();
      debugPrint('✅ Encryption service initialized');
    } catch (e) {
      debugPrint('⚠️ Encryption service initialization failed: $e');
    }

    // Initialize Phase 5 services
    try {
      await screenShareService.initialize(room);
      await statsService.initialize(room);
      await layoutManager.initialize(room);
      debugPrint('✅ Phase 5 services initialized');
    } catch (e) {
      debugPrint('⚠️ Phase 5 services initialization failed: $e');
    }

    // Listen to service changes
    chatService.addListener(_onChatChanged);
    reactionService.addListener(_onReactionChanged);
    // ML service listeners removed
    recordingService.addListener(_onRecordingChanged);
    encryptionService.addListener(_onEncryptionChanged);
    screenShareService.addListener(_onScreenShareChanged);
    // Stats overlay handles its own updates directly from statsService
    // No need to propagate through coordinator to avoid unnecessary rebuilds
    layoutManager.addListener(_onLayoutChanged);

    debugPrint('✅ CallFeaturesCoordinator initialized');
  }

  /// ML services callback
  void _onMlServiceChanged() {
    notifyListeners();
  }

  /// Chat callbacks
  void _onChatChanged() {
    debugPrint('📬 CallFeaturesCoordinator: Chat changed, notifying listeners');
    notifyListeners();
  }

  /// Reaction callbacks
  void _onReactionChanged() {
    notifyListeners();
  }

  /// Recording callback
  void _onRecordingChanged() {
    _isRecording = recordingService.status == RecordingStatus.recording;
    notifyListeners();
  }

  /// Encryption callback
  void _onEncryptionChanged() {
    _isEncrypted = encryptionService.isEnabled;
    notifyListeners();
  }

  /// Screen share callback
  void _onScreenShareChanged() {
    _isScreenSharing = screenShareService.isSharing;
    notifyListeners();
  }

  /// Stats callback
  /// Layout callback
  void _onLayoutChanged() {
    notifyListeners();
  }

  /// Toggle chat panel
  void toggleChat() {
    _isChatOpen = !_isChatOpen;
    if (_isChatOpen) {
      chatService.markAllAsRead();
    }
    notifyListeners();
    debugPrint('Chat ${_isChatOpen ? "opened" : "closed"}');
  }

  /// Send chat message
  Future<bool> sendChatMessage(String message) async {
    debugPrint('📬 CallFeaturesCoordinator: Sending message: $message');
    final success = await chatService.sendMessage(message);
    if (success) {
      // Force notification to ensure UI updates
      notifyListeners();
    }
    return success;
  }

  /// Send reaction
  Future<bool> sendReaction(ReactionType type) async {
    return await reactionService.sendReaction(type);
  }

  /// Toggle recording
  Future<void> toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      final metadata = await recordingService.stopRecording();
      if (metadata != null) {
        debugPrint('Recording stopped: ${metadata.fileName}');
      }
    } else {
      // Start recording
      // Note: callId should be passed from the call screen
      final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
      final success = await recordingService.startRecording(callId);
      if (success) {
        debugPrint('Recording started');
      }
    }
    notifyListeners();
  }

  /// Start recording with explicit call ID
  Future<bool> startRecording(String callId, {String? roomName}) async {
    return await recordingService.startRecording(callId, roomName: roomName);
  }

  /// Stop recording
  Future<RecordingMetadata?> stopRecording() async {
    return await recordingService.stopRecording();
  }

  /// Get recording metadata
  RecordingMetadata? getRecording(String callId) {
    return recordingService.getRecording(callId);
  }

  /// Toggle encryption
  Future<void> toggleEncryption() async {
    if (_isEncrypted) {
      await encryptionService.disableEncryption();
    } else {
      await encryptionService.enableEncryption();
    }
    notifyListeners();
  }

  /// Enable encryption with specific key
  Future<bool> enableEncryption({String? sharedKey}) async {
    return await encryptionService.enableEncryption(sharedKey: sharedKey);
  }

  /// Disable encryption
  Future<bool> disableEncryption() async {
    return await encryptionService.disableEncryption();
  }

  /// Rotate encryption key
  Future<bool> rotateEncryptionKey() async {
    return await encryptionService.rotateKey();
  }

  /// Get encryption statistics
  Map<String, dynamic> getEncryptionStats() {
    return encryptionService.getStats();
  }

  /// Toggle screen sharing
  Future<void> toggleScreenShare({
    ScreenResolution? resolution,
    int? fps,
  }) async {
    if (!Environment.enableScreenShare) return;
    await screenShareService.toggleScreenShare(
      resolution: resolution,
      fps: fps,
    );
    notifyListeners();
  }

  /// Start screen sharing
  Future<bool> startScreenShare({
    ScreenResolution? resolution,
    int? fps,
  }) async {
    if (!Environment.enableScreenShare) return false;
    return await screenShareService.startScreenShare(
      resolution: resolution,
      fps: fps,
    );
  }

  /// Stop screen sharing
  Future<bool> stopScreenShare() async {
    if (!Environment.enableScreenShare) return false;
    return await screenShareService.stopScreenShare();
  }

  /// Get screen share statistics
  Map<String, dynamic> getScreenShareStats() {
    return screenShareService.getStats();
  }

  /// Toggle spatial audio
  void toggleSpatialAudio() {
    _isSpatialAudioEnabled = !_isSpatialAudioEnabled;
    notifyListeners();
    debugPrint('Spatial audio ${_isSpatialAudioEnabled ? "enabled" : "disabled"}');

    // TODO: Implement spatial audio logic
  }

  /// Toggle background blur
  Future<void> toggleBackgroundBlur() async {
    if (!Environment.enableMLFeatures) return;
    _isBackgroundBlurEnabled = !_isBackgroundBlurEnabled;
    _mediaPipeSettings?.update(backgroundBlur: _isBackgroundBlurEnabled);
    await _persistSetting('background_blur', _isBackgroundBlurEnabled);
    notifyListeners();
    debugPrint('Background blur ${_isBackgroundBlurEnabled ? "enabled" : "disabled"}');
  }

  /// Toggle beauty filter
  void toggleBeautyFilter() {
    if (!Environment.enableMLFeatures) return;
    _isBeautyFilterEnabled = !_isBeautyFilterEnabled;
    _mediaPipeSettings?.update(
      beauty: _isBeautyFilterEnabled,
      faceMesh: _isBeautyFilterEnabled,
    );
    unawaited(_persistSetting('beauty_filter', _isBeautyFilterEnabled));
    notifyListeners();
    debugPrint('Beauty filter ${_isBeautyFilterEnabled ? "enabled" : "disabled"}');
  }

  /// Toggle face auto-framing
  void toggleFaceAutoFraming() {
    if (!Environment.enableMLFeatures) return;
    _isFaceAutoFramingEnabled = !_isFaceAutoFramingEnabled;
    _mediaPipeSettings?.update(faceDetection: _isFaceAutoFramingEnabled);
    unawaited(_persistSetting('face_auto_framing', _isFaceAutoFramingEnabled));
    notifyListeners();
    debugPrint('Face auto-framing ${_isFaceAutoFramingEnabled ? "enabled" : "disabled"}');
  }

  Future<void> _persistSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('⚠️ Failed to persist setting $key: $e');
    }
  }

  /// Set beauty filter intensity (0.0 - 1.0)
  void setBeautyIntensity(double intensity) {
    notifyListeners();
  }

  /// Set AR filter (stub - service removed)
  void setArFilter(String filterName) {
    _activeArFilter = filterName;
    _isArFilterEnabled = filterName != 'none';
    
    // AR filters service removed - stub only
    
    notifyListeners();
    debugPrint('AR filter set to: $filterName (stub)');
  }

  /// Toggle AI noise cancellation
  void toggleAiNoiseCancellation() {
    _isAiNoiseCancellationEnabled = !_isAiNoiseCancellationEnabled;
    notifyListeners();
    debugPrint('AI noise cancellation ${_isAiNoiseCancellationEnabled ? "enabled" : "disabled"}');

    // TODO: Implement AI noise cancellation logic
  }

  /// Set layout mode
  void setLayoutMode(LayoutMode mode) {
    layoutManager.setLayoutMode(mode);
    _layoutMode = mode;
    notifyListeners();
    debugPrint('Layout mode changed to: ${mode.name}');
  }

  /// Pin a participant
  void pinParticipant(Participant? participant) {
    layoutManager.pinParticipant(participant);
    notifyListeners();
  }

  /// Toggle pin for a participant
  void togglePinParticipant(Participant participant) {
    layoutManager.togglePinParticipant(participant);
    notifyListeners();
  }

  /// Start collecting call statistics
  void startStatsCollection() {
    statsService.startCollecting();
    notifyListeners();
  }

  /// Stop collecting call statistics
  void stopStatsCollection() {
    statsService.stopCollecting();
    notifyListeners();
  }

  /// Get average call statistics
  CallStats getAverageStats({int seconds = 10}) {
    return statsService.getAverageStats(seconds: seconds);
  }

  /// Get call statistics summary
  Map<String, dynamic> getStatsSummary() {
    return statsService.getSummary();
  }

  /// Update quality score (0-100)
  void updateQualityScore(int score) {
    _qualityScore = score.clamp(0, 100);
    notifyListeners();
  }

  /// Clean up all resources
  Future<void> cleanup() async {
    debugPrint('🧹 CallFeaturesCoordinator cleaning up...');

    chatService.removeListener(_onChatChanged);
    reactionService.removeListener(_onReactionChanged);
    // ML service listeners removed
    recordingService.removeListener(_onRecordingChanged);
    encryptionService.removeListener(_onEncryptionChanged);
    screenShareService.removeListener(_onScreenShareChanged);
    // Stats listener removed to prevent unnecessary rebuilds
    layoutManager.removeListener(_onLayoutChanged);

    chatService.cleanup();
    reactionService.cleanup();
    
    // ML services removed - no disposal needed

    // Dispose Phase 4 services
    recordingService.dispose();
    encryptionService.dispose();

    // Dispose Phase 5 services
    await screenShareService.cleanup();
    await statsService.cleanup();
    await layoutManager.cleanup();

    debugPrint('✅ CallFeaturesCoordinator cleaned up');
  }

  @override
  void dispose() {
    cleanup(); // Fire and forget cleanup
    super.dispose();
  }
}

/// Available AR filter options
class ArFilters {
  static const String none = 'none';
  static const String glasses = 'glasses';
  static const String hat = 'hat';
  static const String mask = 'mask';
  static const String bunnyEars = 'bunny_ears';
  static const String catEars = 'cat_ears';
  static const String crown = 'crown';
  static const String monocle = 'monocle';
  static const String piratePatch = 'pirate_patch';
  static const String santaHat = 'santa_hat';
  static const String sparkles = 'sparkles';

  static List<String> get all => [
        none,
        glasses,
        hat,
        mask,
        bunnyEars,
        catEars,
        crown,
        monocle,
        piratePatch,
        santaHat,
        sparkles,
      ];

  static String getDisplayName(String filter) {
    switch (filter) {
      case none:
        return 'None';
      case glasses:
        return 'Glasses 🕶️';
      case hat:
        return 'Hat 🎩';
      case mask:
        return 'Mask 😷';
      case bunnyEars:
        return 'Bunny Ears 🐰';
      case catEars:
        return 'Cat Ears 🐱';
      case crown:
        return 'Crown 👑';
      case monocle:
        return 'Monocle 🧐';
      case piratePatch:
        return 'Pirate Patch 🏴‍☠️';
      case santaHat:
        return 'Santa Hat 🎅';
      case sparkles:
        return 'Sparkles ✨';
      default:
        return filter;
    }
  }
}
