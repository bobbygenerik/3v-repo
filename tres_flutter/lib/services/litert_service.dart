import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// LiteRT on-device ML service.
///
/// Flutter-side proxy for the native [LiteRTChannel] (Android) and
/// [LiteRTVideoProcessor] (iOS).  Provides typed Dart APIs for all
/// LiteRT ML features and exposes [ChangeNotifier] state for UI widgets.
///
/// Features managed:
///   Video  — background blur, low-light enhancement, sharpening
///   Audio  — hardware noise suppressor, loudness enhancer, VAD
///
/// Usage:
///   final ml = LiteRTService();
///   await ml.initialize();
///   await ml.setBackgroundBlur(true, blurRadius: 25);
class LiteRTService extends ChangeNotifier {
  static const _channel = MethodChannel('tres3/liteRT');

  // ── Capabilities (populated after initialize()) ───────────────────────────
  bool _hasBackgroundBlur = false;
  bool _hasLowLight = false;
  bool _hasSharpening = true;
  bool _hasHardwareNoiseSuppressor = false;
  bool _hasVad = false;
  bool _gpuDelegate = false;
  bool _initialized = false;

  bool get hasBackgroundBlur => _hasBackgroundBlur;
  bool get hasLowLight => _hasLowLight;
  bool get hasSharpening => _hasSharpening;
  bool get hasHardwareNoiseSuppressor => _hasHardwareNoiseSuppressor;
  bool get hasVad => _hasVad;
  bool get gpuDelegate => _gpuDelegate;
  bool get isInitialized => _initialized;

  // ── Video feature states ──────────────────────────────────────────────────
  bool _backgroundBlurEnabled = false;
  bool _lowLightEnabled = false;
  bool _sharpeningEnabled = false;
  double _blurRadius = 20.0;

  bool get backgroundBlurEnabled => _backgroundBlurEnabled;
  bool get lowLightEnabled => _lowLightEnabled;
  bool get sharpeningEnabled => _sharpeningEnabled;
  double get blurRadius => _blurRadius;

  // ── Audio feature states ──────────────────────────────────────────────────
  bool _noiseSuppressorEnabled = false;
  bool _loudnessEnhancerEnabled = false;
  int _loudnessGainMb = 0;
  bool _vadEnabled = false;

  bool get noiseSuppressorEnabled => _noiseSuppressorEnabled;
  bool get loudnessEnhancerEnabled => _loudnessEnhancerEnabled;
  int get loudnessGainMb => _loudnessGainMb;
  bool get vadEnabled => _vadEnabled;

  // ─────────────────────────────────────────────────────────────────────────

  /// Query native capabilities and warm up the ML processors.
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;

