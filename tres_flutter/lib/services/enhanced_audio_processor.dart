import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:livekit_client/livekit_client.dart';

enum NoiseSuppressionLevel { off, low, medium, aggressive }

enum EchoCancellationMode { off, standard, aggressive }

class AudioStats {
  final double snr; // Signal-to-noise ratio
  final double clipping; // Clipping percentage
  final double dynamicRange; // Dynamic range in dB
  final double volume; // Average volume level
  final DateTime timestamp;

  const AudioStats({
    required this.snr,
    required this.clipping,
    required this.dynamicRange,
    required this.volume,
    required this.timestamp,
  });

  static AudioStats empty() => AudioStats(
    snr: 0,
    clipping: 0,
    dynamicRange: 0,
    volume: 0,
    timestamp: DateTime.now(),
  );
}

class EnhancedAudioProcessor extends ChangeNotifier {
  Timer? _monitoringTimer;
  StreamSubscription<AudioStats>? _audioStatsSubscription;

  bool _isMonitoring = false;
  AudioStats _currentStats = AudioStats.empty();

  // Audio processing settings
  NoiseSuppressionLevel _noiseSuppressionLevel =
      NoiseSuppressionLevel.aggressive;
  EchoCancellationMode _echoCancellationMode = EchoCancellationMode.aggressive;
  bool _voiceIsolationEnabled = true;
  bool _windNoiseReductionEnabled = true;
  bool _beamformingEnabled = true;
  double _targetGainLevel = -12.0; // dB

  // Audio quality monitoring
  final List<AudioStats> _statsHistory = [];

  AudioStats get currentStats => _currentStats;
  bool get isMonitoring => _isMonitoring;
  NoiseSuppressionLevel get noiseSuppressionLevel => _noiseSuppressionLevel;
  EchoCancellationMode get echoCancellationMode => _echoCancellationMode;

