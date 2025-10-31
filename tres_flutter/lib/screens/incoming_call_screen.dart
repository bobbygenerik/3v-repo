import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callerName;
  final String callerId;
  final String roomName;
  final bool isVideoCall;
  final String? callerPhotoUrl;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.callerId,
    required this.roomName,
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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _acceptCall() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          roomName: widget.roomName,
          token: '', // TODO: Get token from backend
          livekitUrl: '', // TODO: Get from Environment
        ),
      ),
    );
  }

  void _declineCall() {
    // TODO: Send decline signal to caller
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            
            // Caller Avatar with Pulse Animation
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryBlue,
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 73,
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
                            fontSize: 64,
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
            
            // Room Name (if different from caller)
            if (widget.roomName != widget.callerName)
              Text(
                'Room: ${widget.roomName}',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.gray,
                ),
              ),
            
            const Spacer(flex: 3),
            
            // Call Actions
            Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline Button
                  Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'decline',
                        onPressed: _declineCall,
                        backgroundColor: Colors.red,
                        child: const Icon(
                          Icons.call_end,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Decline',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  
                  // Accept Button
                  Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'accept',
                        onPressed: _acceptCall,
                        backgroundColor: Colors.green,
                        child: Icon(
                          widget.isVideoCall ? Icons.videocam : Icons.phone,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Accept',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontSize: 14,
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
