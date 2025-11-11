import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/guest_link_service.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  bool _showContactsView = true;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _callHistory = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoadingContacts = true;
  bool _isLoadingHistory = true;

  // Ticker animation for search placeholder
  int _currentPlaceholderIndex = 0;
  final List<String> _placeholders = ['Username', 'Email', 'Phone'];
  late AnimationController _tickerController;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadCallHistory();
    _searchController.addListener(_filterContacts);

    // Ticker animation
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _startTickerAnimation();
  }

  void _startTickerAnimation() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _currentPlaceholderIndex =
              (_currentPlaceholderIndex + 1) % _placeholders.length;
        });
        _startTickerAnimation();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tickerController.dispose();
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

  String _getUserInitial(user) {
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName![0].toUpperCase();
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email![0].toUpperCase();
    }
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: const Color(
        0xFF1C1C1E,
      ), // Dark background matching screenshot
      body: SafeArea(
        child: Column(
          children: [
            // Header Row: Logo and Profile
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                24,
                16,
                0,
              ), // Added top padding to move logo down
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo - left aligned with matching edge distance
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 0,
                    ), // 16px from edge (same as profile from right)
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 60,
                      fit: BoxFit.contain,
                    ),
                  ),
                  // Profile button - right aligned with ring
                  PopupMenuButton<String>(
                    offset: const Offset(0, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: const Color(0xFF2C2C2E),
                    onSelected: (value) {
                      switch (value) {
                        case 'profile':
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                          break;
                        case 'guest_link':
                          _showGuestLinkDialog();
                          break;
                        case 'settings':
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsScreen(),
                            ),
                          );
                          break;
                        case 'signout':
                          _signOut();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'profile',
                        child: Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 20,
                              color: Color(0xFF6B7FB8),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Profile',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'guest_link',
                        child: Row(
                          children: [
                            Icon(
                              Icons.link,
                              size: 20,
                              color: Color(0xFF6B7FB8),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Create Guest Link',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(
                              Icons.settings,
                              size: 20,
                              color: Color(0xFF6B7FB8),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Settings',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'signout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 20, color: Colors.red),
                            const SizedBox(width: 12),
                            Text(
                              'Sign Out',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF6B7FB8), // Main app color ring
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF6B7FB8),
                        backgroundImage: user?.photoURL != null
                            ? NetworkImage(user!.photoURL!)
                            : null,
                        child: user?.photoURL == null
                            ? Text(
                                _getUserInitial(user),
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 80),

            // Welcome Message - CENTERED
            const Center(
              child: Text(
                'Welcome, Bobby Generik',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Search Box - EXACT match to screenshot
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E), // Charcoal gray
                  borderRadius: BorderRadius.circular(12), // Less rounded
                  border: Border.all(color: const Color(0xFF3A3A3C), width: 1),
                ),
                child: Row(
                  children: [
                    // @ symbol
                    const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child: Text(
                        '@',
                        style: TextStyle(
                          fontSize: 20,
                          color: Color(0xFF8E8E93), // Gray color
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Search text and placeholder
                    Expanded(
                      child: _searchController.text.isEmpty
                          ? Row(
                              children: [
                                const Text(
                                  'Search ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _placeholders[_currentPlaceholderIndex],
                                  style: const TextStyle(
                                    color: Color(0xFF8E8E93),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            )
                          : TextField(
                              controller: _searchController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                    ),
                    // Add person icon - opens add contact dialog
                    GestureDetector(
                      onTap: () => _showAddContactDialog(),
                      child: Container(
                        padding: const EdgeInsets.only(right: 12, left: 8),
                        child: const Icon(
                          Icons.person_add,
                          color: Color(0xFF6B7FB8),
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Contacts / History buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _showContactsView = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showContactsView
                            ? const Color(0xFF6B7FB8)
                            : const Color(0xFF2C2C2E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _showContactsView
                                ? const Color(0xFF6B7FB8)
                                : const Color(0xFF3A3A3C),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.people, size: 18),
                          const SizedBox(width: 8),
                          Text('Contacts', style: TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          setState(() => _showContactsView = false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_showContactsView
                            ? const Color(0xFF6B7FB8)
                            : const Color(0xFF2C2C2E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: !_showContactsView
                                ? const Color(0xFF6B7FB8)
                                : const Color(0xFF3A3A3C),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.history, size: 18),
                          const SizedBox(width: 8),
                          Text('History', style: TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _showContactsView ? 'Your Contacts' : 'Call History',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _showContactsView
                  ? _buildContactsList()
                  : _buildHistoryList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    if (_isLoadingContacts) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6B7FB8)),
      );
    }

    if (_filteredContacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No contacts yet'
                  : 'No contacts found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Large avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF6B7FB8),
                backgroundImage: contact['photoURL'] != null
                    ? NetworkImage(contact['photoURL'])
                    : null,
                child: contact['photoURL'] == null
                    ? Text(
                        contact['name'][0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              // Name and email
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contact['email'],
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              // Star icon
              IconButton(
                icon: const Icon(
                  Icons.star_border,
                  color: Color(0xFF8E8E93),
                  size: 22,
                ),
                onPressed: () {},
              ),
              // Phone icon
              IconButton(
                icon: const Icon(
                  Icons.phone,
                  color: Color(0xFF6B7FB8),
                  size: 22,
                ),
                onPressed: () => _startCallWithContact(contact),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6B7FB8)),
      );
    }

    if (_callHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'No call history yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _callHistory.length,
      itemBuilder: (context, index) {
        final call = _callHistory[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFF6B7FB8),
                child: Icon(Icons.phone, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call['roomName'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(call['timestamp']),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.phone,
                  color: Color(0xFF6B7FB8),
                  size: 20,
                ),
                onPressed: () {},
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _startCallWithContact(Map<String, dynamic> contact) async {
    final email = contact['email'] as String;
    await _startCall(email);
  }

  Future<void> _startCall(String recipientEmail) async {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF6B7FB8)),
        ),
      );

      final roomName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getLiveKitToken');

      final response = await callable.call({
        'calleeId': recipientEmail,
        'roomName': roomName,
      });

      final token = response.data['token'] as String;
      final wsUrl =
          response.data['wsUrl'] as String? ?? 'wss://livekit.iptvsubz.fun';

      if (mounted) Navigator.pop(context);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CallScreen(roomName: roomName, token: token, livekitUrl: wsUrl),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting call: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error starting call: $e')));
      }
    }
  }

  void _showAddContactDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Contact', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the email address of the person you want to add.',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email Address',
                labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                hintText: 'contact@example.com',
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3A3A3C)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF6B7FB8)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter an email address'),
                  ),
                );
                return;
              }

              if (!email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid email address'),
                  ),
                );
                return;
              }

              Navigator.pop(context);

              try {
                // Search for user by email
                final snapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: email)
                    .limit(1)
                    .get();

                if (snapshot.docs.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No user found with that email'),
                      ),
                    );
                  }
                  return;
                }

                final userData = snapshot.docs.first.data();
                final contactUid = snapshot.docs.first.id;

                // Add to contacts list in UI (in real app, save to Firestore)
                if (mounted) {
                  setState(() {
                    _contacts.add({
                      'uid': contactUid,
                      'name':
                          userData['displayName'] ??
                          userData['name'] ??
                          'Unknown',
                      'email': userData['email'] ?? '',
                      'photoURL': userData['photoURL'],
                    });
                    _filterContacts();
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Added ${userData['displayName'] ?? email} to contacts!',
                      ),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error adding contact: $e');
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B7FB8),
            ),
            child: const Text('ADD', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showGuestLinkDialog() {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Create Guest Link',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Generate a link for guests to join calls without an account.',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Guest Name',
                labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                hintText: 'John Doe',
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a guest name')),
                );
                return;
              }

              Navigator.pop(context);

              try {
                final guestLinkService = GuestLinkService();
                final roomName =
                    'guest_${DateTime.now().millisecondsSinceEpoch}';
                final link = await guestLinkService.generateGuestLink(
                  roomName: roomName,
                  guestName: name,
                );

                if (mounted && link != null) {
                  await Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Guest link copied to clipboard!'),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error generating guest link: $e');
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B7FB8),
            ),
            child: const Text(
              'GENERATE',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Color(0xFF8E8E93)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'SIGN OUT',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await context.read<AuthService>().signOut();
    }
  }
}
