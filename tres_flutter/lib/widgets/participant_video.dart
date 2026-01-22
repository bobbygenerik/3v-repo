import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/user_lookup_service.dart';

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
  String _displayName = '';
  String _photoUrl = '';
  String _lastIdentity = '';
  
  @override
  void initState() {
    super.initState();
    _setupTracks();
    _resolveParticipantProfile();
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
    if (oldWidget.participant.identity != widget.participant.identity) {
      _resolveParticipantProfile();
    }
  }
  
  void _onParticipantChanged() {
    _setupTracks();
    if (_lastIdentity != widget.participant.identity) {
      _resolveParticipantProfile();
    }
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
    
    for (final pub in widget.participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        track = pub.track as VideoTrack;
        break;
      }
    }
    
    // Subscribe if needed
    if (track == null && !widget.isLocal) {
      final futures = <Future>[];
      for (final pub in widget.participant.videoTrackPublications) {
        if (!pub.subscribed && pub is RemoteTrackPublication) {
          futures.add(pub.subscribe().catchError((e) {
            debugPrint('❌ Failed to subscribe to video: $e');
          }));
        }
      }
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }
      // Re-check after subscription to pick up the newly attached track.
      for (final pub in widget.participant.videoTrackPublications) {
        if (pub.subscribed && pub.track != null) {
          track = pub.track as VideoTrack;
          break;
        }
      }
    }
    
    // Request appropriate quality for this view
    _requestAppropriateQuality();
    
    if (mounted && track != _videoTrack) {
      setState(() => _videoTrack = track);
    }
  }
  
  void _requestAppropriateQuality() {
    for (final pub in widget.participant.videoTrackPublications) {
      if (pub is RemoteTrackPublication && pub.subscribed && pub.track != null) {
        _requestQualityForPublication(pub);
      }
    }
  }
  
  void _requestQualityForPublication(RemoteTrackPublication pub) {
    try {
      if (widget.isMainView) {
        // Main view: Request highest quality
        pub.setVideoQuality(VideoQuality.HIGH);
        debugPrint('📹 [${widget.participant.identity}] Requested HIGH quality (main view)');
      } else {
        // PIP/thumbnail: Request lower quality to protect main view stability.
        pub.setVideoQuality(VideoQuality.LOW);
        debugPrint('📹 [${widget.participant.identity}] Requested LOW quality (pip view)');
      }
    } catch (e) {
      debugPrint('⚠️ Could not set video quality: $e');
    }
  }

  Future<void> _resolveParticipantProfile() async {
    final identity = widget.participant.identity;
    if (identity.isEmpty || identity == _lastIdentity) return;
    _lastIdentity = identity;

    try {
      final profile = await UserLookupService().fetchForIdentity(identity);
      if (!mounted) return;
      setState(() {
        _displayName = profile['displayName'] ?? '';
        _photoUrl = profile['photoURL'] ?? '';
      });
    } catch (_) {
      // Ignore lookup errors; fall back to identity.
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
        : (_displayName.isNotEmpty ? _displayName : widget.participant.identity);
    
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: CircleAvatar(
          radius: 40,
          backgroundColor: Colors.grey[700],
          backgroundImage: _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
          child: _photoUrl.isNotEmpty
              ? null
              : Text(
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
