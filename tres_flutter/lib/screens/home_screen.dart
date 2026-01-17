import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/web_reload_stub.dart'
    if (dart.library.html) '../utils/web_reload_web.dart';
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
import '../widgets/skeleton_loader.dart';
import '../services/vibration_service.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';
import 'incoming_call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showContactsView = true;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _callHistory = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoadingContacts = true;
  bool _isLoadingHistory = true;
  bool _searchHasFocus = false;
  StreamSubscription<QuerySnapshot>? _callHistorySub;
  final Map<String, Map<String, dynamic>> _userCache = {};
  
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
    
    // Defer data loading until after first frame to avoid context issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadContacts();
        _loadCallHistory();
      }
    });
    
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
    
    // Defer context-dependent initialization until after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Pick a random welcome message for this session
        _currentWelcomeIndex = DateTime.now().millisecond % _welcomeMessages.length;
        final user = context.read<AuthService>().currentUser;
        _currentWelcomeText = '${_welcomeMessages[_currentWelcomeIndex]}${user?.displayName ?? user?.email?.split('@')[0] ?? 'Guest'}';
        _setupLetterAnimations();
        
        // Play animation once
        _textAnimationController.forward().then((_) {
          if (mounted) {
            setState(() => _hasAnimated = true);
          }
        });
        
        // Request notification permissions after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _requestNotificationPermissions();
          }
        });
      }
    });
  }
  
  Future<void> _requestNotificationPermissions() async {
    try {
      // Check if already granted
      final alreadyEnabled = await NotificationService.areNotificationsEnabled();
      if (alreadyEnabled) {
        debugPrint('✅ Notifications already enabled');
        return;
      }
      
      // Show explanation dialog first for better UX
      if (!mounted) return;
      
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.notifications_active, color: Color(0xFF0175C2), size: 28),
              SizedBox(width: 12),
              Text('Enable Notifications', style: TextStyle(color: Colors.white, fontSize: 20)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stay connected and never miss a call!',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              Text(
                '• Receive instant call notifications\n'
                '• Get notified even when app is closed\n'
                '• See who\'s calling before answering',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0175C2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Enable', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      
      if (shouldRequest == true) {
        final granted = await NotificationService.enableNotifications();
        if (granted) {
          debugPrint('✅ Notification permissions granted');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Notifications enabled successfully!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          debugPrint('⚠️ Notification permissions denied');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Notifications were not enabled. You can enable them later in Settings.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error requesting notification permissions: $e');
    }
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
      final start = index * 0.08; // Stagger each letter fade
      final end = start + 0.2;
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _textAnimationController,
          curve: Interval(
            start.clamp(0.0, 1.0),
            end.clamp(0.0, 1.0),
            curve: Curves.easeIn,
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

  @override
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tickerController.dispose();
    _textAnimationController.dispose();
    _callListener.removeListener(_handleIncomingCall);
    _callListener.stopListening();
    _callHistorySub?.cancel();
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
          .get();

      // Get full user data for each contact
      final List<Map<String, dynamic>> loadedContacts = [];
      
      for (var contactDoc in contactsSnapshot.docs) {
        final contactUid = contactDoc.id;
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(contactUid)
              .get();
          
          if (userDoc.exists) {
            final data = userDoc.data();
            if (data != null) {
              final photoURL = data['photoURL'];
              debugPrint('📸 Contact ${data['displayName']}: photoURL = "$photoURL" (type: ${photoURL.runtimeType})');
              loadedContacts.add({
                'uid': contactUid,
                'name': data['displayName'] ?? data['name'] ?? 'Unknown',
                'email': data['email'] ?? '',
                'photoURL': data['photoURL'],
              });
            } else {
              debugPrint('⚠️ Contact $contactUid exists but has no data');
            }
          }
        } catch (e) {
          debugPrint('Error loading contact $contactUid: $e');
        }
      }

      setState(() {
        _contacts = loadedContacts;
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
    if (currentUser == null) {
      setState(() => _isLoadingHistory = false);
      return;
    }

    // Cancel any previous subscription
    _callHistorySub?.cancel();

    // Listen in real-time to the 'calls' collection where this user participated.
    _callHistorySub = FirebaseFirestore.instance
        .collection('calls')
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) async {
      // 1. Collect all unique participant IDs that need fetching
      final Set<String> participantIdsToFetch = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final participants = List<String>.from(data['participants'] ?? []);

        for (final participantId in participants) {
          if (participantId != currentUser.uid && !_userCache.containsKey(participantId)) {
            participantIdsToFetch.add(participantId);
          }
        }
      }

      // 2. Fetch missing users in parallel
      if (participantIdsToFetch.isNotEmpty) {
        await Future.wait(participantIdsToFetch.map((uid) async {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
            if (userDoc.exists) {
              final userData = userDoc.data();
              if (userData != null) {
                _userCache[uid] = userData;
              }
            }
          } catch (e) {
            debugPrint('Error fetching user $uid: $e');
          }
        }));
      }

      // 3. Construct history list using cache
      final List<Map<String, dynamic>> history = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final participants = List<String>.from(data['participants'] ?? []);

        // Resolve other participant's display name if available
        String otherParticipantName = 'Unknown';
        for (final participantId in participants) {
          if (participantId != currentUser.uid) {
            final userData = _userCache[participantId];
            if (userData != null) {
              otherParticipantName = userData['displayName'] ?? userData['name'] ?? userData['email']?.split('@')[0] ?? 'Unknown User';
            }
            break;
          }
        }

        history.add({
          'id': doc.id,
          'roomName': data['roomName'] ?? 'Unknown',
          'participantName': otherParticipantName,
          'timestamp': (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          'duration': data['duration'] ?? _calculateDuration(data['startTime'] as Timestamp?, data['endTime'] as Timestamp?),
          'participants': participants,
        });
      }

      if (!mounted) return;
      setState(() {
        _callHistory = history;
        _isLoadingHistory = false;
      });
    }, onError: (e) {
      debugPrint('Error listening to call history snapshots: $e');
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
    });
  }

  int _calculateDuration(Timestamp? startTime, Timestamp? endTime) {
    if (startTime == null || endTime == null) return 0;
    final start = startTime.toDate();
    final end = endTime.toDate();
    return end.difference(start).inSeconds;
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

  Future<void> _refreshHome() async {
    if (kIsWeb) {
      await refreshWebApp();
      return;
    }

    setState(() {
      _isLoadingContacts = true;
      _isLoadingHistory = true;
    });
    await Future.wait([
      _loadContacts(),
      _loadCallHistory(),
    ]);
  }

  Future<bool> _confirmDeleteContact(Map<String, dynamic> contact) async {
    final name = (contact['name'] as String?) ?? 'this contact';
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                Text(
                  'Remove contact?',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Remove $name from your contacts list?',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF3A3A3C)),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Remove', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return confirm == true;
  }

  Future<void> _deleteContact(Map<String, dynamic> contact) async {
    final currentUser = context.read<AuthService>().currentUser;
    if (currentUser == null) return;

    try {
      final contactUid = contact['uid'] as String?;
      if (contactUid == null || contactUid.isEmpty) {
        throw Exception('Missing contact uid');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .delete();

      if (!mounted) return;
      setState(() {
        _contacts.removeWhere((c) => c['uid'] == contactUid);
        _filteredContacts.removeWhere((c) => c['uid'] == contactUid);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact removed'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error removing contact: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to remove contact'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
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

            // Welcome Message - CENTERED with fade-in animation
            AnimatedBuilder(
              animation: _textAnimationController,
              builder: (context, child) {
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_currentWelcomeText.length, (index) {
                      return Opacity(
                        opacity: _letterAnimations.length > index 
                            ? _letterAnimations[index].value
                            : (_hasAnimated ? 1.0 : 0.0),
                        child: Text(
                          _currentWelcomeText[index],
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Search Box - EXACT match to screenshot
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
                      onPressed: () {
                  VibrationService.lightImpact();
                  setState(() => _showContactsView = true);
                },
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
                      onPressed: () {
                  VibrationService.lightImpact();
                  setState(() => _showContactsView = false);
                },
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
              child: _wrapWithRefresh(
                _showContactsView ? _buildContactsList() : _buildHistoryList(),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _wrapWithRefresh(Widget child) {
    final refreshable = RefreshIndicator(
      onRefresh: _refreshHome,
      color: const Color(0xFF6B7FB8),
      backgroundColor: const Color(0xFF2C2C2E),
      child: child,
    );

    if (!kIsWeb) {
      return refreshable;
    }

    return ScrollConfiguration(
      behavior: const _WebRefreshScrollBehavior(),
      child: refreshable,
    );
  }

  Widget _buildContactsList() {
    if (_isLoadingContacts) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (context, index) => const ContactSkeleton(),
      );
    }

    if (_filteredContacts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 120),
          Center(
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
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        return Dismissible(
          key: ValueKey('contact_${contact['uid'] ?? contact['email'] ?? index}'),
          direction: DismissDirection.horizontal,
          dismissThresholds: const {
            DismissDirection.startToEnd: 0.2,
            DismissDirection.endToStart: 0.2,
          },
          confirmDismiss: (_) => _confirmDeleteContact(contact),
          onDismissed: (_) => _deleteContact(contact),
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerLeft,
            child: const Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          secondaryBackground: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.delete_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          child: Container(
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
                  onPressed: () {
                    VibrationService.mediumImpact();
                    _startCallWithContact(contact);
                  },
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: Color(0xFF6B7FB8))),
        ],
      );
    }

    if (_callHistory.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 120),
          Center(
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
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _callHistory.length,
      itemBuilder: (context, index) {
        final call = _callHistory[index];
        final duration = call['duration'] as int;
        final durationText = duration > 0 
            ? '${(duration / 60).floor()}m ${duration % 60}s'
            : 'No duration';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF6B7FB8),
                child: Text(
                  _getInitials(call['participantName']),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call['participantName'],
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatTimestamp(call['timestamp'])} • $durationText',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.phone, color: Color(0xFF6B7FB8), size: 20),
                onPressed: () {
                  // Find contact and call them
                  final participants = call['participants'] as List<String>;
                  final currentUser = context.read<AuthService>().currentUser;
                  if (currentUser != null && participants.isNotEmpty) {
                    final otherUserId = participants.firstWhere(
                      (id) => id != currentUser.uid,
                      orElse: () => '',
                    );
                    if (otherUserId.isNotEmpty) {
                      _startCall('', recipientUid: otherUserId);
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty || name == 'Unknown') return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
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
    final uid = contact['uid'] as String?;
    await _startCall(email, recipientUid: uid);
  }

  Future<void> _startCall(String recipientEmail, {String? recipientUid}) async {
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

      String recipientUserId;

      // 1. Get Recipient ID (Use provided UID or lookup by email)
      if (recipientUid != null) {
        recipientUserId = recipientUid;
        debugPrint('✅ Using provided recipient UID: $recipientUserId');
      } else {
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
        recipientUserId = recipientQuery.docs.first.id;
        debugPrint('✅ Found recipient: $recipientUserId');
      }

      final roomName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getLiveKitToken');
      
      // Use constant URL to avoid waiting for Cloud Function
      const defaultWsUrl = 'wss://livekit.iptvsubz.fun';

      debugPrint('🚀 Starting parallel initialization (Token + Invitation)');

      // 2. Run Token Generation and Invitation in Parallel
      final results = await Future.wait([
        // Task A: Get Token from Cloud Function
        callable.call({
          'calleeId': recipientEmail,
          'roomName': roomName,
        }),
        // Task B: Send Invitation via Firestore
        _signalingService.sendCallInvitation(
          recipientUserId: recipientUserId,
          roomName: roomName,
          token: '', // Recipient generates their own
          livekitUrl: defaultWsUrl,
          isVideoCall: true,
        ),
      ]);

      final callerResponse = results[0] as HttpsCallableResult;
      final invitationId = results[1] as String?;

      final callerToken = callerResponse.data['token'] as String;
      // We can use the returned URL if we want, but we already used the default for the invite
      // final wsUrl = callerResponse.data['wsUrl'] as String? ?? defaultWsUrl;

      debugPrint('✅ Parallel initialization complete');

      if (invitationId == null) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send call invitation')),
          );
        }
        return;
      }

      if (mounted) Navigator.pop(context);

      // Show calling dialog and wait for response
      bool? callAccepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CallingDialog(
          invitationId: invitationId,
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
              livekitUrl: defaultWsUrl,
              sessionService: _sessionService,
              signalingService: _signalingService,
            ),
          ),
        ).then((_) {
          // End session when returning from call
          _sessionService.endSession();
        });
      } else if (callAccepted == false && mounted) {
        // Call was cancelled or declined - show feedback
        debugPrint('📞 Call cancelled or declined by caller');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call cancelled'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error starting call: $e');
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

class _WebRefreshScrollBehavior extends MaterialScrollBehavior {
  const _WebRefreshScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
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
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;
      debugPrint('📞 Invitation status: $status');

      if (status == 'accepted') {
        // Call accepted - close dialog with true
        Navigator.of(context, rootNavigator: false).pop(true);
      } else if (status == 'declined') {
        // Call declined - close dialog with false
        Navigator.of(context, rootNavigator: false).pop(false);
        if (mounted) {
          // Use a post-frame callback to show snackbar after navigation completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call declined')),
              );
            }
          });
        }
      } else if (status == 'timeout' || status == 'cancelled') {
        // Call timed out or cancelled - close dialog with false
        Navigator.of(context, rootNavigator: false).pop(false);
      }
    });

    // Auto-cancel after 60 seconds
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) {
        widget.signalingService.cancelInvitation(widget.invitationId);
        Navigator.of(context, rootNavigator: false).pop(false);
        // Use a post-frame callback to show snackbar after navigation completes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Call not answered')),
            );
          }
        });
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
    return WillPopScope(
      onWillPop: () async {
        // Cancel invitation if user tries to go back
        widget.signalingService.cancelInvitation(widget.invitationId);
        return true;
      },
      child: AlertDialog(
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
              onPressed: () {
                widget.signalingService.cancelInvitation(widget.invitationId);
                Navigator.of(context, rootNavigator: false).pop(false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
