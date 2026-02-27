import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;

enum DevicePerformanceLevel { low, medium, high, flagship }

enum ThermalState { normal, fair, serious, critical }

enum BatteryState { unknown, unplugged, charging, full }

class DeviceProfile {
  final DevicePerformanceLevel performanceLevel;
  final ThermalState thermalState;
  final BatteryState batteryState;
  final int batteryLevel; // 0-100%
  final double cpuUsage; // 0-100%
  final double gpuUsage; // 0-100%
  final int availableMemoryMB;
  final int totalMemoryMB;
  final bool isLowPowerModeEnabled;
  final DateTime timestamp;

  const DeviceProfile({
    required this.performanceLevel,
    required this.thermalState,
    required this.batteryState,
    required this.batteryLevel,
    required this.cpuUsage,
    required this.gpuUsage,
    required this.availableMemoryMB,
    required this.totalMemoryMB,
    required this.isLowPowerModeEnabled,
    required this.timestamp,
  });

  static DeviceProfile empty() => DeviceProfile(
    performanceLevel: DevicePerformanceLevel.medium,
    thermalState: ThermalState.normal,
    batteryState: BatteryState.unknown,
    batteryLevel: 50,
    cpuUsage: 0,
    gpuUsage: 0,
    availableMemoryMB: 0,
    totalMemoryMB: 0,
    isLowPowerModeEnabled: false,
    timestamp: DateTime.now(),
  );
}

class AdvancedDeviceProfiler extends ChangeNotifier {
  Timer? _profilingTimer;

  bool _isProfiling = false;
  DeviceProfile _currentProfile = DeviceProfile.empty();

  // Profiling settings
  Duration _profilingInterval = const Duration(seconds: 15);
  int _maxHistorySize = 20;

  // Performance thresholds
  static const double _highCpuThreshold = 80.0;
  static const double _mediumCpuThreshold = 60.0;
  static const double _highGpuThreshold = 75.0;
  static const double _mediumGpuThreshold = 50.0;
  static const int _lowBatteryThreshold = 20;
  static const int _criticalBatteryThreshold = 10;

  // Device capability detection
  bool _capabilityDetected = false;
  DevicePerformanceLevel _detectedPerformanceLevel =
      DevicePerformanceLevel.medium;

  // Profiling history
  final List<DeviceProfile> _profileHistory = [];

  DeviceProfile get currentProfile => _currentProfile;
  bool get isProfiling => _isProfiling;
  List<DeviceProfile> get profileHistory => List.unmodifiable(_profileHistory);
  DevicePerformanceLevel get detectedPerformanceLevel =>
      _detectedPerformanceLevel;

  void startProfiling() {
    if (_isProfiling) return;

    _isProfiling = true;

    // Detect device capabilities if not already done
    if (!_capabilityDetected) {
      _detectDeviceCapabilities();
    }

    // Start periodic device profiling
    _profilingTimer = Timer.periodic(
      _profilingInterval,
      (_) => _collectDeviceProfile(),
    );

    debugPrint('📱 Advanced device profiler started');
  }

  void stopProfiling() {
    _isProfiling = false;
    _profilingTimer?.cancel();
    _profilingTimer = null;

    debugPrint('📱 Advanced device profiler stopped');
  }

  void _detectDeviceCapabilities() {
    try {
      // Detect device performance level based on platform and available info
      if (kIsWeb) {
        _detectedPerformanceLevel = _detectWebPerformance();
      } else if (Platform.isIOS) {
        _detectedPerformanceLevel = _detectIOSPerformance();
      } else if (Platform.isAndroid) {
        _detectedPerformanceLevel = _detectAndroidPerformance();
      } else {
        _detectedPerformanceLevel = DevicePerformanceLevel.medium;
      }

      _capabilityDetected = true;
      debugPrint(
        '📱 Device performance level detected: ${_detectedPerformanceLevel.name}',
      );
    } catch (e) {
      debugPrint('❌ Error detecting device capabilities: $e');
      _detectedPerformanceLevel = DevicePerformanceLevel.medium;
    }
  }

