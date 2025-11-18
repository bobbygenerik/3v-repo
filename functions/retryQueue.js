const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * Helper function to queue a failed notification for retry
 */
async function queueFailedNotification(messagePayload, error, context = {}) {
  try {
    const retryDoc = {
      messagePayload,
      error: {
        code: error.code || 'unknown',
        message: error.message || String(error),
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      },
      context, // Additional context (e.g., invitationId, guestName)
      attemptCount: 0,
      maxAttempts: 5,
      nextRetryAt: admin.firestore.Timestamp.fromMillis(Date.now() + 30000), // Retry in 30 seconds
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'pending'
    };

    const docRef = await admin.firestore().collection('failedNotifications').add(retryDoc);
    console.log(`📋 Queued failed notification for retry: ${docRef.id}`);
    return docRef.id;
  } catch (queueError) {
    console.error('❌ Failed to queue notification for retry:', queueError);
    return null;
  }
}

/**
 * Scheduled function to retry failed notifications
 * Runs every 2 minutes
 */
exports.retryFailedNotifications = functions.pubsub.schedule('every 2 minutes').onRun(async (context) => {
  console.log('🔄 Starting retry of failed notifications...');
  
  try {
    const now = admin.firestore.Timestamp.now();
    
    // Query for pending notifications that are ready to retry
    const snapshot = await admin.firestore()
      .collection('failedNotifications')
      .where('status', '==', 'pending')
      .where('nextRetryAt', '<=', now)
      .where('attemptCount', '<', 5) // Max 5 attempts
      .limit(50) // Process 50 at a time
      .get();

    if (snapshot.empty) {
      console.log('ℹ️ No pending notifications to retry');
      return null;
    }

    console.log(`📬 Found ${snapshot.size} notifications to retry`);

    // Process in smaller batches to avoid memory issues
    const batchSize = 10;
    let processedCount = 0;
    
    for (let i = 0; i < snapshot.docs.length; i += batchSize) {
      const batch = admin.firestore().batch();
      const batchDocs = snapshot.docs.slice(i, i + batchSize);
      const retryPromises = [];

      for (const doc of batchDocs) {
        const data = doc.data();
        const attemptCount = data.attemptCount + 1;
        
        console.log(`Retrying notification ${doc.id} (attempt ${attemptCount}/${data.maxAttempts})`);

        // Attempt to send with timeout
        const sendPromise = Promise.race([
          admin.messaging().send(data.messagePayload),
          new Promise((_, reject) => 
            setTimeout(() => reject(new Error('Retry timeout')), 5000)
          )
        ])
          .then((response) => {
            console.log(`✅ Retry successful for ${doc.id}: ${response}`);
            batch.update(doc.ref, {
              status: 'completed',
              completedAt: admin.firestore.FieldValue.serverTimestamp(),
              attemptCount,
              lastResponse: response
            });
          })
          .catch((error) => {
            console.error(`❌ Retry failed for ${doc.id} (attempt ${attemptCount}):`, error.message);
            
            if (attemptCount >= data.maxAttempts) {
              console.log(`🚫 Max attempts reached for ${doc.id}, marking as failed`);
              batch.update(doc.ref, {
                status: 'failed',
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
                attemptCount,
                lastError: error.message
              });
            } else {
              const backoffMs = Math.min(30000 * Math.pow(2, attemptCount), 600000);
              const nextRetryAt = admin.firestore.Timestamp.fromMillis(Date.now() + backoffMs);
              
              console.log(`⏰ Scheduling next retry for ${doc.id} in ${backoffMs / 1000}s`);
              batch.update(doc.ref, {
                attemptCount,
                nextRetryAt,
                lastError: error.message,
                lastAttemptAt: admin.firestore.FieldValue.serverTimestamp()
              });
            }
          });

        retryPromises.push(sendPromise);
      }

      // Wait for batch to complete
      await Promise.allSettled(retryPromises);
      
      // Commit batch updates
      try {
        await batch.commit();
        processedCount += batchDocs.length;
        console.log(`✅ Processed batch ${i / batchSize + 1}, total: ${processedCount}`);
      } catch (batchError) {
        console.error('❌ Batch commit failed:', batchError);
      }
    }
    
    console.log(`✅ All retry batches completed, processed ${processedCount} notifications`);

    return null;
  } catch (error) {
    console.error('❌ Error in retryFailedNotifications:', error);
    return null;
  }
});

/**
 * Cleanup old completed/failed notifications (runs daily)
 */
exports.cleanupOldNotifications = functions.pubsub.schedule('every 24 hours').onRun(async (context) => {
  console.log('🧹 Cleaning up old notification records...');
  
  try {
    const cutoffDate = admin.firestore.Timestamp.fromMillis(Date.now() - 7 * 24 * 60 * 60 * 1000); // 7 days ago
    
    let totalDeleted = 0;
    let hasMore = true;
    
    while (hasMore) {
      const snapshot = await admin.firestore()
        .collection('failedNotifications')
        .where('createdAt', '<', cutoffDate)
        .limit(100)
        .get();

      hasMore = snapshot.size === 100;
      
      if (snapshot.empty) break;

      console.log(`🗑️ Deleting ${snapshot.size} old notification records`);
      
      const batch = admin.firestore().batch();
      snapshot.docs.forEach(doc => {
        batch.delete(doc.ref);
        totalDeleted++;
      });
      
      await batch.commit();
    }
    
    console.log(`✅ Cleanup completed, deleted ${totalDeleted} records`);

    
    return null;
  } catch (error) {
    console.error('❌ Error in cleanupOldNotifications:', error);
    return null;
  }
});

module.exports = { queueFailedNotification };
