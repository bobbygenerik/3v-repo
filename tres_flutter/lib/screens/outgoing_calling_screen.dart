import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/call_signaling_service.dart';

/// Full-screen page shown while waiting for recipient to accept an outgoing call.
class OutgoingCallingScreen extends StatefulWidget {
  final String invitationId;
  final String recipientEmail;
  final CallSignalingService signalingService;

  const OutgoingCallingScreen({
    super.key,
    required this.invitationId,
    required this.recipientEmail,
    required this.signalingService,
  });

  @override
  State<OutgoingCallingScreen> createState() => _OutgoingCallingScreenState();
}

class _OutgoingCallingScreenState extends State<OutgoingCallingScreen> {
  late StreamSubscription<DocumentSnapshot> _invitationSubscription;
  Timer? _timeoutTimer;
  bool _completed = false;

  void _complete(bool accepted) {
    if (_completed || !mounted) return;
    _completed = true;
    Navigator.of(context).pop(accepted);
  }

  @override
  void initState() {
    super.initState();
    _listenToInvitationStatus();
  }

  void _listenToInvitationStatus() {
    _invitationSubscription = FirebaseFirestore.instance
        .collection('call_invitations')
        .doc(widget.invitationId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;
      debugPrint('📞 Invitation status: $status');

      if (status == 'accepted') {
        _complete(true);
      } else if (status == 'declined' ||
          status == 'timeout' ||
          status == 'cancelled') {
        _complete(false);
      }
    });

    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && !_completed) {
        widget.signalingService.cancelInvitation(widget.invitationId);
        _complete(false);
      }
    });
  }

  @override
  void dispose() {
    _invitationSubscription.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        widget.signalingService.cancelInvitation(widget.invitationId);
        _complete(false);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7AA2FF), Color(0xFF58D8C0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7AA2FF).withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      (widget.recipientEmail.isNotEmpty
                              ? widget.recipientEmail[0]
                              : '?')
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.recipientEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Calling...',
                  style: TextStyle(
                    color: Color(0xB3DCE4FF),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Semantics(
                  label: 'Waiting for answer...',
                  child: const CircularProgressIndicator(
                    color: Color(0xFF7AA2FF),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Waiting for the recipient to answer',
                  style: TextStyle(
                    color: Color(0x99DCE4FF),
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 76,
                  height: 76,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.signalingService.cancelInvitation(widget.invitationId);
                      _complete(false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE14D5A),
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 30),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xD9FFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
