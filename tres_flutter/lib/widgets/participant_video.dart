import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/user_lookup_service.dart';

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
  String? _resolvedDisplayName;
  String? _resolvedPhotoUrl;
  
  @override
  void initState() {
    super.initState();
    _setupVideoTrack();
    widget.participant.addListener(_onParticipantChanged);
    _resolveIdentity();
  }
  
  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    super.dispose();
  }
  
  void _onParticipantChanged() {
    _setupVideoTrack();
    _resolveIdentity();
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
    
      return VideoTrackRenderer(
        _videoTrack!,
        fit: VideoViewFit.cover,
      );
  }
  
  Widget _buildNoVideoPlaceholder() {
    // Prefer participant.name; if not present try resolved display name (from users collection);
    // finally fall back to identity.
    final displayName = (widget.participant.name.isNotEmpty)
      ? widget.participant.name
      : (_resolvedDisplayName != null && _resolvedDisplayName!.isNotEmpty)
        ? _resolvedDisplayName!
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

  void _resolveIdentity() async {
    // If participant already has a name, nothing to do
    if (widget.participant.name.isNotEmpty) return;

    final identity = widget.participant.identity;
    if (identity.isEmpty) return;

    try {
      final lookup = await UserLookupService().fetchForIdentity(identity);
      final display = lookup['displayName'] ?? '';
      final photo = lookup['photoURL'] ?? '';
      if ((display.isNotEmpty && display != _resolvedDisplayName) || (photo.isNotEmpty && photo != _resolvedPhotoUrl)) {
        if (mounted) {
          setState(() {
            _resolvedDisplayName = display;
            _resolvedPhotoUrl = photo;
          });
        }
      }
    } catch (e) {
      // ignore
    }
  }
}