  Future<AudioCaptureOptions> configureAdvancedAudio() async {
    debugPrint('🎵 Configuring advanced audio processing');

    final audioOptions = AudioCaptureOptions(
      // Enhanced noise suppression
      noiseSuppression: _noiseSuppressionLevel != NoiseSuppressionLevel.off,

      // Advanced echo cancellation
      echoCancellation: _echoCancellationMode != EchoCancellationMode.off,

      // Automatic gain control
      autoGainControl: true,
    );

    debugPrint('   - Noise suppression: ${_noiseSuppressionLevel.name}');
    debugPrint('   - Echo cancellation: ${_echoCancellationMode.name}');
    debugPrint('   - Voice isolation: $_voiceIsolationEnabled');
    debugPrint('   - Wind noise reduction: $_windNoiseReductionEnabled');
    debugPrint('   - Beamforming: $_beamformingEnabled');
    debugPrint('   - Target gain: ${_targetGainLevel}dB');

    return audioOptions;
  }

  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // Start periodic audio quality monitoring
    _monitoringTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _collectAudioStats(),
    );

    debugPrint('🎵 Audio quality monitoring started');
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _audioStatsSubscription?.cancel();
    _monitoringTimer = null;
    _audioStatsSubscription = null;

    debugPrint('🎵 Audio quality monitoring stopped');
  }

  Future<void> _collectAudioStats() async {
    try {
      // In a real implementation, this would collect actual audio statistics
      // For now, we'll simulate realistic audio stats
      final stats = await _simulateAudioStats();

      _currentStats = stats;
      _statsHistory.add(stats);

      // Keep only recent history
      if (_statsHistory.length > 100) {
        _statsHistory.removeAt(0);
      }

      // Analyze and potentially adjust audio processing
      await _analyzeAudioQuality(stats);

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error collecting audio stats: $e');
    }
  }

  Future<AudioStats> _simulateAudioStats() async {
    // Simulate realistic audio statistics
    final random = math.Random();

    return AudioStats(
      snr: 15 + random.nextDouble() * 25, // 15-40 dB SNR
      clipping: random.nextDouble() * 0.05, // 0-5% clipping
      dynamicRange: 20 + random.nextDouble() * 40, // 20-60 dB dynamic range
      volume: -30 + random.nextDouble() * 20, // -30 to -10 dB volume
      timestamp: DateTime.now(),
    );
  }

  Future<void> _analyzeAudioQuality(AudioStats stats) async {
    bool needsAdjustment = false;

    // Check signal-to-noise ratio
    if (stats.snr < 20) {
      await _triggerNoiseReduction();
      needsAdjustment = true;
    }

    // Check for clipping
    if (stats.clipping > 0.1) {
      await _applyClippingProtection();
      needsAdjustment = true;
    }

    // Check dynamic range
    if (stats.dynamicRange < 30) {
      await _enhanceDynamicRange();
      needsAdjustment = true;
    }

    // Check volume levels
    if (stats.volume < -40 || stats.volume > -6) {
      await _adjustGainControl(stats.volume);
      needsAdjustment = true;
    }

    if (needsAdjustment) {
      debugPrint('🔧 Audio processing adjusted based on quality analysis');
    }
  }

  Future<void> _triggerNoiseReduction() async {
    if (_noiseSuppressionLevel != NoiseSuppressionLevel.aggressive) {
      _noiseSuppressionLevel = NoiseSuppressionLevel.aggressive;
      debugPrint('🔇 Increased noise suppression to aggressive level');

      // Enable additional noise reduction features
      _voiceIsolationEnabled = true;
      _windNoiseReductionEnabled = true;

      notifyListeners();
    }
  }

  Future<void> _applyClippingProtection() async {
    // Reduce gain to prevent clipping
    _targetGainLevel = math.max(-20.0, _targetGainLevel - 2.0);
    debugPrint(
      '📉 Applied clipping protection, reduced gain to ${_targetGainLevel}dB',
    );

    notifyListeners();
  }

  Future<void> _enhanceDynamicRange() async {
    // Enable advanced processing to improve dynamic range
    _beamformingEnabled = true;
    _voiceIsolationEnabled = true;

    debugPrint('📈 Enhanced dynamic range processing enabled');

    notifyListeners();
  }

  Future<void> _adjustGainControl(double currentVolume) async {
    if (currentVolume < -40) {
      // Volume too low, increase gain
      _targetGainLevel = math.min(-6.0, _targetGainLevel + 3.0);
      debugPrint('📢 Increased gain to ${_targetGainLevel}dB (volume too low)');
    } else if (currentVolume > -6) {
      // Volume too high, decrease gain
      _targetGainLevel = math.max(-20.0, _targetGainLevel - 3.0);
      debugPrint(
        '🔉 Decreased gain to ${_targetGainLevel}dB (volume too high)',
      );
    }

    notifyListeners();
  }

  void setNoiseSuppressionLevel(NoiseSuppressionLevel level) {
    if (_noiseSuppressionLevel != level) {
      _noiseSuppressionLevel = level;
      debugPrint('🔇 Noise suppression level changed to: ${level.name}');
      notifyListeners();
    }
  }

  void setEchoCancellationMode(EchoCancellationMode mode) {
    if (_echoCancellationMode != mode) {
      _echoCancellationMode = mode;
      debugPrint('🔄 Echo cancellation mode changed to: ${mode.name}');
      notifyListeners();
    }
  }

  void setVoiceIsolation(bool enabled) {
    if (_voiceIsolationEnabled != enabled) {
      _voiceIsolationEnabled = enabled;
      debugPrint('🎤 Voice isolation ${enabled ? 'enabled' : 'disabled'}');
      notifyListeners();
    }
  }

  void setWindNoiseReduction(bool enabled) {
    if (_windNoiseReductionEnabled != enabled) {
      _windNoiseReductionEnabled = enabled;
      debugPrint('💨 Wind noise reduction ${enabled ? 'enabled' : 'disabled'}');
      notifyListeners();
    }
  }

  void setBeamforming(bool enabled) {
    if (_beamformingEnabled != enabled) {
      _beamformingEnabled = enabled;
      debugPrint('📡 Beamforming ${enabled ? 'enabled' : 'disabled'}');
      notifyListeners();
    }
  }

  void setTargetGainLevel(double gainDb) {
    final clampedGain = math.max(-30.0, math.min(0.0, gainDb));
    if (_targetGainLevel != clampedGain) {
      _targetGainLevel = clampedGain;
      debugPrint('🎚️ Target gain level set to: ${clampedGain}dB');
      notifyListeners();
    }
  }

  Map<String, dynamic> getAudioProcessingSettings() {
    return {
      'noiseSuppressionLevel': _noiseSuppressionLevel.name,
      'echoCancellationMode': _echoCancellationMode.name,
      'voiceIsolationEnabled': _voiceIsolationEnabled,
      'windNoiseReductionEnabled': _windNoiseReductionEnabled,
      'beamformingEnabled': _beamformingEnabled,
      'targetGainLevel': _targetGainLevel,
    };
  }

  void applyAudioProcessingSettings(Map<String, dynamic> settings) {
    try {
      if (settings.containsKey('noiseSuppressionLevel')) {
        final levelName = settings['noiseSuppressionLevel'] as String;
        _noiseSuppressionLevel = NoiseSuppressionLevel.values.firstWhere(
          (level) => level.name == levelName,
        );
      }

      if (settings.containsKey('echoCancellationMode')) {
        final modeName = settings['echoCancellationMode'] as String;
        _echoCancellationMode = EchoCancellationMode.values.firstWhere(
          (mode) => mode.name == modeName,
        );
      }

      if (settings.containsKey('voiceIsolationEnabled')) {
        _voiceIsolationEnabled = settings['voiceIsolationEnabled'] as bool;
      }

      if (settings.containsKey('windNoiseReductionEnabled')) {
        _windNoiseReductionEnabled =
            settings['windNoiseReductionEnabled'] as bool;
      }

      if (settings.containsKey('beamformingEnabled')) {
        _beamformingEnabled = settings['beamformingEnabled'] as bool;
      }

      if (settings.containsKey('targetGainLevel')) {
        _targetGainLevel = settings['targetGainLevel'] as double;
      }

      debugPrint('🎚️ Applied audio processing settings');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error applying audio settings: $e');
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
