import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../config/app_theme.dart';
import '../services/call_signaling_service.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final String invitationId;
  final String callerName;
  final String callerId;
  final String roomName;
  final String token;
  final String livekitUrl;
  final bool isVideoCall;
  final String? callerPhotoUrl;

  const IncomingCallScreen({
    super.key,
    required this.invitationId,
    required this.callerName,
    required this.callerId,
    required this.roomName,
    required this.token,
    required this.livekitUrl,
    this.isVideoCall = true,
    this.callerPhotoUrl,
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

  @override
  void initState() {
    super.initState();
    
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

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_isAccepting) return;
    
    setState(() => _isAccepting = true);

    try {
      // Generate our own LiveKit token for this room
      debugPrint('🎫 Generating LiveKit token for recipient');
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getLiveKitToken');
      
      final response = await callable.call({
        'calleeId': widget.callerId, // Not actually used for token generation, just for logging
        'roomName': widget.roomName,
      });

      final myToken = response.data['token'] as String;
      debugPrint('✅ Got recipient token');
      
      // Mark invitation as accepted in Firestore
      await _signalingService.acceptInvitation(widget.invitationId);

      if (!mounted) return;

      // Navigate to call screen with OUR token (not the caller's token)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            roomName: widget.roomName,
            token: myToken, // Use our own generated token
            livekitUrl: widget.livekitUrl,
          ),
        ),
      );
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
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
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
            
            // Call Actions
            Padding(
              padding: const EdgeInsets.all(40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline Button
                  Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _declineCall,
                          customBorder: const CircleBorder(),
                          splashColor: Colors.white.withOpacity(0.3),
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.shade900.withOpacity(0.5),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.call_end,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Decline',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  
                  // Accept Button
                  Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isAccepting ? null : _acceptCall,
                          customBorder: const CircleBorder(),
                          splashColor: Colors.white.withOpacity(0.3),
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: _isAccepting 
                                  ? Colors.grey.shade600 
                                  : Colors.green.shade600,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _isAccepting
                                      ? Colors.grey.shade900.withOpacity(0.5)
                                      : Colors.green.shade900.withOpacity(0.5),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: _isAccepting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      strokeWidth: 3,
                                    ),
                                  )
                                : Icon(
                                    widget.isVideoCall ? Icons.videocam : Icons.phone,
                                    size: 34,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isAccepting ? 'Connecting...' : 'Accept',
                        style: const TextStyle(
                          color: AppColors.textLight,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
