// Quick script to fix user emails in Firestore
// Run with: node fix_emails.js

const admin = require('firebase-admin');

// Initialize Firebase Admin (uses application default credentials)
admin.initializeApp({
  projectId: 'tres3-5fdba'
});

const db = admin.firestore();

async function fixEmails() {
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    
    console.log(`Found ${usersSnapshot.size} users`);
    
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      const uid = doc.id;
      
      console.log(`\nUser ${uid}:`);
      console.log(`  Current email: "${data.email}"`);
      console.log(`  Display name: "${data.displayName}"`);
      
      // Get the Firebase Auth user to get the real email
      try {
        const userRecord = await admin.auth().getUser(uid);
        const correctEmail = userRecord.email ? userRecord.email.toLowerCase() : '';
        
        console.log(`  Auth email: "${userRecord.email}"`);
        console.log(`  Correct email (lowercase): "${correctEmail}"`);
        
        if (data.email !== correctEmail) {
          console.log(`  ⚠️  MISMATCH! Updating...`);
          
          await db.collection('users').doc(uid).update({
            email: correctEmail,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
          
          console.log(`  ✅ Updated!`);
        } else {
          console.log(`  ✓ Email is correct`);
        }
      } catch (authError) {
        console.log(`  ❌ Error getting auth user: ${authError.message}`);
      }
    }
    
    console.log('\n✅ Done!');
  } catch (error) {
    console.error('Error:', error);
  }
}

fixEmails();
