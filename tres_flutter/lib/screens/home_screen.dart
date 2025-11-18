import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/guest_link_service.dart';
import '../services/call_listener_service.dart';
import '../services/call_signaling_service.dart';
import '../services/call_session_service.dart';
import '../services/notification_service.dart';
import '../widgets/responsive_container.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';
import 'incoming_call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showContactsView = true;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _callHistory = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoadingContacts = true;
  bool _isLoadingHistory = true;
  bool _searchHasFocus = false;
  bool _showNotificationPrompt = false;
  
  // Call services
  final CallListenerService _callListener = CallListenerService();
  final CallSignalingService _signalingService = CallSignalingService();
  final CallSessionService _sessionService = CallSessionService();
  
  // Ticker animation for search placeholder
  int _currentPlaceholderIndex = 0;
  final List<String> _placeholders = ['Display Name', 'Email']; // Changed from 'Username'
  late AnimationController _tickerController;
  
  // Welcome message
  int _currentWelcomeIndex = 0;
  final List<String> _welcomeMessages = [
    'Welcome, ',
    'Bienvenido, ',
    'Bem-vindo, ',
  ];
  
  // Cascading text animation - only plays once
  late AnimationController _textAnimationController;
  List<Animation<double>> _letterAnimations = [];
  String _currentWelcomeText = '';
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadContacts();
    _loadCallHistory();
    _searchController.addListener(_filterContacts);
    
    // Listen to search focus changes
    _searchFocusNode.addListener(() {
      setState(() {
        _searchHasFocus = _searchFocusNode.hasFocus;
      });
    });
    
    // Start listening for incoming calls
    _callListener.startListening();
    _callListener.addListener(_handleIncomingCall);
    
    // Ticker animation
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _startTickerAnimation();
    
    // Initialize text animation controller
    _textAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    
    // Pick a random welcome message for this session
    _currentWelcomeIndex = DateTime.now().millisecond % _welcomeMessages.length;
    final user = context.read<AuthService>().currentUser;
    _currentWelcomeText = '${_welcomeMessages[_currentWelcomeIndex]}${user?.displayName ?? user?.email?.split('@')[0] ?? 'Guest'}';
    _setupLetterAnimations();
    
    // Play animation once
    _textAnimationController.forward().then((_) {
      setState(() => _hasAnimated = true);
    });
    
    // Check notification permissions
    _checkNotificationPermissions();
    
    // Ensure FCM token is saved
    _ensureFCMToken();
  }
  
  /// Handle incoming call notifications
  void _handleIncomingCall() {
    final incomingCall = _callListener.currentIncomingCall;
    if (incomingCall != null && mounted) {
      debugPrint('📞 Showing incoming call screen');
      
      // Show incoming call screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IncomingCallScreen(
            invitationId: incomingCall['id'],
            callerName: incomingCall['callerName'],
            callerId: incomingCall['callerId'],
            roomName: incomingCall['roomName'],
            token: incomingCall['token'],
            livekitUrl: incomingCall['livekitUrl'],
            isVideoCall: incomingCall['isVideoCall'],
            callerPhotoUrl: incomingCall['callerPhotoUrl'],
          ),
        ),
      ).then((_) {
        // Clear the incoming call after screen is dismissed
        _callListener.clearIncomingCall();
      });
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Refresh UI when returning to screen
      setState(() {});
    }
  }
  
  void _setupLetterAnimations() {
    _letterAnimations = List.generate(_currentWelcomeText.length, (index) {
      final start = index * 0.05; // Stagger each letter
      final end = start + 0.3;
      return Tween<double>(begin: -50.0, end: 0.0).animate(
        CurvedAnimation(
          parent: _textAnimationController,
          curve: Interval(
            start.clamp(0.0, 1.0),
            end.clamp(0.0, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      );
    });
  }

  void _startTickerAnimation() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _currentPlaceholderIndex = (_currentPlaceholderIndex + 1) % _placeholders.length;
        });
        _startTickerAnimation();
      }
    });
  }

  Future<void> _checkNotificationPermissions() async {
    final enabled = await NotificationService.areNotificationsEnabled();
    if (!enabled && mounted) {
      setState(() {
        _showNotificationPrompt = true;
      });
    }
  }
  
  Future<void> _enableNotifications() async {
    final enabled = await NotificationService.enableNotifications();
    if (enabled) {
      setState(() {
        _showNotificationPrompt = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications enabled!')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable notifications in your browser settings')),
        );
      }
    }
  }
  
  Future<void> _ensureFCMToken() async {
    try {
      final enabled = await NotificationService.areNotificationsEnabled();
      if (enabled) {
        // Force refresh FCM token
        await NotificationService.enableNotifications();
        debugPrint('✅ FCM token refreshed on startup');
      }
    } catch (e) {
      debugPrint('⚠️ Error refreshing FCM token: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tickerController.dispose();
    _textAnimationController.dispose();
    _callListener.removeListener(_handleIncomingCall);
    _callListener.stopListening();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) return;

      // Load contacts from the user's contacts subcollection
      final contactsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .limit(50) // Limit initial load
          .get();

      // Batch load user data for better performance
      final List<String> contactUids = contactsSnapshot.docs.map((doc) => doc.id).toList();
      final List<Map<String, dynamic>> loadedContacts = [];
      
      // Process in chunks to avoid overwhelming Firestore
      const chunkSize = 10;
      for (int i = 0; i < contactUids.length; i += chunkSize) {
        final chunk = contactUids.skip(i).take(chunkSize);
        final futures = chunk.map((uid) => 
          FirebaseFirestore.instance.collection('users').doc(uid).get()
        );
        
        final results = await Future.wait(futures, eagerError: false);
        
        for (int j = 0; j < results.length; j++) {
          final userDoc = results[j];
          if (userDoc.exists) {
            final data = userDoc.data();
            if (data != null) {
              loadedContacts.add({
                'uid': chunk.elementAt(j),
                'name': data['displayName'] ?? data['name'] ?? 'Unknown',
                'email': data['email'] ?? '',
                'photoURL': data['photoURL'],
              });
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _contacts = loadedContacts;
          _filteredContacts = _contacts;
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      if (mounted) setState(() => _isLoadingContacts = false);
    }
  }

  Future<void> _loadCallHistory() async {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) {
        setState(() => _isLoadingHistory = false);
        return;
      }

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
      backgroundColor: const Color(0xFF1C1C1E), // Dark background matching screenshot
      body: ResponsiveContainer(
        maxWidth: 768,
        child: SafeArea(
          child: Column(
            children: [
            // Header Row: Logo and Profile
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0), // Very close to top (8px)
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start, // Align items at their top
                children: [
                  // Logo - left aligned very close to edge, lowered 8px
                  Padding(
                    padding: const EdgeInsets.only(top: 8), // Lower logo by 8px
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 60,
                      fit: BoxFit.contain,
                    ),
                  ),
                  // Profile button - right aligned with ring, lowered 10px
                  Padding(
                    padding: const EdgeInsets.only(top: 10), // Lower profile button by 10px
                    child: PopupMenuButton<String>(
                    offset: const Offset(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    color: const Color(0xFF2C2C2E),
                    onSelected: (value) async {
                      switch (value) {
                        case 'profile':
                          await Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
                          // Refresh UI after returning from profile screen
                          setState(() {});
                          break;
                        case 'guest_link':
                          _showGuestLinkDialog();
                          break;
                        case 'settings':
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
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
                            Icon(Icons.person, size: 20, color: Color(0xFF6B7FB8)),
                            SizedBox(width: 12),
                            Text('Profile', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'guest_link',
                        child: Row(
                          children: [
                            Icon(Icons.link, size: 20, color: Color(0xFF6B7FB8)),
                            SizedBox(width: 12),
                            Text('Create Guest Link', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.settings, size: 20, color: Color(0xFF6B7FB8)),
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
                        backgroundColor: const Color(0xFF2C2C2E),
                        backgroundImage: (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                            ? NetworkImage(user.photoURL!)
                            : null,
                        child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                            ? Text(
                                _getUserInitial(user),
                                style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                    ),
                  ),
                ), // Close Padding for profile button
                ],
              ),
            ),

            const SizedBox(height: 80),

            // Welcome Message - CENTERED with cascading animation (plays once)
            AnimatedBuilder(
              animation: _textAnimationController,
              builder: (context, child) {
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_currentWelcomeText.length, (index) {
                      // If animation is complete, show text with no transform
                      if (_hasAnimated) {
                        return Text(
                          _currentWelcomeText[index],
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        );
                      }
                      // During animation, apply transforms
                      return Transform.translate(
                        offset: Offset(0, _letterAnimations.length > index ? _letterAnimations[index].value : 0),
                        child: Opacity(
                          opacity: _letterAnimations.length > index 
                              ? ((_letterAnimations[index].value + 50) / 50).clamp(0.0, 1.0)
                              : 1.0,
                          child: Text(
                            _currentWelcomeText[index],
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w400,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Notification Permission Prompt
            if (_showNotificationPrompt)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6B7FB8), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications, color: Color(0xFF6B7FB8), size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enable Notifications',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              'Get notified when someone calls you',
                              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _enableNotifications,
                        child: const Text('Enable', style: TextStyle(color: Color(0xFF6B7FB8))),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _showNotificationPrompt = false),
                        icon: const Icon(Icons.close, color: Color(0xFF8E8E93), size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            if (_showNotificationPrompt) const SizedBox(height: 16),

            // Search Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E), // Charcoal gray
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _searchHasFocus 
                        ? const Color(0xFF6B7FB8) // Blue border when focused
                        : const Color(0xFF3A3A3C), // Gray border when not focused
                    width: _searchHasFocus ? 2 : 1,
                  ),
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
                      // Search text field with placeholder
                      Expanded(
                        child: Stack(
                          children: [
                            // Placeholder text
                            if (_searchController.text.isEmpty)
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
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
                                  ),
                                ),
                              ),
                            // Actual text field (always present, transparent when empty)
                            TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              cursorColor: const Color(0xFF6B7FB8),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                fillColor: Colors.transparent,
                                filled: false,
                              ),
                            ),
                          ],
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

            const SizedBox(height: 20),            // Contacts / History buttons
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
                          SizedBox(width: 8),
                          Text('Contacts', style: TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _showContactsView = false),
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
                          SizedBox(width: 8),
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
              child: _showContactsView ? _buildContactsList() : _buildHistoryList(),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildContactsList() {
    if (_isLoadingContacts) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6B7FB8)));
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
                backgroundImage: contact['photoURL'] != null && contact['photoURL'].toString().isNotEmpty
                    ? NetworkImage(contact['photoURL'])
                    : null,
                child: contact['photoURL'] == null || contact['photoURL'].toString().isEmpty
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
                icon: const Icon(Icons.star_border, color: Color(0xFF8E8E93), size: 22),
                onPressed: () {},
              ),
              // Phone icon
              IconButton(
                icon: const Icon(Icons.phone, color: Color(0xFF6B7FB8), size: 22),
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
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6B7FB8)));
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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(call['timestamp']),
                      style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.phone, color: Color(0xFF6B7FB8), size: 20),
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

      // Get recipient user ID from email
      debugPrint('🔍 Looking up recipient by email: $recipientEmail');
      final recipientQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: recipientEmail.toLowerCase())
          .limit(1)
          .get();

      if (recipientQuery.docs.isEmpty) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not found')),
          );
        }
        return;
      }

      final recipientUserId = recipientQuery.docs.first.id;
      debugPrint('✅ Found recipient: $recipientUserId');

      final roomName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getLiveKitToken');

      debugPrint('🎫 Getting LiveKit token for caller (room: $roomName)');
      final callerResponse = await callable.call({
        'calleeId': recipientEmail,
        'roomName': roomName,
      });

      final callerToken = callerResponse.data['token'] as String;
      final wsUrl = callerResponse.data['wsUrl'] as String? ?? 'wss://livekit.iptvsubz.fun';

      debugPrint('✅ Got caller token');

      // Get a separate token for the recipient
      debugPrint('🎫 Getting LiveKit token for recipient');
      // Note: We pass the recipientEmail as calleeId so the function creates token with recipient's identity
      // This is a bit confusing - we should refactor the function to accept explicit userId parameter
      // For now, we'll generate recipient token by having recipient call the function when they accept
      
      debugPrint('✅ Got LiveKit tokens and URL');

      // Send call invitation to recipient (WITHOUT token - they'll generate it when accepting)
      debugPrint('📤 Sending call invitation to recipient');
      String? invitationId;
      try {
        invitationId = await _signalingService.sendCallInvitation(
          recipientUserId: recipientUserId,
          roomName: roomName,
          token: '', // Empty - recipient will generate their own token
          livekitUrl: wsUrl,
          isVideoCall: true,
        );
        debugPrint('📤 Call invitation result: $invitationId');
      } catch (signalError) {
        debugPrint('❌ Error in sendCallInvitation: $signalError');
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send invitation: $signalError')),
          );
        }
        return;
      }

      if (invitationId == null) {
        debugPrint('❌ sendCallInvitation returned null');
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send call invitation - please try again')),
          );
        }
        return;
      }
      
      debugPrint('✅ Call invitation sent successfully: $invitationId');

      if (mounted) Navigator.pop(context);
      
      // Show immediate feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calling $recipientEmail...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Show calling dialog and wait for response
      bool? callAccepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CallingDialog(
          invitationId: invitationId!,
          recipientEmail: recipientEmail,
          signalingService: _signalingService,
        ),
      );

      // Only navigate to call screen if call was accepted
      if (callAccepted == true && mounted) {
        // Start call session
        await _sessionService.startSession(roomName, [currentUser.uid, recipientUserId]);
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              roomName: roomName,
              token: callerToken,
              livekitUrl: wsUrl,
              sessionService: _sessionService,
            ),
          ),
        ).then((_) {
          // End session when returning from call
          _sessionService.endSession();
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error starting call: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting call: $e')),
        );
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF8E8E93))),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter an email address')),
                );
                return;
              }
              
              if (!email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid email address')),
                );
                return;
              }
              
              Navigator.pop(context);
              
              try {
                final currentUser = context.read<AuthService>().currentUser;
                if (currentUser == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('You must be signed in to add contacts')),
                    );
                  }
                  return;
                }
                
                // Convert to lowercase for case-insensitive search
                final searchEmail = email.toLowerCase();
                debugPrint('🔍 Searching for user with email: $searchEmail');
                
                // Search for user by email (case-insensitive)
                final snapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: searchEmail)
                    .limit(1)
                    .get();
                
                debugPrint('🔍 Search results: ${snapshot.docs.length} users found');
                if (snapshot.docs.isEmpty) {
                  debugPrint('❌ No users found with email: $searchEmail');
                  // Try to get all users to see what's in the database
                  try {
                    final allUsers = await FirebaseFirestore.instance
                        .collection('users')
                        .limit(10)
                        .get();
                    debugPrint('📋 Total users in database: ${allUsers.docs.length}');
                    debugPrint('📋 Sample users in database:');
                    for (var doc in allUsers.docs) {
                      final data = doc.data();
                      debugPrint('  - ${doc.id}: email="${data['email']}", displayName="${data['displayName']}"');
                    }
                  } catch (e) {
                    debugPrint('❌ Error fetching sample users: $e');
                  }
                }
                
                if (snapshot.docs.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No user found with that email. They may need to sign in first.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                  return;
                }
                
                final userData = snapshot.docs.first.data();
                final contactUid = snapshot.docs.first.id;
                
                debugPrint('✅ Found user: $contactUid, data: $userData');
                
                // Don't add yourself as a contact
                if (contactUid == currentUser.uid) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('You cannot add yourself as a contact')),
                    );
                  }
                  return;
                }
                
                // Check if contact already exists
                final existingContact = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .collection('contacts')
                    .doc(contactUid)
                    .get();
                
                if (existingContact.exists) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contact already added')),
                    );
                  }
                  return;
                }
                
                debugPrint('💾 Saving contact to Firestore (bidirectional)...');
                
                // Save to Firestore contacts subcollection (bidirectional)
                // Add them to your contacts
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .collection('contacts')
                    .doc(contactUid)
                    .set({
                      'addedAt': FieldValue.serverTimestamp(),
                    });
                
                // Add yourself to their contacts
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(contactUid)
                    .collection('contacts')
                    .doc(currentUser.uid)
                    .set({
                      'addedAt': FieldValue.serverTimestamp(),
                    });
                
                debugPrint('✅ Contact saved successfully (both ways)!');
                
                // Reload contacts to show the new one
                await _loadContacts();
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added ${userData['displayName'] ?? email} to contacts!')),
                  );
                }
              } catch (e) {
                debugPrint('Error adding contact: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B7FB8)),
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
        title: const Text('Create Guest Link', style: TextStyle(color: Colors.white)),
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF8E8E93))),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B7FB8)),
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
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF8E8E93))),
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

