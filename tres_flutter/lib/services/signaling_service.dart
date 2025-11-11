import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Call invitation data class
class CallInvitation {
  final String id;
  final String fromUserId;
  final String fromUserName;
  final String roomName;
  final String url;
  final String token;
  final DateTime? timestamp;
  final String? avatarUrl;

  CallInvitation({
    required this.id,
    required this.fromUserId,
    required this.fromUserName,
    required this.roomName,
    required this.url,
    required this.token,
    this.timestamp,
    this.avatarUrl,
  });

  factory CallInvitation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CallInvitation(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      fromUserName: data['fromUserName'] ?? 'Unknown',
      roomName: data['roomName'] ?? '',
      url: data['url'] ?? '',
      token: data['token'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      avatarUrl: data['avatarUrl'],
    );
  }
}

/// Manages call signaling through Firestore
/// Mirrors functionality from Android CallSignalingManager.kt
class SignalingService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<QuerySnapshot>? _callSignalSubscription;
  StreamSubscription<DocumentSnapshot>? _callEndSubscription;

  String? _currentRoomName;
  Function()? _onCallEnded;

  /// Send a call invitation to another user
  /// Returns true if successful
  Future<bool> sendCallInvitation({
    required String recipientUserId,
    required String recipientName,
    required String roomName,
    required String roomUrl,
    required String token,
    String? callerAvatarUrl,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ Cannot send invitation: not authenticated');
        return false;
      }

      final callerName =
          currentUser.displayName ?? currentUser.email ?? 'Unknown';

      final inviteData = {
        'type': 'call_invite',
        'fromUserId': currentUser.uid,
        'fromUserName': callerName,
        'roomName': roomName,
        'url': roomUrl,
        'token': token,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending', // pending, accepted, rejected, missed
        'avatarUrl': callerAvatarUrl ?? '',
      };

      debugPrint(
        '📤 Sending call invitation to $recipientName (ID: $recipientUserId)',
      );
      debugPrint('   Room: $roomName');
      debugPrint('   Caller: $callerName');

      await _firestore
          .collection('users')
          .doc(recipientUserId)
          .collection('callSignals')
          .add(inviteData);

      debugPrint('✅ Call invitation sent successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to send call invitation: $e');
      return false;
    }
  }

  /// Start listening for incoming call invitations
  /// Callback will be triggered when a new call arrives
  void startListeningForCalls(Function(CallInvitation) onCallReceived) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('⚠️ Cannot listen for calls: not authenticated');
      return;
    }

    // Remove any existing listener
    stopListeningForCalls();

    debugPrint(
      '🎧 Starting to listen for call invitations for user: ${currentUser.uid}',
    );
    debugPrint('   Listening path: users/${currentUser.uid}/callSignals');

    _callSignalSubscription = _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('callSignals')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
          (snapshot) {
            debugPrint(
              '🔔 Call signal listener triggered - ${snapshot.docs.length} documents',
            );

            if (snapshot.docs.isEmpty) {
              debugPrint('📭 No pending call signals');
              return;
            }

            debugPrint(
              '📬 Processing ${snapshot.docs.length} call signal documents',
            );

            // Process new call invitations
            for (var docChange in snapshot.docChanges) {
              if (docChange.type == DocumentChangeType.added) {
                final doc = docChange.doc;
                debugPrint('   New call signal document ID: ${doc.id}');

                try {
                  final invitation = CallInvitation.fromFirestore(doc);

                  debugPrint(
                    '📞 Incoming call from: ${invitation.fromUserName}',
                  );
                  debugPrint('   Room: ${invitation.roomName}');

                  // Mark as received (not pending anymore)
                  doc.reference.update({'status': 'ringing'});

                  onCallReceived(invitation);
                } catch (e) {
                  debugPrint('❌ Error processing call invitation: $e');
                }
              }
            }
          },
          onError: (error) {
            debugPrint('❌ Error listening for call signals: $error');
          },
        );
  }

  /// Stop listening for call invitations
  void stopListeningForCalls() {
    _callSignalSubscription?.cancel();
    _callSignalSubscription = null;
    debugPrint('🔇 Stopped listening for call invitations');
  }

  /// Mark a call invitation as accepted
  Future<void> acceptCallInvitation(String invitationId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('callSignals')
          .doc(invitationId)
          .update({'status': 'accepted'});

      debugPrint('✅ Call invitation accepted');
    } catch (e) {
      debugPrint('❌ Error accepting call invitation: $e');
    }
  }

  /// Mark a call invitation as rejected
  Future<void> rejectCallInvitation(String invitationId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('callSignals')
          .doc(invitationId)
          .update({'status': 'rejected'});

      debugPrint('❌ Call invitation rejected');
    } catch (e) {
      debugPrint('❌ Error rejecting call invitation: $e');
    }
  }

  /// Mark a call invitation as missed
  Future<void> missCallInvitation(String invitationId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('callSignals')
          .doc(invitationId)
          .update({'status': 'missed'});

      debugPrint('📵 Call invitation marked as missed');
    } catch (e) {
      debugPrint('❌ Error marking call as missed: $e');
    }
  }

  /// Clean up old call signals (older than 1 hour)
  Future<void> cleanupOldCallSignals() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

      final oldSignals = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('callSignals')
          .where('timestamp', isLessThan: Timestamp.fromDate(oneHourAgo))
          .get();

      for (var doc in oldSignals.docs) {
        await doc.reference.delete();
      }

      if (oldSignals.docs.isNotEmpty) {
        debugPrint('🧹 Cleaned up ${oldSignals.docs.length} old call signals');
      }
    } catch (e) {
      debugPrint('❌ Error cleaning up old call signals: $e');
    }
  }

  /// End an active call and notify the other participant
  Future<void> endCall(String roomName, {String? otherUserId}) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ Cannot end call: not authenticated');
        return;
      }

      debugPrint('🔚 Ending call - Room: $roomName, OtherUser: $otherUserId');

      // Mark the call as ended in a shared location
      final callEndData = {
        'roomName': roomName,
        'endedBy': currentUser.uid,
        'endedByName':
            currentUser.displayName ?? currentUser.email ?? 'Unknown',
        'endedAt': FieldValue.serverTimestamp(),
        'status': 'ended',
      };

      // Use set with merge to ensure the document is created if it doesn't exist
      await _firestore
          .collection('activeCallRooms')
          .doc(roomName)
          .set(callEndData, SetOptions(merge: true));

      debugPrint('✅ Call end signal written to activeCallRooms/$roomName');

      // Notify the other user if we know their ID
      if (otherUserId != null &&
          otherUserId.isNotEmpty &&
          otherUserId != currentUser.uid) {
        final notificationData = {
          'type': 'call_ended',
          'roomName': roomName,
          'endedBy': currentUser.uid,
          'endedByName':
              currentUser.displayName ?? currentUser.email ?? 'Unknown',
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending', // Will be processed by recipient
        };

        await _firestore
            .collection('users')
            .doc(otherUserId)
            .collection('callSignals')
            .add(notificationData);

        debugPrint(
          '✅ Notified other participant ($otherUserId) via callSignals',
        );
      } else {
        debugPrint(
          '⚠️ No other participant ID provided - only using activeCallRooms',
        );
      }

      debugPrint('✅ Call end signaling completed successfully');
    } catch (e) {
      debugPrint('❌ Error ending call: $e');
    }
  }

  /// Listen for call end signals in a specific room
  /// Callback will be triggered when the other participant ends the call
  void listenForCallEnd(String roomName, Function() onCallEnded) {
    final currentUser = _auth.currentUser;
    final currentUserId = currentUser?.uid ?? '';

    debugPrint('🎧 Setting up call end listener for room: $roomName');
    debugPrint('   Current user: $currentUserId');

    // Remove existing listener if any
    _callEndSubscription?.cancel();

    _currentRoomName = roomName;
    _onCallEnded = onCallEnded;

    _callEndSubscription = _firestore
        .collection('activeCallRooms')
        .doc(roomName)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists) {
              final data = snapshot.data();
              final status = data?['status'];
              final endedBy = data?['endedBy'] ?? '';
              final endedByName = data?['endedByName'] ?? 'Other participant';

              debugPrint(
                '🔔 activeCallRooms/$roomName updated - status: $status, endedBy: $endedBy',
              );

              if (status == 'ended') {
                // Only trigger if ended by someone else
                if (endedBy.isNotEmpty && endedBy != currentUserId) {
                  debugPrint('🔚 Call ended by $endedByName ($endedBy)');
                  onCallEnded();
                } else {
                  debugPrint('ℹ️ Call ended by self - ignoring');
                }
              }
            } else {
              debugPrint('📭 activeCallRooms/$roomName does not exist yet');
            }
          },
          onError: (error) {
            debugPrint('❌ Error listening for call end: $error');
          },
        );
  }

  /// Stop listening for call end signals
  void stopListeningForCallEnd() {
    _callEndSubscription?.cancel();
    _callEndSubscription = null;
    _currentRoomName = null;
    _onCallEnded = null;
    debugPrint('🔇 Stopped listening for call end');
  }

  @override
  void dispose() {
    stopListeningForCalls();
    stopListeningForCallEnd();
    super.dispose();
  }
}
