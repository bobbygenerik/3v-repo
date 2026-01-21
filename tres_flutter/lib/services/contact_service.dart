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
        .listen((snapshot) {
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
    }, onError: (e) {
      debugPrint('Error listening to favorites: $e');
    });
  }

  bool isFavorite(String userId) => _favoriteIds.contains(userId);

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
            'favorites': FieldValue.arrayRemove([userId])
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
            'favorites': FieldValue.arrayUnion([userId])
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

  @override
  void dispose() {
    _favoritesSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
