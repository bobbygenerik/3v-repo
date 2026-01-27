import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'firebase_options.dart';

// Plugin instance used by background isolate
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Define an Android notification channel for incoming calls
final AndroidNotificationChannel _callChannel = AndroidNotificationChannel(
  'call_channel', // id
  'Calls', // title
  description: 'Incoming call notifications',
  importance: Importance.high,
  playSound: true,
);

/// Top-level background message handler. This runs in its own isolate when
/// messages arrive while the app is backgrounded or terminated.
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Flutter bindings & Firebase in background isolate
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('🔔 Background FCM received: ${message.data}');
  
  // Only handle call invitations in background
  final type = message.data['type'] ?? '';
  if (type != 'call_invite' && type != 'guest_joining') {
    debugPrint('⚠️ Ignoring non-call notification in background');
    return;
  }

  // Create the notification channel on Android (safe to call repeatedly)
  try {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_callChannel);
  } catch (e) {
    debugPrint('⚠️ Failed to create notification channel: $e');
  }

  // Use data payload fields to populate notification text
  final fromName = message.data['fromUserName'] ?? message.data['guestName'] ?? 'Unknown';
  final invitationId = message.data['invitationId'] ?? '';
  
  // Prepare notification details with full-screen intent
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    _callChannel.id,
    _callChannel.name,
    channelDescription: _callChannel.description,
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.call,
    playSound: true,
    enableVibration: true,
    fullScreenIntent: true,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
    timeoutAfter: 30000, // 30 seconds
    actions: [
      AndroidNotificationAction(
        'accept',
        'Accept',
        icon: DrawableResourceAndroidBitmap('ic_call_accept'),
        contextual: true,
      ),
      AndroidNotificationAction(
        'decline', 
        'Decline',
        icon: DrawableResourceAndroidBitmap('ic_call_decline'),
        contextual: true,
      ),
    ],
  );

  NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
  );

  try {
    await flutterLocalNotificationsPlugin.show(
      id: 1001, // Stable ID for call notifications
      title: '$fromName is calling',
      body: 'Tap to answer or use the buttons below',
      notificationDetails: platformDetails,
      payload: invitationId,
    );
    debugPrint('✅ Background notification shown for $fromName');
  } catch (e) {
    debugPrint('❌ Failed to show background notification: $e');
  }
}
