import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Call Signaling Service
/// Manages call invitations and signaling via Firestore
/// Mirrors functionality from Android CallSignalingManager.kt
class CallSignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Send a call invitation to a recipient
  /// Returns the invitation ID if successful
  Future<String?> sendCallInvitation({
    required String recipientUserId,
    required String roomName,
    required String token,
    required String livekitUrl,
    bool isVideoCall = true,
  }) async {
    debugPrint('📤 Starting sendCallInvitation...');
    debugPrint('  recipientUserId: $recipientUserId');
    debugPrint('  roomName: $roomName');
    debugPrint('  livekitUrl: $livekitUrl');
    debugPrint('  isVideoCall: $isVideoCall');
    
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ Cannot send invitation: No current user');
        return null;
      }
      
      debugPrint('✅ Current user: ${currentUser.uid}');
      
      // Check for recent calls between these users (prevent spam)
      debugPrint('🔍 Checking for recent calls...');
      try {
        final recentCalls = await _firestore
            .collection('call_invitations')
            .where('callerId', whereIn: [currentUser.uid, recipientUserId])
            .where('recipientId', whereIn: [currentUser.uid, recipientUserId])
            .where('timestamp', isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(seconds: 10))
            ))
            .get();
        
        debugPrint('🔍 Recent calls found: ${recentCalls.docs.length}');
        if (recentCalls.docs.isNotEmpty) {
          debugPrint('⏰ Recent call found, waiting before allowing new call');
          return null;
        }
      } catch (recentCallError) {
        debugPrint('⚠️ Error checking recent calls (continuing anyway): $recentCallError');
      }

      // Get caller info from Firestore
      debugPrint('📝 Getting caller info...');
      final callerDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!callerDoc.exists) {
        debugPrint('❌ Caller document does not exist');
        return null;
      }

      final callerData = callerDoc.data();
      final callerName = callerData?['displayName'] ?? 
                        callerData?['name'] ?? 
                        currentUser.email?.split('@')[0] ?? 
                        'Unknown';
      final callerPhotoUrl = callerData?['photoURL'] ?? '';
      
      debugPrint('✅ Caller info: $callerName');

      debugPrint('📞 Sending call invitation:');
      debugPrint('  From: $callerName (${currentUser.uid})');
      debugPrint('  To: $recipientUserId');
      debugPrint('  Room: $roomName');
      debugPrint('  Type: ${isVideoCall ? "Video" : "Audio"}');

      // Create invitation document in the correct collection for Firebase Function
      debugPrint('📝 Creating call signal document...');
      final callSignalData = {
        'type': 'call_invite',
        'status': 'pending',
        'fromUserId': currentUser.uid,
        'fromUserName': callerName,
        'fromUserEmail': currentUser.email,
        'fromUserPhotoUrl': callerPhotoUrl,
        'roomName': roomName,
        'token': token,
        'url': livekitUrl,
        'isVideoCall': isVideoCall,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 60)),
        ),
      };
      
      final invitationRef = await _firestore
          .collection('users')
          .doc(recipientUserId)
          .collection('callSignals')
          .add(callSignalData);
      
      debugPrint('✅ Call signal created: ${invitationRef.id}');
      
      // Also create in call_invitations for tracking
      debugPrint('📝 Creating call invitation document...');
      await _firestore
          .collection('call_invitations')
          .doc(invitationRef.id)
          .set({
        'callerId': currentUser.uid,
        'callerName': callerName,
        'callerEmail': currentUser.email,
        'callerPhotoUrl': callerPhotoUrl,
        'recipientId': recipientUserId,
        'roomName': roomName,
        'token': token,
        'livekitUrl': livekitUrl,
        'isVideoCall': isVideoCall,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 60)),
        ),
      });
      
      debugPrint('✅ Call invitation created: ${invitationRef.id}');

      debugPrint('✅ Call invitation sent: ${invitationRef.id}');
      return invitationRef.id;
    } catch (e, stackTrace) {
      debugPrint('❌ Error sending call invitation: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return null;
    }
  }

  /// Cancel a pending call invitation
  Future<void> cancelInvitation(String invitationId) async {
    try {
      debugPrint('🚫 Cancelling invitation: $invitationId');
      
      // Update both collections atomically
      final batch = _firestore.batch();
      
      // Update call_invitations
      final invitationRef = _firestore.collection('call_invitations').doc(invitationId);
      batch.update(invitationRef, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      
      // Find and update in callSignals collection
      final callSignalsQuery = await _firestore
          .collectionGroup('callSignals')
          .where(FieldPath.documentId, isEqualTo: invitationId)
          .get();
      
      for (var doc in callSignalsQuery.docs) {
        batch.update(doc.reference, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      debugPrint('✅ Call invitation cancelled: $invitationId');
    } catch (e) {
      debugPrint('❌ Error cancelling invitation: $e');
    }
  }

  /// Accept a call invitation
  Future<void> acceptInvitation(String invitationId) async {
    try {
      // Update both collections
      await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      
      // Find and update in callSignals collection
      final callSignalsQuery = await _firestore
          .collectionGroup('callSignals')
          .where(FieldPath.documentId, isEqualTo: invitationId)
          .get();
      
      for (var doc in callSignalsQuery.docs) {
        await doc.reference.update({
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      }
      
      debugPrint('✅ Call invitation accepted: $invitationId');
    } catch (e) {
      debugPrint('❌ Error accepting invitation: $e');
    }
  }

  /// Decline a call invitation
  Future<void> declineInvitation(String invitationId) async {
    try {
      // Update both collections
      await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .update({
        'status': 'declined',
        'declinedAt': FieldValue.serverTimestamp(),
      });
      
      // Find and update in callSignals collection
      final callSignalsQuery = await _firestore
          .collectionGroup('callSignals')
          .where(FieldPath.documentId, isEqualTo: invitationId)
          .get();
      
      for (var doc in callSignalsQuery.docs) {
        await doc.reference.update({
          'status': 'declined',
          'declinedAt': FieldValue.serverTimestamp(),
        });
      }
      
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
}
