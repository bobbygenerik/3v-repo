import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ContactService {
  ContactService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get _currentUserId => _auth.currentUser?.uid;

  /// Returns a stream of favorite user IDs for the current user.
  Stream<List<String>> getFavoritesStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snapshot) {
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

  /// Toggles the favorite status of a contact.
  Future<void> toggleFavorite(String contactId) async {
    final uid = _currentUserId;
    if (uid == null) {
      debugPrint('Cannot toggle favorite: No user logged in');
      return;
    }

    final userRef = _firestore.collection('users').doc(uid);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        if (!snapshot.exists) {
          throw Exception('User document does not exist');
        }

        List<String> favorites = [];
        final data = snapshot.data()!;
        if (data.containsKey('favorites') && data['favorites'] is List) {
          favorites = List<String>.from(data['favorites']);
        }

        if (favorites.contains(contactId)) {
          favorites.remove(contactId);
        } else {
          favorites.add(contactId);
        }

        transaction.update(userRef, {'favorites': favorites});
      });
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      rethrow;
    }
  }
}
