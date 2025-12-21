import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Call Listener Service
/// Listens for incoming call invitations from Firestore
/// Mirrors functionality from Android MyFirebaseMessagingService.kt
class CallListenerService extends ChangeNotifier {
  CallListenerService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  
  StreamSubscription<QuerySnapshot>? _invitationSubscription;
  Map<String, dynamic>? _currentIncomingCall;
  
  Map<String, dynamic>? get currentIncomingCall => _currentIncomingCall;
  bool get hasIncomingCall => _currentIncomingCall != null;

  /// Start listening for incoming call invitations
  void startListening() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('⚠️ Cannot start listening: No current user');
      return;
    }

    debugPrint('👂 Starting to listen for incoming calls for ${currentUser.uid}');

    // Listen to call_invitations where recipientId matches current user
    // Note: Filtering for 'pending' status in memory to avoid needing composite index
    // while Firestore index is building
    _invitationSubscription = _firestore
        .collection('call_invitations')
        .where('recipientId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen(
          _handleInvitationSnapshot,
          onError: (error) {
            debugPrint('❌ Error listening for invitations: $error');
          },
        );
  }

  /// Stop listening for invitations
  void stopListening() {
    debugPrint('🛑 Stopping call listener');
    _invitationSubscription?.cancel();
    _invitationSubscription = null;
    _clearCurrentCall();
  }

  /// Handle incoming invitation snapshot
  void _handleInvitationSnapshot(QuerySnapshot snapshot) {
    if (snapshot.docs.isEmpty) {
      // No pending invitations
      if (_currentIncomingCall != null) {
        debugPrint('📭 No more pending invitations');
        _clearCurrentCall();
      }
      return;
    }

    // Filter for pending status and get the most recent invitation
    var pendingDocs = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['status'] == 'pending';
    }).toList();
    
    if (pendingDocs.isEmpty) {
      if (_currentIncomingCall != null) {
        debugPrint('📭 No pending invitations');
        _clearCurrentCall();
      }
      return;
    }
    
    // Sort by timestamp manually
    if (pendingDocs.length > 1) {
      pendingDocs.sort((a, b) {
        final aTime = (a.data() as Map)['timestamp'] as Timestamp?;
        final bTime = (b.data() as Map)['timestamp'] as Timestamp?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime); // Descending order
      });
    }
    
    final doc = pendingDocs.first;
    final data = doc.data() as Map<String, dynamic>;
    
    // Check if invitation has expired
    final expiresAt = data['expiresAt'] as Timestamp?;
    if (expiresAt != null && 
        expiresAt.toDate().isBefore(DateTime.now())) {
      debugPrint('⏰ Invitation expired: ${doc.id}');
      _markAsTimeout(doc.id);
      return;
    }

    // Check if this is a different call than current
    if (_currentIncomingCall?['id'] != doc.id) {
      final callerName = data['callerName'] ?? 'Unknown';
      final isVideoCall = data['isVideoCall'] ?? true;
      
      debugPrint('📞 Incoming ${isVideoCall ? "video" : "audio"} call from $callerName');
      
      _currentIncomingCall = {
        'id': doc.id,
        'callerId': data['callerId'],
        'callerName': callerName,
        'callerEmail': data['callerEmail'],
        'callerPhotoUrl': data['callerPhotoUrl'],
        'roomName': data['roomName'],
        'token': data['token'],
        'livekitUrl': data['livekitUrl'],
        'isVideoCall': isVideoCall,
        'timestamp': data['timestamp'],
      };
      
      notifyListeners();
    }
  }

  /// Mark an invitation as timed out
  Future<void> _markAsTimeout(String invitationId) async {
    try {
      await _firestore
          .collection('call_invitations')
          .doc(invitationId)
          .update({
        'status': 'timeout',
        'timeoutAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Error marking timeout: $e');
    }
  }

  /// Clear current incoming call
  void _clearCurrentCall() {
    if (_currentIncomingCall != null) {
      _currentIncomingCall = null;
      notifyListeners();
    }
  }

  /// Clear current call after user action
  void clearIncomingCall() {
    _clearCurrentCall();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
