import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'web_auth_helper.dart' if (dart.library.io) 'web_auth_helper_stub.dart';

/// Authentication service wrapping Firebase Auth
/// Supports phone number and email/password authentication
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  ConfirmationResult? _webConfirmationResult;
  
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  bool get isSignedIn => currentUser != null;
  
  String? _verificationId;
  int? _resendToken;
  String? _errorMessage;
  
  String? get errorMessage => _errorMessage;
  bool get isVerificationPending => _verificationId != null || _webConfirmationResult != null;
  
  /// Sign in with email and password
  Future<bool> signInWithEmail(String email, String password) async {
    try {
      _errorMessage = null;
      notifyListeners();
      
      debugPrint('🔐 Attempting to sign in with email: $email');
      
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      debugPrint('✅ Sign in successful: ${credential.user?.uid}');
      return credential.user != null;
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      _errorMessage = _mapFirebaseError(e);
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected Error: $e');
      _errorMessage = 'An unexpected error occurred';
      notifyListeners();
      return false;
    }
  }
  
  /// Create account with email and password
  Future<bool> createAccountWithEmail(String email, String password) async {
    try {
      _errorMessage = null;
      notifyListeners();
      
      debugPrint('🔐 Attempting to create account with email: $email');
      
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      debugPrint('✅ Account created successfully: ${credential.user?.uid}');
      return credential.user != null;
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      _errorMessage = _mapFirebaseError(e);
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ Unexpected Error: $e');
      _errorMessage = 'An unexpected error occurred';
      notifyListeners();
      return false;
    }
  }
  
  /// Send verification code to phone number
  /// phoneNumber should be in E.164 format (e.g., +15551234567)
  Future<bool> sendPhoneVerificationCode(String phoneNumber) async {
    try {
      _errorMessage = null;
      _verificationId = null;
      _webConfirmationResult = null;
      notifyListeners();
      
      // Web-specific phone auth with reCAPTCHA
      if (kIsWeb) {
        try {
          // Initialize reCAPTCHA and send verification code
          _webConfirmationResult = await WebAuthHelper.sendVerificationCode(
            _auth,
            phoneNumber,
          );
          
          notifyListeners();
          return true;
        } catch (e) {
          _errorMessage = 'Failed to send verification code. Make sure you completed the reCAPTCHA. Error: ${e.toString()}';
          notifyListeners();
          return false;
        }
      }
      
      // Mobile phone auth
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (Android only)
          await _auth.signInWithCredential(credential);
          _verificationId = null;
          notifyListeners();
        },
        verificationFailed: (FirebaseAuthException e) {
          _errorMessage = _mapFirebaseError(e);
          _verificationId = null;
          notifyListeners();
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          notifyListeners();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          notifyListeners();
        },
        forceResendingToken: _resendToken,
      );
      
      return true;
    } catch (e) {
      _errorMessage = 'Failed to send verification code: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
  
  /// Verify phone number with SMS code
  Future<bool> verifyPhoneCode(String smsCode) async {
    try {
      _errorMessage = null;
      notifyListeners();
      
      // Web phone verification
      if (kIsWeb && _webConfirmationResult != null) {
        try {
          await _webConfirmationResult!.confirm(smsCode);
          _webConfirmationResult = null;
          notifyListeners();
          return true;
        } catch (e) {
          _errorMessage = 'Invalid verification code';
          notifyListeners();
          return false;
        }
      }
      
      // Mobile phone verification
      if (_verificationId == null) {
        _errorMessage = 'No verification in progress';
        notifyListeners();
        return false;
      }
      
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      
      await _auth.signInWithCredential(credential);
      _verificationId = null;
      notifyListeners();
      
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _mapFirebaseError(e);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Invalid verification code';
      notifyListeners();
      return false;
    }
  }
  
  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _verificationId = null;
    _errorMessage = null;
    notifyListeners();
  }
  
  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
  
  /// Clear verification state
  void clearVerification() {
    _verificationId = null;
    _webConfirmationResult = null;
    _errorMessage = null;
    notifyListeners();
  }
  
  /// Map Firebase error codes to user-friendly messages
  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please enable it in Firebase Console.';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'An account already exists with this email';
      case 'weak-password':
        return 'Password is too weak (minimum 6 characters)';
      case 'invalid-phone-number':
        return 'Invalid phone number. Use format: +15551234567';
      case 'invalid-verification-code':
        return 'Invalid verification code';
      case 'session-expired':
        return 'Verification code expired. Please request a new one';
      case 'quota-exceeded':
        return 'Too many requests. Please try again later';
      default:
        debugPrint('🔴 Unhandled Firebase error code: ${e.code}');
        return e.message ?? 'Authentication failed';
    }
  }
}
