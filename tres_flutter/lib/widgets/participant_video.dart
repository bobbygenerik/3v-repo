import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class ParticipantVideo extends StatefulWidget {
  final Participant participant;
  final bool isLocal;
  final bool isMainView;
  final VideoViewFit fit;
  
  const ParticipantVideo({
    super.key,
    required this.participant,
    this.isLocal = false,
    this.isMainView = true,
    this.fit = VideoViewFit.cover,
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
  
  @override
  void didUpdateWidget(ParticipantVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-request quality if main view status changes
    if (oldWidget.isMainView != widget.isMainView) {
      _requestAppropriateQuality();
    }
  }
  
  void _onParticipantChanged() {
    _setupTracks();
  }
  
  void _setupTracks() {
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
    
    if (track == null && !widget.isLocal) {
      for (final pub in widget.participant.audioTrackPublications) {
        if (!pub.subscribed && pub is RemoteTrackPublication) {
          try {
            await pub.subscribe();
            if (pub.track != null) {
              track = pub.track as AudioTrack;
            }
          } catch (e) {
            debugPrint('❌ Failed to subscribe to audio: $e');
          }
        }
      }
    }
    
    if (mounted && track != _audioTrack) {
      setState(() => _audioTrack = track);
    }
  }
  
  void _setupVideoTrack() async {
    VideoTrack? track;
    RemoteTrackPublication? remotePub;
    
    for (final pub in widget.participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        track = pub.track as VideoTrack;
        if (pub is RemoteTrackPublication) {
          remotePub = pub;
        }
        break;
      }
    }
    
    // Subscribe if needed
    if (track == null && !widget.isLocal) {
      for (final pub in widget.participant.videoTrackPublications) {
        if (!pub.subscribed && pub is RemoteTrackPublication) {
          try {
            await pub.subscribe();
            remotePub = pub;
          } catch (e) {
            debugPrint('❌ Failed to subscribe to video: $e');
          }
        }
      }
    }
    
    // Request appropriate quality for this view
    if (remotePub != null) {
      _requestQualityForPublication(remotePub);
    }
    
    if (mounted && track != _videoTrack) {
      setState(() => _videoTrack = track);
    }
  }
  
  void _requestAppropriateQuality() {
    for (final pub in widget.participant.videoTrackPublications) {
      if (pub is RemoteTrackPublication && pub.subscribed) {
        _requestQualityForPublication(pub);
      }
    }
  }
  
  void _requestQualityForPublication(RemoteTrackPublication pub) {
    try {
      if (widget.isMainView) {
        // Main view: Request highest quality
        pub.setVideoQuality(VideoQuality.HIGH);
        pub.setVideoFPS(30);
        debugPrint('📹 [${widget.participant.identity}] Requested HIGH quality (main view)');
      } else {
        // PIP/thumbnail: Request lower quality to protect main view stability.
        pub.setVideoQuality(VideoQuality.LOW);
        pub.setVideoFPS(15);
        debugPrint('📹 [${widget.participant.identity}] Requested LOW quality (pip view)');
      }
    } catch (e) {
      debugPrint('⚠️ Could not set video quality: $e');
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
        fit: widget.fit,
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
    if (name.contains('@')) name = name.split('@')[0];
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
