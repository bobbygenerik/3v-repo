import 'package:firebase_auth/firebase_auth.dart';

/// Stub for non-web platforms
class WebAuthHelper {
  static Future<void> initializeRecaptcha() async {
    // No-op on non-web platforms
  }

  static void resetRecaptcha() {
    // No-op on non-web platforms
  }

  static Future<ConfirmationResult> sendVerificationCode(
    FirebaseAuth auth,
    String phoneNumber,
  ) async {
    throw UnsupportedError(
      'Phone auth on this platform uses verifyPhoneNumber',
    );
  }
}
