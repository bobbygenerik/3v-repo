import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class ParticipantVideo extends StatefulWidget {
  final Participant participant;
  final bool isLocal;
  final bool isMainView; // If true, request highest quality
  
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
    // Get first audio track from publications
    AudioTrack? track;
    
    debugPrint('🔊 Setting up audio track for ${widget.participant.identity}...');
    debugPrint('🔊 Audio publications: ${widget.participant.audioTrackPublications.length}');
    
    for (final pub in widget.participant.audioTrackPublications) {
      debugPrint('🔊 Publication ${pub.sid}: subscribed=${pub.subscribed}, track=${pub.track != null}, muted=${pub.muted}');
      
      if (pub.subscribed && pub.track != null) {
        track = pub.track as AudioTrack;
        debugPrint('🔊 Using subscribed audio track: ${pub.sid}');
        break;
      }
    }
    
    // If no subscribed track, explicitly subscribe to first available publication
    if (track == null && !widget.isLocal) {
      debugPrint('🔊 No subscribed audio track found, checking for unsubscribed publications...');
      for (final pub in widget.participant.audioTrackPublications) {
        if (!pub.subscribed && pub is RemoteTrackPublication) {
          try {
            debugPrint('🔊 Subscribing to audio track: ${pub.sid}');
            await pub.subscribe();
            if (pub.track != null) {
              track = pub.track as AudioTrack;
              debugPrint('🔊 Audio track subscribed');
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
      debugPrint('🔊 Audio track ${track != null ? "ACTIVE" : "CLEARED"} for ${widget.participant.identity}');
    }
  }
  
  void _setupVideoTrack() async {
    // Get first video track from publications
    VideoTrack? track;
    
    debugPrint('📹 Setting up video track for ${widget.participant.identity}...');
    debugPrint('📹 Video publications: ${widget.participant.videoTrackPublications.length}');
    
    for (final pub in widget.participant.videoTrackPublications) {
      debugPrint('📹 Publication ${pub.sid}: subscribed=${pub.subscribed}, track=${pub.track != null}, muted=${pub.muted}');
      
      if (pub.subscribed && pub.track != null) {
        track = pub.track as VideoTrack;
        debugPrint('📹 Using subscribed track: ${pub.sid}');
        
        // Request high quality for main view
        if (!widget.isLocal && pub is RemoteTrackPublication) {
          _requestHighQuality(pub);
        }
        break;
      }
    }
    
    // If no subscribed track, explicitly subscribe to first available publication
    if (track == null && !widget.isLocal) {
      debugPrint('📹 No subscribed track found, checking for unsubscribed publications...');
      for (final pub in widget.participant.videoTrackPublications) {
        if (!pub.subscribed && pub is RemoteTrackPublication) {
          try {
            debugPrint('📹 Subscribing to video track: ${pub.sid}');
            await pub.subscribe();
            
            // Request high quality after subscribing
            _requestHighQuality(pub);
            
            // The track will be available after subscription completes
            // and _onParticipantChanged will be called
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
      debugPrint('📹 Video track ${track != null ? "ACTIVE" : "CLEARED"} for ${widget.participant.identity}');
    }
  }
  
  /// Request highest quality video layer from sender via simulcast
  void _requestHighQuality(RemoteTrackPublication pub) {
    try {
      if (widget.isMainView) {
        // Request HIGH quality (1080p/720p depending on sender's capability)
        pub.setVideoQuality(VideoQuality.HIGH);
        pub.setVideoFPS(30);
        debugPrint('📹 Requested HIGH quality + 30fps for ${pub.sid}');
      } else {
        // Request LOW quality for smaller views (saves bandwidth)
        pub.setVideoQuality(VideoQuality.LOW);
        pub.setVideoFPS(24);
        debugPrint('📹 Requested LOW quality + 24fps for ${pub.sid}');
      }
    } catch (e) {
      debugPrint('⚠️ Could not set video quality: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Check if video is muted (camera off) or track doesn't exist
    final videoMuted = _videoTrack?.muted ?? true;
    
    if (_videoTrack == null || videoMuted) {
      return _buildNoVideoPlaceholder();
    }
    
    return RepaintBoundary(
      child: VideoTrackRenderer(
        _videoTrack!,
        fit: VideoViewFit.cover, // Use cover for better quality appearance
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
