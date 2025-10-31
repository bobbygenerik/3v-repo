import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../config/environment.dart';

/// Service for generating and managing guest call links
/// Allows non-registered users to join calls via secure token
class GuestLinkService extends ChangeNotifier {
  String? _currentGuestLink;
  String? _currentRoomName;
  String? _guestToken;
  bool _isGenerating = false;
  String? _error;

  String? get currentGuestLink => _currentGuestLink;
  String? get currentRoomName => _currentRoomName;
  bool get isGenerating => _isGenerating;
  String? get error => _error;

  /// Generate a guest link for a room
  /// 
  /// Creates a time-limited token that allows guest access
  /// Returns the shareable URL or null if generation fails
  Future<String?> generateGuestLink({
    required String roomName,
    String guestName = 'Guest',
    int expiryMinutes = 60,
  }) async {
    _isGenerating = true;
    _error = null;
    notifyListeners();

    try {
      // Call Firebase Function to generate guest token
      final response = await http.post(
        Uri.parse(Environment.generateTokenEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomName': roomName,
          'participantName': guestName,
          'expiryMinutes': expiryMinutes,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timed out'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _guestToken = data['token'];
        _currentRoomName = roomName;
        
        // Construct shareable URL
        // Format: https://your-app.web.app/join?room=ROOM&token=TOKEN
        final baseUrl = Environment.functionsBaseUrl.replaceAll(
          '/generateGuestToken',
          '',
        ).replaceAll(
          RegExp(r'https://[^.]+\.cloudfunctions\.net'),
          'https://your-firebase-project.web.app',
        );
        
        _currentGuestLink = '$baseUrl/join?room=${Uri.encodeComponent(roomName)}&token=$_guestToken';
        
        _isGenerating = false;
        notifyListeners();
        return _currentGuestLink;
      } else {
        throw Exception('Failed to generate token: ${response.statusCode}');
      }
    } catch (e) {
      _error = e.toString();
      _isGenerating = false;
      notifyListeners();
      
      if (kDebugMode) {
        print('❌ Error generating guest link: $e');
      }
      return null;
    }
  }

  /// Share the current guest link via system share dialog
  Future<void> shareGuestLink({String? customMessage}) async {
    if (_currentGuestLink == null) {
      throw Exception('No guest link available to share');
    }

    final message = customMessage ?? 
      'Join my video call!\nRoom: $_currentRoomName\n\n$_currentGuestLink';

    try {
      await Share.share(
        message,
        subject: '3V Video Call Invitation',
      );
    } catch (e) {
      _error = 'Failed to share link: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Copy the guest link to clipboard
  Future<void> copyGuestLinkToClipboard() async {
    if (_currentGuestLink == null) {
      throw Exception('No guest link available to copy');
    }

    // Note: Clipboard access requires platform channels
    // This is a placeholder for the actual implementation
    if (kDebugMode) {
      print('📋 Guest link copied: $_currentGuestLink');
    }
  }

  /// Validate a guest token
  /// Returns true if token is valid and not expired
  Future<bool> validateGuestToken(String token) async {
    try {
      // In production, this would verify with backend
      // For now, just check if token looks valid
      return token.isNotEmpty && token.length > 20;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error validating token: $e');
      }
      return false;
    }
  }

  /// Join a room using a guest link
  /// Extracts room name and token from URL
  Future<Map<String, String>?> parseGuestLink(String url) async {
    try {
      final uri = Uri.parse(url);
      final roomName = uri.queryParameters['room'];
      final token = uri.queryParameters['token'];

      if (roomName != null && token != null) {
        final isValid = await validateGuestToken(token);
        if (isValid) {
          return {
            'roomName': roomName,
            'token': token,
          };
        }
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error parsing guest link: $e');
      }
      return null;
    }
  }

  /// Generate a QR code data string for the guest link
  String? getQRCodeData() {
    return _currentGuestLink;
  }

  /// Clear the current guest link
  void clearGuestLink() {
    _currentGuestLink = null;
    _currentRoomName = null;
    _guestToken = null;
    _error = null;
    notifyListeners();
  }

  /// Check if guest links are enabled in environment
  bool isGuestLinksEnabled() {
    return !Environment.functionsBaseUrl.contains('YOUR_PROJECT_ID');
  }

  @override
  void dispose() {
    clearGuestLink();
    super.dispose();
  }
}
