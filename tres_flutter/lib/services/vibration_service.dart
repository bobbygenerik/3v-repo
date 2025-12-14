import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_vibration_stub.dart'
    if (dart.library.js) 'web_vibration_impl.dart';

class VibrationService {
  static Future<void> vibrateIncomingCall() async {
    if (kIsWeb) {
      _webVibrate([1000, 500, 1000, 500, 1000]);
    } else if (await Vibration.hasVibrator() == true) {
      await Vibration.vibrate(pattern: [0, 1000, 500, 1000, 500, 1000], repeat: 0);
    }
  }

  static Future<void> vibrateNewMessage() async {
    if (kIsWeb) {
      _webVibrate([200, 100, 200]);
    } else if (await Vibration.hasVibrator() == true) {
      await Vibration.vibrate(pattern: [0, 200, 100, 200]);
    }
  }

  static Future<void> vibrateCallEnd() async {
    if (kIsWeb) {
      _webVibrate([300]);
    } else if (await Vibration.hasVibrator() == true) {
      await Vibration.vibrate(duration: 300);
    }
  }

  static Future<void> stopVibration() async {
    if (kIsWeb) {
      _webVibrate([]);
    } else {
      await Vibration.cancel();
    }
  }

  static void _webVibrate(List<int> pattern) {
    webVibrate(pattern);
  }
}