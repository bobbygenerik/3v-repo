import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/web_reload_stub.dart'
    if (dart.library.html) '../utils/web_reload_web.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/contact_service.dart';
import '../config/app_theme.dart';
import '../services/guest_link_service.dart';
import '../services/call_listener_service.dart';
import '../services/call_signaling_service.dart';
import '../services/call_session_service.dart';
import '../services/notification_service.dart';
import '../widgets/responsive_container.dart';
import '../widgets/skeleton_loader.dart';
import '../services/vibration_service.dart';
import '../services/device_mode_service.dart';
import '../services/ice_server_config.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'call_screen.dart';
import 'incoming_call_screen.dart';
import 'dart:ui' as ui;

class HomeScreen extends StatefulWidget {
  final FirebaseFirestore? firestore;
  final CallListenerService? callListener;
  final CallSignalingService? signalingService;
  final CallSessionService? sessionService;

  const HomeScreen({
    super.key,
    this.firestore,
    this.callListener,
    this.signalingService,
    this.sessionService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showContactsView = true;
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _callHistory = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  bool _isLoadingContacts = true;
  bool _isLoadingHistory = true;
  bool _searchHasFocus = false;
  bool _showMissedCallsOnly = false; // Added for Call History tabs
  StreamSubscription<QuerySnapshot>? _callHistorySub;
  StreamSubscription<User?>? _authSub;
  final Map<String, Map<String, dynamic>> _userCache = {};

  late final FirebaseFirestore _firestore;
  late final CallListenerService _callListener;
  late final CallSignalingService _signalingService;
  late final CallSessionService _sessionService;

  // Ticker animation for search placeholder
  int _currentPlaceholderIndex = 0;
  final List<String> _placeholders = [
    'Display Name',
    'Email',
  ]; // Changed from 'Username'
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
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _callListener =
        widget.callListener ?? CallListenerService(firestore: _firestore);
    _signalingService =
        widget.signalingService ?? CallSignalingService(firestore: _firestore);
    _sessionService =
        widget.sessionService ?? CallSessionService(firestore: _firestore);

    WidgetsBinding.instance.addObserver(this);

    // Defer data loading until after first frame to avoid context issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadContacts();
        _loadCallHistory();
      }
    });

    _authSub = context.read<AuthService>().authStateChanges.listen((user) {
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _contacts = [];
          _filteredContacts = [];
          _callHistory = [];
          _isLoadingContacts = false;
          _isLoadingHistory = false;
        });
        _callHistorySub?.cancel();
        return;
      }

      _loadContacts();
      _loadCallHistory();
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
        _currentWelcomeIndex =
            DateTime.now().millisecond % _welcomeMessages.length;
        final user = context.read<AuthService>().currentUser;
        _currentWelcomeText =
            '${_welcomeMessages[_currentWelcomeIndex]}${user?.displayName ?? user?.email?.split('@')[0] ?? 'Guest'}';
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
      final alreadyEnabled =
          await NotificationService.areNotificationsEnabled();
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.notifications_active,
                color: Color(0xFF0175C2),
                size: 28,
              ),
              SizedBox(width: 12),
              Text(
                'Enable Notifications',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stay connected and never miss a call!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
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
              child: const Text(
                'Later',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0175C2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Enable',
                style: TextStyle(color: Colors.white),
              ),
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
                content: Text(
                  '⚠️ Notifications were not enabled. You can enable them later in Settings.',
                ),
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
            token: incomingCall['token'] ?? '',
            livekitUrl: incomingCall['livekitUrl'] ?? '',
            isVideoCall: incomingCall['isVideoCall'] ?? true,
            callerPhotoUrl: incomingCall['callerPhotoUrl'],
            isP2PCall: incomingCall['isP2PCall'] ?? false,
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
          _currentPlaceholderIndex =
              (_currentPlaceholderIndex + 1) % _placeholders.length;
        });
        _startTickerAnimation();
      }
    });
  }

  @override
  @override
  void dispose() {
    _authSub?.cancel();
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
      final contactsSnapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .get();

      // Get full user data for each contact using batched queries
      final List<Map<String, dynamic>> loadedContacts = [];
      final contactIds = contactsSnapshot.docs.map((doc) => doc.id).toList();
      final Map<String, Map<String, dynamic>> contactsMap = {};

      // Bolt Optimization: Fetch contacts in batches of 10 to avoid N+1 queries.
      // This reduces reads from N to N/10 and significantly speeds up loading.
      for (var i = 0; i < contactIds.length; i += 10) {
        final end = (i + 10 < contactIds.length) ? i + 10 : contactIds.length;
        final chunk = contactIds.sublist(i, end);

        if (chunk.isEmpty) continue;

        try {
          final chunkSnapshot = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (var userDoc in chunkSnapshot.docs) {
            if (!userDoc.exists) continue;
            final data = userDoc.data();
            final contactUid = userDoc.id;

            contactsMap[contactUid] = {
              'uid': contactUid,
              'name': data['displayName'] ?? data['name'] ?? 'Unknown',
              'email': data['email'] ?? '',
              'photoURL': data['photoURL'],
            };
          }
        } catch (e) {
          debugPrint('Error loading contact chunk: $e');
        }
      }

      // Reconstruct list in original order
      for (var contactId in contactIds) {
        if (contactsMap.containsKey(contactId)) {
          loadedContacts.add(contactsMap[contactId]!);
        } else {
          debugPrint(
            '⚠️ Contact $contactId exists in list but user data not found',
          );
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

    if (mounted) {
      setState(() => _isLoadingHistory = true);
    }

    // Cancel any previous subscription
    _callHistorySub?.cancel();

    // Listen in real-time to the 'calls' collection where this user participated.
    _callHistorySub = _firestore
        .collection('calls')
        .where('participants', arrayContains: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen(
          (snapshot) async {
            // 1. Collect all unique participant IDs that need fetching
            final Set<String> participantIdsToFetch = {};

            for (var doc in snapshot.docs) {
              final data = doc.data();
              final participants = List<String>.from(
                data['participants'] ?? [],
              );

              for (final participantId in participants) {
                if (participantId != currentUser.uid &&
                    !_userCache.containsKey(participantId)) {
                  participantIdsToFetch.add(participantId);
                }
              }
            }

            // 2. Fetch missing users in parallel
            // Bolt Optimization: Fetch users in batches of 10 to avoid N+1 queries
            if (participantIdsToFetch.isNotEmpty) {
              final idsList = participantIdsToFetch.toList();
              final futures = <Future<void>>[];

              for (var i = 0; i < idsList.length; i += 10) {
                final end = (i + 10 < idsList.length) ? i + 10 : idsList.length;
                final chunk = idsList.sublist(i, end);

                if (chunk.isEmpty) continue;

                futures.add(() async {
                  try {
                    final chunkSnapshot = await _firestore
                        .collection('users')
                        .where(FieldPath.documentId, whereIn: chunk)
                        .get();

                    for (var userDoc in chunkSnapshot.docs) {
                      if (userDoc.exists) {
                        final userData = userDoc.data();
                        _userCache[userDoc.id] = userData;
                      }
                    }
                  } catch (e) {
                    debugPrint('Error fetching user chunk: $e');
                  }
                }());
              }

              await Future.wait(futures);
            }

            // 3. Construct history list using cache
            final List<Map<String, dynamic>> history = [];

            for (var doc in snapshot.docs) {
              final data = doc.data();
              final participants = List<String>.from(
                data['participants'] ?? [],
              );

              // Resolve other participant's display name if available
              String otherParticipantName = 'Unknown';
              for (final participantId in participants) {
                if (participantId != currentUser.uid) {
                  final userData = _userCache[participantId];
                  if (userData != null) {
                    otherParticipantName =
                        userData['displayName'] ??
                        userData['name'] ??
                        userData['email']?.split('@')[0] ??
                        'Unknown User';
                  }
                  break;
                }
              }

              history.add({
                'id': doc.id,
                'roomName': data['roomName'] ?? 'Unknown',
                'participantName': otherParticipantName,
                'timestamp':
                    (data['timestamp'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
                'duration':
                    data['duration'] ??
                    _calculateDuration(
                      data['startTime'] as Timestamp?,
                      data['endTime'] as Timestamp?,
                    ),
                'participants': participants,
              });
            }

            if (!mounted) return;
            setState(() {
              _callHistory = history;
              _isLoadingHistory = false;
            });
          },
          onError: (e) {
            debugPrint('Error listening to call history snapshots: $e');
            if (!mounted) return;
            setState(() => _isLoadingHistory = false);
          },
        );
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
    await Future.wait([_loadContacts(), _loadCallHistory()]);
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Remove',
                          style: TextStyle(color: Colors.white),
                        ),
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

      await _firestore
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

  String _getUserInitial(dynamic user) {
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
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          color: AppColors.backgroundBlack,
        ),
        child: ResponsiveContainer(
          maxWidth: 768,
          child: SafeArea(
            child: Column(
            children: [
              // Header: Glassmorphic sticky header
              ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo - matching Sitch size
                        Padding(
                          padding: const EdgeInsets.only(top: 2), // Subtle offset for visual alignment
                          child: Image.asset(
                            'assets/images/logo_white_bg.png',
                            height: 32, // Slightly smaller for better balance
                            fit: BoxFit.contain,
                            semanticLabel: 'Tres Logo',
                          ),
                        ),
                        // Profile Button
                        PopupMenuButton<String>(
                          tooltip: 'Account Menu',
                          offset: const Offset(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: const Color(0xFF1F2128),
                          onSelected: (value) async {
                            switch (value) {
                              case 'profile':
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ProfileScreen(),
                                  ),
                                );
                                // Refresh UI after returning from profile screen
                                setState(() {});
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
                                SizedBox(width: 12),
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
                                SizedBox(width: 12),
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
                                SizedBox(width: 12),
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
                                SizedBox(width: 12),
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
                              color: const Color(
                                0xFF6B7FB8,
                              ), // Main app color ring
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF2C2C2E),
                            backgroundImage:
                                (user?.photoURL?.isNotEmpty ?? false)
                                ? CachedNetworkImageProvider(user!.photoURL!)
                                : null,
                            child: (user?.photoURL?.isEmpty ?? true)
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
              ),
            ),

              // Welcome Section - Cascading text
              _buildWelcomeSection(),

              // Search Bar
              _buildSearchBar(),

              const SizedBox(height: 32),

              // Tab Selector
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _buildTabSelector('Your Contacts', _showContactsView, () {
                      setState(() => _showContactsView = true);
                    }),
                    const SizedBox(width: 8),
                    _buildTabSelector('Call History', !_showContactsView, () {
                      setState(() => _showContactsView = false);
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: _showContactsView ? _buildContactsList() : _buildHistoryList(),
              ),
            ],
          ),
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _showAddContactDialog(),
      backgroundColor: const Color(0xFF6B7FB8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Icon(Icons.add, color: Colors.white),
    ),
  );
}

  Widget _buildTabSelector(String title, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6B7FB8) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? null : Border.all(color: Colors.white10),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
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

  Widget _buildWelcomeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            children: List.generate(_currentWelcomeText.length, (index) {
              return FadeTransition(
                opacity: _letterAnimations[index],
                child: Text(
                  _currentWelcomeText[index],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your connection is secured.',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white10),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Display Name',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.4)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false, // Ensure no default background is drawn
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0), // Adjust for vertical centering
            ),
          ),
        ),
      ),
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
                if (_searchController.text.isEmpty) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 200,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        VibrationService.lightImpact();
                        _showAddContactDialog();
                      },
                      icon: const Icon(Icons.person_add, size: 20),
                      label: const Text('Add Contact'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7FB8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Start by adding friends to call',
                    style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
                  ),
                ] else ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 200,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        VibrationService.lightImpact();
                        _searchController.clear();
                      },
                      icon: const Icon(Icons.clear, size: 20),
                      label: const Text('Clear Search'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7FB8),
                        side: const BorderSide(color: Color(0xFF6B7FB8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                ],
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
          key: ValueKey(
            'contact_${contact['uid'] ?? contact['email'] ?? index}',
          ),
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
                Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                Text(
                  'Remove',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                // Large avatar
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF6B7FB8),
                  backgroundImage:
                      contact['photoURL'] != null &&
                          contact['photoURL'].toString().isNotEmpty
                      ? CachedNetworkImageProvider(contact['photoURL'])
                      : null,
                  child:
                      contact['photoURL'] == null ||
                          contact['photoURL'].toString().isEmpty
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
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact['email'],
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Action Icons
                Row(
                  children: [
                    // Star icon
                    Consumer<ContactService>(
                      builder: (context, contactService, _) {
                        final isFavorite = contactService.isFavorite(contact['uid']);
                        return IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite ? Colors.amber : Colors.white60,
                            size: 20,
                          ),
                          onPressed: () {
                            VibrationService.lightImpact();
                            contactService.toggleFavorite(contact['uid']);
                          },
                        );
                      },
                    ),
                    // Call icon
                    IconButton(
                      icon: const Icon(Icons.call, color: Color(0xFF6B7FB8), size: 20),
                      onPressed: () => _startCallWithContact(contact),
                    ),
                  ],
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
        children: [
          const SizedBox(height: 120),
          Center(
            child: Semantics(
              label: 'Loading call history...',
              child: const CircularProgressIndicator(color: Color(0xFF6B7FB8)),
            ),
          ),
        ],
      );
    }

    final displayedHistory = _showMissedCallsOnly
        ? _callHistory.where((call) => (call['duration'] as int) == 0).toList()
        : _callHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab Filters: All / Missed
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E), // bg-surface
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHistoryTab('All', !_showMissedCallsOnly, () {
                  setState(() => _showMissedCallsOnly = false);
                }),
                _buildHistoryTab('Missed', _showMissedCallsOnly, () {
                  setState(() => _showMissedCallsOnly = true);
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // List Content
        Expanded(
          child: displayedHistory.isEmpty
              ? _buildEmptyHistoryState()
              : _buildHistoryListView(displayedHistory),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(String text, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3A3A3C) : Colors.transparent, // bg-surface-light
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF8E8E93),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHistoryState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 64,
                  color: Colors.white.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No call history yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      VibrationService.lightImpact();
                      setState(() => _showContactsView = true);
                    },
                    icon: const Icon(Icons.people, size: 20),
                    label: const Text('Find People to Call'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7FB8),
                      side: const BorderSide(color: Color(0xFF6B7FB8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  }

  Widget _buildHistoryListView(List<Map<String, dynamic>> displayedHistory) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: displayedHistory.length,
      itemBuilder: (context, index) {
        final call = displayedHistory[index];
        final duration = call['duration'] as int;
        final durationText = duration > 0
            ? '${(duration / 60).floor()}m ${duration % 60}s'
            : 'No duration';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2F3448).withOpacity(0.5), // Surface-dark
            borderRadius: BorderRadius.circular(16), // rounded-xl
            border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
          ),
          child: Row(
            children: [
              // Icon block
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7FB8).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.call,
                  color: Color(0xFF6B7FB8),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call['participantName'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          durationText,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF94A3B8), // slate-400
                          ),
                        ),
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF94A3B8),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          _formatTimestamp(call['timestamp']),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.bolt, // Matching "quick-rejoin" bolt
                  color: Color(0xFF6B7FB8),
                  size: 24,
                ),
                tooltip: 'Call back ${call['participantName']}',
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
                style: IconButton.styleFrom(
                  hoverColor: const Color(0xFF6B7FB8).withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
    final name = contact['name'] as String?;
    await _startCall(email, recipientUid: uid, recipientName: name);
  }

  Future<void> _startCall(String recipientEmail, {String? recipientUid, String? recipientName}) async {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Semantics(
            label: 'Starting call...',
            child: const CircularProgressIndicator(color: Color(0xFF6B7FB8)),
          ),
        ),
      );

      String recipientUserId;

      // 1. Get Recipient ID (Use provided UID or lookup by email)
      if (recipientUid != null) {
        recipientUserId = recipientUid;
        debugPrint('✅ Using provided recipient UID: $recipientUserId');
      } else {
        debugPrint('🔍 Looking up recipient by email: $recipientEmail');
        final recipientQuery = await _firestore
            .collection('users')
            .where('email', isEqualTo: recipientEmail.toLowerCase())
            .limit(1)
            .get();

        if (recipientQuery.docs.isEmpty) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('User not found')));
          }
          return;
        }
        recipientUserId = recipientQuery.docs.first.id;
        debugPrint('✅ Found recipient: $recipientUserId');
      }

      final roomName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      final functions = FirebaseFunctions.instance;

      debugPrint('🚀 Starting P2P call setup (ICE servers + Invitation in parallel)');

      // For 1:1 calls we use direct P2P — no LiveKit SFU token needed.
      // We still fetch ICE servers so TURN works through NAT, and send the
      // call invitation so the recipient gets a push notification.
      final results = await Future.wait([
        // Task A: Get ICE server config (no SFU token generated)
        functions.httpsCallable('getIceServers').call({}),
        // Task B: Send P2P invitation via Firestore + FCM
        _signalingService.sendCallInvitation(
          recipientUserId: recipientUserId,
          roomName: roomName,
          token: '',
          livekitUrl: '',
          isVideoCall: true,
          isP2PCall: true,
        ),
      ]);

      final iceResponse = results[0] as HttpsCallableResult;
      final invitationId = results[1] as String?;

      // Cache ICE servers so P2PCallService can use TURN.
      await IceServerConfig.updateFromTokenResponse(
        Map<String, dynamic>.from(iceResponse.data as Map),
      );

      debugPrint('✅ P2P call setup complete');

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
        await _sessionService.startSession(roomName, [
          currentUser.uid,
          recipientUserId,
        ]);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              roomName: roomName,
              sessionService: _sessionService,
              signalingService: _signalingService,
              isP2PCall: true,
              remoteUserId: recipientUserId,
              remoteUserName: recipientName ?? recipientEmail,
              isInitiator: true,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error starting call: $e')));
      }
    }
  }

  void _showAddContactDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddContactDialog(
        firestore: _firestore,
        onContactAdded: _loadContacts,
      ),
    );
  }

  void _showGuestLinkDialog() {
    final TextEditingController nameController = TextEditingController();

    Future<void> generateLink() async {
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2C2C2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.done,
                  onChanged: (text) => setState(() {}),
                  onSubmitted: (_) => generateLink(),
                  decoration: InputDecoration(
                    labelText: 'Guest Name',
                    labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                    hintText: 'John Doe',
                    filled: true,
                    fillColor: const Color(0xFF1C1C1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: nameController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Color(0xFF8E8E93),
                            ),
                            onPressed: () {
                              nameController.clear();
                              setState(() {});
                            },
                            tooltip: 'Clear name',
                          )
                        : null,
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
                onPressed: generateLink,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B7FB8),
                ),
                child: const Text(
                  'GENERATE',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
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

class _AddContactDialog extends StatefulWidget {
  final FirebaseFirestore firestore;
  final VoidCallback onContactAdded;

  const _AddContactDialog({
    required this.firestore,
    required this.onContactAdded,
  });

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _emailController = TextEditingController();
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_onTextChanged);
    _emailController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {}); // Rebuild to show/hide clear button
  }

  Future<void> _addContact() async {
    final email = _emailController.text.trim();
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

    setState(() => _isAdding = true);

    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be signed in to add contacts'),
            ),
          );
        }
        setState(() => _isAdding = false);
        return;
      }

      // Convert to lowercase for case-insensitive search
      final searchEmail = email.toLowerCase();
      debugPrint('🔍 Searching for user with email: $searchEmail');

      // Search for user by email (case-insensitive)
      final snapshot = await widget.firestore
          .collection('users')
          .where('email', isEqualTo: searchEmail)
          .limit(1)
          .get();

      if (!context.mounted) return;

      if (snapshot.docs.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No user found with that email. They may need to sign in first.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() => _isAdding = false);
        return;
      }

      final userData = snapshot.docs.first.data();
      final contactUid = snapshot.docs.first.id;

      debugPrint('✅ Found user: $contactUid, data: $userData');

      // Don't add yourself as a contact
      if (contactUid == currentUser.uid) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You cannot add yourself as a contact'),
            ),
          );
        }
        setState(() => _isAdding = false);
        return;
      }

      // Check if contact already exists
      final existingContact = await widget.firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .get();

      if (existingContact.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contact already added')),
          );
        }
        setState(() => _isAdding = false);
        return;
      }

      debugPrint('💾 Saving contact to Firestore (bidirectional)...');

      // Save to Firestore contacts subcollection (bidirectional)
      // Add them to your contacts
      await widget.firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .set({'addedAt': FieldValue.serverTimestamp()});

      // Add yourself to their contacts
      await widget.firestore
          .collection('users')
          .doc(contactUid)
          .collection('contacts')
          .doc(currentUser.uid)
          .set({'addedAt': FieldValue.serverTimestamp()});

      debugPrint('✅ Contact saved successfully (both ways)!');

      // Trigger callback to reload contacts
      widget.onContactAdded();

      if (context.mounted) {
        Navigator.pop(context); // Close dialog on success
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
      if (context.mounted) {
        setState(() => _isAdding = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
            controller: _emailController,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _isAdding ? null : _addContact(),
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
              suffixIcon: _emailController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Color(0xFF8E8E93)),
                      onPressed: () => _emailController.clear(),
                      tooltip: 'Clear email',
                    )
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isAdding ? null : () => Navigator.pop(context),
          child: const Text(
            'CANCEL',
            style: TextStyle(color: Color(0xFF8E8E93)),
          ),
        ),
        ElevatedButton(
          onPressed: _isAdding ? null : _addContact,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6B7FB8),
          ),
          child: _isAdding
              ? Semantics(
                  label: 'Adding contact...',
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : const Text('ADD', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Call not answered')));
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
            Semantics(
              label: 'Waiting for answer...',
              child: const CircularProgressIndicator(color: Color(0xFF6B7FB8)),
            ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decorative wave painter for the Hero card gradient background.
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path1 = Path()
      ..moveTo(0, size.height * 0.6)
      ..cubicTo(
        size.width * 0.25, size.height * 0.4,
        size.width * 0.75, size.height * 0.8,
        size.width, size.height * 0.5,
      );
    canvas.drawPath(path1, paint);

    final path2 = Path()
      ..moveTo(0, size.height * 0.75)
      ..cubicTo(
        size.width * 0.3, size.height * 0.55,
        size.width * 0.7, size.height * 0.95,
        size.width, size.height * 0.65,
      );
    canvas.drawPath(path2, paint..color = Colors.white.withOpacity(0.04));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
