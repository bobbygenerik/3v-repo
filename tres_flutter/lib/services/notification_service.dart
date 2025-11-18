import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;
  
  static Future<bool> requestPermissions() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        criticalAlert: false,
      );
      
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (e) {
      debugPrint('⚠️ Permission request failed: $e');
      return false;
    }
  }
  
  static Future<void> initialize() async {
    if (_initialized) return;
    
    // Check current permission status first
    NotificationSettings settings = await _messaging.getNotificationSettings();
    
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      // Don't auto-request on initialization - let user trigger it
      debugPrint('📱 Notifications not determined - waiting for user action');
      _initialized = true;
      return;
    }
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await _setupToken();
    }
    
    _initialized = true;
  }
  
  static Future<bool> enableNotifications() async {
    bool granted = await requestPermissions();
    
    if (granted) {
      await _setupToken();
      return true;
    }
    
    return false;
  }
  
  static Future<void> _setupToken() async {
    try {
      String? token;
      if (kIsWeb) {
        token = await _messaging.getToken(
          vapidKey: 'BFK4jHQlX-hagn0gXdag3CJ5U8cD3x2sI_1GemoCGT95Gdqrpwb1SNkPOISh0zaR7jBamKsqnX9eArZfm50DgJI',
        );
      } else {
        token = await _messaging.getToken();
      }
      
      if (token != null) {
        debugPrint('📱 FCM Token: ${token.substring(0, 20)}...');
        await _saveTokenToFirestore(token);
        
        // Also save to local storage as backup
        if (kIsWeb) {
          try {
            // Use SharedPreferences for web
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('fcm_token', token);
          } catch (e) {
            debugPrint('⚠️ Failed to save token locally: $e');
          }
        }
      }
      
      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 FCM Token refreshed');
        _saveTokenToFirestore(newToken);
      });
    } catch (e) {
      debugPrint('⚠️ FCM token setup error: $e');
    }
  }
  
  static Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Use set with merge to create document if it doesn't exist
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
              'fcmToken': token,
              'tokenUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        debugPrint('✅ FCM token saved to Firestore');
      } else {
        debugPrint('⚠️ No user logged in, cannot save FCM token');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to save FCM token: $e');
      // Retry once
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'fcmToken': token}, SetOptions(merge: true));
          debugPrint('✅ FCM token saved on retry');
        }
      } catch (retryError) {
        debugPrint('❌ FCM token save failed on retry: $retryError');
      }
    }
  }
  
  static Future<bool> areNotificationsEnabled() async {
    NotificationSettings settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }
}