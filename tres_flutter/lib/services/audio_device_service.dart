import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'dart:io' show Platform;

enum AudioOutputDevice { speaker, earpiece, bluetooth, wired }

class AudioDeviceService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('tres3/audio');

  AudioOutputDevice _currentOutput = AudioOutputDevice.speaker;
  double _volume = 1.0;
  List<AudioOutputDevice> _availableDevices = [
    AudioOutputDevice.speaker,
    AudioOutputDevice.earpiece,
  ];

  AudioOutputDevice get currentOutput => _currentOutput;
  double get volume => _volume;
  List<AudioOutputDevice> get availableDevices => _availableDevices;

  Future<void> initialize() async {
    await _detectAvailableDevices();
    await _setDefaultOutput();
  }

  Future<void> _detectAvailableDevices() async {
    _availableDevices = [];

    if (kIsWeb) {
      // Web: Only speaker available (browser controls audio routing)
      _availableDevices = [AudioOutputDevice.speaker];
    } else {
      // Mobile: Speaker and earpiece always available
      _availableDevices = [
        AudioOutputDevice.speaker,
        AudioOutputDevice.earpiece,
      ];

      // Add Bluetooth and wired on mobile platforms
      try {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          _availableDevices.add(AudioOutputDevice.bluetooth);
          _availableDevices.add(AudioOutputDevice.wired);
        }
      } catch (e) {
        debugPrint('Platform-specific device detection failed: $e');
      }
    }

    notifyListeners();
  }

  Future<void> _setDefaultOutput() async {
    // Default to speaker for video calls
    await setAudioOutput(AudioOutputDevice.speaker);
  }

  Future<void> setAudioOutput(AudioOutputDevice device) async {
    try {
      _currentOutput = device;

      // Only apply audio routing on mobile platforms
      if (!kIsWeb) {
        switch (device) {
          case AudioOutputDevice.speaker:
            await Hardware.instance.setSpeakerphoneOn(true);
            break;
          case AudioOutputDevice.earpiece:
          case AudioOutputDevice.bluetooth:
          case AudioOutputDevice.wired:
            await Hardware.instance.setSpeakerphoneOn(false);
            break;
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to set audio output: $e');
    }
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    // In a real implementation, you'd set system volume
    notifyListeners();
  }

  /// Enable/Disable spatial audio (native platform feature)
  Future<void> setSpatialAudioEnabled(bool enabled) async {
    if (kIsWeb) return; // Not supported on web via this channel
    try {
      await _channel.invokeMethod('setSpatialAudioEnabled', {
        'enabled': enabled,
      });
      debugPrint(
        'Spatial audio ${enabled ? "enabled" : "disabled"} (native request sent)',
      );
    } catch (e) {
      debugPrint('Failed to set spatial audio: $e');
    }
  }

  String getDeviceName(AudioOutputDevice device) {
    switch (device) {
      case AudioOutputDevice.speaker:
        return kIsWeb ? 'System Audio' : 'Speaker';
      case AudioOutputDevice.earpiece:
        return 'Earpiece';
      case AudioOutputDevice.bluetooth:
        return 'Bluetooth';
      case AudioOutputDevice.wired:
        return 'Wired Headphones';
    }
  }

  IconData getDeviceIcon(AudioOutputDevice device) {
    switch (device) {
      case AudioOutputDevice.speaker:
        return Icons.volume_up;
      case AudioOutputDevice.earpiece:
        return Icons.phone;
      case AudioOutputDevice.bluetooth:
        return Icons.bluetooth_audio;
      case AudioOutputDevice.wired:
        return Icons.headphones;
    }
  }
}