  DevicePerformanceLevel _detectWebPerformance() {
    // For web, we'll use a heuristic based on user agent and hardware concurrency
    final hardwareConcurrency = kIsWeb ? 4 : 2; // Simulated for now

    if (hardwareConcurrency >= 8) {
      return DevicePerformanceLevel.flagship;
    } else if (hardwareConcurrency >= 6) {
      return DevicePerformanceLevel.high;
    } else if (hardwareConcurrency >= 4) {
      return DevicePerformanceLevel.medium;
    } else {
      return DevicePerformanceLevel.low;
    }
  }

  DevicePerformanceLevel _detectIOSPerformance() {
    // In a real implementation, this would use iOS-specific APIs
    // For simulation, we'll use random assignment with realistic distribution
    final random = math.Random();
    final value = random.nextDouble();

    if (value < 0.3) return DevicePerformanceLevel.flagship; // iPhone 14/15 Pro
    if (value < 0.6) return DevicePerformanceLevel.high; // iPhone 12/13/14
    if (value < 0.85) return DevicePerformanceLevel.medium; // iPhone X/11
    return DevicePerformanceLevel.low; // Older iPhones
  }

  DevicePerformanceLevel _detectAndroidPerformance() {
    // In a real implementation, this would use Android-specific APIs
    // For simulation, we'll use random assignment with realistic distribution
    final random = math.Random();
    final value = random.nextDouble();

    if (value < 0.2) return DevicePerformanceLevel.flagship; // Flagship Android
    if (value < 0.4) return DevicePerformanceLevel.high; // High-end Android
    if (value < 0.7) return DevicePerformanceLevel.medium; // Mid-range Android
    return DevicePerformanceLevel.low; // Budget Android
  }

  Future<void> _collectDeviceProfile() async {
    try {
      // In a real implementation, this would collect actual device metrics
      // For now, we'll simulate realistic device profile data
      final profile = await _simulateDeviceProfile();

      _currentProfile = profile;
      _profileHistory.add(profile);

      // Keep only recent history
      if (_profileHistory.length > _maxHistorySize) {
        _profileHistory.removeAt(0);
      }

      // Analyze device performance and provide recommendations
      _analyzeDevicePerformance(profile);

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error collecting device profile: $e');
    }
  }

  Future<DeviceProfile> _simulateDeviceProfile() async {
    final random = math.Random();

    // Simulate thermal state based on usage
    final thermalState = _simulateThermalState();

    // Simulate battery state and level
    final batteryState = _simulateBatteryState();
    final batteryLevel = 20 + random.nextInt(80); // 20-100%

    // Simulate CPU usage (higher during video calls)
    final baseCpuUsage = _detectedPerformanceLevel == DevicePerformanceLevel.low
        ? 40.0
        : 25.0;
    final cpuUsage = baseCpuUsage + random.nextDouble() * 30; // Add variance

    // Simulate GPU usage (video rendering)
    final baseGpuUsage = _detectedPerformanceLevel == DevicePerformanceLevel.low
        ? 50.0
        : 30.0;
    final gpuUsage = baseGpuUsage + random.nextDouble() * 25; // Add variance

    // Simulate memory based on device performance level
    final totalMemory = _getExpectedMemoryForPerformanceLevel(
      _detectedPerformanceLevel,
    );
    final availableMemory =
        totalMemory - 1024 - random.nextInt(1024); // Used memory variance

    // Simulate low power mode (more likely on low battery)
    final isLowPowerMode = batteryLevel < 30 && random.nextBool();

    return DeviceProfile(
      performanceLevel: _detectedPerformanceLevel,
      thermalState: thermalState,
      batteryState: batteryState,
      batteryLevel: batteryLevel,
      cpuUsage: math.min(100.0, cpuUsage),
      gpuUsage: math.min(100.0, gpuUsage),
      availableMemoryMB: math.max(512, availableMemory),
      totalMemoryMB: totalMemory,
      isLowPowerModeEnabled: isLowPowerMode,
      timestamp: DateTime.now(),
    );
  }

