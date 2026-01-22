import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/environment.dart';

class IceServerConfig {
  static const String _prefsKey = 'livekit_ice_servers_json';
  static String _overrideJson = '';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _overrideJson = prefs.getString(_prefsKey) ?? '';
  }

  static String get iceServersJson {
    final override = _overrideJson.trim();
    if (override.isNotEmpty) {
      return override;
    }
    return Environment.liveKitIceServersJson.trim();
  }

  static bool get isConfigured => iceServersJson.isNotEmpty;

  static Future<void> setIceServersJson(String value) async {
    final trimmed = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      _overrideJson = '';
      await prefs.remove(_prefsKey);
      return;
    }
    _overrideJson = trimmed;
    await prefs.setString(_prefsKey, trimmed);
  }

  static Future<void> updateFromTokenResponse(Map<String, dynamic> data) async {
    if (data.containsKey('iceServersJson')) {
      final raw = data['iceServersJson']?.toString().trim() ?? '';
      if (raw.isNotEmpty) {
        await setIceServersJson(raw);
      }
      return;
    }
    if (data.containsKey('iceServers')) {
      final raw = data['iceServers'];
      try {
        final encoded = jsonEncode(raw);
        if (encoded.trim().isNotEmpty) {
          await setIceServersJson(encoded);
        }
      } catch (_) {
        // Ignore invalid data
      }
    }
  }
}
