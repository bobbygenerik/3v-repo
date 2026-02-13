import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Lightweight user lookup service with an in-memory cache and request batching.
class UserLookupService {
  static final UserLookupService _instance = UserLookupService._internal();
  factory UserLookupService() => _instance;
  UserLookupService._internal();

  FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Map<String, String>> _cache = {}; // identity -> {displayName, photoURL}

  // Pending requests for batching
  final Map<String, List<Completer<Map<String, String>>>> _pendingRequests = {};
  Timer? _batchTimer;

  @visibleForTesting
  set firestore(FirebaseFirestore fs) => _firestore = fs;

  @visibleForTesting
  void clearCache() {
    _cache.clear();
    // Cancel timer if active to reset state completely for tests
    _batchTimer?.cancel();
    _batchTimer = null;
    _pendingRequests.clear();
  }

  /// Fetch display name and photoURL for a LiveKit identity.
  ///
  /// If the identity looks like an email (contains '@'), this will search the
  /// `users` collection for a matching `email` (case-insensitive). Otherwise
  /// it will try to fetch the user document by id.
  Future<Map<String, String>> fetchForIdentity(String identity) async {
    if (identity.isEmpty) return {'displayName': '', 'photoURL': ''};

    if (_cache.containsKey(identity)) return _cache[identity]!;

    // Add to pending requests
    final completer = Completer<Map<String, String>>();
    if (!_pendingRequests.containsKey(identity)) {
      _pendingRequests[identity] = [];
    }
    _pendingRequests[identity]!.add(completer);

    // Schedule batch processing if not already scheduled
    if (_batchTimer == null || !_batchTimer!.isActive) {
      _batchTimer = Timer(const Duration(milliseconds: 50), _processBatch);
    }

    return completer.future;
  }

  Future<void> _processBatch() async {
    _batchTimer = null;
    if (_pendingRequests.isEmpty) return;

    // Snapshot pending requests and clear queue
    final currentBatch = Map<String, List<Completer<Map<String, String>>>>.from(_pendingRequests);
    _pendingRequests.clear();

    final emailsToFetch = <String>{};
    final uidsToFetch = <String>{};

    // Map email (lowercase) back to original identities requested
    final emailToIdentities = <String, List<String>>{};

    for (final identity in currentBatch.keys) {
      if (identity.contains('@')) {
        final emailLower = identity.toLowerCase();
        emailsToFetch.add(emailLower);
        emailToIdentities.putIfAbsent(emailLower, () => []).add(identity);
      } else {
        uidsToFetch.add(identity);
      }
    }

    // 1. Process Emails
    if (emailsToFetch.isNotEmpty) {
      final chunks = _chunkList(emailsToFetch.toList(), 10);
      for (final chunk in chunks) {
        try {
          final querySnap = await _firestore
              .collection('users')
              .where('email', whereIn: chunk)
              .get();

          for (final doc in querySnap.docs) {
            final data = doc.data();
            final email = (data['email'] as String? ?? '').toLowerCase();

            // Resolve for all identities matching this email
            if (emailToIdentities.containsKey(email)) {
              final result = _extractProfile(data);
              for (final identity in emailToIdentities[email]!) {
                _completeRequest(identity, result, currentBatch);
              }
              emailToIdentities.remove(email);
            }
          }
        } catch (e) {
          debugPrint('Error fetching emails batch: $e');
        }
      }

      // Any emails NOT found?
      // Check remaining emailToIdentities keys. These failed email lookup.
      // Add their original identities to uidsToFetch for fallback.
      for (final email in emailToIdentities.keys) {
        for (final identity in emailToIdentities[email]!) {
           uidsToFetch.add(identity);
        }
      }
    }

    // 2. Process UIDs (including fallbacks from email)
    if (uidsToFetch.isNotEmpty) {
      final chunks = _chunkList(uidsToFetch.toList(), 10);
      for (final chunk in chunks) {
        try {
          final querySnap = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (final doc in querySnap.docs) {
            final data = doc.data();
            final result = _extractProfile(data);
            _completeRequest(doc.id, result, currentBatch);
          }
        } catch (e) {
          debugPrint('Error fetching UIDs batch: $e');
        }
      }
    }

    // 3. Complete remaining with empty result
    currentBatch.forEach((identity, completers) {
      final fallback = {'displayName': '', 'photoURL': ''};
      _cache[identity] = fallback;
      for (final c in completers) {
        if (!c.isCompleted) c.complete(fallback);
      }
    });
  }

  void _completeRequest(String identity, Map<String, String> result, Map<String, List<Completer<Map<String, String>>>> batch) {
    _cache[identity] = result;
    if (batch.containsKey(identity)) {
      for (final c in batch[identity]!) {
        if (!c.isCompleted) c.complete(result);
      }
      batch.remove(identity);
    }
  }

  Map<String, String> _extractProfile(Map<String, dynamic> data) {
    final displayName = (data['displayName'] ?? data['name'] ?? '') as String;
    final photo = (data['photoURL'] ?? '') as String;
    return {'displayName': displayName, 'photoURL': photo};
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, (i + chunkSize < list.length) ? i + chunkSize : list.length));
    }
    return chunks;
  }
}
