import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  // Initialize Firebase
  await Firebase.initializeApp();
  
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  
  print('Fetching all users...');
  
  // Get all users from Firestore
  final usersSnapshot = await firestore.collection('users').get();
  
  print('Found ${usersSnapshot.docs.length} users\n');
  
  for (var doc in usersSnapshot.docs) {
    final data = doc.data();
    final uid = doc.id;
    
    print('User $uid:');
    print('  Current email in Firestore: "${data['email']}"');
    print('  Display name: "${data['displayName']}"');
    
    // Get the Firebase Auth user
    try {
      final userRecord = await auth.currentUser;
      if (userRecord != null && userRecord.uid == uid) {
        final correctEmail = userRecord.email?.toLowerCase() ?? '';
        print('  Email from Auth: "${userRecord.email}"');
        print('  Correct email (lowercase): "$correctEmail"');
        
        if (data['email'] != correctEmail) {
          print('  ⚠️ MISMATCH! Updating...');
          
          await firestore.collection('users').doc(uid).update({
            'email': correctEmail,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
          print('  ✅ Updated!');
        }
      }
    } catch (e) {
      print('  ❌ Error: $e');
    }
    print('');
  }
  
  print('✅ Done!');
}
