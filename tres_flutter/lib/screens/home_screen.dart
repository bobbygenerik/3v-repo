import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('3V Video Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
            },
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam,
              size: 100,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              user?.phoneNumber ?? user?.email ?? 'User',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Video calling is ready! Configure LiveKit URL and token generation, then use the button below to start a call.',
                textAlign: TextAlign.center,
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _showCallSetupDialog(context);
              },
              icon: const Icon(Icons.settings),
              label: const Text('Configure LiveKit'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Get proper room name and token from backend
          // For now, show message about configuration
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Configure LiveKit URL and generate token first. '
                'See FLUTTER_MIGRATION.md for setup instructions.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        },
        icon: const Icon(Icons.video_call),
        label: const Text('Start Call'),
      ),
    );
  }
  
  void _showCallSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('LiveKit Configuration'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To enable video calls, you need:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('1. LiveKit Cloud account or self-hosted server'),
              SizedBox(height: 8),
              Text('2. Backend API to generate access tokens'),
              SizedBox(height: 8),
              Text('3. Configure LIVEKIT_URL in app'),
              SizedBox(height: 16),
              Text(
                'See Android app for reference:\n'
                '• LiveKitManager.kt has token generation\n'
                '• Uses Firebase Functions or direct API\n'
                '• Tokens are room-scoped with TTL',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
