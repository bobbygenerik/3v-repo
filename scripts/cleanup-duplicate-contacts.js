#!/usr/bin/env node
/*
 * Script: cleanup-duplicate-contacts.js
 * Purpose: Detect (and optionally remove) duplicate contacts in Firestore
 * Usage:
 *   # Set GOOGLE_APPLICATION_CREDENTIALS to your service account JSON
 *   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/serviceAccount.json"
 *
 *   # Dry run (report only)
 *   node scripts/cleanup-duplicate-contacts.js
 *
 *   # Fix mode (delete duplicates, keep earliest)
 *   node scripts/cleanup-duplicate-contacts.js --fix
 *
 * Notes:
 *  - This script requires a service account with Firestore read/write permissions.
 *  - It scans every user in `users` and inspects their `contacts` subcollection.
 *  - Duplicates are detected by resolving contact document to an email (best-effort).
 */

const admin = require('firebase-admin');
const argv = require('minimist')(process.argv.slice(2));

const FIX = argv.fix || argv.f || false;
const BACKUP = argv.backup || argv.b || false;

async function main() {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !process.env.FIREBASE_CONFIG) {
    console.error('ERROR: Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON path.');
    process.exit(1);
  }

  admin.initializeApp();
  const db = admin.firestore();

  console.log('Scanning users for duplicate contacts...');

  const usersSnap = await db.collection('users').get();
  console.log(`Found ${usersSnap.size} users to inspect`);

  let totalDuplicates = 0;
  let totalDeleted = 0;

  for (const userDoc of usersSnap.docs) {
    const userId = userDoc.id;
    const contactsRef = db.collection('users').doc(userId).collection('contacts');
    const contactsSnap = await contactsRef.get();
    if (contactsSnap.empty) continue;

    // Map by resolved email -> array of {docId, addedAt}
    const byEmail = new Map();

    for (const contactDoc of contactsSnap.docs) {
      const data = contactDoc.data() || {};

      // Representation id: prefer explicit uid field if present, else doc id
      const reprId = data.uid || data.contactUid || contactDoc.id;

      // Try to fetch the referenced user doc to resolve email
      let email = null;
      try {
        const refUser = await db.collection('users').doc(reprId).get();
        if (refUser.exists) {
          const rd = refUser.data() || {};
          email = (rd.email || rd.displayName || rd.name || reprId).toString().toLowerCase();
        }
      } catch (e) {
        // Ignore fetch errors
      }

      // Fallback to any email-like field in contact doc
      if (!email) {
        if (data.email) email = String(data.email).toLowerCase();
        else if (data.contactEmail) email = String(data.contactEmail).toLowerCase();
        else email = reprId.toLowerCase();
      }

      const addedAt = data.addedAt ? data.addedAt.toDate ? data.addedAt.toDate() : new Date(data.addedAt) : null;

      if (!byEmail.has(email)) byEmail.set(email, []);
      byEmail.get(email).push({ docId: contactDoc.id, addedAt });
    }

    // Find duplicates (more than 1 entry for same email)
    for (const [email, entries] of byEmail.entries()) {
      if (entries.length <= 1) continue;
      totalDuplicates += entries.length - 1;
      console.log(`User ${userId} has ${entries.length} contacts for ${email}:`, entries.map(e => e.docId));

      // Decide which to keep: earliest addedAt (if available) else first
      entries.sort((a, b) => {
        if (a.addedAt && b.addedAt) return a.addedAt - b.addedAt;
        if (a.addedAt) return -1;
        if (b.addedAt) return 1;
        return 0;
      });

      const keep = entries[0].docId;
      const toDelete = entries.slice(1).map(e => e.docId);

      console.log(`  Keeping: ${keep}. Will delete: ${toDelete.join(', ')}`);

      if (toDelete.length > 0) {
        if (BACKUP) {
          // Copy duplicates to backup collection before deleting
          const backupBase = db.collection('backup').doc('duplicate_contacts').collection(userId);
          const batchBackup = db.batch();
          for (const delId of toDelete) {
            const srcRef = contactsRef.doc(delId);
            const destRef = backupBase.doc(delId);
            // Read doc and write to backup (batch can't read, so read individually)
            const snap = await srcRef.get();
            if (snap.exists) {
              batchBackup.set(destRef, {
                _originalPath: srcRef.path,
                _backedUpAt: admin.firestore.FieldValue.serverTimestamp(),
                ...snap.data(),
              });
            }
          }
          await batchBackup.commit();
          console.log(`  Backed up ${toDelete.length} duplicate(s) for user ${userId} to backup/duplicate_contacts/${userId}`);
        }

        if (FIX) {
          const batch = db.batch();
          for (const delId of toDelete) {
            batch.delete(contactsRef.doc(delId));
          }
          await batch.commit();
          console.log(`  Deleted ${toDelete.length} duplicate(s) for user ${userId}`);
          totalDeleted += toDelete.length;
        } else {
          console.log('  (dry-run) Not deleting — run with --fix to remove duplicates');
        }
      }
    }
  }

  console.log('Scan complete.');
  console.log(`Total duplicate entries found: ${totalDuplicates}`);
  if (FIX) console.log(`Total duplicate entries deleted: ${totalDeleted}`);
  else console.log('Run with --fix to delete duplicates.');
  process.exit(0);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(2);
});