  ThermalState _simulateThermalState() {
    final random = math.Random();

    // Thermal state depends on device performance level and usage
    switch (_detectedPerformanceLevel) {
      case DevicePerformanceLevel.flagship:
        // Flagship devices have better thermal management
        final value = random.nextDouble();
        if (value < 0.7) return ThermalState.normal;
        if (value < 0.95) return ThermalState.fair;
        return ThermalState.serious;

      case DevicePerformanceLevel.high:
        final value = random.nextDouble();
        if (value < 0.6) return ThermalState.normal;
        if (value < 0.85) return ThermalState.fair;
        if (value < 0.98) return ThermalState.serious;
        return ThermalState.critical;

      case DevicePerformanceLevel.medium:
        final value = random.nextDouble();
        if (value < 0.5) return ThermalState.normal;
        if (value < 0.75) return ThermalState.fair;
        if (value < 0.95) return ThermalState.serious;
        return ThermalState.critical;

      case DevicePerformanceLevel.low:
        // Low-end devices heat up more easily
        final value = random.nextDouble();
        if (value < 0.4) return ThermalState.normal;
        if (value < 0.65) return ThermalState.fair;
        if (value < 0.9) return ThermalState.serious;
        return ThermalState.critical;
    }
  }

  BatteryState _simulateBatteryState() {
    final random = math.Random();
    final value = random.nextDouble();

    if (value < 0.1) return BatteryState.full;
    if (value < 0.4) return BatteryState.charging;
    if (value < 0.9) return BatteryState.unplugged;
    return BatteryState.unknown;
  }

  int _getExpectedMemoryForPerformanceLevel(DevicePerformanceLevel level) {
    switch (level) {
      case DevicePerformanceLevel.flagship:
        return 8192; // 8GB
      case DevicePerformanceLevel.high:
        return 6144; // 6GB
      case DevicePerformanceLevel.medium:
        return 4096; // 4GB
      case DevicePerformanceLevel.low:
        return 2048; // 2GB
    }
  }

  void _analyzeDevicePerformance(DeviceProfile profile) {
    final issues = <String>[];

    // Check CPU usage
    if (profile.cpuUsage > _highCpuThreshold) {
      issues.add('High CPU usage (${profile.cpuUsage.toStringAsFixed(1)}%)');
    }

    // Check GPU usage
    if (profile.gpuUsage > _highGpuThreshold) {
      issues.add('High GPU usage (${profile.gpuUsage.toStringAsFixed(1)}%)');
    }

    // Check thermal state
    if (profile.thermalState == ThermalState.critical) {
      issues.add('Critical thermal state - device overheating');
    } else if (profile.thermalState == ThermalState.serious) {
      issues.add('Serious thermal state - device getting hot');
    }

    // Check battery level
    if (profile.batteryLevel <= _criticalBatteryThreshold) {
      issues.add('Critical battery level (${profile.batteryLevel}%)');
    } else if (profile.batteryLevel <= _lowBatteryThreshold) {
      issues.add('Low battery level (${profile.batteryLevel}%)');
    }

    // Check low power mode
    if (profile.isLowPowerModeEnabled) {
      issues.add('Low power mode enabled');
    }

    // Check available memory
    final memoryUsagePercent =
        ((profile.totalMemoryMB - profile.availableMemoryMB) /
            profile.totalMemoryMB) *
        100;
    if (memoryUsagePercent > 90) {
      issues.add(
        'Very high memory usage (${memoryUsagePercent.toStringAsFixed(1)}%)',
      );
    } else if (memoryUsagePercent > 80) {
      issues.add(
        'High memory usage (${memoryUsagePercent.toStringAsFixed(1)}%)',
      );
    }

    if (issues.isNotEmpty) {
      debugPrint('⚠️ Device performance issues detected:');
      for (final issue in issues) {
        debugPrint('   - $issue');
      }
    }
  }

  bool shouldReduceVideoQuality() {
    return _currentProfile.thermalState == ThermalState.critical ||
        _currentProfile.cpuUsage > _highCpuThreshold ||
        _currentProfile.gpuUsage > _highGpuThreshold ||
        _currentProfile.isLowPowerModeEnabled ||
        _currentProfile.batteryLevel <= _lowBatteryThreshold;
  }

  bool shouldEnablePerformanceMode() {
    return _currentProfile.thermalState == ThermalState.normal &&
        _currentProfile.cpuUsage < _mediumCpuThreshold &&
        _currentProfile.gpuUsage < _mediumGpuThreshold &&
        _currentProfile.batteryLevel > 50 &&
        !_currentProfile.isLowPowerModeEnabled;
  }

