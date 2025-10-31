import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'config/environment.dart';
import 'config/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/livekit_service.dart';
import 'services/guest_link_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with auto-generated options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
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
        title: 'Tres',
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        
        return const AuthScreen();
      },
    );
  }
}