    // Web platform has no native LiteRT — skip silently
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      final caps = await _channel.invokeMapMethod<String, bool>('getCapabilities');
      if (caps != null) {
        _hasBackgroundBlur = caps['backgroundBlur'] ?? false;
        _hasLowLight = caps['lowLight'] ?? false;
        _hasSharpening = caps['sharpening'] ?? true;
        _hasHardwareNoiseSuppressor = caps['hardwareNoiseSuppressor'] ?? false;
        _hasVad = caps['vad'] ?? false;
        _gpuDelegate = caps['gpuDelegate'] ?? false;
      }
      _initialized = true;
      debugPrint('✅ LiteRTService initialized — caps: $caps');
    } on MissingPluginException {
      // Running on a platform without the native implementation (web, desktop)
      _initialized = true;
      debugPrint('⚠️ LiteRTService: native channel not available on this platform');
    } catch (e) {
      debugPrint('⚠️ LiteRTService initialization error: $e');
    }

    notifyListeners();
  }

  // ── Video track registration ──────────────────────────────────────────────

  /// Attach the LiteRT video processor to the local video track identified by
  /// [trackId].  Must be called once after the local video track is created
  /// (i.e. after getUserMedia / room.localParticipant.publishVideoTrack).
  ///
  /// On Android this delegates to [FlutterWebRTCPlugin.sharedSingleton]
  /// .getLocalTrack(trackId).addProcessor(). On iOS the processor runs on
  /// every CVPixelBuffer delivered to the Flutter plugin — no per-track hook.
  Future<void> registerVideoTrack(String trackId) async {
    await _invoke('registerVideoTrack', {'trackId': trackId});
    debugPrint('📷 LiteRT video processor registered for track $trackId');
  }

  // ── Remote video processing (for non-native senders) ─────────────────────

  /// Attach LiteRT low-light + sharpening to a remote video [trackId].
  /// Returns a Flutter texture ID that can be rendered with `Texture`.
  Future<int?> attachRemoteProcessing(String trackId) async {
    if (kIsWeb) return null;
    try {
      final result = await _channel.invokeMethod<int>('attachRemoteProcessing', {
        'trackId': trackId,
      });
      debugPrint('📺 LiteRT remote attached: $trackId -> textureId $result');
      return result;
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('⚠️ attachRemoteProcessing($trackId) error: $e');
      return null;
    }
  }

  /// Detach and release remote processor resources for a [trackId].
  Future<void> detachRemoteProcessing(String trackId) async {
    await _invoke('detachRemoteProcessing', {'trackId': trackId});
  }

  // ── Video controls ────────────────────────────────────────────────────────

  Future<void> setBackgroundBlur(bool enabled, {double? blurRadius}) async {
    if (!_hasBackgroundBlur && enabled) {
      debugPrint('⚠️ Background blur model not loaded — ignoring request');
      return;
    }
    _backgroundBlurEnabled = enabled;
    if (blurRadius != null) _blurRadius = blurRadius;
    await _invoke('setBackgroundBlur', {
      'enabled': enabled,
      'blurRadius': _blurRadius,
    });
    notifyListeners();
  }

  Future<void> setLowLightEnhancement(bool enabled) async {
    // Always available: uses Zero-DCE model when loaded, adaptive gamma otherwise.
    _lowLightEnabled = enabled;
    await _invoke('setLowLightEnhancement', {'enabled': enabled});
    notifyListeners();
  }

  Future<void> setSharpening(bool enabled) async {
    _sharpeningEnabled = enabled;
    await _invoke('setSharpening', {'enabled': enabled});
    notifyListeners();
  }

  Future<void> setBlurRadius(double radius) async {
    _blurRadius = radius.clamp(1.0, 50.0);
    if (_backgroundBlurEnabled) {
      await _invoke('setBackgroundBlur', {
        'enabled': true,
        'blurRadius': _blurRadius,
      });
    }
    notifyListeners();
  }

  // ── Audio controls ────────────────────────────────────────────────────────

  Future<void> setNoiseSuppression(bool enabled) async {
    _noiseSuppressorEnabled = enabled;
    await _invoke('setNoiseSuppression', {'enabled': enabled});
    notifyListeners();
  }

  Future<void> setLoudnessGain(int gainMb) async {
    _loudnessGainMb = gainMb.clamp(0, 900);
    _loudnessEnhancerEnabled = _loudnessGainMb > 0;
    await _invoke('setLoudnessGain', {'gainMb': _loudnessGainMb});
    notifyListeners();
  }

  Future<void> setVadEnabled(bool enabled) async {
    _vadEnabled = enabled && _hasVad;
    await _invoke('setVadEnabled', {'enabled': _vadEnabled});
    notifyListeners();
  }

  /// Attach audio processors to the WebRTC audio session.
  /// [audioSessionId] — obtained from the native WebRTC audio track.
  /// Call after the call/room connects and the local audio track is live.
  Future<void> attachAudio(int audioSessionId) async {
    await _invoke('attachAudio', {'audioSessionId': audioSessionId});
    debugPrint('🎙️ LiteRT audio processors attached to session $audioSessionId');
  }

  Future<void> detachAudio() async {
    await _invoke('detachAudio', {});
  }

  /// Returns raw stats from the native audio processor (for diagnostics).
  Future<Map<String, dynamic>> getAudioStats() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getAudioStats');
      return result ?? {};
    } catch (e) {
      return {};
    }
  }

  // ── Convenience: apply default "call quality boost" profile ──────────────

  /// Enables a sensible default set of enhancements for a typical video call.
  Future<void> applyCallProfile({
    bool blur = false,
    bool lowLight = true,
    bool sharpening = true,
    bool noiseSuppression = true,
    int loudnessGainMb = 200,
  }) async {
    if (blur) await setBackgroundBlur(true);
    await setLowLightEnhancement(lowLight);
    await setSharpening(sharpening);
    await setNoiseSuppression(noiseSuppression);
    await setLoudnessGain(loudnessGainMb);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _invoke(String method, Map<String, dynamic> args) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      // Platform without native LiteRT — ignore silently
    } catch (e) {
      debugPrint('⚠️ LiteRTService._invoke($method) error: $e');
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> disposeProcessors() async {
    await _invoke('dispose', {});
    _initialized = false;
  }

  @override
  void dispose() {
    disposeProcessors();
    super.dispose();
  }
}
