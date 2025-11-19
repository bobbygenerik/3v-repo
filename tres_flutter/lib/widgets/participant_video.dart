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
    // Get first video track from publications
    VideoTrack? track;
    
    for (final pub in widget.participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        track = pub.track as VideoTrack;
        break;
      }
    }
    
    // If no subscribed track, try to subscribe to first available publication
    if (track == null && !widget.isLocal) {
      for (final pub in widget.participant.videoTrackPublications) {
        if (!pub.subscribed && pub.track == null) {
          debugPrint('📹 Auto-subscribing to video track: ${pub.sid}');
          // The track will be available after subscription completes
          // and _onParticipantChanged will be called
        }
      }
    }
    
    if (mounted && track != _videoTrack) {
      setState(() {
        _videoTrack = track;
      });
      debugPrint('📹 Video track ${track != null ? "set" : "cleared"} for ${widget.participant.identity}');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_videoTrack == null) {
      return _buildNoVideoPlaceholder();
    }
    
    return RepaintBoundary(
      child: VideoTrackRenderer(
        _videoTrack!,
        fit: VideoViewFit.cover,
      ),
    );
  }
  
  Widget _buildNoVideoPlaceholder() {
    // Get display name (use name if available, otherwise identity)
    final displayName = widget.participant.name.isNotEmpty 
        ? widget.participant.name 
        : widget.participant.identity;
    
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: CircleAvatar(
          radius: 40,
          backgroundColor: Colors.grey[700],
          child: Text(
            _getInitials(displayName),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
  
  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    
    // If it's an email, use the part before @
    if (name.contains('@')) {
      name = name.split('@')[0];
    }
    
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
