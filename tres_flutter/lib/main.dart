import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'services/audio_device_service.dart';
import 'services/mediapipe_settings.dart';
import 'firebase_background_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Firebase with auto-generated options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      debugPrint('✅ Firebase auth persistence set to LOCAL');
    }
  } catch (e) {
    debugPrint('❌ Firebase initialization error: $e');
  }
  
  // Register background message handler BEFORE calling runApp
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize notifications (non-blocking)
  NotificationService.initialize();

  // Ensure local notification plugin has a channel for calls (Android)
  // Don't await - let it initialize in background
  Future.microtask(() async {
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
  });
  
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
        ChangeNotifierProvider(create: (_) => MediaPipeSettings()),
        ChangeNotifierProvider(
          create: (context) => LiveKitService(
            mediaPipeSettings: context.read<MediaPipeSettings>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => GuestLinkService()),
        ChangeNotifierProvider(create: (_) => AudioDeviceService()),
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

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    // Small delay to ensure Firebase is ready
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentBlue),
        ),
      );
    }
    
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // User is signed in
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }
        
        // User is signed out or loading
        return const AuthScreen();
      },
    );
  }
}
