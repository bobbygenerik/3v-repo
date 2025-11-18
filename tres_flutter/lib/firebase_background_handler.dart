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

  // Create the notification channel on Android (safe to call repeatedly)
  try {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_callChannel);
  } catch (e) {
    // ignore - fall back to best-effort
  }

  // Prepare notification details (Android)
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    _callChannel.id,
    _callChannel.name,
    channelDescription: _callChannel.description,
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    fullScreenIntent: true,
  );

  NotificationDetails platformDetails = NotificationDetails(
    android: androidDetails,
  );

  // Use data payload fields to populate notification text
  final fromName = message.data['fromUserName'] ?? message.data['guestName'] ?? 'Unknown';
  final title = message.data['title'] ?? 'Incoming call';
  final body = message.data['body'] ?? '$fromName is calling';

  try {
    await flutterLocalNotificationsPlugin.show(
      // use a stable id for call notifications so they replace each other
      1001,
      title,
      body,
      platformDetails,
      payload: message.data['invitationId'] ?? message.data['invitationId'] ?? '',
    );
  } catch (e) {
    // best-effort: if notification fails, nothing else to do in background
  }
}
