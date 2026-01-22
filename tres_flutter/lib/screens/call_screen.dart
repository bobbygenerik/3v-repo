import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/livekit_service.dart';
import '../services/feature_flags.dart';
import '../services/device_mode_service.dart';
import '../services/android_pip_service.dart';
import '../services/call_features_coordinator.dart';
import '../services/call_session_service.dart';
import '../services/call_signaling_service.dart';
import '../services/call_listener_service.dart';
import '../services/reaction_service.dart';
import '../services/chat_service.dart' as chat;
import '../services/vibration_service.dart';
import '../services/call_stats_service.dart';
import '../services/ice_server_config.dart';
// MediaPipe removed: settings and processing removed
import '../config/environment.dart';
import '../widgets/participant_video.dart';
import '../widgets/call_waiting_banner.dart';
import '../widgets/video_call_quality_dashboard.dart';
import '../widgets/modern_chat_overlay.dart';
import '../widgets/chat_notification_badge.dart';
import '../widgets/audio_controls_panel.dart';
import '../services/audio_device_service.dart';

class CallScreen extends StatefulWidget {
  final String roomName;
  final String token;
  final String livekitUrl;
  final CallSessionService? sessionService;
  final CallSignalingService signalingService;
  
  const CallScreen({
    super.key,
    required this.roomName,
    required this.token,
    required this.livekitUrl,
    this.sessionService,
    required this.signalingService,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isConnecting = true;
  late CallFeaturesCoordinator _coordinator;
  LiveKitService? _livekit;
  final TextEditingController _chatController = TextEditingController();
  final CallListenerService _callListener = CallListenerService();
  
  // Call timer
  Duration _callDuration = Duration.zero;
  
  // Control animations
  bool _controlsVisible = true;
  late AnimationController _controlsAnimationController;
  late List<Animation<Offset>> _buttonSlideAnimations;
  Timer? _controlsHideTimer;
  
  // Reaction panel animation
  bool _reactionsVisible = false;
  late AnimationController _reactionsAnimationController;
  late Animation<Offset> _reactionsSlideAnimation;
  
  // PIP box state (tracks position from top-left corner)
  Offset? _pipPosition; // null = use default top-right position
  bool _pipExpanded = false;
  bool _pipSwapped = false;
  bool _isInAndroidPip = false;
  
  // Remote PIPs state
  final Map<String, Offset?> _remotePipPositions = {}; // Track position for each remote PIP
  int _mainParticipantIndex = 0; // Index of participant shown in main view (0 = first remote)
  String? _mainParticipantSid; // Track SID of participant in main view for stability
  
  // Track if we've ever had a remote participant (to avoid false disconnect on call start)
  bool _hadRemoteParticipant = false;
  
  // Track participant SIDs to detect new joins
  final Set<String> _knownParticipantSids = {};
  
  // Track newly joined participants for highlight animation
  final Set<String> _highlightedParticipants = {};
  
  // Track app lifecycle state
  bool _isAppInBackground = false;
  
  // Quality dashboard state
  bool _qualityDashboardVisible = false;
  
  // Call ending state
  bool _isCallEnding = false;
  bool _callEndedSnackbarShown = false;
  
  // Modern chat state
  bool _chatOverlayVisible = false;
  int _unreadMessageCount = 0;
  bool _hasNewMessage = false;
  String? _lastMessageId;
  DateTime? _lastNetworkWarning;
  bool _wasReconnecting = false;
  bool _pipEnabled = true;
  // Developer diagnostics overlay
  
  @override
  void initState() {
    super.initState();
    _coordinator = CallFeaturesCoordinator();
    _connectToRoom();
    _loadPipPreference();
    _setAndroidCallActive(true);
    
    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Start listening for incoming calls while in call (for call-waiting)
    _callListener.startListening();
    _callListener.addListener(_handleIncomingCallWhileInCall);
    
    // Listen for session end
    widget.sessionService?.addListener(_handleSessionEnd);
    
    // Listen for LiveKit room changes (participant disconnect) after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final livekit = context.read<LiveKitService>();
        livekit.addListener(_handleLiveKitUpdate);
        
        // Setup auto PiP for web if enabled
        _configureWebPip(livekit);
        
        // Listen for new chat messages
        _coordinator.addListener(_handleNewChatMessage);
      }
    });
    
