import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/guest_link_service.dart';
import '../services/call_signaling_service.dart';
import '../config/app_theme.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final CallSignalingService _signalingService = CallSignalingService();
  bool _showContactsView = true; // true = Contacts, false = History
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _callHistory = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoadingContacts = true;
  bool _isLoadingHistory = true;
  
  // Animated search placeholder
  int _currentPlaceholderIndex = 0;
  final List<String> _placeholders = ['Email', 'Phone', 'Display Name'];
  late AnimationController _placeholderController;
  late AnimationController _welcomeController;
  late Animation<double> _welcomeFadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadCallHistory();
    _searchController.addListener(_filterContacts);
    
    // Animate placeholder with ticker effect
    _placeholderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _currentPlaceholderIndex = (_currentPlaceholderIndex + 1) % _placeholders.length;
            });
            _placeholderController.forward(from: 0.0);
          }
        });
      }
    });
    _placeholderController.forward();
    
    // Welcome message fade-in animation
    _welcomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _welcomeFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _welcomeController, curve: Curves.easeIn),
    );
    _welcomeController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _placeholderController.dispose();
    _welcomeController.dispose();
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

  String _getUserInitial(dynamic user) {
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName![0].toUpperCase();
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email![0].toUpperCase();
    }
    return 'U';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Logo and Profile - Equal distance from edges
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo - aligned to left
                  Image.asset(
                    'assets/images/logo.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  // Profile Button with Dropdown
                  PopupMenuButton<String>(
                    offset: const Offset(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: AppColors.primaryDark,
                    onSelected: (value) {
                      switch (value) {
                        case 'profile':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ProfileScreen()),
                          );
                          break;
                        case 'guest_link':
                          _showGuestLinkDialog();
                          break;
                        case 'settings':
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          );
                          break;
                        case 'signout':
                          _signOut();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'profile',
                        child: Row(
                          children: const [
                            Icon(Icons.person, size: 20, color: AppColors.accentBlue),
                            SizedBox(width: 12),
                            Text('Profile', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'guest_link',
                        child: Row(
                          children: const [
                            Icon(Icons.link, size: 20, color: AppColors.accentBlue),
                            SizedBox(width: 12),
                            Text('Create Guest Link', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: const [
                            Icon(Icons.settings, size: 20, color: AppColors.accentBlue),
                            SizedBox(width: 12),
                            Text('Settings', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'signout',
                        child: Row(
                          children: const [
                            Icon(Icons.logout, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Sign Out', style: TextStyle(color: Colors.red)),
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
                              style: const TextStyle(fontSize: 18, color: Colors.white),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // Centered Welcome Text with Animation
            FadeTransition(
              opacity: _welcomeFadeAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Center(
                  child: Text(
                    'Welcome, ${user?.displayName ?? 'User'}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            // Search Bar with @ icon and Add Contact button - Exact match to Android
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // @ icon
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Icon(
                        Icons.alternate_email,
                        color: AppColors.accentBlue,
                        size: 20,
                      ),
                    ),
                    // Search field with ticker animation
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Search ${_placeholders[_currentPlaceholderIndex]}',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (value) => setState(() {}),
                      ),
                    ),
                    // Clear button
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70, size: 20),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      ),
                    // Add Contact button
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        icon: const Icon(Icons.person_add, color: AppColors.accentBlue, size: 22),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Add contact feature coming soon')),
                          );
                        },
                        tooltip: 'Add Contact',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Toggle Buttons (Contacts / History)
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
                        backgroundColor: _showContactsView ? AppColors.primaryBlue : Colors.transparent,
                        foregroundColor: _showContactsView ? Colors.white : AppColors.accentBlue,
                        side: BorderSide(
                          color: _showContactsView ? AppColors.primaryBlue : AppColors.accentBlue,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        backgroundColor: !_showContactsView ? AppColors.primaryBlue : Colors.transparent,
                        foregroundColor: !_showContactsView ? Colors.white : AppColors.accentBlue,
                        side: BorderSide(
                          color: !_showContactsView ? AppColors.primaryBlue : AppColors.accentBlue,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Content Area (Contacts or History)
            Expanded(
              child: _showContactsView ? _buildContactsList() : _buildHistoryList(),
            ),

            // Start Call FAB
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => _showStartCallDialog(),
                  icon: const Icon(Icons.phone, size: 20, color: Colors.white),
                  label: const Text(
                    'Start Call',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    if (_isLoadingContacts) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
    }

    if (_filteredContacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty ? 'No contacts yet' : 'No contacts found',
              style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        return Card(
          color: AppColors.primaryDark,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primaryBlue,
              backgroundImage: contact['photoURL'] != null ? NetworkImage(contact['photoURL']) : null,
              child: contact['photoURL'] == null
                  ? Text(
                      contact['name'][0].toUpperCase(),
                      style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            title: Text(
              contact['name'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              contact['email'],
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.phone, color: AppColors.accentBlue, size: 24),
                  onPressed: () => _startCallWithContact(contact),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
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
              style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      itemCount: _callHistory.length,
      itemBuilder: (context, index) {
        final call = _callHistory[index];
        return Card(
          color: AppColors.primaryDark,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryBlue,
              child: Icon(Icons.phone, color: Colors.white, size: 24),
            ),
            title: Text(
              call['roomName'],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              '${_formatTimestamp(call['timestamp'])} • ${_formatDuration(call['duration'])}',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7)),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.phone, color: AppColors.accentBlue, size: 20),
              onPressed: () {
                // Call again with same room
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Call again feature coming soon')),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _startCallWithContact(Map<String, dynamic> contact) async {
    final email = contact['email'] as String;
    await _startCall(email);
  }

  void _showStartCallDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Start Call', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: 'Recipient Email',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                hintText: 'user@example.com',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: AppColors.backgroundDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.accentBlue),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.primaryBlue.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.accentBlue, width: 2),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter an email')),
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
              await _startCall(email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Start Call', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _startCall(String recipientEmail) async {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) return;

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppColors.accentBlue),
        ),
      );

      // Generate room name
      final roomName = 'call_${DateTime.now().millisecondsSinceEpoch}';

      // Call Firebase Function to get LiveKit token
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getLiveKitToken');

      final response = await callable.call({
        'calleeId': recipientEmail,
        'roomName': roomName,
      });

      final token = response.data['token'] as String;
      final wsUrl = response.data['wsUrl'] as String? ?? 'wss://livekit.iptvsubz.fun';

      // Dismiss loading
      if (mounted) Navigator.pop(context);

      // Navigate to call screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              roomName: roomName,
              token: token,
              livekitUrl: wsUrl,
              signalingService: _signalingService,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting call: $e');
      if (mounted) {
        // Dismiss loading if shown
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting call: $e')),
        );
      }
    }
  }

  void _showGuestLinkDialog() {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create Guest Link', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Generate a link for guests to join calls without an account.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Guest Name',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                hintText: 'John Doe',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: AppColors.backgroundDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
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
                final roomName = 'guest_${DateTime.now().millisecondsSinceEpoch}';
                final link = await guestLinkService.generateGuestLink(
                  roomName: roomName,
                  guestName: name,
                );
                
                if (mounted && link != null) {
                  await Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Guest link copied to clipboard!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to generate guest link')),
                  );
                }
              } catch (e) {
                debugPrint('Error generating guest link: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Generate Link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await context.read<AuthService>().signOut();
    }
  }
}
