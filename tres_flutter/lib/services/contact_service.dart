import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ContactService extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  List<String> _favoriteIds = [];
  List<String> get favoriteIds => _favoriteIds;

  StreamSubscription<DocumentSnapshot>? _favoritesSubscription;
  StreamSubscription<User?>? _authSubscription;

  ContactService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _updateSubscription(user);
    });
  }

  void _updateSubscription(User? user) {
    _favoritesSubscription?.cancel();
    if (user != null) {
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
    } else {
      _favoriteIds = [];
      notifyListeners();
    }
  }

  bool isFavorite(String userId) {
    return _favoriteIds.contains(userId);
  }

  Future<void> toggleFavorite(String userId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final isFav = isFavorite(userId);
    try {
      if (isFav) {
        // Optimistic update
        _favoriteIds.remove(userId);
        notifyListeners();

        try {
          await _firestore.collection('users').doc(user.uid).update({
            'favorites': FieldValue.arrayRemove([userId])
          });
        } catch (e) {
          // Revert on failure
          if (!_favoriteIds.contains(userId)) {
             _favoriteIds.add(userId);
             notifyListeners();
          }
          rethrow;
        }
      } else {
        // Optimistic update
        _favoriteIds.add(userId);
        notifyListeners();

        try {
          await _firestore.collection('users').doc(user.uid).update({
            'favorites': FieldValue.arrayUnion([userId])
          });
        } catch (e) {
          // Revert on failure
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