/// Dialog shown while waiting for recipient to accept/decline call
class _CallingDialog extends StatefulWidget {
  final String invitationId;
  final String recipientEmail;
  final CallSignalingService signalingService;

  const _CallingDialog({
    required this.invitationId,
    required this.recipientEmail,
    required this.signalingService,
  });

  @override
  State<_CallingDialog> createState() => _CallingDialogState();
}

class _CallingDialogState extends State<_CallingDialog> {
  late StreamSubscription<DocumentSnapshot> _invitationSubscription;

  @override
  void initState() {
    super.initState();
    _listenToInvitationStatus();
  }

  void _listenToInvitationStatus() {
    _invitationSubscription = FirebaseFirestore.instance
        .collection('call_invitations')
        .doc(widget.invitationId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      if (!snapshot.exists) {
        debugPrint('📞 Invitation document deleted');
        Navigator.of(context).pop(false);
        return;
      }

      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;
      debugPrint('📞 Invitation status: $status');

      if (status == 'accepted') {
        // Call accepted - close dialog with true
        Navigator.of(context).pop(true);
      } else if (status == 'declined') {
        // Call declined - close dialog with false
        Navigator.of(context).pop(false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call declined')),
          );
        }
      } else if (status == 'timeout' || status == 'cancelled') {
        // Call timed out or cancelled - close dialog with false
        Navigator.of(context).pop(false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call cancelled')),
          );
        }
      }
    }, onError: (error) {
      debugPrint('❌ Error listening to invitation: $error');
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    });

    // Auto-cancel after 60 seconds
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) {
        widget.signalingService.cancelInvitation(widget.invitationId);
        Navigator.of(context).pop(false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call not answered')),
        );
      }
    });
  }

  @override
  void dispose() {
    _invitationSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF6B7FB8)),
          const SizedBox(height: 24),
          Text(
            'Calling ${widget.recipientEmail}...',
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              try {
                await widget.signalingService.cancelInvitation(widget.invitationId);
                debugPrint('✅ Call cancelled by caller');
              } catch (e) {
                debugPrint('❌ Error cancelling call: $e');
              }
              if (mounted) {
                Navigator.of(context).pop(false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
