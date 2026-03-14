import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ice_server_config.dart';

/// Direct peer-to-peer WebRTC call, bypassing the LiveKit SFU entirely.
///
/// Media flows device → device (via STUN/TURN for NAT traversal).
/// Firestore is used as the signaling channel — SDP offers/answers and ICE
/// candidates are written to `p2p_calls/{roomId}` and its subcollections.
class P2PCallService extends ChangeNotifier {
  P2PCallService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // WebRTC primitives
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Renderers exposed to the UI
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  // State
  bool _isConnected = false;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isReconnecting = false;
  bool _disposed = false;
  String? _errorMessage;

  // Signaling subscriptions
  StreamSubscription<DocumentSnapshot>? _signalingDocSub;
  StreamSubscription<QuerySnapshot>? _remoteIceSub;

  // Call parameters
  String? _roomId;
  String? _localUserId;
  String? _remoteUserId;

  // Getters
  bool get isConnected => _isConnected;
  bool get isMicMuted => _isMicMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isReconnecting => _isReconnecting;
  bool get hasRemoteVideo => _remoteStream != null;
  String? get errorMessage => _errorMessage;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  // ─── Public API ──────────────────────────────────────────────────────────────

  /// Caller side: creates the offer and waits for the callee's answer.
  Future<bool> connectAsInitiator({
    required String roomId,
    required String remoteUserId,
  }) async {
    _roomId = roomId;
    _remoteUserId = remoteUserId;
    _localUserId = _auth.currentUser?.uid;
    if (_localUserId == null) return false;

    try {
      await _setup();
      _listenForRemoteIceCandidates();

      // Create offer and publish to Firestore.
      final offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      await _signalingDoc.set({
        'offer': {'type': offer.type, 'sdp': offer.sdp},
        'initiatorId': _localUserId,
        'remoteId': remoteUserId,
        'isP2P': true,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'offering',
      });

      return await _waitForAnswer();
    } catch (e) {
      _errorMessage = 'P2P connection failed: $e';
      debugPrint('❌ P2P: initiator error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Callee side: reads the offer and sends back an answer.
  Future<bool> connectAsReceiver({
    required String roomId,
    required String initiatorUserId,
  }) async {
    _roomId = roomId;
    _remoteUserId = initiatorUserId;
    _localUserId = _auth.currentUser?.uid;
    if (_localUserId == null) return false;

    try {
      await _setup();
      _listenForRemoteIceCandidates();
      return await _waitForOfferAndAnswer();
    } catch (e) {
      _errorMessage = 'P2P connection failed: $e';
      debugPrint('❌ P2PCallService receiver error: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleMicrophone() async {
    final tracks = _localStream?.getAudioTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !t.enabled;
    }
    _isMicMuted = tracks.isNotEmpty && !tracks.first.enabled;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !t.enabled;
    }
    _isCameraOff = tracks.isNotEmpty && !tracks.first.enabled;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _disposed = true;
    _isConnected = false;
    _isReconnecting = false;

    await _signalingDocSub?.cancel();
    await _remoteIceSub?.cancel();

    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _pc?.close();
    _pc = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    await localRenderer.dispose();
    await remoteRenderer.dispose();

    // Mark signaling doc as ended so the other side knows.
    try {
      await _signalingDoc.update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    notifyListeners();
  }

  @override
  void dispose() {
    if (!_disposed) disconnect();
    super.dispose();
  }

  // ─── Private helpers ─────────────────────────────────────────────────────────

  DocumentReference get _signalingDoc =>
      _firestore.collection('p2p_calls').doc(_roomId);

  CollectionReference _iceBucketFor(String userId) =>
      _signalingDoc.collection('ice_$userId');

  Future<void> _setup() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await _captureLocalMedia();
    await _buildPeerConnection();
    await _addLocalTracksToPC();
  }

  Future<void> _captureLocalMedia() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30},
      },
    });
    localRenderer.srcObject = _localStream;
    notifyListeners();
  }

  Future<void> _buildPeerConnection() async {
    final iceServers = _parseIceServers();
    final config = {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'all',
    };

    _pc = await createPeerConnection(config);

    // Trickle-ICE: send each local candidate to Firestore as it arrives.
    _pc!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || _localUserId == null) return;
      await _iceBucketFor(_localUserId!).add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'ts': FieldValue.serverTimestamp(),
      });
    };

    // Incoming remote track → show in remoteRenderer.
    _pc!.onTrack = (event) async {
      debugPrint('📹 P2P: onTrack event: kind=${event.track.kind}, id=${event.track.id}');
      
      // Ensure we have a stream to hold the track
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      } else {
        _remoteStream ??= await createLocalMediaStream('remote');
        await _remoteStream!.addTrack(event.track);
      }

      if (event.track.kind == 'video') {
        debugPrint('📹 P2P: Setting remote video track to renderer: ${event.track.id}');
        // Re-assign srcObject to ensure the renderer picks up the new track
        remoteRenderer.srcObject = _remoteStream;
      } else if (event.track.kind == 'audio') {
        debugPrint('🔊 P2P: Received remote audio track: ${event.track.id}');
      }
      
      // Always notify when a track arrives to ensure UI reacts.
      notifyListeners();
    };

    _pc!.onConnectionState = (state) {
      debugPrint('🔗 P2P Connection State: ${state.toString()}');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          debugPrint('✅ P2P: Fully Connected!');
          _isConnected = true;
          _isReconnecting = false;
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          debugPrint('⏳ P2P: Connecting...');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          debugPrint('⚠️ P2P: Disconnected');
          _isReconnecting = true;
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          debugPrint('❌ P2P: Failed');
          _isReconnecting = true;
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          debugPrint('🔌 P2P: Closed');
          _isConnected = false;
          _isReconnecting = false;
          break;
        default:
          break;
      }
      notifyListeners();
    };
  }

  Future<void> _addLocalTracksToPC() async {
    final tracks = _localStream?.getTracks() ?? [];
    for (final track in tracks) {
      if (track.kind == 'video') {
        // Use addTransceiver for video so we can bake in a 2 Mbps encoding
        // constraint before the SDP offer is created — no post-negotiation
        // setParameters call needed.
        try {
          await _pc!.addTransceiver(
            track: track,
            kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
            init: RTCRtpTransceiverInit(
              direction: TransceiverDirection.SendRecv,
              sendEncodings: [
                RTCRtpEncoding(maxBitrate: 2000000, maxFramerate: 30),
              ],
            ),
          );
        } catch (e) {
          // Fall back to plain addTrack if transceiver API fails.
          debugPrint('⚠️ addTransceiver failed, falling back: $e');
          await _pc!.addTrack(track, _localStream!);
        }
      } else {
        await _pc!.addTrack(track, _localStream!);
      }
    }
  }

  /// Listen for ICE candidates sent by the remote peer.
  void _listenForRemoteIceCandidates() {
    if (_remoteUserId == null) return;
    _remoteIceSub = _iceBucketFor(_remoteUserId!)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final d = change.doc.data() as Map<String, dynamic>;
        final candidate = RTCIceCandidate(
          d['candidate'] as String,
          d['sdpMid'] as String?,
          d['sdpMLineIndex'] as int?,
        );
        _pc?.addCandidate(candidate).catchError((e) {
          debugPrint('⚠️ Failed to add ICE candidate: $e');
        });
      }
    });
  }

  /// Initiator: wait up to 30 s for the callee to write an answer.
  Future<bool> _waitForAnswer({Duration timeout = const Duration(seconds: 30)}) async {
    final completer = Completer<bool>();
    
    // Start persistent monitor for "ended" etc.
    _startStatusMonitor();

    _signalingDocSub = _signalingDoc.snapshots().listen((snap) async {
      if (!snap.exists || completer.isCompleted) return;
      final d = snap.data() as Map<String, dynamic>;

      final answer = d['answer'] as Map<String, dynamic>?;
      if (answer == null) return;
      try {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
        );
        completer.complete(true);
      } catch (e) {
        debugPrint('❌ P2P: error setting remote description: $e');
        completer.complete(false);
      }
    });

    return Future.any([completer.future, Future.delayed(timeout, () => false)]);
  }

  /// Callee: wait for an offer to appear, then create and publish an answer.
  Future<bool> _waitForOfferAndAnswer({Duration timeout = const Duration(seconds: 30)}) async {
    final completer = Completer<bool>();
    bool answering = false; // guard against re-entrant snapshot callbacks
    
    // Start persistent monitor for "ended" etc.
    _startStatusMonitor();

    _signalingDocSub = _signalingDoc.snapshots().listen((snap) async {
      if (!snap.exists || completer.isCompleted || answering) return;
      final d = snap.data() as Map<String, dynamic>;

      final offer = d['offer'] as Map<String, dynamic>?;
      if (offer == null) return;
      answering = true; // prevent duplicate answer attempts
      try {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
        );
        final answer = await _pc!.createAnswer({});
        await _pc!.setLocalDescription(answer);
        await _signalingDoc.update({
          'answer': {'type': answer.type, 'sdp': answer.sdp},
          'status': 'answered',
        });
        if (!completer.isCompleted) completer.complete(true);
      } catch (e) {
        debugPrint('❌ Error creating P2P answer: $e');
        if (!completer.isCompleted) completer.complete(false);
        answering = false; // allow retry on transient error
      }
    });

    return Future.any([completer.future, Future.delayed(timeout, () => false)]);
  }

  /// Persistent monitor for call status changes (e.g. remote hang-up)
  void _startStatusMonitor() {
    _signalingDoc.snapshots().listen((snap) {
      if (!snap.exists || _disposed) return;
      final d = snap.data() as Map<String, dynamic>;
      
      if (d['status'] == 'ended') {
        debugPrint('📞 P2P: Remote hang-up detected via signaling status');
        disconnect();
      }
    });
  }

  /// Parse ICE servers from the cached config, falling back to Google STUN.
  /// TURN entries with empty credentials are stripped — they cause the native
  /// Android RTCPeerConnection to be created with a null handle.
  List<Map<String, dynamic>> _parseIceServers() {
    final json = IceServerConfig.iceServersJson.trim();
    if (json.isNotEmpty) {
      try {
        final all = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
        final valid = all.where((entry) {
          final urls = entry['urls'];
          final isTurn = urls is String
              ? urls.contains('turn:')
              : (urls as List?)?.any((u) => u.toString().contains('turn:')) ?? false;
          if (!isTurn) return true;
          final cred = (entry['credential'] ?? '').toString().trim();
          return cred.isNotEmpty;
        }).toList();
        if (valid.isNotEmpty) return valid;
      } catch (_) {}
    }
    // Fallback: Google's public STUN servers (works for non-NAT scenarios).
    return [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
  }
}
