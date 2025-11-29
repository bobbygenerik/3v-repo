import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class ParticipantVideo extends StatefulWidget {
  final Participant participant;
  final bool isLocal;
  final bool isMainView;
  
  const ParticipantVideo({
    super.key,
    required this.participant,
    this.isLocal = false,
    this.isMainView = true,
  });

  @override
  State<ParticipantVideo> createState() => _ParticipantVideoState();
}

class _ParticipantVideoState extends State<ParticipantVideo> {
  VideoTrack? _videoTrack;
  AudioTrack? _audioTrack;
  
  @override
  void initState() {
    super.initState();
    _setupTracks();
    widget.participant.addListener(_onParticipantChanged);
  }
  
  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    super.dispose();
  }
  
  void _onParticipantChanged() {
    _setupTracks();
  }
  
  void _setupTracks() async {
    _setupVideoTrack();
    _setupAudioTrack();
  }
  
  void _setupAudioTrack() async {
    AudioTrack? track;
    
    for (final pub in widget.participant.audioTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        track = pub.track as AudioTrack;
        break;
      }
    }
    
    // Subscribe to unsubscribed tracks
    if (track == null && !widget.isLocal) {
      for (final pub in widget.participant.audioTrackPublications) {
        if (!pub.subscribed && pub is RemoteTrackPublication) {
          try {
            await pub.subscribe();
            if (pub.track != null) {
              track = pub.track as AudioTrack;
            }
          } catch (e) {
            debugPrint('❌ Failed to subscribe to audio track: $e');
          }
        }
      }
    }
    
    if (mounted && track != _audioTrack) {
      setState(() {
        _audioTrack = track;
      });
    }
  }
  
  void _setupVideoTrack() async {
    VideoTrack? track;
    
    for (final pub in widget.participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        track = pub.track as VideoTrack;
        break;
      }
    }
    
    // Subscribe to unsubscribed tracks
    if (track == null && !widget.isLocal) {
      for (final pub in widget.participant.videoTrackPublications) {
        if (!pub.subscribed && pub is RemoteTrackPublication) {
          try {
            await pub.subscribe();
          } catch (e) {
            debugPrint('❌ Failed to subscribe to track: $e');
          }
        }
      }
    }
    
    if (mounted && track != _videoTrack) {
      setState(() {
        _videoTrack = track;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final videoMuted = _videoTrack?.muted ?? true;
    
    if (_videoTrack == null || videoMuted) {
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
