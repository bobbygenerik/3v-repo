import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/livekit_service.dart';
import '../services/call_features_coordinator.dart';
import '../services/performance_monitor.dart';
import '../services/call_session_service.dart';
import '../services/reaction_service.dart';
import '../services/chat_service.dart' as chat;
import '../widgets/participant_video.dart';
import '../widgets/stats_overlay.dart';

class CallScreen extends StatefulWidget {
  final String roomName;
  final String token;
  final String livekitUrl;
  final CallSessionService? sessionService;
  
  const CallScreen({
    super.key,
    required this.roomName,
    required this.token,
    required this.livekitUrl,
    this.sessionService,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  bool _isConnecting = true;
  late CallFeaturesCoordinator _coordinator;
  PerformanceMonitor? _performanceMonitor;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionDocSubscription;
  final TextEditingController _chatController = TextEditingController();
  
  // Call timer
  Duration _callDuration = Duration.zero;
  
  // Control animations
  bool _controlsVisible = true;
  late AnimationController _controlsAnimationController;
  late List<Animation<Offset>> _buttonSlideAnimations;
  Timer? _controlsHideTimer;
  
  // Reaction panel animation
  bool _reactionsVisible = false;
  late AnimationController _reactionsAnimationController;
  late Animation<Offset> _reactionsSlideAnimation;
  
  // PIP box state (tracks position from top-left corner)
  Offset? _pipPosition; // null = use default top-right position
  bool _pipExpanded = false;
  bool _pipSwapped = false;
  
  // Performance optimizations
  Timer? _switchDebounce;
  int _mainSpeakerIndex = 0;
  final int _maxPips = 6;
  
  @override
  void initState() {
    super.initState();
    _coordinator = CallFeaturesCoordinator();
    _connectToRoom();
    
    // Listen for session end
    widget.sessionService?.addListener(_handleSessionEnd);
    // Also ensure we subscribe directly to the call_sessions document if available
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSessionDocListener());
    
    // Start call timer
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
        return true;
      }
      return false;
    });
    
    // Initialize controls animation (cascade from bottom)
    _controlsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    // Create staggered animations for 7 buttons
    // Create staggered animations for buttons. Generate a few extra slots
    // so dynamic button counts won't cause index errors.
    _buttonSlideAnimations = List.generate(10, (index) {
      final start = index * 0.15; // Left button starts first (0.0, 0.15, 0.3, 0.45, 0.6)
      final end = start + 0.4; // Each animation duration
      return Tween<Offset>(
        begin: const Offset(0, 2), // Start below screen
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _controlsAnimationController,
        curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOut),
      ));
    });
    
    // Initialize reactions panel animation (slide from left)
    _reactionsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _reactionsSlideAnimation = Tween<Offset>(
      begin: const Offset(-1.5, 0), // Start off-screen left
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _reactionsAnimationController,
      curve: Curves.easeOut,
    ));
    
    // Show controls initially
    _controlsAnimationController.forward();
    
    // Start auto-hide timer for controls
    _startControlsHideTimer();
  }
  
  /// Handle session end by other participant
  void _handleSessionEnd() {
    debugPrint('📞 Session end event triggered');
    if (widget.sessionService?.isInCall == false && mounted) {
      debugPrint('📞 Call ended by another participant - exiting call screen');
      // Call ended by another participant
      if (Navigator.canPop(context)) Navigator.of(context).pop();
    }
  }

  void _ensureSessionDocListener() {
    try {
      final sessionId = widget.sessionService?.currentSessionId;
      if (sessionId == null) return;
      if (_sessionDocSubscription != null) return;

      debugPrint('🔔 Subscribing to call_sessions/$sessionId for direct updates');
      _sessionDocSubscription = FirebaseFirestore.instance
          .collection('call_sessions')
          .doc(sessionId)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        if (!snapshot.exists) {
          debugPrint('🔔 call_sessions/$sessionId deleted -> pop');
          if (Navigator.canPop(context)) Navigator.of(context).pop();
          return;
        }
        final data = snapshot.data();
        if (data == null) return;
        final status = data['status'] as String?;
        final endedBy = data['endedBy'] as String?;
        debugPrint('🔔 call_sessions/$sessionId update status=$status endedBy=$endedBy');
        if (status == 'ended') {
          // If session ended, leave screen (other side should already have cleaned up locally)
          if (Navigator.canPop(context)) Navigator.of(context).pop();
        }
      }, onError: (e) {
        debugPrint('🔔 Error listening to session doc: $e');
      });
    } catch (e) {
      debugPrint('🔔 Failed to ensure session doc listener: $e');
    }
  }
  
  void _startControlsHideTimer() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controlsVisible) {
        setState(() {
          _controlsVisible = false;
          _controlsAnimationController.reverse();
        });
      }
    });
  }
  
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
  
  Future<void> _connectToRoom() async {
    final livekit = context.read<LiveKitService>();
    
    final success = await livekit.connect(
      url: widget.livekitUrl,
      token: widget.token,
      roomName: widget.roomName,
    );
    
    // Initialize coordinator with room (now async)
    if (success && livekit.room != null) {
      await _coordinator.initialize(livekit.room!);
      // Don't start stats collection automatically - let user enable it
      // Start runtime performance monitor to adapt capture/ML settings
      try {
        _performanceMonitor = PerformanceMonitor(livekit, _coordinator, livekit.networkService);
        _performanceMonitor?.start();
      } catch (e) {
        debugPrint('⚠️ Failed to start PerformanceMonitor: $e');
      }
    }
    
    setState(() => _isConnecting = false);
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(livekit.errorMessage ?? 'Failed to connect'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to call...'),
            ],
          ),
        ),
      );
    }
    
    return ChangeNotifierProvider<CallFeaturesCoordinator>.value(
      value: _coordinator,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleControls,
          onHorizontalDragStart: (details) {
            // Track if drag started from left edge
            if (details.globalPosition.dx < 50) {
              setState(() {
                _reactionsVisible = true;
                _reactionsAnimationController.forward();
              });
            }
          },
          onHorizontalDragEnd: (details) {
            // Swipe right from left edge to show reactions
            if (details.primaryVelocity != null && details.primaryVelocity! > 500) {
              if (!_reactionsVisible) {
                _toggleReactions();
              }
            }
            // Swipe left to hide reactions
            else if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
              if (_reactionsVisible) {
                _toggleReactions();
              }
            }
          },
          child: SafeArea(
            child: Consumer2<LiveKitService, CallFeaturesCoordinator>(
              builder: (context, livekit, coordinator, child) {
                return Stack(
                  children: [
                    // Remote participants grid
                    _buildParticipantsGrid(livekit),
                    
                    // Reaction overlay (floating emojis)
                    ReactionOverlay(reactions: coordinator.activeReactions),
                    
                    // Reactions panel (slide from left)
                    _buildReactionsPanel(coordinator),
                    
                    // Multiple PIPs for all non-main participants
                    ..._buildMultiplePIPs(livekit),
                    
                    // Room info (top-left)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _buildRoomInfo(coordinator),
                    ),
                    

                    
                    // Stats overlay (if enabled) - positioned below quality pill on left side
                    if (coordinator.isStatsCollecting)
                      Positioned(
                        top: 130, // More spacing from quality pill
                        left: 16, // Aligned with room info on left
                        child: StatsOverlay(
                          statsService: coordinator.statsService,
                        ),
                      ),

                    // QA Banner (top-right): shows which ML features are active for quick verification
                    if (coordinator.aiFeaturesService.isInitialized || coordinator.isBackgroundBlurEnabled || coordinator.isFaceAutoFramingEnabled || coordinator.isBeautyFilterEnabled)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.analytics, color: Colors.white, size: 14),
                              const SizedBox(width: 8),
                              Text(
                                'ML: ${coordinator.isBackgroundBlurEnabled ? 'Blur' : ''}${coordinator.isBackgroundBlurEnabled && (coordinator.isFaceAutoFramingEnabled || coordinator.isBeautyFilterEnabled) ? ' • ' : ''}${coordinator.isFaceAutoFramingEnabled ? 'Auto-frame' : ''}${coordinator.isFaceAutoFramingEnabled && coordinator.isBeautyFilterEnabled ? ' • ' : ''}${coordinator.isBeautyFilterEnabled ? 'Beauty' : ''}',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Call controls (bottom) - always rendered, visibility controlled by animation
                    Positioned(
                      // Respect safe area so controls don't sit under system UI on tall devices
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                      left: 0,
                      right: 0,
                      child: _buildCallControls(livekit, coordinator),
                    ),
                    
                    // Chat panel (bottom sheet)
                    if (coordinator.isChatOpen)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _buildChatPanel(coordinator),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
  
  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) {
        _controlsAnimationController.forward();
        _startControlsHideTimer();
      } else {
        _controlsAnimationController.reverse();
        _controlsHideTimer?.cancel();
      }
    });
  }
  
  void _toggleReactions() {
    setState(() {
      _reactionsVisible = !_reactionsVisible;
      if (_reactionsVisible) {
        _reactionsAnimationController.forward();
      } else {
        _reactionsAnimationController.reverse();
      }
    });
  }
  
  Widget _buildReactionsPanel(CallFeaturesCoordinator coordinator) {
    if (!_reactionsVisible) return const SizedBox.shrink();
    
    return Positioned(
      left: 16,
      top: MediaQuery.of(context).size.height * 0.3,
      child: SlideTransition(
        position: _reactionsSlideAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ReactionType.values.map((type) {
              return GestureDetector(
                onTap: () {
                  coordinator.sendReaction(type);
                  _toggleReactions(); // Hide after selection
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    type.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
  
  Widget _buildMenuButton(CallFeaturesCoordinator coordinator) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showMoreMenu(coordinator),
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withOpacity(0.3),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.more_vert,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
  
  Widget _buildRoomInfo(CallFeaturesCoordinator coordinator) {
    // Get remote participant name or use room name
    final livekit = context.read<LiveKitService>();
    final remoteParticipants = livekit.remoteParticipants;
    final callerName = remoteParticipants.isNotEmpty 
        ? (remoteParticipants.first.name.isNotEmpty ? remoteParticipants.first.name : remoteParticipants.first.identity)
        : widget.roomName;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Caller name - just text, no box
        Text(
          callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black,
                offset: Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Time elapsed - just text, no box
        Text(
          _formatDuration(_callDuration),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(
                color: Colors.black,
                offset: Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        // Quality indicator - only show when stats overlay is on
        if (coordinator.isStatsCollecting) ...[
          const SizedBox(height: 8),
          // Quality indicator (yellow box)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getQualityColor(coordinator.qualityScore).withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getQualityIcon(coordinator.qualityScore),
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  '${coordinator.qualityScore}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  Color _getQualityColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }
  
  IconData _getQualityIcon(int score) {
    if (score >= 80) return Icons.signal_cellular_4_bar;
    if (score >= 50) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }
  
  Widget _buildParticipantsGrid(LiveKitService livekit) {
    final remoteParticipants = livekit.remoteParticipants;
    
    // If PIP is swapped, show local participant in main view
    if (_pipSwapped && livekit.localParticipant != null) {
      return GestureDetector(
        onDoubleTap: _switchToNextParticipant,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: ParticipantVideo(
            key: const ValueKey('main-local-swapped'),
            participant: livekit.localParticipant!,
            isLocal: true,
          ),
        ),
      );
    }
    
    if (remoteParticipants.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'Waiting for others to join...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    
    // Show main speaker with smooth transitions
    return GestureDetector(
      onDoubleTap: _switchToNextParticipant,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: ParticipantVideo(
          key: ValueKey('main-speaker-$_mainSpeakerIndex'),
          participant: remoteParticipants[_mainSpeakerIndex % remoteParticipants.length],
        ),
      ),
    );
  }
  
  void _switchToNextParticipant() {
    _switchDebounce?.cancel();
    _switchDebounce = Timer(const Duration(milliseconds: 300), () {
      final livekit = context.read<LiveKitService>();
      if (livekit.remoteParticipants.isNotEmpty) {
        setState(() {
          _mainSpeakerIndex = (_mainSpeakerIndex + 1) % livekit.remoteParticipants.length;
        });
      }
    });
  }
  
  List<Widget> _buildMultiplePIPs(LiveKitService livekit) {
    final List<Widget> pips = [];
    final remoteParticipants = livekit.remoteParticipants;
    
    // Always add local participant PIP (smallest)
    if (livekit.localParticipant != null && !_pipSwapped) {
      pips.add(
        Positioned(
          right: 16,
          top: 16,
          child: RepaintBoundary(
            child: _buildPIPWindow(
              participant: livekit.localParticipant!,
              isLocal: true,
              size: 140, // increased so self-view is more visible
              showName: false,
              index: -1,
            ),
          ),
        ),
      );
    }
    
    // Add other remote participants as PIPs (limit to maxPips, skip main speaker)
    int pipCount = 0;
    for (int i = 0; i < remoteParticipants.length && pipCount < _maxPips; i++) {
      if (i == _mainSpeakerIndex) continue; // Skip main speaker
      
      final participant = remoteParticipants[i];
      pips.add(
        Positioned(
          right: 16,
          top: 16 + ((pipCount + (_pipSwapped ? 0 : 1)) * 110),
          child: RepaintBoundary(
            child: _buildPIPWindow(
              participant: participant,
              isLocal: false,
              size: 120,
              showName: true,
              index: i,
            ),
          ),
        ),
      );
      pipCount++;
    }
    
    return pips;
  }
  
  Widget _buildPIPWindow({
    required dynamic participant,
    required bool isLocal,
    required double size,
    required bool showName,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (isLocal) {
          setState(() {
            _pipSwapped = !_pipSwapped;
          });
        } else {
          setState(() {
            _mainSpeakerIndex = index;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size * 1.5,
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            ParticipantVideo(
              participant: participant,
              isLocal: isLocal,
            ),
            // Enhanced gradient overlay for better text readability
            if (showName && !isLocal)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.9),
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                  child: Text(
                    participant.name.isNotEmpty ? participant.name : participant.identity,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLocalVideoPreview(LiveKitService livekit) {
    final localParticipant = livekit.localParticipant;
    
    if (localParticipant == null) {
      return const SizedBox.shrink();
    }

    // Detect orientation - but for desktop/web, check screen size instead
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height && screenSize.width > 800;
    
    // Calculate dimensions based on orientation
    // Default to PORTRAIT for desktop/web
    double width, height;
    if (isLandscape) {
      // Landscape: 16:9 ratio (wider than tall)
      if (_pipExpanded) {
        width = 360; // 16:9 landscape - extra large (increased)
        height = 220;
      } else {
        width = 300; // 16:9 landscape - default (increased)
        height = 170;
      }
    } else {
      // Portrait: 9:16 ratio (taller than wide) - DEFAULT
      if (_pipExpanded) {
        width = 220; // 9:16 portrait - extra large (increased)
        height = 420;
      } else {
        width = 180; // 9:16 portrait - default (increased)
        height = 320;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Single tap: toggle size
        setState(() {
          _pipExpanded = !_pipExpanded;
          // Dimensions will be recalculated on rebuild based on orientation
        });
      },
      onDoubleTap: () {
        // Double tap: swap feeds
        setState(() {
          _pipSwapped = !_pipSwapped;
        });
      },
      onPanUpdate: (details) {
        // Get screen dimensions
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        
        // Get current position (if null, calculate from top-right with 16px margin)
        final currentPos = _pipPosition ?? Offset(
          screenWidth - width - 16,
          16,
        );
        
        // Drag to reposition with proper bounds checking
        setState(() {
          _pipPosition = Offset(
            (currentPos.dx + details.delta.dx).clamp(16.0, screenWidth - width - 16),
            (currentPos.dy + details.delta.dy).clamp(16.0, screenHeight - height - 16),
          );
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20), // Rounder corners
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Show appropriate participant based on swap state
            if (_pipSwapped && livekit.remoteParticipants.isNotEmpty)
              ParticipantVideo(
                key: const ValueKey('pip-remote-swapped'),
                participant: livekit.remoteParticipants.first,
              )
            else
              ParticipantVideo(
                key: const ValueKey('pip-local-normal'),
                participant: localParticipant,
                isLocal: true,
              ),
            // Label at bottom - only show for remote participant when swapped
            if (_pipSwapped && livekit.remoteParticipants.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    livekit.remoteParticipants.first.name.isNotEmpty 
                        ? livekit.remoteParticipants.first.name 
                        : livekit.remoteParticipants.first.identity,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCallControls(LiveKitService livekit, CallFeaturesCoordinator coordinator) {
    // Button order: Add Person, Chat, Mic, END CALL (center), Camera, Flip, Menu
    // New order: More (leftmost), Mic, END CALL (center), Camera, Flip
    final buttons = [
      // 0: More / Extra (moved to left)
      _buildAnimatedButton(
        index: 0,
        icon: Icons.more_vert,
        onPressed: () => _showMoreMenu(coordinator),
        backgroundColor: Colors.white.withOpacity(0.2),
        size: 50,
      ),
      // 1: Mic with pulse animation when muted
      _buildAnimatedButton(
        index: 1,
        icon: livekit.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
        onPressed: livekit.toggleMicrophone,
        backgroundColor: livekit.isMicrophoneEnabled
            ? Colors.white.withOpacity(0.2)
            : Colors.red.shade600,
        size: 50,
        pulse: !livekit.isMicrophoneEnabled,
      ),
      // 2: END CALL (center - larger)
      _buildAnimatedButton(
        index: 2,
        icon: Icons.call_end,
        onPressed: () async {
          debugPrint('📞 End call button pressed');
          try {
            // End session for all participants
            await widget.sessionService?.endSession();
            debugPrint('📞 Session ended successfully');
          } catch (e) {
            debugPrint('❌ Error ending session: $e');
          }
          
          try {
            await livekit.disconnect();
            debugPrint('📞 LiveKit disconnected');
          } catch (e) {
            debugPrint('❌ Error disconnecting LiveKit: $e');
          }
          
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
        backgroundColor: Colors.red.shade600,
        size: 64, // Larger center button
      ),
      // 3: Camera
      _buildAnimatedButton(
        index: 3,
        icon: livekit.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
        onPressed: livekit.toggleCamera,
        backgroundColor: livekit.isCameraEnabled
            ? Colors.white.withOpacity(0.2)
            : Colors.red.shade600,
        size: 50,
      ),
      // 4: Flip camera
      _buildAnimatedButton(
        index: 4,
        icon: Icons.cameraswitch,
        onPressed: livekit.switchCamera,
        backgroundColor: Colors.white.withOpacity(0.2),
        size: 50,
      ),
    ];

    // Wrap controls in a horizontal scroll view so they never overflow on narrow devices.
    // Keeps the centered row appearance on wide screens, but allows scrolling when space is limited.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        // Wrap the row in a Center so that on wide screens/tablets
        // the controls are visually centered while still allowing
        // horizontal scrolling on narrow devices.
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: buttons,
          ),
        ),
      ),
    );
  }
  
  Widget _buildAnimatedButton({
    required int index,
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    required double size,
    String? badge,
    bool pulse = false,
  }) {
    Widget button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
    
    if (pulse) {
      button = AnimatedBuilder(
        animation: _controlsAnimationController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (0.1 * (1.0 + math.sin(_controlsAnimationController.value * 2 * math.pi)) / 2),
            child: child,
          );
        },
        child: button,
      );
    }
    return SlideTransition(
      position: _buttonSlideAnimations[index],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                splashColor: Colors.white.withOpacity(0.3),
                highlightColor: Colors.white.withOpacity(0.1),
                child: button,
              ),
            ),
            if (badge != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Center(
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  // Chat panel
  Widget _buildChatPanel(CallFeaturesCoordinator coordinator) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white24, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: coordinator.toggleChat,
                ),
              ],
            ),
          ),
          
          // Messages list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              reverse: true,
              itemCount: coordinator.chatMessages.length,
              itemBuilder: (context, index) {
                final reversedIndex = coordinator.chatMessages.length - 1 - index;
                final message = coordinator.chatMessages[reversedIndex];
                return _buildChatMessage(message);
              },
            ),
          ),
          
          // Typing indicators
          if (coordinator.chatService.typingUsers.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${coordinator.chatService.typingUsers.map((u) => u.userName).join(", ")} ${coordinator.chatService.typingUsers.length == 1 ? "is" : "are"} typing...',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          
          // Message input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white24, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (text) {
                      if (text.isNotEmpty) {
                        coordinator.chatService.sendTypingIndicator();
                      }
                    },
                    onSubmitted: (text) {
                      if (text.trim().isNotEmpty) {
                        coordinator.sendChatMessage(text);
                        _chatController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: () {
                    final text = _chatController.text;
                    if (text.trim().isNotEmpty) {
                      coordinator.sendChatMessage(text);
                      _chatController.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChatMessage(chat.ChatMessage message) {
    return Align(
      alignment: message.isLocal ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: message.isLocal ? Colors.blue : Colors.white24,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.isLocal)
              Text(
                message.senderName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              message.message,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              message.getFormattedTime(),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // More menu
  void _showMoreMenu(CallFeaturesCoordinator coordinator) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              // Add Person moved into the More menu
              ListTile(
                leading: const Icon(Icons.person_add, color: Color(0xFF6B7FB8)),
                title: const Text('Add Person', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showAddPersonDialog();
                },
              ),
              // Chat moved into the More menu
              ListTile(
                leading: const Icon(Icons.chat_bubble, color: Color(0xFF6B7FB8)),
                title: const Text('Chat', style: TextStyle(color: Colors.white)),
                trailing: Switch(
                  value: coordinator.isChatOpen,
                  onChanged: (value) {
                    coordinator.toggleChat();
                    Navigator.pop(context);
                  },
                ),
              ),
            const Text(
              'Call Options',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            // Screen Share
            ListTile(
              leading: const Icon(Icons.screen_share, color: Color(0xFF6B7FB8)),
              title: const Text('Share Screen', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: coordinator.isScreenSharing,
                onChanged: (value) async {
                  await coordinator.toggleScreenShare();
                  Navigator.pop(context);
                },
              ),
            ),
            
            // Recording
            ListTile(
              leading: Icon(
                coordinator.isRecording ? Icons.stop : Icons.fiber_manual_record,
                color: coordinator.isRecording ? Colors.red : const Color(0xFF6B7FB8),
              ),
              title: Text(
                coordinator.isRecording ? 'Stop Recording' : 'Start Recording',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                await coordinator.toggleRecording();
                Navigator.pop(context);
              },
            ),
            
            // Background Blur
            ListTile(
              leading: const Icon(Icons.blur_on, color: Color(0xFF6B7FB8)),
              title: const Text('Background Blur', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: coordinator.isBackgroundBlurEnabled,
                onChanged: (value) async {
                  await coordinator.toggleBackgroundBlur();
                  Navigator.pop(context);
                },
              ),
            ),
            
            // Beauty Filter
            ListTile(
              leading: const Icon(Icons.face_retouching_natural, color: Color(0xFF6B7FB8)),
              title: const Text('Beauty Filter', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: coordinator.isBeautyFilterEnabled,
                onChanged: (value) async {
                  coordinator.toggleBeautyFilter();
                  Navigator.pop(context);
                },
              ),
            ),
            
            // AR Filters
            ListTile(
              leading: const Icon(Icons.face, color: Color(0xFF6B7FB8)),
              title: const Text('AR Filters', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showARFiltersDialog(coordinator);
              },
            ),
            
            // Call Health Overlay
            ListTile(
              leading: const Icon(Icons.monitor_heart, color: Color(0xFF6B7FB8)),
              title: const Text('Call Health Overlay', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: coordinator.isStatsCollecting,
                onChanged: (value) {
                  if (value) {
                    coordinator.startStatsCollection();
                  } else {
                    coordinator.stopStatsCollection();
                  }
                  Navigator.pop(context);
                },
              ),
            ),
            

            

          ],
        ),
      ),
    );
  }
  
  String _getQualityText(int score) {
    if (score >= 80) return 'Excellent';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Poor';
  }
  
  void _showAddPersonDialog() {
    final TextEditingController emailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('Add Person to Call', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: emailController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter email address',
            hintStyle: TextStyle(color: Colors.white60),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF6B7FB8)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF6B7FB8)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              // TODO: Implement add person functionality
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add person feature coming soon')),
              );
            },
            child: const Text('Add', style: TextStyle(color: Color(0xFF6B7FB8))),
          ),
        ],
      ),
    );
  }
  
  void _showARFiltersDialog(CallFeaturesCoordinator coordinator) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('AR Filters', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Choose an AR filter to apply to your video',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AR filters coming soon')),
              );
            },
            child: const Text('Apply', style: TextStyle(color: Color(0xFF6B7FB8))),
          ),
        ],
      ),
    );
  }
  
  void _showGridLayoutOptions(CallFeaturesCoordinator coordinator) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('Grid Layout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Adjust how participants are displayed',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF6B7FB8))),
          ),
        ],
      ),
    );
  }
  
  void _showNetworkInfo(CallFeaturesCoordinator coordinator) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        title: const Text('Network Quality', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quality Score: ${coordinator.qualityScore}%',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${_getQualityText(coordinator.qualityScore)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF6B7FB8))),
          ),
        ],
      ),
    );
  }
  

  
  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    _switchDebounce?.cancel();
    widget.sessionService?.removeListener(_handleSessionEnd);
    
    // Dispose video tracks for memory management
    final livekit = context.read<LiveKitService>();
    livekit.remoteParticipants.forEach((participant) {
      participant.videoTrackPublications.forEach((pub) {
        pub.track?.dispose();
      });
    });
    livekit.localParticipant?.videoTrackPublications.forEach((pub) {
      pub.track?.dispose();
    });
    
    // Proper async cleanup
    _coordinator.cleanup().catchError((e) => debugPrint('Cleanup error: $e'));
    
    _chatController.dispose();
    _controlsAnimationController.dispose();
    _reactionsAnimationController.dispose();
    // Cancel direct session document listener
    _sessionDocSubscription?.cancel();
    
    // Disconnect LiveKit properly
    livekit.disconnect();
    // Stop performance monitor explicitly to cancel its timer
    _performanceMonitor?.stop();
    
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure monitor uses updated services if dependencies change
    final livekit = context.read<LiveKitService>();
    if (_performanceMonitor == null && !_isConnecting) {
      try {
        _performanceMonitor = PerformanceMonitor(livekit, _coordinator, livekit.networkService);
        _performanceMonitor?.start();
      } catch (e) {
        debugPrint('⚠️ Failed to start PerformanceMonitor in didChangeDependencies: $e');
      }
    }
  }
}
