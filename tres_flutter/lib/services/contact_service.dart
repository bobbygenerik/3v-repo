import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ContactService extends ChangeNotifier {
  ContactService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance {
    _authSubscription = _auth.authStateChanges().listen(_updateSubscription);
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  List<String> _favoriteIds = [];
  List<String> get favoriteIds => _favoriteIds;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _favoritesSubscription;
  StreamSubscription<User?>? _authSubscription;

  String? get _currentUserId => _auth.currentUser?.uid;

  void _updateSubscription(User? user) {
    _favoritesSubscription?.cancel();
    if (user == null) {
      _favoriteIds = [];
      notifyListeners();
      return;
    }

    _favoritesSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists) {
              final data = snapshot.data();
              if (data != null && data.containsKey('favorites')) {
                _favoriteIds = List<String>.from(data['favorites'] ?? []);
              } else {
                _favoriteIds = [];
              }
            } else {
              _favoriteIds = [];
            }
            notifyListeners();
          },
          onError: (e) {
            debugPrint('Error listening to favorites: $e');
          },
        );
  }

  bool isFavorite(String userId) => _favoriteIds.contains(userId);

  /// Returns a stream of favorite user IDs for the current user.
  Stream<List<String>> getFavoritesStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return [];
      final data = snapshot.data();
      if (data == null || !data.containsKey('favorites')) return [];

      final favorites = data['favorites'];
      if (favorites is List) {
        return favorites.map((e) => e.toString()).toList();
      }
      return [];
    });
  }

  Future<void> toggleFavorite(String userId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final isFav = isFavorite(userId);
    try {
      if (isFav) {
        _favoriteIds.remove(userId);
        notifyListeners();

        try {
          await _firestore.collection('users').doc(user.uid).update({
            'favorites': FieldValue.arrayRemove([userId]),
          });
        } catch (e) {
          if (!_favoriteIds.contains(userId)) {
            _favoriteIds.add(userId);
            notifyListeners();
          }
          rethrow;
        }
      } else {
        _favoriteIds.add(userId);
        notifyListeners();

        try {
          await _firestore.collection('users').doc(user.uid).update({
            'favorites': FieldValue.arrayUnion([userId]),
          });
        } catch (e) {
          if (_favoriteIds.contains(userId)) {
            _favoriteIds.remove(userId);
            notifyListeners();
          }
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
    }
  }

  Future<List<Map<String, dynamic>>> searchContacts(
    String query, {
    int limit = 5,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final contactsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('contacts')
          .get();

      if (contactsSnapshot.docs.isEmpty) return [];

      final contactIds = contactsSnapshot.docs.map((doc) => doc.id).toList();
      final List<Map<String, dynamic>> allContacts = [];

      // Batch size of 10 for 'whereIn' compatibility
      const batchSize = 10;

      // Create a list of futures to run in parallel
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

      for (var i = 0; i < contactIds.length; i += batchSize) {
        final end = (i + batchSize < contactIds.length)
            ? i + batchSize
            : contactIds.length;
        final batchIds = contactIds.sublist(i, end);

        futures.add(
          _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: batchIds)
              .get(),
        );
      }

      final snapshots = await Future.wait(futures);

      for (var snapshot in snapshots) {
        for (var doc in snapshot.docs) {
          final data = doc.data();
          allContacts.add({
            'uid': doc.id,
            'name': data['displayName'] ?? data['name'] ?? 'Unknown',
            'email': data['email'] ?? '',
          });
        }
      }

      final lowerQuery = query.toLowerCase();
      return allContacts
          .where((c) {
            final name = (c['name'] as String).toLowerCase();
            final email = (c['email'] as String).toLowerCase();
            return name.contains(lowerQuery) || email.contains(lowerQuery);
          })
          .take(limit)
          .toList();
    } catch (e) {
      debugPrint('Error searching contacts: $e');
      return [];
    }
  }

  @override
  void dispose() {
    _favoritesSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