    // Start call timer
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _callDuration += const Duration(seconds: 1);
        });
        return true;
      }
      return false;
    });
    
    // Initialize controls animation (cascade from bottom)
    _controlsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    // Create staggered animations for 5 buttons
    // LEFT to RIGHT for both rise and fall (0, 1, 2, 3, 4)
    _buttonSlideAnimations = List.generate(5, (index) {
      final start = index * 0.15; // Left button starts first (0.0, 0.15, 0.3, 0.45, 0.6)
      final end = start + 0.4; // Each animation duration
      return Tween<Offset>(
        begin: const Offset(0, 2), // Start below screen
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _controlsAnimationController,
        curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOut),
      ));
    });
    
    // Initialize reactions panel animation (slide from left)
    _reactionsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _reactionsSlideAnimation = Tween<Offset>(
      begin: const Offset(-1.5, 0), // Start off-screen left
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _reactionsAnimationController,
      curve: Curves.easeOut,
    ));
    
    // Show controls initially
    _controlsAnimationController.forward();
    
    // Start auto-hide timer for controls
    _startControlsHideTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _livekit ??= context.read<LiveKitService>();
  }
  
  /// Handle session end by other participant
  void _handleSessionEnd() {
    if (widget.sessionService?.isInCall == false && mounted) {
      // Call ended by another participant
      debugPrint('📞 Session ended - navigating back');
      _endCallAndNavigateBack();
    }
  }
  
  /// End call and navigate back with proper cleanup
  Future<void> _endCallAndNavigateBack() async {
    if (!mounted || _isCallEnding) return;
    
    setState(() {
      _isCallEnding = true;
    });
    
    try {
      debugPrint('📞 Ending call and cleaning up...');

      await _disableAndroidPipAfterCall();
      
      // Fire and forget cleanup operations
      widget.signalingService.endCall(widget.roomName).catchError((e) {
        debugPrint('Error ending signaling call: $e');
      });
      
      widget.sessionService?.endSession().catchError((e) {
        debugPrint('Error ending session: $e');
      });
      
      // Disconnect from LiveKit
      final livekit = Provider.of<LiveKitService>(context, listen: false);
      try {
        await livekit.disconnect().timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Error disconnecting from LiveKit: $e');
      }
      
      // Small delay to show ending state, then navigate
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Navigate back
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Error during call cleanup: $e');
      // Force navigation even if cleanup fails
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _disableAndroidPipAfterCall() async {
    try {
      await AndroidPipService.setCallActive(false);
      await AndroidPipService.setAutoPipEnabled(false);
      if (mounted) {
        setState(() {
          _isInAndroidPip = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to disable Android PiP after call: $e');
    }
  }
  
  /// Update PiP stream with current main participant's video (web only)
  void _updatePipForMainParticipant() {
    if (!mounted) return;
    
    final livekit = context.read<LiveKitService>();
    final remoteParticipants = livekit.remoteParticipants;
    
    if (remoteParticipants.isEmpty || _mainParticipantIndex >= remoteParticipants.length) {
      return;
    }
    
    final mainParticipant = remoteParticipants[_mainParticipantIndex];
    
    // Get the video track from the main participant
    VideoTrack? videoTrack;
    for (final pub in mainParticipant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        videoTrack = pub.track as VideoTrack;
        break;
      }
    }
    
    // Update the PiP service with this track
    livekit.updatePipStream(videoTrack);
  }
  
  /// Handle LiveKit updates - check if all participants left
  void _handleLiveKitUpdate() {
    final livekit = context.read<LiveKitService>();

    // Only surface MediaPipe errors when MediaPipe features are enabled.
    final mediaPipeError = FeatureFlags.enableMediaPipe ? livekit.consumeMediaPipeError() : null;
    if (mediaPipeError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mediaPipeError,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xFFB24A4A),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    if (livekit.isReconnecting != _wasReconnecting && mounted) {
      _wasReconnecting = livekit.isReconnecting;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                livekit.isReconnecting ? Icons.wifi_off : Icons.wifi,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  livekit.isReconnecting
                      ? 'Reconnecting... call will resume automatically'
                      : 'Reconnected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF6B7FB8),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      if (!livekit.isReconnecting) {
        // Reconnected — gentle haptic
        VibrationService.mediumImpact();
      }
    }
    
    // Track if we've ever had a remote participant join
    final hadParticipants = _hadRemoteParticipant;
    if (livekit.remoteParticipants.isNotEmpty) {
      _hadRemoteParticipant = true;
      
      // If this is the first participant joining, update PiP stream
      if (!hadParticipants) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updatePipForMainParticipant();
        });
      }
      
      // Detect new participant joins
      final currentSids = livekit.remoteParticipants.map((p) => p.sid).toSet();
      final newSids = currentSids.difference(_knownParticipantSids);
      
      if (newSids.isNotEmpty && _knownParticipantSids.isNotEmpty) {
        // Someone new joined (and this isn't the initial call setup)
        for (final sid in newSids) {
          final participant = livekit.remoteParticipants.firstWhere((p) => p.sid == sid);
          final name = participant.name ?? participant.identity ?? 'Someone';
          
          // Show toast notification
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.person_add, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$name joined the call',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 3),
                backgroundColor: const Color(0xFF6B7FB8),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
          
          // Add to highlighted participants for animation
          _highlightedParticipants.add(sid);
          
          // Remove highlight after 4 seconds
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _highlightedParticipants.remove(sid);
              });
            }
          });
        }
      }
      
      // Update known participants
      _knownParticipantSids.clear();
      _knownParticipantSids.addAll(currentSids);
    }
    
    // Clean up positions for disconnected participants
    final activeSids = livekit.remoteParticipants.map((p) => p.sid).toSet();
    _remotePipPositions.removeWhere((sid, _) => !activeSids.contains(sid));
    
    // Update main participant tracking if current one disconnected
    if (_mainParticipantSid != null && !activeSids.contains(_mainParticipantSid)) {
      // Current main participant left - find their index and adjust
      if (livekit.remoteParticipants.isNotEmpty) {
        // Switch to first available participant
        _mainParticipantIndex = 0;
        _mainParticipantSid = livekit.remoteParticipants[0].sid;
        
        // Update PiP to show new main participant
        _updatePipForMainParticipant();
      } else {
        _mainParticipantSid = null;
      }
    }
    
    // Handle case when all remote participants have left (call ended)
    if (livekit.remoteParticipants.isEmpty && _knownParticipantSids.isNotEmpty && !_callEndedSnackbarShown) {
      // All remote participants have disconnected
      debugPrint('📞 All participants have left - ending call immediately');
      
      if (mounted) {
        _callEndedSnackbarShown = true; // Prevent duplicate snackbars
        
        // Show brief notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.call_end, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Call ended',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 1),
            backgroundColor: const Color(0xFF6B7FB8),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        
        // End call immediately without delay to prevent black screen
        _endCallAndNavigateBack();
      }
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    debugPrint('📱 App lifecycle changed: $state');
    
    switch (state) {
      case AppLifecycleState.inactive:
        // Transient loss of focus (e.g., notification shade). Keep video rendering.
        debugPrint('📱 App inactive (transient) - keeping video active');
        break;
      case AppLifecycleState.paused:
        // App moved to background or entered PiP.
        debugPrint('📱 App backgrounded during call - call continues');
        _handlePausedState();
        break;
        
      case AppLifecycleState.resumed:
        // App returned to foreground
        final wasBackgrounded = _isAppInBackground;
        _isAppInBackground = false;
        _isInAndroidPip = false;
        _loadPipPreference();
        debugPrint('📱 App resumed - refreshing UI');
        if (mounted && wasBackgrounded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.phone_in_talk, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Call resumed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF6B7FB8),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        
        // Refresh UI state
        if (mounted) {
          setState(() {
            // Force UI rebuild to ensure everything is current
          });
        }
        break;
        
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is terminating or hidden
        debugPrint('📱 App detached/hidden');
        break;
    }
  }

  void _handlePausedState() {
    if (Theme.of(context).platform == TargetPlatform.android) {
      _tryEnterAndroidPip().then((enteredPip) {
        if (!mounted) return;
        _isAppInBackground = !enteredPip;
        if (!enteredPip) {
          _showBackgroundCallSnack();
        }
      });
      return;
    }

    _isAppInBackground = true;
    _showBackgroundCallSnack();
  }

  void _showBackgroundCallSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.phone_in_talk, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Call continues in background',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF6B7FB8),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  
  Future<bool> _tryEnterAndroidPip() async {
    try {
      if (!_pipEnabled) return false;
      final available = await AndroidPipService.isPipAvailable();
      if (available) {
        final entered = await AndroidPipService.enterPipMode();
        if (entered) {
          debugPrint('✅ Entered Android PiP mode');
          if (mounted) {
            setState(() {
              _isInAndroidPip = true;
              _pipSwapped = false;
              _pipExpanded = false;
            });
          }
        }
        return entered;
      }
    } catch (e) {
      debugPrint('❌ Error entering Android PiP: $e');
    }
    return false;
  }

  Future<void> _loadPipPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('picture_in_picture') ?? true;
      _pipEnabled = enabled;
      if (!mounted) return;
      final livekit = context.read<LiveKitService>();
      // Respect global PiP feature flag and Safari PWA conservative defaults
      final pipAllowed = FeatureFlags.enablePictureInPicture && !DeviceModeService.isSafariPwa();
      if (pipAllowed) {
        _configureWebPip(livekit);
        await AndroidPipService.setAutoPipEnabled(_pipEnabled);
      } else {
        _configureWebPip(livekit);
        await AndroidPipService.setAutoPipEnabled(false);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load PiP preference: $e');
    }
  }

  Future<void> _setAndroidCallActive(bool active) async {
    // Only notify Android PiP if PiP is allowed by flags and not a Safari PWA
    final pipAllowed = FeatureFlags.enablePictureInPicture && !DeviceModeService.isSafariPwa();
    await AndroidPipService.setCallActive(active);
    if (active) {
      await AndroidPipService.setAutoPipEnabled(pipAllowed ? _pipEnabled : false);
    }
  }

  void _configureWebPip(LiveKitService livekit) {
    final pipAllowed = FeatureFlags.enablePictureInPicture && !DeviceModeService.isSafariPwa();
    livekit.pipService.setAutoEnterPip(pipAllowed && _pipEnabled);
    if (pipAllowed && _pipEnabled) {
      livekit.setupAutoPip();
    } else if (livekit.pipService.isPipActive) {
      livekit.pipService.exitPip();
    }
  }

  Future<bool> _enterPipNow(LiveKitService livekit) async {
    final pipAllowed = FeatureFlags.enablePictureInPicture && !DeviceModeService.isSafariPwa();
    if (!_pipEnabled || !pipAllowed) return false;
    if (Theme.of(context).platform == TargetPlatform.android) {
      final available = await AndroidPipService.isPipAvailable();
      if (!available) return false;
      final entered = await AndroidPipService.enterPipMode();
      if (entered && mounted) {
        setState(() {
          _isInAndroidPip = true;
          _pipSwapped = false;
          _pipExpanded = false;
        });
      }
      return entered;
    }
    return livekit.pipService.enterPip();
  }
  
  void _startControlsHideTimer() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controlsVisible) {
        setState(() {
          _controlsVisible = false;
          _controlsAnimationController.reverse();
        });
      }
    });
  }
  
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
  
  bool _shouldShowPlaceholder(LiveKitService livekit) {
    // Show placeholder when app is backgrounded
    if (_isAppInBackground) return true;
    
    // Show placeholder when main participant has video disabled
    final remoteParticipants = livekit.remoteParticipants;
    if (remoteParticipants.isEmpty) return false;
    
    // Check if main participant has video enabled
    int mainIndex = _mainParticipantIndex;
    if (_mainParticipantSid != null) {
      final foundIndex = remoteParticipants.indexWhere((p) => p.sid == _mainParticipantSid);
      if (foundIndex != -1) mainIndex = foundIndex;
    }
    if (mainIndex >= remoteParticipants.length) mainIndex = 0;
    
    final mainParticipant = remoteParticipants[mainIndex];
    
    // Check if participant has any video track enabled
    for (final pub in mainParticipant.videoTrackPublications) {
      if (!pub.muted && pub.subscribed) {
        return false; // Video is on, don't show placeholder
      }
    }
    
    return true; // No active video, show placeholder
  }
  
  Widget _buildBackgroundPlaceholder(LiveKitService livekit) {
    final remoteCount = livekit.remoteParticipants.length;
    final participantText = remoteCount == 1 
        ? livekit.remoteParticipants.first.name ?? livekit.remoteParticipants.first.identity ?? 'participant'
        : '$remoteCount participants';
    
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated phone icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1.1),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone_in_talk,
                      size: 64,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                );
              },
              onEnd: () {
                // Restart animation if still in background
                if (mounted && _isAppInBackground) {
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 32),
            Text(
              _isAppInBackground ? 'Call in progress' : 'Camera off',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connected with $participantText',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(_callDuration),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 32),
            if (_isAppInBackground)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.white70, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Return to app to see video',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _connectToRoom() async {
    final livekit = context.read<LiveKitService>();
    
    final success = await livekit.connect(
      url: widget.livekitUrl,
      token: widget.token,
      roomName: widget.roomName,
    );

    if (!mounted || _isCallEnding) {
      if (success) {
        await livekit.disconnect();
      }
      return;
    }

    // Initialize coordinator with room (now async)
    if (success && livekit.room != null) {
      await _coordinator.initialize(
        livekit.room!,
        liveKitService: livekit,
        audioDeviceService: context.read<AudioDeviceService>(),
      );
      // Wire stats updates into LiveKitService adaptive logic.
      // Whenever stats change, forward to LiveKitService so it can
      // react (recreate/publish tracks) based on real event-driven metrics.
      _coordinator.statsService.addListener(() {
        try {
          final stats = _coordinator.statsService.currentStats;
          _maybeShowNetworkWarning(stats);
          livekit.applyObservedStats(stats);
        } catch (e) {
          debugPrint('Failed to process call stats: $e');
        }
      });
      _coordinator.statsService.startCollecting();
    }
    
    if (mounted) {
      setState(() => _isConnecting = false);
    }
    if (success) {
      // subtle haptic to indicate call connected (no-op on Safari PWA)
      VibrationService.lightImpact();
    }
    
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  livekit.errorMessage ?? 'Failed to connect',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFE53E3E),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _maybeShowNetworkWarning(CallStats stats) {
    if (!mounted) return;

    final rttMs = stats.roundTripTime * 1000.0;
    final jitterMs = stats.jitter * 1000.0;
    final packetLoss = stats.videoPacketLoss;

    final isDegraded = packetLoss > 5.0 || rttMs > 300.0 || jitterMs > 50.0;
    if (!isDegraded) return;

    final now = DateTime.now();
    if (_lastNetworkWarning != null &&
        now.difference(_lastNetworkWarning!) < const Duration(seconds: 30)) {
      return;
    }

    _lastNetworkWarning = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.network_check, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Network is unstable. Try Wi-Fi or move closer to your router.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFFE67E22),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return WillPopScope(
        onWillPop: () async {
          await _endCallAndNavigateBack();
          return false;
        },
        child: const Scaffold(
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
        ),
      );
    }

    if (_isCallEnding) {
      return WillPopScope(
        onWillPop: () async {
          await _endCallAndNavigateBack();
          return false;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    size: 64,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Call ended',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Duration: ${_formatDuration(_callDuration)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        await _endCallAndNavigateBack();
        return false;
      },
      child: ChangeNotifierProvider<CallFeaturesCoordinator>.value(
        value: _coordinator,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onHorizontalDragStart: (details) {
              // Track if drag started from left edge
              if (details.globalPosition.dx < 50) {
                setState(() {
                  _reactionsVisible = true;
                  _reactionsAnimationController.forward();
                });
              }
            },
            onHorizontalDragEnd: (details) {
              // Swipe right from left edge to show reactions
              if (details.primaryVelocity != null && details.primaryVelocity! > 500) {
                if (!_reactionsVisible) {
                  _toggleReactions();
                }
              }
              // Swipe left to hide reactions
              else if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
                if (_reactionsVisible) {
                  _toggleReactions();
                }
              }
            },
            child: SafeArea(
              child: Consumer2<LiveKitService, CallFeaturesCoordinator>(
                builder: (context, livekit, coordinator, child) {
                  final isAndroidPipView =
                      _isInAndroidPip && Theme.of(context).platform == TargetPlatform.android;
                  if (isAndroidPipView) {
                    return _buildAndroidPipLayout(livekit);
                  }
                  return Stack(
                    children: [
                      // Main participant view
                      _buildMainParticipantView(livekit),

                      // Placeholder overlay (when backgrounded OR video is disabled)
                      if (_shouldShowPlaceholder(livekit))
                        _buildBackgroundPlaceholder(livekit),

                      // Reaction overlay (floating emojis)
                      ReactionOverlay(reactions: coordinator.activeReactions),

                      // Reactions panel (slide from left)
                      _buildReactionsPanel(coordinator),

                      // Remote participant PIPs (bottom-left, stacked vertically)
                      ..._buildRemotePips(livekit),

                      // Local video preview (PIP - repositionable, starts at fixed top-right)
                      Positioned(
                        left: _pipPosition?.dx ?? (MediaQuery.of(context).size.width - (_pipExpanded ? 169 : 135) - 16),
                        top: _pipPosition?.dy ?? 16,
                        child: _buildLocalVideoPreview(livekit),
                      ),

                      // Room info (top-left)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: _buildRoomInfo(coordinator),
                      ),

                      if (livekit.isReconnecting)
                        Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.sync, color: Colors.white, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    'Reconnecting...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Call-waiting banner (shows when receiving a call while in call)
                      if (_callListener.hasIncomingCall)
                        Positioned(
                          top: 80,
                          left: 16,
                          right: 16,
                          child: CallWaitingBanner(
                            callerName: _callListener.currentIncomingCall!['callerName'],
                            callerPhotoUrl: _callListener.currentIncomingCall!['callerPhotoUrl'],
                            isVideoCall: _callListener.currentIncomingCall!['isVideoCall'],
                            onAccept: _acceptWaitingCall,
                            onDecline: _declineWaitingCall,
                          ),
                        ),

                      // Call controls (bottom) - always rendered, visibility controlled by animation
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        bottom: _controlsVisible ? 0 : -120,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildCallControls(livekit, coordinator),
                          ),
                        ),
                      ),

                      // Quality Dashboard (positioned to avoid overlap)
                      if (_qualityDashboardVisible)
                        Positioned(
                          top: 100,
                          right: 16,
                          child: VideoCallQualityDashboard(
                            isExpanded: true,
                            statsService: _coordinator.statsService,
                            onToggle: () {
                              setState(() {
                                _qualityDashboardVisible = false;
                              });
                            },
                          ),
                        ),

                      // Modern Chat Overlay
                      ModernChatOverlay(
                        messages: coordinator.chatMessages,
                        onSendMessage: (message) {
                          coordinator.sendChatMessage(message);
                          setState(() {
                            _hasNewMessage = false;
                          });
                        },
                        isVisible: _chatOverlayVisible,
                        onToggleExpanded: () {
                          setState(() {
                            _chatOverlayVisible = !_chatOverlayVisible;
                            if (_chatOverlayVisible) {
                              _unreadMessageCount = 0;
                              _hasNewMessage = false;
                            }
                          });
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidPipLayout(LiveKitService livekit) {
    final localParticipant = livekit.localParticipant;
    return Stack(
      children: [
        _buildMainParticipantView(livekit, fit: VideoViewFit.contain),
        if (localParticipant != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: SizedBox(
              width: 120,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ParticipantVideo(
                  key: const ValueKey('android-pip-local'),
                  participant: localParticipant,
                  isLocal: true,
                  fit: VideoViewFit.cover,
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) {
        _controlsAnimationController.forward();
        _startControlsHideTimer();
      } else {
        _controlsAnimationController.reverse();
        _controlsHideTimer?.cancel();
      }
    });
  }
  
  void _toggleReactions() {
    setState(() {
      _reactionsVisible = !_reactionsVisible;
      if (_reactionsVisible) {
        _reactionsAnimationController.forward();
      } else {
        _reactionsAnimationController.reverse();
      }
    });
  }
  
  Widget _buildReactionsPanel(CallFeaturesCoordinator coordinator) {
    if (!_reactionsVisible) return const SizedBox.shrink();
    
    return Positioned(
      left: 16,
      top: MediaQuery.of(context).size.height * 0.3,
      child: SlideTransition(
        position: _reactionsSlideAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ReactionType.values.map((type) {
              return GestureDetector(
                onTap: () {
                  coordinator.sendReaction(type);
                  _toggleReactions(); // Hide after selection
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    type.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
  
  Widget _buildRoomInfo(CallFeaturesCoordinator coordinator) {
    // Get remote participant name or use room name
    final livekit = context.read<LiveKitService>();
    final remoteParticipants = livekit.remoteParticipants;
    final callerName = remoteParticipants.isNotEmpty 
        ? (remoteParticipants.first.name.isNotEmpty ? remoteParticipants.first.name : remoteParticipants.first.identity)
        : widget.roomName;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Caller name - just text, no box
        Text(
          callerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black,
                offset: Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Time elapsed - just text, no box
        Text(
          _formatDuration(_callDuration),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(
                color: Colors.black,
                offset: Offset(0, 1),
                blurRadius: 3,
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
  
  Widget _buildMainParticipantView(
    LiveKitService livekit, {
    VideoViewFit fit = VideoViewFit.cover,
  }) {
    final remoteParticipants = livekit.remoteParticipants;
    
    // If PIP is swapped, show local participant in main view
    if (_pipSwapped && livekit.localParticipant != null) {
      return RepaintBoundary(
        child: ParticipantVideo(
          key: const ValueKey('main-local-swapped'),
          participant: livekit.localParticipant!,
          isLocal: true,
          fit: fit,
        ),
      );
    }
    
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
    
    // Find participant by SID, or use index as fallback
    int mainIndex = _mainParticipantIndex;
    if (_mainParticipantSid != null) {
      final foundIndex = remoteParticipants.indexWhere((p) => p.sid == _mainParticipantSid);
      if (foundIndex != -1) {
        mainIndex = foundIndex;
      }
    }
    
    // Ensure index is valid
    if (mainIndex >= remoteParticipants.length) {
      mainIndex = 0;
    }
    
    // Update tracking
    _mainParticipantIndex = mainIndex;
    _mainParticipantSid = remoteParticipants[mainIndex].sid;
    
    // Show selected remote participant in main view
    return RepaintBoundary(
      child: ParticipantVideo(
        key: ValueKey('main-remote-${remoteParticipants[mainIndex].sid}'),
        participant: remoteParticipants[mainIndex],
        fit: fit,
      ),
    );
  }
  
  List<Widget> _buildRemotePips(LiveKitService livekit) {
    final remoteParticipants = livekit.remoteParticipants;
    
    // If swapped or only one participant, no remote PIPs needed
    if (_pipSwapped || remoteParticipants.length <= 1) {
      return [];
    }
    
    // Show additional remote participants (skip the one in main view)
    final List<Widget> pips = [];
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height && screenSize.width > 800;
    
    // Count PIPs that will be displayed (excluding main participant)
    final pipCount = remoteParticipants.length - 1;
    
    // Calculate available vertical space (screen height minus margins and controls)
    // Leave space for: top margin (16), bottom margin (16), and controls at bottom (~120)
    final availableHeight = screenSize.height - 16 - 16 - 120;
    
    // Calculate dimensions based on available space
    double width, height;
    if (isLandscape) {
      width = 213;
      height = 120;
    } else {
      width = 135;
      height = 240;
    }
    
    // Calculate spacing between PIPs to fit them all on screen
    final totalPipHeight = pipCount * height;
    final totalGapHeight = availableHeight - totalPipHeight;
    final gap = pipCount > 1 ? (totalGapHeight / (pipCount - 1)).clamp(4.0, 8.0) : 8.0;
    
    // If PIPs won't fit with minimum spacing, shrink them proportionally
    if (totalPipHeight + (pipCount - 1) * 4 > availableHeight && pipCount > 1) {
      final scale = (availableHeight - (pipCount - 1) * 4) / totalPipHeight;
      width *= scale;
      height *= scale;
    }
    
    int pipIndex = 0; // Track position index for PIPs (for stacking calculation)
    for (int i = 0; i < remoteParticipants.length; i++) {
      // Skip the participant currently in main view
      if (i == _mainParticipantIndex) continue;
      final participant = remoteParticipants[i];
      final pipKey = participant.sid;
      
      // Calculate default position: bottom-left, stacked vertically with dynamic spacing
      final defaultBottom = 16.0 + pipIndex * (height + gap);
      final defaultPosition = Offset(16, screenSize.height - defaultBottom - height);
      
      final position = _remotePipPositions[pipKey] ?? defaultPosition;
      
      final participantIndex = i; // Capture for closure
      
      pips.add(
        Positioned(
          left: position.dx,
          top: position.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              // Tapping does nothing now - removed expand/collapse to keep consistent sizing
            },
            onDoubleTap: () {
              // Swap this participant to main view
              setState(() {
                _mainParticipantIndex = participantIndex;
                _mainParticipantSid = participant.sid;
              });
              
              // Update PiP stream to show new main participant (web only)
              _updatePipForMainParticipant();
            },
            onPanUpdate: (details) {
              setState(() {
                _remotePipPositions[pipKey] = Offset(
                  (position.dx + details.delta.dx).clamp(16.0, screenSize.width - width - 16),
                  (position.dy + details.delta.dy).clamp(16.0, screenSize.height - height - 16),
                );
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: width,
              height: height,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _highlightedParticipants.contains(pipKey) 
                      ? const Color(0xFF4CAF50) 
                      : Colors.white,
                  width: _highlightedParticipants.contains(pipKey) ? 4 : 2,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: _highlightedParticipants.contains(pipKey)
                        ? const Color(0xFF4CAF50).withOpacity(0.6)
                        : Colors.black.withOpacity(0.5),
                    blurRadius: _highlightedParticipants.contains(pipKey) ? 20 : 10,
                    offset: const Offset(0, 4),
                    spreadRadius: _highlightedParticipants.contains(pipKey) ? 2 : 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: RepaintBoundary(
                  child: ParticipantVideo(
                    key: ValueKey('remote-pip-$pipKey'),
                    participant: participant,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      
      pipIndex++; // Increment for next PIP's stacking position
    }
    
    return pips;
  }
  
  Widget _buildLocalVideoPreview(LiveKitService livekit) {
    final localParticipant = livekit.localParticipant;
    
    if (localParticipant == null) {
      return const SizedBox.shrink();
    }

    // Detect orientation - but for desktop/web, check screen size instead
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height && screenSize.width > 800;
    
    // Calculate dimensions based on orientation
    // Default to PORTRAIT for desktop/web
    double width, height;
    if (isLandscape) {
      // Landscape: 16:9 ratio (wider than tall)
      if (_pipExpanded) {
        width = 267; // 16:9 landscape - extra large
        height = 150;
      } else {
        width = 213; // 16:9 landscape - default
        height = 120;
      }
    } else {
      // Portrait: 9:16 ratio (taller than wide) - DEFAULT
      if (_pipExpanded) {
        width = 169; // 9:16 portrait - extra large
        height = 300;
      } else {
        width = 135; // 9:16 portrait - default
        height = 240;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () {
        // Single tap: toggle size
        setState(() {
          _pipExpanded = !_pipExpanded;
          // Dimensions will be recalculated on rebuild based on orientation
        });
      },
      onDoubleTap: () {
        // Double tap: swap feeds
        setState(() {
          _pipSwapped = !_pipSwapped;
        });
      },
      onPanUpdate: (details) {
        // Get screen dimensions
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        
        // Get current position (if null, calculate from top-right with 16px margin)
        final currentPos = _pipPosition ?? Offset(
          screenWidth - width - 16,
          16,
        );
        
        // Drag to reposition with proper bounds checking
        setState(() {
          _pipPosition = Offset(
            (currentPos.dx + details.delta.dx).clamp(16.0, screenWidth - width - 16),
            (currentPos.dy + details.delta.dy).clamp(16.0, screenHeight - height - 16),
          );
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20), // Rounder corners
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Show appropriate participant based on swap state
            if (_pipSwapped && livekit.remoteParticipants.isNotEmpty)
              ParticipantVideo(
                key: const ValueKey('pip-remote-swapped'),
                participant: livekit.remoteParticipants.first,
              )
            else
              ParticipantVideo(
                key: const ValueKey('pip-local-normal'),
                participant: localParticipant,
                isLocal: true,
              ),
            // Label at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  _pipSwapped && livekit.remoteParticipants.isNotEmpty
                      ? (livekit.remoteParticipants.first.name.isNotEmpty ? livekit.remoteParticipants.first.name : livekit.remoteParticipants.first.identity)
                      : (livekit.localParticipant?.name.isNotEmpty == true ? livekit.localParticipant!.name : (livekit.localParticipant?.identity?.isNotEmpty == true ? livekit.localParticipant!.identity! : 'You')),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCallControls(LiveKitService livekit, CallFeaturesCoordinator coordinator) {
    // Calculate responsive button sizes based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = screenWidth < 360 ? 45.0 : 50.0;
    final centerButtonSize = screenWidth < 360 ? 56.0 : 64.0;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 16.0;
    final buttonSpacing = screenWidth < 400 ? 4.0 : 8.0;
    
    // Button order: More (leftmost), Mic, END CALL (center), Camera, Flip
    final buttons = [
      // 0: More / Extra (moved to left)
      _buildAnimatedButton(
        index: 0,
        icon: Icons.more_vert,
        onPressed: () => _showMoreMenu(livekit, coordinator),
        backgroundColor: Colors.white.withOpacity(0.2),
        size: buttonSize,
        spacing: buttonSpacing,
      ),
      // 1: Mic (left of center)
      _buildAnimatedButton(
        index: 1,
        icon: livekit.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
        onPressed: () => livekit.toggleMicrophone(),
        backgroundColor: livekit.isMicrophoneEnabled
            ? Colors.white.withOpacity(0.2)
            : Colors.red.shade600,
        size: buttonSize,
        spacing: buttonSpacing,
      ),
      // 2: END CALL (center - larger)
      _buildAnimatedButton(
        index: 2,
        icon: Icons.call_end,
        onPressed: () async {
          if (!mounted) return;
          
          // Vibrate when call is ended
          VibrationService.vibrateCallEnd();
          
          // End call using the centralized method
          await _endCallAndNavigateBack();
        },
        backgroundColor: Colors.red.shade600,
        size: centerButtonSize, // Larger center button
        spacing: buttonSpacing,
      ),
      // 3: Camera (right of center)
      _buildAnimatedButton(
        index: 3,
        icon: livekit.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
        onPressed: livekit.toggleCamera,
        backgroundColor: livekit.isCameraEnabled
            ? Colors.white.withOpacity(0.2)
            : Colors.red.shade600,
        size: buttonSize,
        spacing: buttonSpacing,
      ),
      // 4: Flip camera (rightmost)
      _buildAnimatedButton(
        index: 4,
        icon: Icons.cameraswitch,
        onPressed: livekit.switchCamera,
        backgroundColor: Colors.white.withOpacity(0.2),
        size: buttonSize,
        spacing: buttonSpacing,
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: buttons,
      ),
    );
  }
  
  Widget _buildAnimatedButton({
    required int index,
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    required double size,
    required double spacing,
    String? badge,
  }) {
    return SlideTransition(
      position: _buttonSlideAnimations[index],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                splashColor: Colors.white.withOpacity(0.3),
                highlightColor: Colors.white.withOpacity(0.1),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: size * 0.5,
                  ),
                ),
              ),
            ),
            if (badge != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Center(
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  

  
  // More menu
  void _showMoreMenu(LiveKitService livekit, CallFeaturesCoordinator coordinator) {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      builder: (context) {
        final menuCoordinator = coordinator;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'More Options',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF8E8E93)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    _buildMoreSectionLabel('People'),
                    ListTile(
                      leading: const Icon(Icons.person_add, color: Color(0xFF6B7FB8)),
                      title: const Text('Add Person', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        _showAddPersonDialog();
                      },
                    ),
                    ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.chat_bubble, color: Color(0xFF6B7FB8)),
                          if (_unreadMessageCount > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        _unreadMessageCount > 0 ? 'Chat ($_unreadMessageCount)' : 'Chat',
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        setState(() {
                          _chatOverlayVisible = !_chatOverlayVisible;
                          if (_chatOverlayVisible) {
                            _unreadMessageCount = 0;
                            _hasNewMessage = false;
                          }
                        });
                        Navigator.pop(context);
                      },
                    ),

                    // ML features removed for Safari PWA stability

                    const Divider(color: Color(0xFF2C2C2E)),
                    _buildMoreSectionLabel('Call Tools'),
                    if (Theme.of(context).platform == TargetPlatform.android || livekit.pipService.isPipSupported) ...[
                      ListTile(
                        leading: const Icon(Icons.picture_in_picture, color: Color(0xFF6B7FB8)),
                        title: const Text('Enter PiP', style: TextStyle(color: Colors.white)),
                        subtitle: const Text(
                          'Keep call visible while multitasking',
                          style: TextStyle(color: Color(0xFF8E8E93)),
                        ),
                        onTap: () async {
                          final entered = await _enterPipNow(livekit);
                          if (!mounted) return;
                          Navigator.pop(context);
                          if (!entered && mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: Text('PiP not available on this device/browser'),
                                backgroundColor: Color(0xFF2C2C2E),
                                behavior: SnackBarBehavior.floating,
                                margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                    const Divider(color: Color(0xFF2C2C2E)),
                    _buildMoreSectionLabel('Insights'),
                    ListTile(
                      leading: const Icon(Icons.analytics, color: Color(0xFF6B7FB8)),
                      title: const Text('Quality Dashboard', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        setState(() {
                          _qualityDashboardVisible = !_qualityDashboardVisible;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.volume_up, color: Color(0xFF6B7FB8)),
                      title: const Text('Audio Controls', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        _showAudioControlsPanel();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMoreSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
  
  void _showAddPersonDialog() {
    final TextEditingController emailController = TextEditingController();
    List<Map<String, dynamic>> filteredContacts = [];
    bool isLoading = false;
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void updateContacts(String query) async {
            if (query.isEmpty) {
              setDialogState(() {
                filteredContacts = [];
                isLoading = false;
              });
              return;
            }
            
            setDialogState(() => isLoading = true);
            
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser == null) {
              setDialogState(() => isLoading = false);
              return;
            }
            
            try {
              final contactsSnapshot = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .collection('contacts')
                  .get();
              
              final List<Map<String, dynamic>> contacts = [];
              for (var contactDoc in contactsSnapshot.docs) {
                final contactUid = contactDoc.id;
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(contactUid)
                    .get();
                
                if (userDoc.exists) {
                  final data = userDoc.data();
                  if (data != null) {
                    contacts.add({
                      'uid': contactUid,
                      'name': data['displayName'] ?? data['name'] ?? 'Unknown',
                      'email': data['email'] ?? '',
                    });
                  }
                }
              }
              
              final filtered = contacts.where((contact) {
                final name = (contact['name'] as String).toLowerCase();
                final email = (contact['email'] as String).toLowerCase();
                final searchQuery = query.toLowerCase();
                return name.contains(searchQuery) || email.contains(searchQuery);
              }).take(5).toList();
              
              setDialogState(() {
                filteredContacts = filtered;
                isLoading = false;
              });
            } catch (e) {
              debugPrint('Error loading contacts: $e');
              setDialogState(() => isLoading = false);
            }
          }
          
          return AlertDialog(
            backgroundColor: const Color(0xFF2C2C2E),
            title: const Text('Add Person to Call', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Enter name or email',
                    hintStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF6B7FB8)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF6B7FB8)),
                    ),
                  ),
                  onChanged: updateContacts,
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF6B7FB8),
                        ),
                      ),
                    ),
                  ),
                if (!isLoading && filteredContacts.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3C3C3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: filteredContacts.length,
                      itemBuilder: (context, index) {
                        final contact = filteredContacts[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF6B7FB8),
                            child: Text(
                              (contact['name'] as String).isNotEmpty 
                                  ? (contact['name'] as String)[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                          title: Text(
                            contact['name'] as String,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: Text(
                            contact['email'] as String,
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          onTap: () {
                            emailController.text = contact['email'] as String;
                            setDialogState(() {
                              filteredContacts = [];
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
              ),
              TextButton(
                onPressed: () async {
                  final email = emailController.text.trim();
                  if (email.isEmpty) return;
                  
                  Navigator.pop(dialogContext);
                  
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6B7FB8)),
                    ),
                  );
                  
                  try {
                    final userQuery = await FirebaseFirestore.instance
                        .collection('users')
                        .where('email', isEqualTo: email.toLowerCase())
                        .limit(1)
                        .get();
                    
                    if (userQuery.docs.isEmpty) {
                      if (mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.person_off, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'User not found',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: const Color(0xFF2C2C2E),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                      return;
                    }
                    
                    final recipientUserId = userQuery.docs.first.id;
                    
                    final signalingService = CallSignalingService();
                    await signalingService.sendCallInvitation(
                      recipientUserId: recipientUserId,
                      roomName: widget.roomName,
                      token: '',
                      livekitUrl: widget.livekitUrl,
                      isVideoCall: true,
                    );
                    
                    if (mounted) Navigator.pop(context);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.send, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Invitation sent to $email',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: const Color(0xFF6B7FB8),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) Navigator.pop(context);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Failed to send invitation: $e',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: const Color(0xFFE53E3E),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Add', style: TextStyle(color: Color(0xFF6B7FB8))),
              ),
            ],
          );
        },
      ),
    );
  }
  
  /// Handle incoming call while already in call (call-waiting)
  void _handleIncomingCallWhileInCall() {
    if (_callListener.hasIncomingCall && mounted) {
      setState(() {}); // Trigger rebuild to show banner
    }
  }
  
  /// Handle new chat messages
  void _handleNewChatMessage() {
    final coordinator = context.read<CallFeaturesCoordinator>();
    
    if (coordinator.chatMessages.isNotEmpty) {
      final lastMessage = coordinator.chatMessages.last;
      
      // Check if this is a new message from someone else
      if (!lastMessage.isLocal && lastMessage.id != _lastMessageId) {
        setState(() {
          _lastMessageId = lastMessage.id;
          _hasNewMessage = true;
          
          // Only increment unread count if chat overlay is not visible
          if (!_chatOverlayVisible) {
            _unreadMessageCount++;
            // Auto-show chat overlay for new messages
            _chatOverlayVisible = true;
          }
        });
        
        // Vibrate for new message
        VibrationService.vibrateNewMessage();
        
        debugPrint('📬 New chat message received: ${lastMessage.message}');
      }
    }
  }
  
  /// Accept waiting call and add caller to current group call
  Future<void> _acceptWaitingCall() async {
    final incomingCall = _callListener.currentIncomingCall;
    if (incomingCall == null) return;
    
    try {
      debugPrint('📞 Accepting waiting call from ${incomingCall['callerName']}');
      
      // Generate token for the new participant
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getLiveKitToken');
      
      final response = await callable.call({
        'calleeId': incomingCall['callerId'],
        'roomName': widget.roomName, // Add them to THIS room
        'platform': DeviceModeService.platformLabel(),
      });
      
      final theirToken = response.data['token'] as String;
      await IceServerConfig.updateFromTokenResponse(
        Map<String, dynamic>.from(response.data as Map),
      );
      
      // Accept the invitation - this will signal them to join
      await widget.signalingService.acceptInvitation(incomingCall['id']);
      
      // Add them to the current session
      if (widget.sessionService != null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await widget.sessionService!.startSession(
            widget.roomName, 
            [currentUser.uid, incomingCall['callerId']],
          );
        }
      }
      
      // Clear the call from listener
      _callListener.clearIncomingCall();
      
      if (mounted) {
        setState(() {}); // Hide banner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.person_add, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${incomingCall['callerName']} joined the call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF6B7FB8),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      
      debugPrint('✅ Added ${incomingCall['callerName']} to group call');
    } catch (e) {
      debugPrint('❌ Error accepting waiting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to add ${incomingCall?['callerName'] ?? 'caller'} to call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFE53E3E),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }
  
  /// Decline waiting call
  Future<void> _declineWaitingCall() async {
    final incomingCall = _callListener.currentIncomingCall;
    if (incomingCall == null) return;
    
    try {
      await widget.signalingService.declineInvitation(incomingCall['id']);
      _callListener.clearIncomingCall();
      
      if (mounted) {
        setState(() {}); // Hide banner
      }
      
      debugPrint('❌ Declined waiting call from ${incomingCall['callerName']}');
    } catch (e) {
      debugPrint('❌ Error declining waiting call: $e');
    }
  }
  
  /// Show audio controls panel
  void _showAudioControlsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const AudioControlsPanel(),
    );
  }
  

  
  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.sessionService?.removeListener(_handleSessionEnd);
    _callListener.removeListener(_handleIncomingCallWhileInCall);
    _callListener.stopListening();
    
    // Remove listeners safely
    try {
      final livekit = _livekit;
      if (livekit != null) {
        livekit.removeListener(_handleLiveKitUpdate);
        // Always disconnect to cancel pending connects and release camera.
        livekit.disconnect();
      }
    } catch (e) {
      debugPrint('Error during LiveKit cleanup: $e');
    }
    
    // Remove chat message listener
    _coordinator.removeListener(_handleNewChatMessage);
    
    // Cleanup coordinator (fire and forget)
    _coordinator.cleanup();
    
    // Dispose controllers
    _chatController.dispose();
    _controlsAnimationController.dispose();
    _reactionsAnimationController.dispose();
    _setAndroidCallActive(false);
    AndroidPipService.setAutoPipEnabled(false);
    
    super.dispose();
  }
}
