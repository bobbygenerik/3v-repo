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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  bool _showContactsView = true; // true = Contacts, false = History

    @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _placeholderAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    final displayName = user?.displayName ?? user?.email?.split('@')[0] ?? 'User';
    
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with logo and profile
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo
                  Image.asset(
                    'assets/images/logo.png',
                    height: 50,
                    fit: BoxFit.contain,
                  ),
                  // Profile menu
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      switch (value) {
                        case 'profile':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ProfileScreen()),
                          );
                          break;
                        case 'guest':
                          _showGuestLinkDialog();
                          break;
                        case 'settings':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          );
                          break;
                        case 'signout':
                          await authService.signOut();
                          break;
                      }
                    },
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primaryBlue,
                      backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null
                          ? Text(
                              _getUserInitial(user),
                              style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person), SizedBox(width: 12), Text('Profile')])),
                      const PopupMenuItem(value: 'guest', child: Row(children: [Icon(Icons.share), SizedBox(width: 12), Text('Create Guest Link')])),
                      const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings), SizedBox(width: 12), Text('Settings')])),
                      const PopupMenuItem(value: 'signout', child: Row(children: [Icon(Icons.logout, color: Colors.red), SizedBox(width: 12), Text('Sign Out', style: TextStyle(color: Colors.red))])),
                    ],
                  ),
                ],
              ),
            ),

            // Welcome message
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: Text(
                'Welcome, $displayName',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Search Bar with animated placeholder
                  AnimatedBuilder(
                    animation: _placeholderAnimationController,
                    builder: (context, child) {
                      return TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search ${_placeholders[_currentPlaceholderIndex]}',
                          prefixIcon: const Icon(Icons.alternate_email, color: AppColors.textLight),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.person_add, color: AppColors.accentBlue),
                            onPressed: () {
                              // TODO: Add contact
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Add contact coming soon!')),
                              );
                            },
                          ),

            const SizedBox(height: 16),

            // Contacts / History toggle buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _showContactsView = true),
                      icon: const Icon(Icons.people, size: 18),
                      label: const Text('Contacts'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showContactsView ? AppColors.primaryBlue : AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _showContactsView = false),
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('History'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_showContactsView ? AppColors.primaryBlue : AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _showContactsView ? 'Your Contacts' : 'Call History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Content area
            Expanded(
              child: _showContactsView ? _buildContactsList() : _buildHistoryList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    // TODO: Connect to Firestore for real contacts
    final contacts = [
      {'name': 'Bobby Generik', 'email': 'bgkalt001@gmail.com', 'initial': 'B'},
    ];

    if (contacts.isEmpty) {
      return _buildEmptyState('No contacts yet', 'Add contacts to start calling');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return Card(
          color: AppColors.primaryDark,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primaryBlue,
              child: Text(
                contact['initial']!,
                style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              contact['name']!,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              contact['email']!,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.star_border, color: Colors.grey),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Favorites coming soon!')),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.phone, color: AppColors.primaryBlue),
                  onPressed: () => _showStartCallDialog(recipient: contact['email']),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryList() {
    // TODO: Connect to Firestore for real call history
    final history = <Map<String, String>>[];

    if (history.isEmpty) {
      return _buildEmptyState('No call history', 'Your recent calls will appear here');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final call = history[index];
        return Card(
          color: AppColors.primaryDark,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.phone, color: AppColors.primaryBlue),
            title: Text('To: ${call['recipient']}', style: const TextStyle(color: Colors.white)),
            subtitle: Text('VIDEO • ${call['duration']}', style: TextStyle(color: Colors.grey.shade500)),
            trailing: Text(call['time']!, style: TextStyle(color: Colors.grey.shade600)),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showGuestLinkDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Guest link generation coming soon!')),
    );
  }

  void _showStartCallDialog({String? recipient}) {
    final roomController = TextEditingController(text: recipient ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Start a Call'),
        content: TextField(
          controller: roomController,
          decoration: const InputDecoration(
            labelText: 'Room Name or Email',
            hintText: 'Enter recipient',
            prefixIcon: Icon(Icons.alternate_email),
          ),
          autofocus: recipient == null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final roomName = roomController.text.trim();
              if (roomName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a room name')),
                );
                return;
              }
              Navigator.pop(context);
              _startCall(roomName);
            },
            icon: const Icon(Icons.video_call),
            label: const Text('Start'),
          ),
        ],
      ),
    );
  }

  void _showShareLinkDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link sharing coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _startCall(String roomName) async {
    // TODO: Get token from Firebase Functions and start call
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Call functionality requires backend token generation'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  String _getUserInitial(dynamic user) {
    if (user?.displayName?.isNotEmpty == true) {
      return user!.displayName![0].toUpperCase();
    } else if (user?.email?.isNotEmpty == true) {
      return user!.email![0].toUpperCase();
    }
    return 'U';
  }
}
