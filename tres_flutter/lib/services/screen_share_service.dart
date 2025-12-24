import 'dart:async';
import 'package:flutter/foundation.dart';

/// Minimal inert ScreenShareService stub.
///
/// Screen sharing has been removed for stability. This stub preserves the
/// public API so callers do not need further changes, but methods are
/// no-ops and return failure/disabled results.
enum ScreenShareStatus { notSharing, requestingPermission, sharing, failed }

enum ScreenResolution { hd720p, fullHd1080p, qhd1440p, auto }

class ScreenShareService extends ChangeNotifier {
  static const String _tag = 'ScreenShare';

  ScreenShareStatus _status = ScreenShareStatus.notSharing;
  ScreenShareStatus get status => _status;
  bool get isSharing => _status == ScreenShareStatus.sharing;

  Future<void> initialize(dynamic /* room */ _) async {
    debugPrint('$_tag: initialize called on inert stub');
  }

  Future<bool> startScreenShare({ScreenResolution? resolution, int? fps}) async {
    debugPrint('$_tag: startScreenShare called but screen sharing is disabled');
    _status = ScreenShareStatus.failed;
    notifyListeners();
    return false;
  }

  Future<bool> stopScreenShare() async {
    debugPrint('$_tag: stopScreenShare called on inert stub');
    _status = ScreenShareStatus.notSharing;
    notifyListeners();
    return true;
  }

  Future<bool> toggleScreenShare({ScreenResolution? resolution, int? fps}) async {
    return await startScreenShare(resolution: resolution, fps: fps);
  }

  Future<bool> updateResolution(ScreenResolution resolution) async {
    debugPrint('$_tag: updateResolution called on inert stub');
    return false;
  }

  Future<bool> updateFps(int fps) async {
    debugPrint('$_tag: updateFps called on inert stub');
    return false;
  }

  Map<String, dynamic> getStats() {
    return {
      'status': _status.toString(),
      'isSharing': isSharing,
    };
  }

  static bool isSupported() => false;

  Future<void> cleanup() async {
    debugPrint('$_tag: cleanup called on inert stub');
    _status = ScreenShareStatus.notSharing;
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