  int getRecommendedMaxBitrate() {
    if (shouldReduceVideoQuality()) {
      switch (_detectedPerformanceLevel) {
        case DevicePerformanceLevel.flagship:
          return 2000000; // 2 Mbps
        case DevicePerformanceLevel.high:
          return 1500000; // 1.5 Mbps
        case DevicePerformanceLevel.medium:
          return 1000000; // 1 Mbps
        case DevicePerformanceLevel.low:
          return 500000; // 500 kbps
      }
    } else {
      switch (_detectedPerformanceLevel) {
        case DevicePerformanceLevel.flagship:
          return 8000000; // 8 Mbps
        case DevicePerformanceLevel.high:
          return 5000000; // 5 Mbps
        case DevicePerformanceLevel.medium:
          return 3000000; // 3 Mbps
        case DevicePerformanceLevel.low:
          return 1500000; // 1.5 Mbps
      }
    }
  }

  int getRecommendedMaxFramerate() {
    if (shouldReduceVideoQuality()) {
      return _detectedPerformanceLevel == DevicePerformanceLevel.low ? 15 : 20;
    } else {
      return _detectedPerformanceLevel == DevicePerformanceLevel.low ? 24 : 30;
    }
  }

  bool shouldUse1080p() {
    return _detectedPerformanceLevel == DevicePerformanceLevel.flagship ||
        (_detectedPerformanceLevel == DevicePerformanceLevel.high &&
            shouldEnablePerformanceMode());
  }

  void setProfilingInterval(Duration interval) {
    if (_profilingInterval != interval) {
      _profilingInterval = interval;

      // Restart profiling with new interval if currently profiling
      if (_isProfiling) {
        stopProfiling();
        startProfiling();
      }

      debugPrint(
        '⏱️ Device profiling interval changed to: ${interval.inSeconds}s',
      );
    }
  }

  Map<String, dynamic> getDeviceMetrics() {
    return {
      'performanceLevel': _currentProfile.performanceLevel.name,
      'thermalState': _currentProfile.thermalState.name,
      'batteryState': _currentProfile.batteryState.name,
      'batteryLevel': _currentProfile.batteryLevel,
      'cpuUsage': _currentProfile.cpuUsage,
      'gpuUsage': _currentProfile.gpuUsage,
      'availableMemoryMB': _currentProfile.availableMemoryMB,
      'totalMemoryMB': _currentProfile.totalMemoryMB,
      'memoryUsagePercent':
          (((_currentProfile.totalMemoryMB -
                  _currentProfile.availableMemoryMB) /
              _currentProfile.totalMemoryMB) *
          100),
      'isLowPowerModeEnabled': _currentProfile.isLowPowerModeEnabled,
      'shouldReduceQuality': shouldReduceVideoQuality(),
      'shouldEnablePerformanceMode': shouldEnablePerformanceMode(),
      'recommendedMaxBitrate': getRecommendedMaxBitrate(),
      'recommendedMaxFramerate': getRecommendedMaxFramerate(),
      'shouldUse1080p': shouldUse1080p(),
    };
  }

  double getPerformanceScore() {
    double score = 1.0;

    // Thermal penalty
    switch (_currentProfile.thermalState) {
      case ThermalState.critical:
        score -= 0.4;
        break;
      case ThermalState.serious:
        score -= 0.2;
        break;
      case ThermalState.fair:
        score -= 0.1;
        break;
      case ThermalState.normal:
        break;
    }

    // CPU usage penalty
    if (_currentProfile.cpuUsage > 80) {
      score -= 0.3;
    } else if (_currentProfile.cpuUsage > 60) {
      score -= 0.15;
    }

    // Battery penalty
    if (_currentProfile.batteryLevel < 10) {
      score -= 0.2;
    } else if (_currentProfile.batteryLevel < 20) {
      score -= 0.1;
    }

    // Low power mode penalty
    if (_currentProfile.isLowPowerModeEnabled) {
      score -= 0.15;
    }

    return math.max(0.0, math.min(1.0, score));
  }

  @override
  void dispose() {
    stopProfiling();
    super.dispose();
  }
}
