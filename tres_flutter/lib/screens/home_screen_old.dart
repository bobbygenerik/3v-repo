import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/guest_link_service.dart';
import '../services/call_signaling_service.dart';
import '../services/contact_service.dart';
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
  final CallSignalingService _signalingService = CallSignalingService();
  final ContactService _contactService = ContactService();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callHistorySub;
  StreamSubscription<List<String>>? _favoritesSub;
  bool _showContactsView = true;
  List<Map<String, dynamic>> _contacts = [];
  List<String> _favoriteIds = [];
  List<Map<String, dynamic>> _callHistory = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoadingContacts = true;
  bool _isLoadingHistory = true;
  
  // Animated search placeholder - ticker style
  int _currentPlaceholderIndex = 0;
  final List<String> _placeholders = ['Username', 'Email', 'Phone'];
  late AnimationController _tickerController;
  late Animation<double> _tickerAnimation;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadCallHistory();
    _favoritesSub = _contactService.getFavoritesStream().listen((favorites) {
      if (mounted) {
        setState(() {
          _favoriteIds = favorites;
        });
      }
    });
    _searchController.addListener(_filterContacts);
    
    // Ticker animation like old airport signs
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _tickerAnimation = CurvedAnimation(
      parent: _tickerController,
      curve: Curves.easeInOut,
    );
    
    _startTickerAnimation();
  }

  void _startTickerAnimation() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _tickerController.forward().then((_) {
          setState(() {
            _currentPlaceholderIndex = (_currentPlaceholderIndex + 1) % _placeholders.length;
          });
          _tickerController.reset();
          _startTickerAnimation();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _callHistorySub?.cancel();
    _favoritesSub?.cancel();
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
    final currentUser = context.read<AuthService>().currentUser;
    if (currentUser == null) return;

    _callHistorySub?.cancel();
    _isLoadingHistory = true;
    _callHistorySub = FirebaseFirestore.instance
        .collection('calls')
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
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
    }, onError: (e) {
      debugPrint('Error listening to call history: $e');
      setState(() => _isLoadingHistory = false);
    });
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
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Logo and Profile - EXACT spacing
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo - same size and position as Android
                  Image.asset(
                    'assets/images/logo.png',
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                  // Profile dropdown button
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
                      const PopupMenuItem(
                        value: 'profile',
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 20, color: AppColors.accentBlue),
                            SizedBox(width: 12),
                            Text('Profile', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'guest_link',
                        child: Row(
                          children: [
                            Icon(Icons.link, size: 20, color: AppColors.accentBlue),
                            SizedBox(width: 12),
                            Text('Create Guest Link', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.settings, size: 20, color: AppColors.accentBlue),
                            SizedBox(width: 12),
                            Text('Settings', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'signout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Sign Out', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primaryBlue,
                      backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null
                          ? Text(
                              _getUserInitial(user),
                              style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // Welcome Message - CENTERED like Android
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: Text(
                  'Welcome, ${user?.displayName ?? 'User'}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Search Box - EXACT Android design with @ and add contact button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryDark,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // @ symbol
                    const Padding(
                      padding: EdgeInsets.only(left: 20, right: 12),
                      child: Text(
                        '@',
                        style: TextStyle(
                          fontSize: 24,
                          color: AppColors.accentBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Search input with ticker animation
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
                        ),
                      ),
                    ),
                    // Add Contact button - EXACT Android style
                    IconButton(
                      onPressed: _showAddContactDialog,
                      icon: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: AppColors.accentBlue, size: 20),
                          Icon(Icons.person, color: AppColors.accentBlue, size: 20),
                        ],
                      ),
                      padding: const EdgeInsets.only(right: 16),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Toggle Buttons - EXACT Android style
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _showContactsView = true),
                      icon: const Icon(Icons.people, size: 20),
                      label: const Text('Contacts', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showContactsView ? AppColors.primaryBlue : Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: _showContactsView ? AppColors.primaryBlue : AppColors.primaryDark,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _showContactsView = false),
                      icon: const Icon(Icons.history, size: 20),
                      label: const Text('History', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_showContactsView ? AppColors.primaryBlue : Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: !_showContactsView ? AppColors.primaryBlue : AppColors.primaryDark,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section Header - EXACT Android style
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _showContactsView ? 'Your Contacts' : 'Call History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Content Area
            Expanded(
              child: _showContactsView ? _buildContactsList() : _buildHistoryList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Avatar - EXACT Android size
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primaryBlue,
                backgroundImage: contact['photoURL'] != null ? NetworkImage(contact['photoURL']) : null,
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
              // Contact info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact['name'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contact['email'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // Star icon
              IconButton(
                icon: Icon(
                  _favoriteIds.contains(contact['uid'])
                      ? Icons.star
                      : Icons.star_border,
                  color: _favoriteIds.contains(contact['uid'])
                      ? AppColors.accentBlue
                      : Colors.white54,
                  size: 24,
                ),
                onPressed: () async {
                  try {
                    await _contactService.toggleFavorite(contact['uid']);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update favorite: $e')),
                      );
                    }
                  }
                },
              ),
              // Call button
              IconButton(
                icon: const Icon(Icons.phone, color: AppColors.accentBlue, size: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _callHistory.length,
      itemBuilder: (context, index) {
        final call = _callHistory[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryBlue,
              child: Icon(Icons.phone, color: Colors.white, size: 24),
            ),
            title: Text(
              call['roomName'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
            ),
            subtitle: Text(
              '${_formatTimestamp(call['timestamp'])}',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.phone, color: AppColors.accentBlue, size: 20),
              onPressed: () {
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

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showAddContactDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Contact', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: emailController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Email or Username',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            hintText: 'user@example.com',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: AppColors.backgroundDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.accentBlue),
            ),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter an email or username')),
                );
                return;
              }
              Navigator.pop(context);
              // TODO: Add contact to Firestore
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Added $email to contacts')),
              );
              _loadContacts(); // Reload contacts
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            child: const Text('ADD', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
          child: CircularProgressIndicator(color: AppColors.accentBlue),
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
      final wsUrl = response.data['wsUrl'] as String? ?? 'wss://livekit.iptvsubz.fun';

      if (mounted) Navigator.pop(context);

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
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Guest Name',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                hintText: 'John Doe',
                filled: true,
                fillColor: AppColors.backgroundDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            child: const Text('GENERATE', style: TextStyle(color: Colors.white)),
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
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SIGN OUT', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await context.read<AuthService>().signOut();
    }
  }
}
