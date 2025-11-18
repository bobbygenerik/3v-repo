import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/livekit_service.dart';
import '../services/call_features_coordinator.dart';
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
  
  @override
  void initState() {
    super.initState();
    _coordinator = CallFeaturesCoordinator();
    _connectToRoom();
    
    // Listen for session end
    widget.sessionService?.addListener(_handleSessionEnd);
    
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
    
    // Create staggered animations for 5 buttons
    // LEFT to RIGHT for both rise and fall (0, 1, 2, 3, 4)
    _buttonSlideAnimations = List.generate(5, (index) {
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
    if (widget.sessionService?.isInCall == false && mounted) {
      // Call ended by another participant
      Navigator.of(context).pop();
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
                    
                    // Local video preview (PIP - repositionable, starts at fixed top-right)
                    Positioned(
                      left: _pipPosition?.dx ?? (MediaQuery.of(context).size.width - (_pipExpanded ? 169 : 135) - 16),
                      top: _pipPosition?.dy ?? 16,
                      child: _buildLocalVideoPreview(livekit),
                    ),
                    
                    // Room info (top-left)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _buildRoomInfo(coordinator),
                    ),
                    
                    // 3-dot menu button (top-right, below local video)
                    Positioned(
                      top: 196,
                      right: 16,
                      child: _buildMenuButton(coordinator),
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
                    
                    // Call controls (bottom) - always rendered, visibility controlled by animation
                    Positioned(
                      bottom: 32,
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
      return ParticipantVideo(
        key: const ValueKey('main-local-swapped'),
        participant: livekit.localParticipant!,
        isLocal: true,
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
    
    // For single participant, use full screen without aspect ratio constraint
    if (remoteParticipants.length == 1) {
      return ParticipantVideo(
        key: const ValueKey('main-remote-normal'),
        participant: remoteParticipants[0],
      );
    }
    
    // For multiple participants, use grid layout
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 16 / 9,
      ),
      itemCount: remoteParticipants.length,
      itemBuilder: (context, index) {
        return ParticipantVideo(
          participant: remoteParticipants[index],
        );
      },
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
        width = 267; // 16:9 landscape - extra large
        height = 150;
      } else {
        width = 213; // 16:9 landscape - default
        height = 120;
      }
    } else {
      // Portrait: 9:16 ratio (taller than wide) - DEFAULT
      if (_pipExpanded) {
        width = 169; // 9:16 portrait - extra large
        height = 300;
      } else {
        width = 135; // 9:16 portrait - default
        height = 240;
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
            // Label at bottom
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
                  _pipSwapped && livekit.remoteParticipants.isNotEmpty
                      ? (livekit.remoteParticipants.first.name.isNotEmpty ? livekit.remoteParticipants.first.name : livekit.remoteParticipants.first.identity)
                      : (livekit.localParticipant?.name.isNotEmpty == true ? livekit.localParticipant!.name : (livekit.localParticipant?.identity?.isNotEmpty == true ? livekit.localParticipant!.identity! : 'You')),
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
    // Button order: Chat, Mic, END CALL (center), Camera, Flip
    final buttons = [
      // 0: Chat (leftmost)
      _buildAnimatedButton(
        index: 0,
        icon: Icons.chat_bubble,
        onPressed: coordinator.toggleChat,
        backgroundColor: coordinator.isChatOpen
            ? const Color(0xFF6B7FB8)
            : Colors.white.withOpacity(0.2),
        size: 50,
        badge: coordinator.unreadMessageCount > 0
            ? coordinator.unreadMessageCount.toString()
            : null,
      ),
      // 1: Mic (left of center)
      _buildAnimatedButton(
        index: 1,
        icon: livekit.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
        onPressed: livekit.toggleMicrophone,
        backgroundColor: livekit.isMicrophoneEnabled
            ? Colors.white.withOpacity(0.2)
            : Colors.red.shade600,
        size: 50,
      ),
      // 2: END CALL (center - larger)
      _buildAnimatedButton(
        index: 2,
        icon: Icons.call_end,
        onPressed: () async {
          // End session for all participants
          await widget.sessionService?.endSession();
          await livekit.disconnect();
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
        backgroundColor: Colors.red.shade600,
        size: 64, // Larger center button
      ),
      // 3: Camera (right of center)
      _buildAnimatedButton(
        index: 3,
        icon: livekit.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
        onPressed: livekit.toggleCamera,
        backgroundColor: livekit.isCameraEnabled
            ? Colors.white.withOpacity(0.2)
            : Colors.red.shade600,
        size: 50,
      ),
      // 4: Flip camera (rightmost)
      _buildAnimatedButton(
        index: 4,
        icon: Icons.cameraswitch,
        onPressed: livekit.switchCamera,
        backgroundColor: Colors.white.withOpacity(0.2),
        size: 50,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: buttons,
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
  }) {
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
                child: Container(
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
                ),
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
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'More Options',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.monitor_heart, color: Colors.white),
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
            ListTile(
              leading: const Icon(Icons.blur_on, color: Colors.white),
              title: const Text('Background Blur', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: coordinator.isBackgroundBlurEnabled,
                onChanged: (value) async {
                  await coordinator.toggleBackgroundBlur();
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  

  
  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    widget.sessionService?.removeListener(_handleSessionEnd);
    _coordinator.cleanup(); // Fire and forget async cleanup
    _chatController.dispose();
    _controlsAnimationController.dispose();
    _reactionsAnimationController.dispose();
    final livekit = context.read<LiveKitService>();
    livekit.disconnect();
    super.dispose();
  }
}
