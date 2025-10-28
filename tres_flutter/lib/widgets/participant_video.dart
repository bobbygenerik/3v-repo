import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class ParticipantVideo extends StatefulWidget {
  final Participant participant;
  final bool isLocal;
  
  const ParticipantVideo({
    super.key,
    required this.participant,
    this.isLocal = false,
  });

  @override
  State<ParticipantVideo> createState() => _ParticipantVideoState();
}

class _ParticipantVideoState extends State<ParticipantVideo> {
  VideoTrack? _videoTrack;
  
  @override
  void initState() {
    super.initState();
    _setupVideoTrack();
    widget.participant.addListener(_onParticipantChanged);
  }
  
  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    super.dispose();
  }
  
  void _onParticipantChanged() {
    _setupVideoTrack();
  }
  
  void _setupVideoTrack() {
    // Get first video track
    final track = widget.participant.videoTrackPublications
        .where((pub) => pub.subscribed)
        .map((pub) => pub.track as VideoTrack?)
        .firstWhere((track) => track != null, orElse: () => null);
    
    if (mounted && track != _videoTrack) {
      setState(() {
        _videoTrack = track;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_videoTrack == null) {
      return _buildNoVideoPlaceholder();
    }
    
      return Stack(
      children: [
        // Video renderer
        VideoTrackRenderer(
          _videoTrack!,
          fit: VideoViewFit.cover,
        ),
        
        // Participant name overlay
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.participant.identity,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
        // Microphone muted indicator
        if (_isMicrophoneMuted())
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_off,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildNoVideoPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey[700],
              child: Text(
                _getInitials(widget.participant.identity),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.participant.identity,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  bool _isMicrophoneMuted() {
    final audioTracks = widget.participant.audioTrackPublications;
    if (audioTracks.isEmpty) return true;
    
    return audioTracks.first.muted;
  }
  
  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
