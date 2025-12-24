import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Call Session Service
/// Manages active call sessions and ensures proper cleanup
class CallSessionService extends ChangeNotifier {
  CallSessionService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  
  String? _currentSessionId;
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;
  Timer? _heartbeatTimer;
  
  String? get currentSessionId => _currentSessionId;
  bool get isInCall => _currentSessionId != null;
  
  /// Start a call session
  Future<void> startSession(String roomName, List<String> participants) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;
      // First, check if a session already exists for this room (join if present)
      final existingQuery = await _firestore
          .collection('call_sessions')
          .where('roomName', isEqualTo: roomName)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        final doc = existingQuery.docs.first;
        final data = doc.data();
        debugPrint('🔁 Joining existing call session: ${doc.id} for room $roomName');

        // Ensure participants array includes current user and any passed participants
        await _firestore.collection('call_sessions').doc(doc.id).update({
          'participants': FieldValue.arrayUnion([...participants, currentUser.uid]),
          'participantStatus.${currentUser.uid}': 'connected',
          'lastHeartbeat': FieldValue.serverTimestamp(),
        });

        _currentSessionId = doc.id;
        _sessionSubscription = _firestore.collection('call_sessions').doc(_currentSessionId).snapshots().listen(_handleSessionUpdate);
        _startHeartbeat();
        debugPrint('📞 Joined call session: $_currentSessionId');
        notifyListeners();
        return;
      }

      // No existing session found - create a new one
      // Ensure the current user is included in the participants list
      final createdParticipants = <String>{...participants, currentUser.uid}.toList();

      final sessionRef = await _firestore.collection('call_sessions').add({
        'roomName': roomName,
        'participants': createdParticipants,
        'createdBy': currentUser.uid,
        'status': 'active',
        'startTime': FieldValue.serverTimestamp(),
        'lastHeartbeat': FieldValue.serverTimestamp(),
        'participantStatus': {
          for (String uid in createdParticipants) uid: 'connected'
        },
      });

      _currentSessionId = sessionRef.id;

      // Listen for session changes
      _sessionSubscription = sessionRef.snapshots().listen(_handleSessionUpdate);

      // Start heartbeat
      _startHeartbeat();

      debugPrint('📞 Call session started: $_currentSessionId');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error starting session: $e');
    }
  }
  
  /// End the call session
  Future<void> endSession() async {
    if (_currentSessionId == null) return;
    
    try {
      // Mark session as ended
      await _firestore.collection('call_sessions').doc(_currentSessionId).update({
        'status': 'ended',
        'endTime': FieldValue.serverTimestamp(),
        'endedBy': _auth.currentUser?.uid,
      });
      
      debugPrint('📞 Call session ended: $_currentSessionId');
      _cleanup();
    } catch (e) {
      debugPrint('❌ Error ending session: $e');
      _cleanup(); // Still cleanup locally even if Firestore update fails
    }
  }
  
  /// Handle session updates
  void _handleSessionUpdate(DocumentSnapshot snapshot) {
    if (!snapshot.exists) {
      debugPrint('📞 Call session document deleted');
      _cleanup();
      notifyListeners();
      return;
    }
    
    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) return;
    
    final status = data['status'] as String?;
    final endedBy = data['endedBy'] as String?;
    final currentUserId = _auth.currentUser?.uid;
    
    // If session ended by someone else, cleanup locally
    if (status == 'ended' && endedBy != currentUserId) {
      debugPrint('📞 Call ended by another participant: $endedBy');
      _cleanup();
      // Notify UI to exit call screen
      notifyListeners();
    }
  }
  
  /// Start heartbeat to keep session alive
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendHeartbeat();
    });
  }
  
  /// Send heartbeat
  Future<void> _sendHeartbeat() async {
    if (_currentSessionId == null) return;
    
    try {
      await _firestore.collection('call_sessions').doc(_currentSessionId).update({
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Heartbeat failed: $e');
    }
  }
  
  /// Cleanup session
  void _cleanup() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _currentSessionId = null;
    notifyListeners();
  }
  
  @override
  void dispose() {
    endSession();
    super.dispose();
  }
}
