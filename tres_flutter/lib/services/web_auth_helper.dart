import 'dart:html' as html;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Web-specific helper for phone authentication
/// Handles reCAPTCHA initialization and verification
class WebAuthHelper {
  static bool _recaptchaInitialized = false;

  /// Initialize reCAPTCHA verifier for phone authentication on web
  static Future<void> initializeRecaptcha() async {
    if (_recaptchaInitialized) return;

    try {
      // Ensure the recaptcha container exists
      final container = html.document.getElementById('recaptcha-container');
      if (container == null) {
        throw Exception('recaptcha-container element not found in HTML');
      }

      // Clear any existing reCAPTCHA
      container.innerHtml = '';

      _recaptchaInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize reCAPTCHA: $e');
      rethrow;
    }
  }

  /// Reset reCAPTCHA state
  static void resetRecaptcha() {
    _recaptchaInitialized = false;
    final container = html.document.getElementById('recaptcha-container');
    if (container != null) {
      container.innerHtml = '';
    }
  }

  /// Send phone verification code with proper error handling
  static Future<ConfirmationResult> sendVerificationCode(
    FirebaseAuth auth,
    String phoneNumber,
  ) async {
    try {
      await initializeRecaptcha();

      // Sign in with phone number - Firebase will automatically use the recaptcha-container
      final confirmationResult = await auth.signInWithPhoneNumber(phoneNumber);

      return confirmationResult;
    } catch (e) {
      debugPrint('Error sending verification code: $e');
      rethrow;
    }
  }
}
