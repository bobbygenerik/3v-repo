import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/livekit_service.dart';
import '../widgets/participant_video.dart';

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
  
  @override
  void initState() {
    super.initState();
    _connectToRoom();
  }
  
  Future<void> _connectToRoom() async {
    final livekit = context.read<LiveKitService>();
    
    final success = await livekit.connect(
      url: widget.livekitUrl,
      token: widget.token,
      roomName: widget.roomName,
    );
    
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
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Consumer<LiveKitService>(
          builder: (context, livekit, child) {
            return Stack(
              children: [
                // Remote participants grid
                _buildParticipantsGrid(livekit),
                
                // Local video preview (small, top-right)
                Positioned(
                  top: 16,
                  right: 16,
                  child: _buildLocalVideoPreview(livekit),
                ),
                
                // Call controls (bottom)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: _buildCallControls(livekit),
                ),
                
                // Room name (top-left)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.roomName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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
    
    return Container(
      width: 120,
      height: 160,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: ParticipantVideo(
        participant: localParticipant,
        isLocal: true,
      ),
    );
  }
  
  Widget _buildCallControls(LiveKitService livekit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
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
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        iconSize: 32,
        onPressed: onPressed,
      ),
    );
  }
  
  @override
  void dispose() {
    final livekit = context.read<LiveKitService>();
    livekit.disconnect();
    super.dispose();
  }
}
