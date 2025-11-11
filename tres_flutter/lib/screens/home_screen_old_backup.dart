import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../config/app_theme.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _roomNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roomNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
        ),
        title: null,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.call), text: 'Calls'),
            Tab(icon: Icon(Icons.contacts), text: 'Contacts'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: CircleAvatar(
                backgroundColor: AppColors.primaryBlue,
                child: user?.photoURL != null
                    ? ClipOval(
                        child: Image.network(
                          user!.photoURL!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              _getUserInitial(user),
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      )
                    : Text(
                        _getUserInitial(user),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
              tooltip: 'Profile',
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildCallsTab(),
              _buildContactsTab(),
              _buildSettingsTab(user),
            ],
          ),
        ),
      ),
      floatingActionButton:
          _tabController.index == 0 || _tabController.index == 1
          ? FloatingActionButton.extended(
              onPressed: () => _showStartCallDialog(),
              icon: const Icon(Icons.video_call),
              label: const Text('New Call'),
            )
          : null,
    );
  }

  Widget _buildCallsTab() {
    // TODO: Connect to real Firestore call history
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_end, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No call history yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Your call history will appear here',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _showStartCallDialog(),
            icon: const Icon(Icons.video_call),
            label: const Text('Start Your First Call'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsTab() {
    // TODO: Connect to real Firestore contacts
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contacts_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No contacts yet',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Share your room link to connect with others',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _showStartCallDialog(),
            icon: const Icon(Icons.share),
            label: const Text('Create Room & Share Link'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(dynamic user) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User Profile Card
        Card(
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    child: Text(
                      (user?.displayName?.isNotEmpty == true
                          ? user!.displayName![0].toUpperCase()
                          : user?.email?[0].toUpperCase() ?? 'U'),
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.displayName ??
                        user?.phoneNumber ??
                        user?.email ??
                        'User',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to view profile',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Quick Settings
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('All Settings'),
                subtitle: const Text('Video, audio, notifications'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                subtitle: const Text('Edit your profile'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Help & About
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAboutDialog(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('Report Issue'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Issue reporting coming soon'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showStartCallDialog({String? defaultRoom}) {
    _roomNameController.text = defaultRoom ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a Call'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(
                labelText: 'Room Name',
                hintText: 'Enter room name',
                prefixIcon: Icon(Icons.meeting_room),
              ),
              autofocus: defaultRoom == null,
            ),
            const SizedBox(height: 16),
            const Text(
              'Note: LiveKit server must be configured with proper URL and token generation',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final roomName = _roomNameController.text.trim();
              if (roomName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a room name')),
                );
                return;
              }

              Navigator.of(context).pop();

              // TODO: Get token from backend
              // For now, show configuration needed
              _showLiveKitConfigNeeded();
            },
            icon: const Icon(Icons.video_call),
            label: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _showLiveKitConfigNeeded() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('LiveKit Configuration Needed'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To start video calls, configure:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('1. LiveKit server URL (Cloud or self-hosted)'),
              SizedBox(height: 8),
              Text('2. Token generation API endpoint'),
              SizedBox(height: 8),
              Text('3. Update LiveKitService with credentials'),
              SizedBox(height: 16),
              Text(
                'See Android implementation:\n'
                '• LiveKitManager.kt\n'
                '• Firebase Functions for token gen\n'
                '• Or direct API integration',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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

  // _showVideoQualityDialog removed (unused)

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About 3V Video Chat'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, size: 64, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              '3V Video Chat',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Version 1.0.0'),
            SizedBox(height: 16),
            Text(
              'Flutter version with full feature parity:\n'
              '• HD video calls\n'
              '• In-call chat & reactions\n'
              '• ML filters & effects\n'
              '• End-to-end encryption\n'
              '• Cloud recording\n'
              '• Screen sharing',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

enum CallType { video, audio }

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
          Text('Welcome!', style: Theme.of(context).textTheme.headlineMedium),
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

String _getUserInitial(dynamic user) {
  if (user?.displayName?.isNotEmpty == true) {
    return user!.displayName![0].toUpperCase();
  } else if (user?.email?.isNotEmpty == true) {
    return user!.email![0].toUpperCase();
  }
  return "U";
}
