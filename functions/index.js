const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

admin.initializeApp();

exports.getLiveKitToken = functions.https.onCall(async (request) => {
  console.log('=== getLiveKitToken Function Called ===');
  console.log('Raw request object keys:', Object.keys(request));
  console.log('Request auth:', request.auth);
  console.log('Request data:', request.data);
  console.log('Auth context exists:', !!request.auth);
  console.log('Auth uid:', request.auth?.uid);
  console.log('Auth token:', request.auth?.token ? 'Present' : 'Missing');
  
  // Verify user is authenticated
  if (!request.auth) {
    console.error('ERROR: No authentication context');
    console.error('Full request object:', request);
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated. Make sure you are signed in with Firebase Auth.'
    );
  }

  const userId = request.auth.uid;
  console.log('Authenticated user:', userId);
  
  const { calleeId, roomName } = request.data;
  console.log('Parameters - calleeId:', calleeId, 'roomName:', roomName);

  if (!calleeId || !roomName) {
    console.error('ERROR: Missing required parameters');
    throw new functions.https.HttpsError(
      'invalid-argument',
      'calleeId and roomName are required'
    );
  }

  try {
    // Get LiveKit credentials from environment variables (v2 functions)
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;

    console.log('LiveKit config - Key exists:', !!apiKey, 'Secret exists:', !!apiSecret);

    if (!apiKey || !apiSecret) {
      console.error('ERROR: LiveKit credentials missing in environment variables');
      console.error('Please set LIVEKIT_API_KEY and LIVEKIT_API_SECRET');
      throw new Error('LiveKit credentials not configured');
    }

    // Get user info
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userId)
      .get();

    const userName = userDoc.data()?.name || userDoc.data()?.displayName || 'User';
    console.log('User name:', userName);

    // Create token
    console.log('Creating AccessToken...');
    const at = new AccessToken(apiKey, apiSecret, {
      identity: userId,
      name: userName,
    });

    at.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    const token = await at.toJwt();
    console.log('SUCCESS: Token generated for user', userId);

    return {
      token: token,
      url: 'wss://tres3-l25y6pxz.livekit.cloud'
    };

  } catch (error) {
    console.error('ERROR in token generation:', error.message);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to generate token: ${error.message}`
    );
  }
});

/**
 * Cloud Function: Send push notification when call invitation is created
 * Triggers when a new document is added to users/{userId}/callSignals
 */
exports.sendCallNotification = functions.firestore.onDocumentCreated(
  'users/{userId}/callSignals/{signalId}',
  async (event) => {
    const snap = event.data;
    try {
      const userId = event.params.userId;
      const signalId = event.params.signalId;
      const callData = snap.data();
      
      console.log(`📞 New call signal for user ${userId} from ${callData.fromUserName}`);
      
      // Only send notification for pending call invitations
      if (callData.type !== 'call_invite' || callData.status !== 'pending') {
        console.log('Skipping notification - not a pending call invite');
        return null;
      }
      
      // Get recipient's FCM token
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(userId)
        .get();
      
      if (!userDoc.exists) {
        console.error(`User ${userId} not found`);
        return null;
      }
      
      const fcmToken = userDoc.data().fcmToken;
      
      if (!fcmToken) {
        console.log(`User ${userId} has no FCM token registered`);
        return null;
      }
      
      console.log(`Sending push notification to FCM token: ${fcmToken.substring(0, 20)}...`);
      
      // Send data-only message to ensure MyFirebaseMessagingService.onMessageReceived() is called
      // even when app is in background/killed. This allows us to show full-screen intent.
      const message = {
        token: fcmToken,
        data: {
          type: 'call_invite',
          invitationId: signalId,
          fromUserId: callData.fromUserId,
          fromUserName: callData.fromUserName,
          roomName: callData.roomName,
          url: callData.url,
          token: callData.token,
          timestamp: (callData.timestamp || new Date()).toString()
        },
        android: {
          priority: 'high',
          // Data messages with high priority are delivered immediately
          // even when device is in Doze mode
          ttl: 60 * 1000 // 60 seconds TTL for call invitations
        }
      };
      
      // Send the notification
      const response = await admin.messaging().send(message);
      console.log(`✅ Push notification sent successfully: ${response}`);
      
      return response;
      
    } catch (error) {
      console.error('❌ Error sending call notification:', error);
      // Don't throw - we don't want to retry if FCM fails
      return null;
    }
  }
);

/**
 * Cloud Function: Clean up old call signals (older than 1 hour)
 * Runs every hour to keep database clean
 */
exports.cleanupOldCallSignals = functions.scheduler.onSchedule(
  'every 1 hours',
  async (event) => {
    try {
      console.log('🧹 Starting cleanup of old call signals');
      
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
      const db = admin.firestore();
      
      // Get all users
      const usersSnapshot = await db.collection('users').get();
      let totalDeleted = 0;
      
      for (const userDoc of usersSnapshot.docs) {
        const oldSignals = await db
          .collection('users')
          .doc(userDoc.id)
          .collection('callSignals')
          .where('timestamp', '<', oneHourAgo)
          .get();
        
        // Delete old signals in batches
        const batch = db.batch();
        oldSignals.forEach(doc => {
          batch.delete(doc.ref);
          totalDeleted++;
        });
        
        if (oldSignals.size > 0) {
          await batch.commit();
        }
      }
      
      console.log(`✅ Cleanup complete: Deleted ${totalDeleted} old call signals`);
      return null;
      
    } catch (error) {
      console.error('❌ Error during cleanup:', error);
      return null;
    }
  }
);
