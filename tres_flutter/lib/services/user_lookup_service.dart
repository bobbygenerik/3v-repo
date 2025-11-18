import 'package:cloud_firestore/cloud_firestore.dart';

/// Lightweight user lookup service with an in-memory cache.
class UserLookupService {
  static final UserLookupService _instance = UserLookupService._internal();
  factory UserLookupService() => _instance;
  UserLookupService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Map<String, String>> _cache = {}; // identity -> {displayName, photoURL}

  /// Fetch display name and photoURL for a LiveKit identity.
  ///
  /// If the identity looks like an email (contains '@'), this will search the
  /// `users` collection for a matching `email` (case-insensitive). Otherwise
  /// it will try to fetch the user document by id.
  Future<Map<String, String>> fetchForIdentity(String identity) async {
    if (identity.isEmpty) return {'displayName': '', 'photoURL': ''};

    if (_cache.containsKey(identity)) return _cache[identity]!;

    try {
      // If identity looks like an email, search by email
      if (identity.contains('@')) {
        final q = await _firestore
            .collection('users')
            .where('email', isEqualTo: identity.toLowerCase())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final data = q.docs.first.data();
          final displayName = (data['displayName'] ?? data['name'] ?? '') as String;
          final photo = (data['photoURL'] ?? '') as String;
          final result = {'displayName': displayName, 'photoURL': photo};
          _cache[identity] = result;
          return result;
        }
      }

      // Try to fetch by document id (identity may be uid)
      final doc = await _firestore.collection('users').doc(identity).get();
      if (doc.exists) {
        final data = doc.data()!;
        final displayName = (data['displayName'] ?? data['name'] ?? '') as String;
        final photo = (data['photoURL'] ?? '') as String;
        final result = {'displayName': displayName, 'photoURL': photo};
        _cache[identity] = result;
        return result;
      }
    } catch (e) {
      // Ignore errors and fall back to identity
    }

    // Fallback - return empty displayName and no photo
    final fallback = {'displayName': '', 'photoURL': ''};
    _cache[identity] = fallback;
    return fallback;
  }
}
