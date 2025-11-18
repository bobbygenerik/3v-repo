/*
 One-off cleanup script to mark pending call signals older than N seconds as 'missed'.
 Usage:
   node scripts/one_off_cleanup_call_signals.js --dry-run
   node scripts/one_off_cleanup_call_signals.js --cutoff-seconds=60 --limit=100
   node scripts/one_off_cleanup_call_signals.js --userId=USER_ID

 Notes:
 - This script uses Application Default Credentials. Set GOOGLE_APPLICATION_CREDENTIALS
   to a service account JSON file with Firestore access, or run it from an environment
   where ADC is available (Cloud Shell, GCE, etc.).
 - By default it performs a dry-run. Remove --dry-run to apply updates.
*/

const admin = require('firebase-admin');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');

const argv = yargs(hideBin(process.argv))
  .option('dry-run', { type: 'boolean', default: true, describe: 'Do not write changes; only log' })
  .option('cutoff-seconds', { type: 'number', default: 60, describe: 'Age in seconds to consider a signal stale' })
  .option('limit', { type: 'number', default: 1000, describe: 'Max number of signals to process per run' })
  .option('userId', { type: 'string', describe: 'If provided, only process this userId' })
  .help()
  .argv;

async function main() {
  console.log('one_off_cleanup_call_signals starting with args:', argv);

  // Initialize admin using ADC if not already initialized
  try {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
    });
  } catch (e) {
    // If already initialized in environment, ignore
    if (!/already exists/.test(String(e))) {
      console.error('Failed to initialize Firebase Admin SDK:', e);
      process.exit(1);
    }
  }

  const db = admin.firestore();
  const cutoff = new Date(Date.now() - (argv['cutoff-seconds'] * 1000));
  console.log('Cutoff timestamp:', cutoff.toISOString());

  let totalFound = 0;
  let totalMarked = 0;

  try {
    if (argv.userId) {
      const userRef = db.collection('users').doc(argv.userId);
      const q = await userRef.collection('callSignals')
        .where('status', '==', 'pending')
        .limit(argv.limit)
        .get();

      // Filter by timestamp in application code to avoid composite index requirement
      const staleDocs = q.docs.filter(d => {
        const ts = d.data().timestamp;
        if (!ts) return false;
        const tsMillis = (typeof ts.toMillis === 'function') ? ts.toMillis() : (new Date(ts)).getTime();
        return tsMillis < cutoff.getTime();
      });

      console.log(`Found ${staleDocs.length} stale pending signals for user ${argv.userId}`);
      totalFound += staleDocs.length;

      if (!argv['dry-run'] && staleDocs.length > 0) {
        const batch = db.batch();
        staleDocs.forEach(doc => {
          batch.update(doc.ref, {
            status: 'missed',
            missedTimestamp: admin.firestore.FieldValue.serverTimestamp(),
            missedByCleanup: true
          });
          totalMarked++;
        });
        await batch.commit();
      }

    } else {
      // Iterate all users (respect limit)
      const usersSnapshot = await db.collection('users').get();
      for (const userDoc of usersSnapshot.docs) {
        const q = await db
          .collection('users')
          .doc(userDoc.id)
          .collection('callSignals')
          .where('status', '==', 'pending')
          .limit(argv.limit)
          .get();

        if (q.empty) continue;

        // Filter by timestamp in application code to avoid composite index requirement
        const staleDocs = q.docs.filter(d => {
          const ts = d.data().timestamp;
          if (!ts) return false;
          const tsMillis = (typeof ts.toMillis === 'function') ? ts.toMillis() : (new Date(ts)).getTime();
          return tsMillis < cutoff.getTime();
        });

        if (staleDocs.length === 0) continue;
        console.log(`User ${userDoc.id} - found ${staleDocs.length} stale pending signals`);
        totalFound += staleDocs.length;

        if (!argv['dry-run']) {
          const batch = db.batch();
          staleDocs.forEach(doc => {
            batch.update(doc.ref, {
              status: 'missed',
              missedTimestamp: admin.firestore.FieldValue.serverTimestamp(),
              missedByCleanup: true
            });
            totalMarked++;
          });
          await batch.commit();
        }
      }
    }

    console.log(`Done. totalFound=${totalFound} totalMarked=${totalMarked} (dryRun=${argv['dry-run']})`);
    process.exit(0);

  } catch (err) {
    console.error('Error during cleanup:', err);
    process.exit(2);
  }
}

main();
