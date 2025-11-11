import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/livekit_service.dart';
import '../services/call_features_coordinator.dart';
import '../services/reaction_service.dart';
import '../services/chat_service.dart' as chat;
import '../widgets/participant_video.dart';
import '../widgets/stats_overlay.dart';

class CallScreen extends StatefulWidget {
  final String roomName;
  final String token;
  final String livekitUrl;

  const CallScreen({
    super.key,
    required this.roomName,
    required this.token,
    required this.livekitUrl,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isConnecting = true;
  late CallFeaturesCoordinator _coordinator;
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _coordinator = CallFeaturesCoordinator();
    _connectToRoom();
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
      // Start collecting stats automatically
      _coordinator.startStatsCollection();
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
        body: SafeArea(
          child: Consumer2<LiveKitService, CallFeaturesCoordinator>(
            builder: (context, livekit, coordinator, child) {
              return Stack(
                children: [
                  // Remote participants grid
                  _buildParticipantsGrid(livekit),

                  // Reaction overlay (floating emojis)
                  ReactionOverlay(reactions: coordinator.activeReactions),

                  // Local video preview (small, top-right)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: _buildLocalVideoPreview(livekit),
                  ),

                  // Room info (top-left)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildRoomInfo(coordinator),
                  ),

                  // Stats overlay (top-right, below local video)
                  if (coordinator.isStatsCollecting)
                    Positioned(
                      top: 196, // Below local video preview
                      right: 16,
                      child: StatsOverlay(
                        statsService: coordinator.statsService,
                      ),
                    ),

                  // Call controls (bottom)
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
    );
  }

  Widget _buildRoomInfo(CallFeaturesCoordinator coordinator) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.roomName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (coordinator.isEncrypted) ...[
                const SizedBox(width: 8),
                const Icon(Icons.lock, color: Colors.green, size: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Quality indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getQualityColor(coordinator.qualityScore).withOpacity(0.7),
            borderRadius: BorderRadius.circular(6),
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

    // Simple grid layout for multiple participants
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: remoteParticipants.length == 1 ? 1 : 2,
        childAspectRatio: 16 / 9,
      ),
      itemCount: remoteParticipants.length,
      itemBuilder: (context, index) {
        return ParticipantVideo(participant: remoteParticipants[index]);
      },
    );
  }

  Widget _buildLocalVideoPreview(LiveKitService livekit) {
    final localParticipant = livekit.localParticipant;

    if (localParticipant == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 120,
      height: 160,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: ParticipantVideo(participant: localParticipant, isLocal: true),
    );
  }

  Widget _buildCallControls(
    LiveKitService livekit,
    CallFeaturesCoordinator coordinator,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reaction picker (floating above controls)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: ReactionType.values.map((type) {
                return GestureDetector(
                  onTap: () => coordinator.sendReaction(type),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      type.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Main control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Toggle microphone
              _buildControlButton(
                icon: livekit.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
                onPressed: livekit.toggleMicrophone,
                backgroundColor: livekit.isMicrophoneEnabled
                    ? Colors.white24
                    : Colors.red,
              ),

              // Chat button with badge
              _buildControlButton(
                icon: Icons.chat,
                onPressed: coordinator.toggleChat,
                backgroundColor: coordinator.isChatOpen
                    ? Colors.blue
                    : Colors.white24,
                badge: coordinator.unreadMessageCount > 0
                    ? coordinator.unreadMessageCount.toString()
                    : null,
              ),

              // Switch camera
              _buildControlButton(
                icon: Icons.cameraswitch,
                onPressed: livekit.switchCamera,
                backgroundColor: Colors.white24,
              ),

              // Toggle camera
              _buildControlButton(
                icon: livekit.isCameraEnabled
                    ? Icons.videocam
                    : Icons.videocam_off,
                onPressed: livekit.toggleCamera,
                backgroundColor: livekit.isCameraEnabled
                    ? Colors.white24
                    : Colors.red,
              ),

              // More menu
              _buildControlButton(
                icon: Icons.more_vert,
                onPressed: () => _showMoreMenu(coordinator),
                backgroundColor: Colors.white24,
              ),

              // End call
              _buildControlButton(
                icon: Icons.call_end,
                onPressed: () async {
                  await livekit.disconnect();
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                backgroundColor: Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    String? badge,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            iconSize: 28,
            onPressed: onPressed,
          ),
        ),
        if (badge != null)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
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
                final reversedIndex =
                    coordinator.chatMessages.length - 1 - index;
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
              border: Border(top: BorderSide(color: Colors.white24, width: 1)),
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
            Text(message.message, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              message.getFormattedTime(),
              style: const TextStyle(color: Colors.white60, fontSize: 10),
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
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  const Icon(Icons.tune, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'More Options',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Feature toggles
            _buildMenuToggle(
              icon: Icons.fiber_manual_record,
              title: 'Recording',
              value: coordinator.isRecording,
              onChanged: (value) => coordinator.toggleRecording(),
            ),
            _buildMenuToggle(
              icon: Icons.lock,
              title: 'End-to-End Encryption',
              value: coordinator.isEncrypted,
              onChanged: (value) => coordinator.toggleEncryption(),
            ),
            _buildMenuToggle(
              icon: Icons.screen_share,
              title: 'Screen Share',
              value: coordinator.isScreenSharing,
              onChanged: (value) => coordinator.toggleScreenShare(),
            ),
            _buildMenuToggle(
              icon: Icons.blur_on,
              title: 'Background Blur',
              value: coordinator.isBackgroundBlurEnabled,
              onChanged: (value) => coordinator.toggleBackgroundBlur(),
            ),
            _buildMenuToggle(
              icon: Icons.face_retouching_natural,
              title: 'Beauty Filter',
              value: coordinator.isBeautyFilterEnabled,
              onChanged: (value) => coordinator.toggleBeautyFilter(),
            ),
            _buildMenuToggle(
              icon: Icons.noise_control_off,
              title: 'AI Noise Cancellation',
              value: coordinator.isAiNoiseCancellationEnabled,
              onChanged: (value) => coordinator.toggleAiNoiseCancellation(),
            ),
            _buildMenuToggle(
              icon: Icons.spatial_audio,
              title: 'Spatial Audio',
              value: coordinator.isSpatialAudioEnabled,
              onChanged: (value) => coordinator.toggleSpatialAudio(),
            ),

            // AR Filters picker
            ListTile(
              leading: const Icon(Icons.face, color: Colors.white),
              title: const Text(
                'AR Filters',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                ArFilters.getDisplayName(coordinator.activeArFilter),
                style: const TextStyle(color: Colors.white60),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.pop(context);
                _showArFilterPicker(coordinator);
              },
            ),

            // Layout mode picker
            ListTile(
              leading: const Icon(Icons.grid_view, color: Colors.white),
              title: const Text(
                'Layout Mode',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                coordinator.layoutMode.name.toUpperCase(),
                style: const TextStyle(color: Colors.white60),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () {
                Navigator.pop(context);
                _showLayoutModePicker(coordinator);
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuToggle({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.blue,
    );
  }

  void _showArFilterPicker(CallFeaturesCoordinator coordinator) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'AR Filters',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...ArFilters.all.map((filter) {
              return ListTile(
                title: Text(
                  ArFilters.getDisplayName(filter),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: coordinator.activeArFilter == filter
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  coordinator.setArFilter(filter);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showLayoutModePicker(CallFeaturesCoordinator coordinator) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Layout Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...LayoutMode.values.map((mode) {
              return ListTile(
                title: Text(
                  mode.name.toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: coordinator.layoutMode == mode
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  coordinator.setLayoutMode(mode);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _coordinator.cleanup(); // Fire and forget async cleanup
    _chatController.dispose();
    final livekit = context.read<LiveKitService>();
    livekit.disconnect();
    super.dispose();
  }
}
