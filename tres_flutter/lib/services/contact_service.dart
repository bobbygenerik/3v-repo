import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Contact Service
/// Manages user contacts and favorites
class ContactService extends ChangeNotifier {
  ContactService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Stream of favorite contact IDs for the current user
  Stream<List<String>> get favoritesStream {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream.value([]);
    }

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

  /// Toggle a contact as favorite
  Future<void> toggleFavorite(String contactId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final userRef = _firestore.collection('users').doc(uid);

    try {
      final doc = await userRef.get();
      if (!doc.exists) {
        // Create user doc if it doesn't exist (should normally exist)
         await userRef.set({
          'favorites': [contactId],
        }, SetOptions(merge: true));
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final favorites = List<String>.from(data['favorites'] ?? []);

      if (favorites.contains(contactId)) {
        await userRef.update({
          'favorites': FieldValue.arrayRemove([contactId])
        });
      } else {
        await userRef.update({
          'favorites': FieldValue.arrayUnion([contactId])
        });
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      rethrow;
    }
  }

  /// Check if a contact is a favorite
  Future<bool> isFavorite(String contactId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;

      final data = doc.data();
      final favorites = List<String>.from(data?['favorites'] ?? []);
      return favorites.contains(contactId);
    } catch (e) {
      debugPrint('Error checking favorite status: $e');
      return false;
    }
  }
}
