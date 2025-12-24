import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Call Signaling Service
/// Manages call invitations and signaling via Firestore
/// Mirrors functionality from Android CallSignalingManager.kt
class CallSignalingService {
  CallSignalingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Send a call invitation to a recipient
  /// Returns the invitation ID if successful
  Future<String?> sendCallInvitation({
    required String recipientUserId,
    required String roomName,
    required String token,
    required String livekitUrl,
    bool isVideoCall = true,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ Cannot send invitation: No current user');
        return null;
      }
      
      // Check for recent calls between these users (prevent spam)
      try {
        final tenSecondsAgo = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(seconds: 10))
        );

        // Check outgoing calls (Me -> Them)
        final outgoingCalls = await _firestore
            .collection('call_invitations')
            .where('callerId', isEqualTo: currentUser.uid)
            .where('recipientId', isEqualTo: recipientUserId)
            .where('timestamp', isGreaterThan: tenSecondsAgo)
            .get();

        // Check incoming calls (Them -> Me)
        final incomingCalls = await _firestore
            .collection('call_invitations')
            .where('callerId', isEqualTo: recipientUserId)
            .where('recipientId', isEqualTo: currentUser.uid)
            .where('timestamp', isGreaterThan: tenSecondsAgo)
            .get();
        
        if (outgoingCalls.docs.isNotEmpty || incomingCalls.docs.isNotEmpty) {
          debugPrint('⏰ Recent call found, waiting before allowing new call');
          return null;
        }
      } catch (e) {
        // If index is missing or other error, log it but allow the call to proceed
        debugPrint('⚠️ Error checking recent calls (likely missing index), proceeding anyway: $e');
      }

      // Get caller info from Firestore
      final callerDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final callerData = callerDoc.data();
      final callerName = callerData?['displayName'] ?? 
                        callerData?['name'] ?? 
                        currentUser.email?.split('@')[0] ?? 
                        'Unknown';
      final callerPhotoUrl = callerData?['photoURL'] ?? '';

      debugPrint('📞 Sending call invitation:');
      debugPrint('  From: $callerName (${currentUser.uid})');
      debugPrint('  To: $recipientUserId');
      debugPrint('  Room: $roomName');
      debugPrint('  Type: ${isVideoCall ? "Video" : "Audio"}');

      // Create invitation document
      final invitationRef = await _firestore
          .collection('call_invitations')
          .add({
        'callerId': currentUser.uid,
        'callerName': callerName,
        'callerEmail': currentUser.email,
        'callerPhotoUrl': callerPhotoUrl,
        'recipientId': recipientUserId,
        'roomName': roomName,
        'token': token,
        'livekitUrl': livekitUrl,
        'isVideoCall': isVideoCall,
        'status': 'pending', // pending, accepted, declined, cancelled, timeout
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 60)),
        ),
      });

      debugPrint('✅ Call invitation sent: ${invitationRef.id}');
      return invitationRef.id;
    } catch (e) {
      debugPrint('❌ Error sending call invitation: $e');
      return null;
    }
  }

  /// Cancel a pending call invitation
  Future<void> cancelInvitation(String invitationId) async {
    try {
      await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Call invitation cancelled: $invitationId');
    } catch (e) {
      debugPrint('❌ Error cancelling invitation: $e');
    }
  }

  /// Accept a call invitation
  /// Returns true if accepted successfully, false if expired/cancelled
  Future<bool> acceptInvitation(String invitationId) async {
    try {
      // First, check if the invitation exists and is still valid
      final invitationDoc = await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .get();

      if (!invitationDoc.exists) {
        debugPrint('❌ Invitation does not exist: $invitationId');
        return false;
      }

      final data = invitationDoc.data();
      if (data == null) {
        debugPrint('❌ Invitation has no data: $invitationId');
        return false;
      }

      final status = data['status'] as String?;
      final expiresAt = data['expiresAt'] as Timestamp?;

      // Check if already cancelled or declined
      if (status == 'cancelled' || status == 'declined' || status == 'timeout') {
        debugPrint('❌ Invitation already $status: $invitationId');
        return false;
      }

      // Check if expired
      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        debugPrint('⏰ Invitation expired: $invitationId');
        // Update status to timeout
        await _firestore
            .collection('call_invitations')
            .doc(invitationId)
            .update({'status': 'timeout'});
        return false;
      }

      // Accept the invitation
      await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Call invitation accepted: $invitationId');
      return true;
    } catch (e) {
      debugPrint('❌ Error accepting invitation: $e');
      return false;
    }
  }

  /// Decline a call invitation
  Future<void> declineInvitation(String invitationId) async {
    try {
      await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .update({
        'status': 'declined',
        'declinedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Call invitation declined: $invitationId');
    } catch (e) {
      debugPrint('❌ Error declining invitation: $e');
    }
  }

  /// Get a specific invitation by ID
  Future<Map<String, dynamic>?> getInvitation(String invitationId) async {
    try {
      final doc = await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .get();
      
      if (!doc.exists) return null;
      
      final data = doc.data();
      if (data == null) return null;
      
      return {
        'id': doc.id,
        ...data,
      };
    } catch (e) {
      debugPrint('❌ Error getting invitation: $e');
      return null;
    }
  }

  /// Clean up old invitations (called periodically)
  Future<void> cleanupExpiredInvitations() async {
    try {
      final now = Timestamp.now();
      final expiredQuery = await _firestore
          .collection('call_invitations')
          .where('expiresAt', isLessThan: now)
          .where('status', isEqualTo: 'pending')
          .get();

      final batch = _firestore.batch();
      for (var doc in expiredQuery.docs) {
        batch.update(doc.reference, {
          'status': 'timeout',
          'timeoutAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      debugPrint('✅ Cleaned up ${expiredQuery.docs.length} expired invitations');
    } catch (e) {
      debugPrint('❌ Error cleaning up invitations: $e');
    }
  }

  /// Delete an invitation completely
  Future<void> deleteInvitation(String invitationId) async {
    try {
      await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .delete();
      debugPrint('✅ Call invitation deleted: $invitationId');
    } catch (e) {
      debugPrint('❌ Error deleting invitation: $e');
    }
  }

  /// End an active call and notify all participants
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
        'endedByName': currentUser.displayName ?? currentUser.email ?? 'Unknown',
        'endedAt': FieldValue.serverTimestamp(),
        'status': 'ended',
      };

      // Use set with merge to ensure the document is created if it doesn't exist
      await _firestore
          .collection('activeCallRooms')
          .doc(roomName)
          .set(callEndData, SetOptions(merge: true));

      debugPrint('✅ Call end signal written to activeCallRooms/$roomName');

      // Also write a call history record to `calls` collection so the app
      // can show call history without requiring backend functions.
      try {
        final participants = <String>[currentUser.uid];
        if (otherUserId != null && otherUserId.isNotEmpty && otherUserId != currentUser.uid) {
          participants.add(otherUserId);
        }
        await _firestore.collection('calls').add({
          'roomName': roomName,
          'participants': participants,
          'timestamp': FieldValue.serverTimestamp(),
          'endedAt': FieldValue.serverTimestamp(),
          'duration': 0,
          'endedBy': currentUser.uid,
        });
        debugPrint('✅ Call history record written for room: $roomName');
      } catch (e) {
        debugPrint('⚠️ Failed to write call history record: $e');
      }

      // Notify the other user if we know their ID
      if (otherUserId != null &&
          otherUserId.isNotEmpty &&
          otherUserId != currentUser.uid) {
        final notificationData = {
          'type': 'call_ended',
          'roomName': roomName,
          'endedBy': currentUser.uid,
          'endedByName': currentUser.displayName ?? currentUser.email ?? 'Unknown',
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending', // Will be processed by recipient
        };

        await _firestore
            .collection('users')
            .doc(otherUserId)
            .collection('callSignals')
            .add(notificationData);

        debugPrint('✅ Notified other participant ($otherUserId) via callSignals');
      } else {
        debugPrint('⚠️ No other participant ID provided - only using activeCallRooms');
      }

      debugPrint('✅ Call end signaling completed successfully');
    } catch (e) {
      debugPrint('❌ Error ending call: $e');
    }
  }
}
