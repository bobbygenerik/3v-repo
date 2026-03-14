import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_capability_service.dart';
import 'package:livekit_client/livekit_client.dart';
import 'chat_service.dart' as chat;
import 'reaction_service.dart';
import 'e2e_encryption_service.dart';
// ScreenShare feature removed; keep no-op compatibility methods below.
import 'call_stats_service.dart';
import '../config/environment.dart';
import 'grid_layout_manager.dart';
import 'feature_flags.dart';
import 'audio_device_service.dart';
import 'livekit_service.dart';
import 'litert_service.dart';

export 'grid_layout_manager.dart' show LayoutMode;

/// Call Features Coordinator
/// Manages all in-call features and provides unified state management
/// Mirrors functionality from Android InCallManagerCoordinator.kt
class CallFeaturesCoordinator extends ChangeNotifier {
  // Services
  final chat.ChatService chatService = chat.ChatService();
  final ReactionService reactionService = ReactionService();
  final E2EEncryptionService encryptionService = E2EEncryptionService();
  // ScreenShareService removed to fully disable feature.
  final CallStatsService statsService = CallStatsService();
  final GridLayoutManager layoutManager = GridLayoutManager();

  // Audio Device Service (injected)
  AudioDeviceService? _audioDeviceService;

  // LiteRT on-device ML service
  final LiteRTService liteRTService = LiteRTService();

  Room? _room;
  LiveKitService? _liveKitService;
  bool _liteRTVideoTrackRegistered = false;
  final Map<String, int> _remoteTextureIds = {};

  // Feature states
  bool _isChatOpen = false;
  bool _isEncrypted = false;
  bool _isScreenSharing = false;
  bool _isSpatialAudioEnabled = false;
  bool _isBackgroundBlurEnabled = false;
  bool _isBeautyFilterEnabled = false;
  bool _isArFilterEnabled = false;
  bool _isAiNoiseCancellationEnabled = true;

  String _activeArFilter = 'none';
  LayoutMode _layoutMode = LayoutMode.grid;
  int _qualityScore = 100;

  // Getters for feature states
  bool get isChatOpen => _isChatOpen;
  bool get isEncrypted => _isEncrypted;
  bool get isScreenSharing => _isScreenSharing;
  bool get isSpatialAudioEnabled => _isSpatialAudioEnabled;
  bool get isBackgroundBlurEnabled => liteRTService.backgroundBlurEnabled;
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

  // LiteRT ML feature accessors (delegate to LiteRTService)
  bool get isBlurProcessing => liteRTService.backgroundBlurEnabled;
  bool get isLowLightEnabled => liteRTService.lowLightEnabled;
  bool get isSharpeningEnabled => liteRTService.sharpeningEnabled;
  bool get liteRTGpuDelegate => liteRTService.gpuDelegate;
  // Legacy stubs retained for interface compatibility
  bool get isBeautyProcessing => false;
  bool get isArProcessing => false;
  double get beautyIntensity => 0.0;

  // Recording & Encryption status
  EncryptionStatus get encryptionStatus => encryptionService.status;
  CallStats get currentCallStats => statsService.currentStats;
  CallConnectionQuality get connectionQuality => statsService.currentQuality;
  List<ParticipantTile> get participantTiles => layoutManager.participants.isEmpty
      ? []
      : layoutManager.getTiles(containerWidth: 1920, containerHeight: 1080);
  Participant? get pinnedParticipant => layoutManager.pinnedParticipant;
  bool get isStatsCollecting => statsService.isCollecting;

  /// Initialize coordinator with LiveKit room
  CallFeaturesCoordinator();

