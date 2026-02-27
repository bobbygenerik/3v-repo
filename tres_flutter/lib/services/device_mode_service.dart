import 'package:flutter/foundation.dart' show kIsWeb;
// Web imports are guarded
import 'web_platform_stub.dart' if (dart.library.html) 'web_platform_impl.dart';
import 'dart:io' show Platform;

/// Simple device / runtime mode helpers centralized for consistent checks
class DeviceModeService {
  /// Detect Safari running as a PWA (standalone) — true only on web
  static bool isSafariPwa() {
    if (!kIsWeb) return false;
    try {
      final ua = webUserAgent().toLowerCase();
      final isSafari =
          ua.contains('safari') &&
          !ua.contains('chrome') &&
          !ua.contains('crios') &&
          !ua.contains('fxios');

      var isStandalone = false;
      try {
        isStandalone = webMatchMediaStandalone();
      } catch (_) {}
      try {
        if (webNavigatorStandalone()) isStandalone = true;
      } catch (_) {}

      return isSafari && isStandalone;
    } catch (_) {
      return false;
    }
  }

  static bool isAndroidNative() {
    try {
      return !kIsWeb && Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static bool isIosNative() {
    try {
      return !kIsWeb && Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Platform label for backend metadata and codec decisions.
  static String platformLabel() {
    if (kIsWeb) {
      if (isSafariPwa()) return 'ios-pwa';
      return 'web';
    }
    if (isAndroidNative()) return 'android';
    if (isIosNative()) return 'ios';
    return 'unknown';
  }
}
