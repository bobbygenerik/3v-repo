import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
export 'package:livekit_client/livekit_client.dart';

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
          // Actually subscribe to the track
          pub.subscribe();
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
    
      return VideoTrackRenderer(
        _videoTrack!,
        fit: VideoViewFit.cover,
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
  
  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
