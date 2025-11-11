import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../config/app_theme.dart';
import '../config/environment.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _hdVideoEnabled = true;
  bool _autoAnswerEnabled = false;
  String _videoQuality = 'auto';
  final String _theme = 'dark';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            children: [
              // Notifications Section
              _buildSectionHeader('Notifications'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Push Notifications'),
                      subtitle: const Text('Receive call notifications'),
                      value: _notificationsEnabled,
                      secondary: const Icon(Icons.notifications),
                      onChanged: (value) {
                        setState(() => _notificationsEnabled = value);
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Sound'),
                      subtitle: const Text('Play notification sounds'),
                      value: _soundEnabled,
                      secondary: const Icon(Icons.volume_up),
                      onChanged: (value) {
                        setState(() => _soundEnabled = value);
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Vibration'),
                      subtitle: const Text('Vibrate for incoming calls'),
                      value: _vibrationEnabled,
                      secondary: const Icon(Icons.vibration),
                      onChanged: (value) {
                        setState(() => _vibrationEnabled = value);
                      },
                    ),
                  ],
                ),
              ),

              // Video Settings Section
              _buildSectionHeader('Video & Audio'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('HD Video'),
                      subtitle: const Text('Enable high definition video'),
                      value: _hdVideoEnabled,
                      secondary: const Icon(Icons.hd),
                      onChanged: (value) {
                        setState(() => _hdVideoEnabled = value);
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.video_settings),
                      title: const Text('Video Quality'),
                      subtitle: Text(_videoQuality.toUpperCase()),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showVideoQualityDialog(),
                    ),
                  ],
                ),
              ),

              // Call Settings Section
              _buildSectionHeader('Call Settings'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Auto Answer'),
                      subtitle: const Text(
                        'Automatically answer incoming calls',
                      ),
                      value: _autoAnswerEnabled,
                      secondary: const Icon(Icons.phone_forwarded),
                      onChanged: (value) {
                        setState(() => _autoAnswerEnabled = value);
                      },
                    ),
                  ],
                ),
              ),

              // Appearance Section
              _buildSectionHeader('Appearance'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.palette),
                      title: const Text('Theme'),
                      subtitle: Text(_theme == 'dark' ? 'Dark' : 'Light'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // Theme is always dark for now (matching Android)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dark theme is the default'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Advanced Section
              _buildSectionHeader('Advanced'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.bug_report,
                        color: AppColors.accentBlue,
                      ),
                      title: const Text('Diagnostics'),
                      subtitle: const Text('View system diagnostics'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DiagnosticsScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.info_outline,
                        color: AppColors.accentBlue,
                      ),
                      title: const Text('About'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showAboutDialog(),
                    ),
                  ],
                ),
              ),

              // Account Section
              _buildSectionHeader('Account'),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        'Sign Out',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: () => _showSignOutDialog(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Version Info
              Center(
                child: Text(
                  'Version 1.0.0',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textLight),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'LiveKit: ${Environment.liveKitUrl}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryBlue,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _showVideoQualityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Video Quality'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('Auto'),
              subtitle: const Text('Adjust based on connection'),
              value: 'auto',
              groupValue: _videoQuality,
              onChanged: (value) {
                setState(() => _videoQuality = value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('High (1080p)'),
              value: 'high',
              groupValue: _videoQuality,
              onChanged: (value) {
                setState(() => _videoQuality = value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Medium (480p)'),
              value: 'medium',
              groupValue: _videoQuality,
              onChanged: (value) {
                setState(() => _videoQuality = value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Low (360p)'),
              value: 'low',
              groupValue: _videoQuality,
              onChanged: (value) {
                setState(() => _videoQuality = value!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Tres',
      applicationVersion: '1.0.0',
      applicationIcon: Image.asset(
        'assets/images/logo.png',
        width: 64,
        height: 64,
      ),
      children: [
        const Text('Secure video calling with end-to-end encryption.'),
      ],
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final authService = context.read<AuthService>();
              await authService.signOut();
              if (context.mounted) {
                Navigator.pop(context); // Go back to home
              }
            },
            child: const Text('SIGN OUT', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
