import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/call_signaling_service.dart';
import '../services/call_session_service.dart';
import '../services/device_mode_service.dart';
import '../services/vibration_service.dart';
import '../services/ice_server_config.dart';
import 'call_screen.dart';
import 'dart:ui' as ui;

class IncomingCallScreen extends StatefulWidget {
  final String invitationId;
  final String callerName;
  final String callerId;
  final String roomName;
  final String token;
  final String livekitUrl;
  final bool isVideoCall;
  final String? callerPhotoUrl;
  /// When true the call uses a direct P2P connection — no SFU token needed.
  final bool isP2PCall;

  const IncomingCallScreen({
    super.key,
    required this.invitationId,
    required this.callerName,
    required this.callerId,
    required this.roomName,
    this.token = '',
    this.livekitUrl = '',
    this.isVideoCall = true,
    this.callerPhotoUrl,
    this.isP2PCall = false,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final CallSignalingService _signalingService = CallSignalingService();
  bool _isAccepting = false;
  bool _showActions = true;
  StreamSubscription<DocumentSnapshot>? _invitationSubscription;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    
    // Start vibration for incoming call
    VibrationService.vibrateIncomingCall();
    _listenForCancellation();
    
    // Setup pulse animation for avatar
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Auto-timeout after 60 seconds
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) {
        _timeoutCall();
      }
    });
  }

  void _listenForCancellation() {
    _invitationSubscription = FirebaseFirestore.instance
        .collection('call_invitations')
        .doc(widget.invitationId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || _dismissed) return;
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;
      final status = data['status'] as String?;
      if (status == null) return;
      if (status == 'cancelled' || status == 'timeout' || status == 'declined') {
        _dismissed = true;
        VibrationService.stopVibration();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Call ${status == 'cancelled' ? 'cancelled' : status}')),
        );
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    // Stop vibration when screen is disposed
    VibrationService.stopVibration();
    _invitationSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_isAccepting) return;
    VibrationService.stopVibration();
    setState(() => _isAccepting = true);

    try {
      final isValid = await _signalingService.acceptInvitation(widget.invitationId);
      if (!isValid) {
        debugPrint('❌ Cannot accept - invitation expired or cancelled');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This call has expired or been cancelled'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      final functions = FirebaseFunctions.instance;
      final sessionService = CallSessionService();
      final currentUser = FirebaseAuth.instance.currentUser;

      if (widget.isP2PCall) {
        // ── P2P path: fetch ICE servers, no LiveKit token needed ─────────────
        debugPrint('🔗 Accepting P2P call — fetching ICE servers');
        final iceResponse = await functions
            .httpsCallable('getIceServers')
            .call({})
            .timeout(const Duration(seconds: 10), onTimeout: () {
          throw Exception('ICE server request timed out');
        });
        await IceServerConfig.updateFromTokenResponse(
          Map<String, dynamic>.from(iceResponse.data as Map),
        );

        if (currentUser != null) {
          try {
            await sessionService.startSession(
                widget.roomName, [currentUser.uid, widget.callerId]);
          } catch (e) {
            debugPrint('❌ Failed to start session: $e');
          }
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              roomName: widget.roomName,
              signalingService: _signalingService,
              sessionService: sessionService,
              isP2PCall: true,
              remoteUserId: widget.callerId,
              remoteUserName: widget.callerName,
              isInitiator: false, // callee
            ),
          ),
        );
      } else {
        // ── LiveKit SFU path (group calls) ───────────────────────────────────
        debugPrint('🎫 Generating LiveKit token for recipient');
        final response = await functions
            .httpsCallable('getLiveKitToken')
            .call({
          'calleeId': widget.callerId,
          'roomName': widget.roomName,
          'platform': DeviceModeService.platformLabel(),
        }).timeout(const Duration(seconds: 10), onTimeout: () {
          throw Exception('Token request timed out');
        });

        final myToken = response.data['token'] as String;
        await IceServerConfig.updateFromTokenResponse(
          Map<String, dynamic>.from(response.data as Map),
        );

        if (currentUser != null) {
          try {
            await sessionService.startSession(
                widget.roomName, [currentUser.uid, widget.callerId]);
          } catch (e) {
            debugPrint('❌ Failed to start session: $e');
          }
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => CallScreen(
              roomName: widget.roomName,
              token: myToken,
              livekitUrl: widget.livekitUrl,
              signalingService: _signalingService,
              sessionService: sessionService,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error accepting call: $e');
      if (mounted) {
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept call: $e')),
        );
      }
    }
  }

  Future<void> _declineCall() async {
    // Stop vibration when call is declined
    VibrationService.stopVibration();
    
    try {
      // Mark invitation as declined in Firestore
      await _signalingService.declineInvitation(widget.invitationId);
      
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Error declining call: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _timeoutCall() {
    if (mounted) {
      debugPrint('⏰ Call timed out');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Respect system bottom inset (navigation bar / gesture area) explicitly
    final double bottomInset = MediaQuery.of(context).viewPadding.bottom;
    // Pixel distance to move the action row offscreen; includes bottom inset
    final double offscreenDy = 220.0 + bottomInset;
    return Scaffold(
      body: Stack(
        children: [
          // Blurred background
          Container(
            color: const Color(0xFF1C1C1E),
          ),
          if (widget.callerPhotoUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.4,
                child: Image.network(
                  widget.callerPhotoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(),
                ),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),
          SafeArea(
            child: Column(
          children: [
            // Upper area: tappable to toggle action visibility
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  setState(() => _showActions = !_showActions);
                },
                child: Column(
                  children: [
                    const Spacer(flex: 2),
            
                        // Caller Avatar with pulse animation
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.5),
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 76,
                  backgroundColor: AppColors.primaryBlue,
                  backgroundImage: widget.callerPhotoUrl != null
                      ? NetworkImage(widget.callerPhotoUrl!)
                      : null,
                  child: widget.callerPhotoUrl == null
                      ? Text(
                          widget.callerName.isNotEmpty
                              ? widget.callerName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 70,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Caller Name
            Text(
              widget.callerName,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.textWhite,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            // Call Type
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isVideoCall ? Icons.videocam : Icons.phone,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isVideoCall
                      ? 'Incoming Video Call'
                      : 'Incoming Voice Call',
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
                    const Spacer(flex: 3),
                  ],
                ),
              ),
            ),

            // Call Actions
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              transform: Matrix4.translationValues(0, _showActions ? 0 : offscreenDy, 0),
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.fromLTRB(40, 0, 40, 40 + bottomInset),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, // Center buttons
                  children: [
                    // Decline Button
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          button: true,
                          label: 'Decline call',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _declineCall,
                              customBorder: const CircleBorder(),
                              splashColor: Colors.white.withOpacity(0.3),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.call_end,
                                  size: 32,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(width: 48), // Close proximity as requested

                    // Accept Button
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          button: true,
                          label: _isAccepting
                              ? 'Connecting call...'
                              : 'Accept call',
                          enabled: !_isAccepting,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _isAccepting ? null : _acceptCall,
                              customBorder: const CircleBorder(),
                              splashColor: Colors.white.withOpacity(0.3),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: _isAccepting
                                      ? Colors.grey.shade700
                                      : Colors.green.shade600,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _isAccepting
                                    ? const Center(
                                        child: SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 3,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        widget.isVideoCall
                                            ? Icons.videocam
                                            : Icons.phone,
                                        size: 32,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isAccepting ? 'Connecting...' : 'Accept',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
      ],
      ),
    );
  }
}
