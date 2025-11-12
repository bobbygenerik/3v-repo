import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../config/app_theme.dart';
import 'profile_screen.dart';
import 'call_screen.dart';
// livekit service import removed (unused in this screen)

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Fields are intentionally kept for potential UI state; analyzer flagged them as unused
  // ignore: unused_field
  final bool _showContactsView = true;
  List<Map<String, dynamic>> _contacts = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _callHistory = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _filteredContacts = [];
  // ignore: unused_field
  bool _isLoadingContacts = true;
  // ignore: unused_field
  bool _isLoadingHistory = true;

  // Animated search placeholder
  int _currentPlaceholderIndex = 0;
  final List<String> _placeholders = ['Email', 'Phone', 'Display Name'];
  late AnimationController _placeholderController;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadCallHistory();
    _searchController.addListener(_filterContacts);

    // Animate placeholder
    _placeholderController =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..addListener(() {
            if (_placeholderController.isCompleted) {
              setState(() {
                _currentPlaceholderIndex =
                    (_currentPlaceholderIndex + 1) % _placeholders.length;
              });
              _placeholderController.forward(from: 0.0);
            }
          });
    _placeholderController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _placeholderController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, isNotEqualTo: currentUser.uid)
          .limit(50)
          .get();

      setState(() {
        _contacts = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'uid': doc.id,
            'name': data['displayName'] ?? data['name'] ?? 'Unknown',
            'email': data['email'] ?? '',
            'photoURL': data['photoURL'],
          };
        }).toList();
        _filteredContacts = _contacts;
        _isLoadingContacts = false;
      });
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      setState(() => _isLoadingContacts = false);
    }
  }

  Future<void> _loadCallHistory() async {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('calls')
          .where('participants', arrayContains: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      setState(() {
        _callHistory = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'roomName': data['roomName'] ?? 'Unknown',
            'timestamp': (data['timestamp'] as Timestamp?)?.toDate(),
            'duration': data['duration'] ?? 0,
            'participants': data['participants'] ?? [],
          };
        }).toList();
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Error loading call history: $e');
      setState(() => _isLoadingHistory = false);
    }
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts = _contacts.where((contact) {
        final name = (contact['name'] as String).toLowerCase();
        final email = (contact['email'] as String).toLowerCase();
        return name.contains(query) || email.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: IconButton(
              icon: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primaryBlue,
                child: user?.photoURL != null
                    ? ClipOval(
                        child: Image.network(
                          user!.photoURL!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              _getUserInitial(user),
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      )
                    : Text(
                        _getUserInitial(user),
                        style: const TextStyle(
                          fontSize: 18,
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
              tooltip: 'Profile & Settings',
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Container(
            margin: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.primaryBlue.withAlpha((0.3 * 255).round()),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(48),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(45),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Large centered logo
                    Image.asset(
                      'assets/images/logo.png',
                      height: 192,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 32),

                    // Search Bar
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search contacts or start a call...',
                        prefixIcon: const Icon(
                          Icons.alternate_email,
                          color: AppColors.accentBlue,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.primaryDark,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppColors.primaryBlue.withAlpha((0.5 * 255).round()),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppColors.primaryBlue.withAlpha((0.3 * 255).round()),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppColors.accentBlue,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {});
                      },
                    ),

                    const SizedBox(height: 16),

                    // Contacts and Call Logs buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Contacts coming soon!'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.people, size: 18),
                            label: const Text('Contacts'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentBlue,
                              side: const BorderSide(
                                color: AppColors.accentBlue,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Call history coming soon!'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('Call Logs'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentBlue,
                              side: const BorderSide(
                                color: AppColors.accentBlue,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Start Call button with gradient
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.accentBlue, AppColors.primaryBlue],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _showStartCallDialog(),
                        icon: const Icon(
                          Icons.phone,
                          size: 20,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Start Call',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
            labelText: 'Recipient Email',
            hintText: 'Enter email address',
            prefixIcon: Icon(Icons.email),
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
              final email = roomController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter recipient email')),
                );
                return;
              }
              if (!email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid email')),
                );
                return;
              }
              Navigator.pop(context);
              _startCall(email);
            },
            icon: const Icon(Icons.video_call),
            label: const Text('Start Call'),
          ),
        ],
      ),
    );
  }

  // share link dialog intentionally removed (unused)

  Future<void> _startCall(String recipientEmail) async {
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Starting call...')));
      }

      // Generate room name
      final roomName = 'room_${DateTime.now().millisecondsSinceEpoch}';

      // Call Firebase Function to get LiveKit token
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getLiveKitToken');

      final response = await callable.call({
        'calleeId': recipientEmail,
        'roomName': roomName,
      });

      final token = response.data['token'] as String;
      final wsUrl =
          response.data['wsUrl'] as String? ?? 'wss://livekit.iptvsubz.fun';

      if (mounted) {
        // Navigate to call screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CallScreen(roomName: roomName, token: token, livekitUrl: wsUrl),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start call: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error starting call: $e');
    }
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
