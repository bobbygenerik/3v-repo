import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'config/environment.dart';
import 'config/app_theme.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/livekit_service.dart';
import 'services/guest_link_service.dart';
import 'services/notification_service.dart';
import 'firebase_background_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with auto-generated options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Register background message handler BEFORE calling runApp
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize notifications (non-blocking)
  NotificationService.initialize();

  // Ensure local notification plugin has a channel for calls (Android)
  try {
    final flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'call_channel',
      'Calls',
      description: 'Incoming call notifications',
      importance: Importance.high,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  } catch (e) {
    // ignore
  }
  
  // Print environment configuration in debug mode
  Environment.printConfig();
  
  // Validate environment configuration
  if (!Environment.validate()) {
    debugPrint('⚠️  Warning: Some environment variables are not configured');
    debugPrint('Please update lib/config/environment.dart with your credentials');
  }
  
  runApp(const TresApp());
}

class TresApp extends StatelessWidget {
  const TresApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => LiveKitService()),
        ChangeNotifierProvider(create: (_) => GuestLinkService()),
      ],
      child: MaterialApp(
        title: 'Três3',
        theme: AppTheme.darkTheme,
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == widgets.ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.backgroundDark,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accentBlue),
            ),
          );
        }
        
        // User is signed in
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }
        
        // User is signed out
        return const AuthScreen();
      },
    );
  }
}
