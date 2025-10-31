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
  final ScrollController _scrollController = ScrollController();
  bool _showContactsView = true; // true = Contacts, false = History
  int _currentPlaceholderIndex = 0;
  final List<String> _placeholders = ['Email', 'Phone', 'Display Name', 'Username'];
  late AnimationController _placeholderAnimationController;

  @override
  void initState() {
    super.initState();
    _placeholderAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(() {
        if (_placeholderAnimationController.isCompleted) {
          setState(() {
            _currentPlaceholderIndex = (_currentPlaceholderIndex + 1) % _placeholders.length;
          });
          _placeholderAnimationController.forward(from: 0.0);
        }
      });
    _placeholderAnimationController.forward();
  }

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
                    offset: const Offset(0, 50),
                    onSelected: (value) {
                      switch (value) {
                        case 'profile':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ProfileScreen()),
                          );
                          break;
                        case 'guest_link':
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Guest link coming soon!')),
                          );
                          break;
                        case 'settings':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          );
                          break;
                        case 'crash_reports':
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Crash reports coming soon!')),
                          );
                          break;
                        case 'sign_out':
                          authService.signOut();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'profile',
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 20),
                            SizedBox(width: 12),
                            Text('Profile'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'guest_link',
                        child: Row(
                          children: [
                            Icon(Icons.share, size: 20),
                            SizedBox(width: 12),
                            Text('Create Guest Link'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.settings, size: 20),
                            SizedBox(width: 12),
                            Text('Settings'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'sign_out',
                        child: Row(
                          children: [
                            Icon(Icons.logout, color: Colors.red, size: 20),
                            SizedBox(width: 12),
                            Text('Sign Out', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'crash_reports',
                        child: Row(
                          children: [
                            Icon(Icons.bug_report, color: Colors.yellow, size: 20),
                            SizedBox(width: 12),
                            Text('Crash Reports', style: TextStyle(color: Colors.yellow)),
                          ],
                        ),
                      ),
                    ],
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primaryBlue,
                      backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null
                          ? Text(
                              _getUserInitial(user),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    
                    // Welcome text
                    Center(
                      child: Text(
                        'Welcome, $displayName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),

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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Add contact coming soon!')),
                                );
                              },
                            ),
                            filled: true,
                            fillColor: AppColors.primaryDark,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                          onChanged: (value) {
                            setState(() {});
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Toggle buttons (Contacts / History)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _showContactsView = true;
                              });
                            },
                            icon: const Icon(Icons.people, size: 20),
                            label: const Text('Contacts'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _showContactsView ? AppColors.primaryBlue : AppColors.primaryDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _showContactsView = false;
                              });
                            },
                            icon: const Icon(Icons.history, size: 20),
                            label: const Text('History'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: !_showContactsView ? AppColors.primaryBlue : AppColors.primaryDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Section title
                    Text(
                      _showContactsView ? 'Your Contacts' : 'Call History',
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // List
                    _showContactsView ? _buildContactsList() : _buildHistoryList(),

                    const SizedBox(height: 80), // Bottom padding
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    // TODO: Connect to Firestore
    final mockContacts = [
      {'name': 'Bobby Generik', 'email': 'bgkalt001@gmail.com'},
      {'name': 'bobbybrown2k1', 'email': 'bobbybrown2k1@gmail.com'},
    ];

    return Column(
      children: mockContacts.map((contact) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryBlue,
              child: Text(
                contact['name']![0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              contact['name']!,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              contact['email']!,
              style: const TextStyle(color: AppColors.textLight, fontSize: 13),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.star_border, color: AppColors.textLight, size: 22),
                  onPressed: () {
                    // TODO: Toggle favorite
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.phone, color: AppColors.accentBlue, size: 22),
                  onPressed: () => _showStartCallDialog(contact['email']),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHistoryList() {
    // TODO: Connect to Firestore
    final mockHistory = [
      {'to': 'VIDEO', 'duration': '2m 19s', 'time': '2d ago'},
      {'to': 'bobbybrown2k1', 'duration': '19s', 'time': '3d ago'},
      {'to': 'bobbybrown2k1', 'duration': '21s', 'time': '3d ago'},
      {'to': 'her', 'duration': '2m 19s', 'time': '4d ago'},
    ];

    return Column(
      children: mockHistory.map((call) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primaryBlue,
              child: const Icon(Icons.phone, color: Colors.white, size: 20),
            ),
            title: Text(
              'To: ${call['to']}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'VIDEO • ${call['duration']}',
                style: const TextStyle(color: AppColors.textLight, fontSize: 13),
              ),
            ),
            trailing: Text(
              call['time']!,
              style: const TextStyle(color: AppColors.textLight, fontSize: 12),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showStartCallDialog([String? recipient]) {
    final roomController = TextEditingController(text: recipient);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Start a Call'),
        content: TextField(
          controller: roomController,
          decoration: const InputDecoration(
            labelText: 'Email or Room Name',
            hintText: 'Enter recipient email',
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
              final room = roomController.text.trim();
              if (room.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a recipient')),
                );
                return;
              }
              Navigator.pop(context);
              _startCall(room);
            },
            icon: const Icon(Icons.video_call),
            label: const Text('Start'),
          ),
        ],
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