  Future<void> initialize(
    Room room, {
    LiveKitService? liveKitService,
    AudioDeviceService? audioDeviceService,
  }) async {
    debugPrint('🎯 CallFeaturesCoordinator initializing...');
    _room = room;
    _liveKitService = liveKitService;

    _audioDeviceService = audioDeviceService;

    // Initialize LiteRT on-device ML
    if (FeatureFlags.enableLiteRT) {
      try {
        await liteRTService.initialize();
        debugPrint('✅ LiteRT service initialized (GPU: ${liteRTService.gpuDelegate})');
      } catch (e) {
        debugPrint('⚠️ LiteRT initialization failed: $e');
      }
    }

    // Initialize services
    chatService.initialize(room);
    reactionService.initialize(room);

    // Apply user preferences (if present) so features the user enabled in Settings
    try {
      final prefs = await SharedPreferences.getInstance();
      // ML features removed; ensure related flags are disabled
      _isBackgroundBlurEnabled = false;
      _isBeautyFilterEnabled = false;
      _isFaceAutoFramingEnabled = false;
      
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
          // MediaPipe removed - no update to settings
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
      // ScreenShare removed; skip initialization.
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
    encryptionService.addListener(_onEncryptionChanged);
    // Watch for local video track creation so we can attach the LiteRT processor
    _liveKitService?.addListener(_onLiveKitChanged);
    _liveKitService?.onRemoteVideoTrackSubscribed = _onRemoteVideoTrackSubscribed;
    _liveKitService?.onRemoteVideoTrackUnsubscribed = _onRemoteVideoTrackUnsubscribed;
    // No-op: screen share listeners removed
    // Stats overlay handles its own updates directly from statsService
    // No need to propagate through coordinator to avoid unnecessary rebuilds
    layoutManager.addListener(_onLayoutChanged);

    debugPrint('✅ CallFeaturesCoordinator initialized');
  }

  /// Called when LiveKitService changes state — used to detect when the local
  /// video track is first created so we can attach the LiteRT processor.
  void _onLiveKitChanged() {
    if (!kIsWeb && FeatureFlags.enableLiteRT && !_liteRTVideoTrackRegistered) {
      final trackId = _liveKitService?.localVideoTrack?.mediaStreamTrack.id;
      if (trackId != null && trackId.isNotEmpty) {
        _liteRTVideoTrackRegistered = true;
        liteRTService.registerVideoTrack(trackId).catchError((e) {
          debugPrint('⚠️ LiteRT registerVideoTrack failed: $e');
          _liteRTVideoTrackRegistered = false; // allow retry on next change
        });
      }
    }
    notifyListeners();
  }

  /// Explicitly register the LiteRT video processor for the given track ID.
  /// Use this for the P2P path where LiveKitService is not involved.
  Future<void> registerLiteRTVideoTrack(String trackId) async {
    if (kIsWeb || !FeatureFlags.enableLiteRT) return;
    _liteRTVideoTrackRegistered = true;
    await liteRTService.registerVideoTrack(trackId);
  }

  Future<void> _onRemoteVideoTrackSubscribed(
    String trackId,
    RemoteParticipant participant,
  ) async {
    if (kIsWeb || !FeatureFlags.enableLiteRT) return;
    final platform = participant.attributes['platform'];
    if (platform == 'flutter') return;

    final textureId = await liteRTService.attachRemoteProcessing(trackId);
    if (textureId != null) {
      _remoteTextureIds[trackId] = textureId;
      notifyListeners();
    }
  }

  void _onRemoteVideoTrackUnsubscribed(String trackId) {
    if (_remoteTextureIds.containsKey(trackId)) {
      unawaited(liteRTService.detachRemoteProcessing(trackId));
      _remoteTextureIds.remove(trackId);
      notifyListeners();
    }
  }

  /// Texture id for remote track rendering when remote LiteRT is attached.
  int? remoteTextureId(String trackId) => _remoteTextureIds[trackId];

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

  /// Encryption callback
  void _onEncryptionChanged() {
    _isEncrypted = encryptionService.isEnabled;
    notifyListeners();
  }

  // Screen share removed: no callbacks or service listeners remain.

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

  // Screen sharing removed from the product. Methods and service calls
  // previously present have been deleted to remove public APIs and UI
  // surface for this feature.

  /// Toggle spatial audio
  void toggleSpatialAudio() {
    _isSpatialAudioEnabled = !_isSpatialAudioEnabled;
    notifyListeners();
    debugPrint('Spatial audio ${_isSpatialAudioEnabled ? "enabled" : "disabled"}');

    // Call native implementation if available
    _audioDeviceService?.setSpatialAudioEnabled(_isSpatialAudioEnabled);
  }

  /// Toggle background blur
  Future<void> toggleBackgroundBlur() async {
    if (!Environment.enableMLFeatures) return;
    _isBackgroundBlurEnabled = !_isBackgroundBlurEnabled;
    await liteRTService.setBackgroundBlur(_isBackgroundBlurEnabled);
    await _persistSetting('background_blur', _isBackgroundBlurEnabled);
    notifyListeners();
    debugPrint('Background blur ${_isBackgroundBlurEnabled ? "enabled" : "disabled"}');
  }

  /// Set blur radius (1–50 px)
  Future<void> setBackgroundBlurRadius(double radius) async {
    await liteRTService.setBlurRadius(radius);
    notifyListeners();
  }

  /// Toggle low-light video enhancement
  Future<void> toggleLowLightEnhancement() async {
    if (!Environment.enableMLFeatures) return;
    final newVal = !liteRTService.lowLightEnabled;
    await liteRTService.setLowLightEnhancement(newVal);
    await _persistSetting('low_light_enhancement', newVal);
    notifyListeners();
    debugPrint('Low-light enhancement ${newVal ? "enabled" : "disabled"}');
  }

  /// Toggle video sharpening
  Future<void> toggleSharpening() async {
    if (!Environment.enableMLFeatures) return;
    final newVal = !liteRTService.sharpeningEnabled;
    await liteRTService.setSharpening(newVal);
    await _persistSetting('sharpening', newVal);
    notifyListeners();
    debugPrint('Sharpening ${newVal ? "enabled" : "disabled"}');
  }

  /// Toggle beauty filter
  void toggleBeautyFilter() {
    if (!Environment.enableMLFeatures) return;
    _isBeautyFilterEnabled = !_isBeautyFilterEnabled;
    unawaited(_persistSetting('beauty_filter', _isBeautyFilterEnabled));
    notifyListeners();
    debugPrint('Beauty filter ${_isBeautyFilterEnabled ? "enabled" : "disabled"}');
  }

  /// Toggle face auto-framing
  void toggleFaceAutoFraming() {
    if (!Environment.enableMLFeatures) return;
    _isFaceAutoFramingEnabled = !_isFaceAutoFramingEnabled;
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

  /// Toggle AI noise cancellation (WebRTC built-in + LiteRT hardware suppressor)
  Future<void> toggleAiNoiseCancellation() async {
    _isAiNoiseCancellationEnabled = !_isAiNoiseCancellationEnabled;
    notifyListeners();
    debugPrint('AI noise cancellation ${_isAiNoiseCancellationEnabled ? "enabled" : "disabled"}');

    // WebRTC-layer NS/EC/AGC
    if (_liveKitService != null) {
      await _liveKitService!.updateAudioCaptureOptions(
        AudioCaptureOptions(
          noiseSuppression: _isAiNoiseCancellationEnabled,
          echoCancellation: true,
          autoGainControl: true,
        ),
      );
    }

    // Platform-level LiteRT hardware noise suppressor
    if (FeatureFlags.enableLiteRT) {
      await liteRTService.setNoiseSuppression(_isAiNoiseCancellationEnabled);
    }
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

    for (final trackId in _remoteTextureIds.keys.toList()) {
      unawaited(liteRTService.detachRemoteProcessing(trackId));
    }
    _remoteTextureIds.clear();
    _liveKitService?.onRemoteVideoTrackSubscribed = null;
    _liveKitService?.onRemoteVideoTrackUnsubscribed = null;

    chatService.removeListener(_onChatChanged);
    reactionService.removeListener(_onReactionChanged);
    // ML service listeners removed
    encryptionService.removeListener(_onEncryptionChanged);
    _liveKitService?.removeListener(_onLiveKitChanged);
    // Stats listener removed to prevent unnecessary rebuilds
    layoutManager.removeListener(_onLayoutChanged);

    chatService.cleanup();
    reactionService.cleanup();
    
    // LiteRT ML services
    await liteRTService.disposeProcessors();

    // Dispose Phase 4 services
    encryptionService.dispose();

    // Dispose Phase 5 services
    // No-op: screen share cleanup not required
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
