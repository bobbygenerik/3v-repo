const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { AccessToken, EgressClient, EncodedFileOutput, RoomCompositeEgressRequest } = require('livekit-server-sdk');
const { onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const {
  queueFailedNotification,
  retryFailedNotifications,
  cleanupOldNotifications,
} = require('./retryQueue');

admin.initializeApp();

// Load environment variables (check both .env and Firebase config)
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const LIVEKIT_WS_URL = process.env.LIVEKIT_URL || 'wss://livekit.iptvsubz.fun';
const LIVEKIT_HTTP_URL = process.env.LIVEKIT_HTTP_URL || 'https://livekit.iptvsubz.fun';
const LIVEKIT_ICE_SERVERS_JSON = process.env.LIVEKIT_ICE_SERVERS_JSON || '';
const TURN_HOST = process.env.TURN_HOST || 'livekit.iptvsubz.fun';
const TURN_USERNAME = process.env.TURN_USERNAME || 'tres-turn';
const TURN_PASSWORD = process.env.TURN_PASSWORD || 'uOed6dZmbnWEtCiEI4/dhSLn';
const WEB_URL = process.env.WEB_URL || 'https://tres3.web.app';
const STALE_SESSION_MINUTES = Number(process.env.CALL_SESSION_STALE_MINUTES || 2);

const buildDefaultIceServersJson = () => JSON.stringify([
  { urls: ['stun:stun.l.google.com:19302'] },
  { urls: ['stun:stun1.l.google.com:19302'] },
  {
    urls: [
      `turn:${TURN_HOST}:3478?transport=udp`,
      `turn:${TURN_HOST}:3478?transport=tcp`,
    ],
    username: TURN_USERNAME,
    credential: TURN_PASSWORD,
  },
]);

const normalizeCallableRequest = (requestOrData, context) => {
  if (requestOrData && typeof requestOrData === 'object' && 'data' in requestOrData) {
    return requestOrData;
  }
  return {
    data: requestOrData || {},
    auth: context?.auth,
  };
};

exports.getLiveKitToken = functions.https.onCall(async (requestOrData, context) => {
  const request = normalizeCallableRequest(requestOrData, context);
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
  
  const { calleeId, roomName, platform } = request.data;
  console.log('Parameters - calleeId:', calleeId, 'roomName:', roomName, 'platform:', platform);

  if (!calleeId || !roomName) {
    console.error('ERROR: Missing required parameters');
    throw new functions.https.HttpsError(
      'invalid-argument',
      'calleeId and roomName are required'
    );
  }

  try {
    // Use environment variables loaded at startup
    const apiKey = LIVEKIT_API_KEY;
    const apiSecret = LIVEKIT_API_SECRET;

    console.log('LiveKit config - Key exists:', !!apiKey, 'Secret exists:', !!apiSecret);
    console.log('API Key (first 10 chars):', apiKey?.substring(0, 10));

    if (!apiKey || !apiSecret) {
      console.error('ERROR: LiveKit credentials missing from environment variables');
      console.error('Key present:', !!apiKey, 'Secret present:', !!apiSecret);
      throw new Error('LiveKit credentials not configured in .env file');
    }

    // Get user info (fallback to a safe default if Firestore is unavailable)
    let userName = 'User';
    try {
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(userId)
        .get();
      userName = userDoc.data()?.name || userDoc.data()?.displayName || 'User';
    } catch (error) {
      console.warn('User lookup failed, using fallback name:', error.message);
    }
    console.log('User name:', userName);

    // Create token
    console.log('Creating AccessToken...');
    const platformLabel = typeof platform === 'string' && platform.trim().length > 0
      ? platform.trim().toLowerCase()
      : 'unknown';

    const at = new AccessToken(apiKey, apiSecret, {
      identity: userId,
      name: userName,
      metadata: JSON.stringify({
        displayName: userName,
        platform: platformLabel,
      }),
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
    console.log('Token preview (first 10 chars):', token.substring(0, 10) + '...');
    console.log('Room name:', roomName);
    console.log('WSS URL:', LIVEKIT_WS_URL);

    const iceServersJson = LIVEKIT_ICE_SERVERS_JSON && LIVEKIT_ICE_SERVERS_JSON.trim().length > 0
      ? LIVEKIT_ICE_SERVERS_JSON
      : buildDefaultIceServersJson();

    return {
      token: token,
      wsUrl: LIVEKIT_WS_URL,
      iceServersJson,
    };

  } catch (error) {
    console.error('ERROR in token generation:', error.message);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to generate token: ${error.message}`
    );
  }
});

// smokeGetLiveKitToken removed — temporary test endpoint deleted

/**
 * Cloud Function: Send push notification when call invitation is created
 * Triggers when a new document is added to call_invitations collection
 */
exports.sendCallNotification = functions.firestore.onDocumentCreated(
  'call_invitations/{invitationId}',
  async (event) => {
    const snap = event.data;
    try {
      const invitationId = event.params.invitationId;
      const callData = snap.data();
      
      console.log(`📞 New call invitation ${invitationId} from ${callData.callerName} to ${callData.recipientId}`);
      
      // Only send notification for pending call invitations
      if (callData.status !== 'pending') {
        console.log('Skipping notification - not a pending invitation');
        return null;
      }
      
      const recipientId = callData.recipientId;
      
      // Get recipient's FCM token
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(recipientId)
        .get();
      
      if (!userDoc.exists) {
        console.error(`Recipient user ${recipientId} not found`);
        return null;
      }
      
      const fcmToken = userDoc.data().fcmToken;
      
      if (!fcmToken) {
        console.log(`❌ Recipient ${recipientId} has no FCM token registered`);
        
        // Update call invitation status so caller knows the notification failed
        try {
          await admin.firestore()
            .collection('call_invitations')
            .doc(invitationId)
            .update({ 
              status: 'failed',
              failureReason: 'no_fcm_token',
              failureTimestamp: admin.firestore.FieldValue.serverTimestamp()
  });

/**
 * Cleanup stale call sessions that stopped heartbeating.
 */
exports.cleanupStaleCallSessions = onSchedule('every 5 minutes', async () => {
  const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 2 * 60 * 1000);

  const snapshot = await admin.firestore()
    .collection('call_sessions')
    .where('status', '==', 'active')
    .where('lastHeartbeat', '<', cutoff)
    .get();

  if (snapshot.empty) {
    return null;
  }

  const batch = admin.firestore().batch();
  for (const doc of snapshot.docs) {
    batch.update(doc.ref, {
      status: 'ended',
      endTime: admin.firestore.FieldValue.serverTimestamp(),
      endedBy: 'system',
      endedReason: 'stale_heartbeat',
    });
  }

  await batch.commit();
  console.log(`✅ Cleaned up ${snapshot.size} stale call sessions`);
  return null;
});
          console.log(`✅ Marked call invitation as failed (no FCM token)`);
        } catch (updateError) {
          console.error(`Failed to update call invitation status: ${updateError}`);
        }
        
        return null;
      }
      
      console.log(`Sending push notification to FCM token: ${fcmToken.substring(0, 5)}...`);
      
      // Send notification with both data and notification payload
      // Android needs notification payload to wake app when killed
      const message = {
        token: fcmToken,
        notification: {
          title: `Incoming call from ${callData.callerName}`,
          body: 'Tap to answer'
        },
        data: {
          type: 'call_invitation',
          invitationId: invitationId,
          callerId: callData.callerId,
          callerName: callData.callerName,
          callerEmail: callData.callerEmail || '',
          callerPhotoUrl: callData.callerPhotoUrl || '',
          roomName: callData.roomName,
          livekitUrl: callData.livekitUrl,
          token: callData.token,
          isVideoCall: (callData.isVideoCall || true).toString(),
          timestamp: (callData.timestamp || new Date()).toString()
        },
        android: {
          priority: 'high',
          // High priority ensures delivery even in Doze mode
          ttl: 60 * 1000, // 60 seconds TTL for call invitations
          notification: {
            channelId: 'call_channel',
            sound: 'default',
            priority: 'high'
          }
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert'
          },
          payload: {
            aps: {
              alert: {
                title: `Incoming call from ${callData.callerName}`,
                body: 'Tap to answer'
              },
              sound: 'default',
              badge: 1
            }
          }
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
      
      // Use Collection Group query to find all callSignals across all users efficiently
      const oldSignalsSnapshot = await db.collectionGroup('callSignals')
        .where('timestamp', '<', oneHourAgo)
        .get();

      let totalDeleted = 0;

      if (!oldSignalsSnapshot.empty) {
        // Delete in batches of 500 (Firestore limit)
        const batches = [];
        let currentBatch = db.batch();
        let operationCount = 0;

        oldSignalsSnapshot.forEach((doc) => {
          currentBatch.delete(doc.ref);
          operationCount++;
          totalDeleted++;

          if (operationCount >= 500) {
            batches.push(currentBatch.commit());
            currentBatch = db.batch();
            operationCount = 0;
          }
        });

        if (operationCount > 0) {
          batches.push(currentBatch.commit());
        }

        await Promise.all(batches);
      }
      
      console.log(`✅ Cleanup complete: Deleted ${totalDeleted} old call signals`);
      return null;
      
    } catch (error) {
      console.error('❌ Error during cleanup:', error);
      return null;
    }
  }
);

/**
 * Cloud Function: Mark pending call signals older than 60 seconds as 'missed'
 * Runs every 5 minutes to quickly mark short-lived invites as missed so
 * clients don't show stale incoming call UI when users open the app.
 */
exports.markStaleCallSignals = functions.scheduler.onSchedule(
  'every 5 minutes',
  async (event) => {
    try {
      console.log('⌛ Running markStaleCallSignals to mark old pending invites as missed');
      const db = admin.firestore();
      const cutoff = new Date(Date.now() - 60 * 1000); // 60 seconds ago

      // Use Collection Group Query to find all stale signals across all users efficiently
      const pendingQuery = await db.collectionGroup('callSignals')
        .where('status', '==', 'pending')
        .where('timestamp', '<', cutoff)
        .get();

      let totalMarked = 0;

      if (!pendingQuery.empty) {
        // Process in batches of 500 (Firestore batch limit)
        const chunks = [];
        const docs = pendingQuery.docs;
        const BATCH_SIZE = 500;

        for (let i = 0; i < docs.length; i += BATCH_SIZE) {
          chunks.push(docs.slice(i, i + BATCH_SIZE));
        }

        for (const chunk of chunks) {
          const batch = db.batch();
          chunk.forEach(doc => {
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

      console.log(`✅ markStaleCallSignals complete: Marked ${totalMarked} pending call signals as missed`);
      return null;
    } catch (error) {
      console.error('❌ Error in markStaleCallSignals:', error);
      return null;
    }
  }
);

/**
 * Cloud Function: Generate guest call token for web users
 * Allows authenticated app users to create shareable links for non-app users
 */
exports.generateGuestToken = functions.https.onCall(async (requestOrData, context) => {
  const request = normalizeCallableRequest(requestOrData, context);
  // Verify caller is authenticated
  if (!request.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated', 
      'Must be logged in to generate guest links'
    );
  }

  const { roomName, guestName } = request.data;
  
  // Validate input
  if (!roomName || typeof roomName !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      'roomName is required and must be a string'
    );
  }
  
  if (!guestName || typeof guestName !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument', 
      'guestName is required and must be a string'
    );
  }

  try {
    // Use environment variables loaded at startup
    const apiKey = LIVEKIT_API_KEY;
    const apiSecret = LIVEKIT_API_SECRET;
    const wsUrl = LIVEKIT_WS_URL;
    const webUrl = WEB_URL;

    console.log('Guest token - LiveKit config check');
    console.log('API Key exists:', !!apiKey, 'API Secret exists:', !!apiSecret);
    console.log('API Key (first 10 chars):', apiKey?.substring(0, 10));

    if (!apiKey || !apiSecret) {
      console.error('Missing LiveKit configuration. API Key:', !!apiKey, 'Secret:', !!apiSecret);
      throw new functions.https.HttpsError(
        'failed-precondition',
        'LiveKit is not properly configured. Please contact support.'
      );
    }

    // Create guest identity
    const guestIdentity = `guest_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    console.log(`Generating token for guest: ${guestName} (${guestIdentity}) in room: ${roomName}`);
    
    // Generate LiveKit access token
    const at = new AccessToken(apiKey, apiSecret, {
      identity: guestIdentity,
      name: guestName,
      metadata: JSON.stringify({ displayName: guestName }), // Add metadata for browser to read
      ttl: 86400, // 24 hours
    });

    // Grant permissions
    at.addGrant({
      room: roomName,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: false, // Guests can't send data messages
    });

    const token = await at.toJwt();
    
    // Generate short invitation code (8 characters, URL-safe)
    const inviteCode = Math.random().toString(36).substring(2, 10);
    
    // Create short shareable link using invite code
    const link = `${webUrl}/g/${inviteCode}`;

    // Save invitation record to Firestore with full token data
    const invitationRef = await admin.firestore().collection('guestInvitations').add({
      roomName,
      guestName,
      guestIdentity,
      hostUserId: request.auth.uid,
      inviteCode,
      token,
      wsUrl,
      link,
      used: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400 * 1000) // 24 hours
    });

    console.log(`✅ Generated guest token for ${guestName} in room ${roomName}`);

    return {
      success: true,
      link,
      invitationId: invitationRef.id,
      expiresIn: 86400 // seconds
    };

  } catch (error) {
    console.error('Error generating guest token:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to generate guest token: ' + error.message
    );
  }
});

/**
 * Optional: Cleanup expired guest invitations (runs daily)
 */
exports.cleanupExpiredInvitations = functions.scheduler.onSchedule(
  'every 24 hours',
  async (event) => {
    try {
      console.log('🧹 Cleaning up expired guest invitations');
      const now = admin.firestore.Timestamp.now();
      const expiredQuery = await admin.firestore()
        .collection('guestInvitations')
        .where('expiresAt', '<', now)
        .get();

      const batch = admin.firestore().batch();
      expiredQuery.docs.forEach(doc => {
        batch.delete(doc.ref);
      });

      await batch.commit();
      console.log(`✅ Cleaned up ${expiredQuery.size} expired guest invitations`);
      return null;
    } catch (error) {
      console.error('❌ Error cleaning up invitations:', error);
      return null;
    }
  }
);

/**
 * Handle short guest invitation links
 * GET /g/:inviteCode
 */
exports.joinGuest = onRequest(async (req, res) => {
  try {
    // Extract invite code from path
    const pathParts = req.path.split('/');
    const inviteCode = pathParts[pathParts.length - 1];
    
    if (!inviteCode) {
      res.status(400).send('Invalid invitation link');
      return;
    }

    // Preview-safe behavior: only claim on POST. For GET/HEAD, render a minimal HTML page
    // that requires an explicit user tap to POST and claim the invite. This avoids iOS
    // link preview bots (Messages/Safari/Mail) consuming the invite prematurely.
    if (req.method !== 'POST') {
      try {
        // Look up the invitation to show some friendly info without claiming it
        const previewQuery = await admin.firestore()
          .collection('guestInvitations')
          .where('inviteCode', '==', inviteCode)
          .limit(1)
          .get();

        // Do not reveal sensitive info; just show a generic prompt
        res.set('Cache-Control', 'no-store, no-cache, max-age=0, must-revalidate');
        res.set('Content-Type', 'text/html; charset=utf-8');
        return res.status(200).send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Join Call</title>
  <meta name="robots" content="noindex,nofollow" />
  <meta http-equiv="Cache-Control" content="no-store" />
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #1b1c1e; color: #F4F4F5; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 24px; }
    .logo { width: 200px; height: auto; max-width: 90%; margin: 0 auto 40px; display: block; }
    .card { max-width: 520px; width: 100%; padding: 48px 40px; border-radius: 16px; background: rgba(126, 129, 131, 0.1); text-align: center; }
    p { color: #F4F4F5; font-size: 18px; margin-bottom: 24px; line-height: 1.6; }
    button { background: #6B7FB8; color: #F4F4F5; border: 0; border-radius: 30px; padding: 16px 40px; font-size: 18px; font-weight: 600; cursor: pointer; width: 100%; transition: all 0.3s ease; box-shadow: 0 4px 12px rgba(107, 127, 184, 0.3); }
    button:hover { background: #7589C4; transform: translateY(-2px); box-shadow: 0 6px 20px rgba(107, 127, 184, 0.5); }
    button:active { transform: translateY(0); }
    button:disabled { opacity: 0.6; cursor: not-allowed; }
    .note { font-size: 14px; color: #A0A2A6; margin-top: 16px; }
    .error { color: #EF4444; margin-top: 16px; display: none; background: rgba(239, 68, 68, 0.1); padding: 12px; border-radius: 8px; border: 1px solid rgba(239, 68, 68, 0.3); }
  </style>
  <script>
    async function join() {
      const btn = document.getElementById('joinBtn');
      const err = document.getElementById('err');
      btn.disabled = true; btn.textContent = 'Joining...';
      try {
        const resp = await fetch(window.location.href, { method: 'POST', headers: { 'Content-Type': 'application/json' } });
        if (resp.redirected) {
          // Successful claim will redirect to join page
          window.location.href = resp.url;
          return;
        }
        if (!resp.ok) {
          const text = await resp.text();
          err.textContent = text || 'Failed to process invitation';
          err.style.display = 'block';
          btn.disabled = false; btn.textContent = 'Join Call';
          return;
        }
        // If no redirect but OK, reload (defensive)
        window.location.reload();
      } catch (e) {
        err.textContent = 'Network error. Please try again.';
        err.style.display = 'block';
        btn.disabled = false; btn.textContent = 'Join Call';
      }
    }
  </script>
  <meta property="og:title" content="Join Call" />
  <meta property="og:description" content="Tap to join the call." />
  <meta property="og:type" content="website" />
  <meta name="apple-itunes-app" content="app-argument=join" />
  <!-- Intentionally minimal: link preview bots won't execute JS or POST -->
  
</head>
<body>
  <img src="https://vchat-46b32.web.app/splash-logo.png" alt="Très³" class="logo" onerror="this.style.display='none'" />
  <div class="card">
    <p>Tap the button below to join the call.</p>
    ${previewQuery.empty ? '<p class="note">If this link doesn\'t work, it may have expired. Ask the host for a new link.</p>' : ''}
    <button id="joinBtn" onclick="join()">Join Call</button>
    <div id="err" class="error"></div>
  </div>
</body>
</html>`);
      } catch (e) {
        // Fail closed but still do not claim
        res.status(200).send('Open this link in your browser and tap Join to continue.');
      }
      return;
    }

    // Look up invitation by code
    const invitationsQuery = await admin.firestore()
      .collection('guestInvitations')
      .where('inviteCode', '==', inviteCode)
      .limit(1)
      .get();

    if (invitationsQuery.empty) {
      res.status(404).send('Invitation not found or expired');
      return;
    }

    const invitation = invitationsQuery.docs[0].data();
    const invitationId = invitationsQuery.docs[0].id;
    
    // Check if expired (quick fail before transaction)
    if (invitation.expiresAt.toMillis() < Date.now()) {
      res.status(410).send('This invitation has expired');
      return;
    }
    
    // DON'T check 'used' flag here - only check inside transaction to prevent race conditions

    console.log(`🔔 Guest ${invitation.guestName} is joining. Attempting to claim invite for: ${invitation.hostUserId}`);

    const inviteRef = invitationsQuery.docs[0].ref;

    // Atomically claim the invitation using a transaction to prevent races/duplicate uses
    try {
      await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(inviteRef);
        if (!snap.exists) {
          throw new Error('Invitation document disappeared');
        }

        const inv = snap.data();
        // Check expiration and used flag inside transaction (ONLY place to check 'used')
        if (inv.expiresAt && inv.expiresAt.toMillis && inv.expiresAt.toMillis() < Date.now()) {
          throw new Error('Invitation expired');
        }
        if (inv.used === true) {
          throw new Error('Invitation already used');
        }

        // Mark as used with server timestamp
        tx.update(inviteRef, {
          used: true,
          usedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });

      console.log('✅ Invitation claimed atomically');

      // Fetch host FCM token (after claiming to ensure single-use semantics)
      const hostUserDoc = await admin.firestore().collection('users').doc(invitation.hostUserId).get();
      const fcmToken = hostUserDoc.data()?.fcmToken;

      console.log('Host user data:', hostUserDoc.exists ? 'exists' : 'NOT FOUND');
      console.log('FCM token exists:', !!fcmToken);
      if (fcmToken) console.log('FCM token (first 5 chars):', fcmToken.substring(0, 5) + '...');

      if (fcmToken) {
        console.log('📤 Sending notification to host (notification+data fallback)');

        // Build message with both notification and data: notification ensures OS will show UI when app is killed;
        // data lets the app handle the event when it's in foreground/background and receives data.
        const messagePayload = {
          token: fcmToken,
          notification: {
            title: `${invitation.guestName} is requesting to join`,
            body: 'Tap to answer',
          },
          data: {
            type: 'guest_joining',
            guestName: invitation.guestName,
            roomName: invitation.roomName,
            invitationId: invitationId,
            token: invitation.token || '',
            url: invitation.wsUrl || LIVEKIT_WS_URL
          },
          android: {
            priority: 'high',
            ttl: 60 * 1000 // 60 seconds TTL for call invitations
          }
        };

        try {
          const resp = await admin.messaging().send(messagePayload);
          console.log('✅ Notification sent to host, response:', resp);
        } catch (sendErr) {
          console.error('❌ Failed to send notification to host:', sendErr);
          await queueFailedNotification(messagePayload, sendErr, {
            guestName: invitation.guestName,
            roomName: invitation.roomName,
            invitationId: invitationId,
            hostUserId: invitation.hostUserId
          });
        }
      } else {
        console.warn('⚠️ Host has no FCM token');
      }

      // Redirect to join page with token (guest always gets redirected)
      const redirectUrl = `${WEB_URL}/join.html?token=${encodeURIComponent(invitation.token)}&url=${encodeURIComponent(invitation.wsUrl)}`;
      res.redirect(redirectUrl);

    } catch (claimErr) {
      console.error('❌ Failed to claim invitation atomically:', claimErr);
      console.error('   Invite code:', inviteCode);
      console.error('   User-Agent:', req.get('user-agent'));
      console.error('   IP:', req.ip);
      
      // If claim failed due to already used/expired, return appropriate HTTP status
      const errMsg = String(claimErr.message || claimErr);
      if (errMsg.includes('already used')) {
        res.status(410).send('This invitation has already been used. Please ask for a NEW link (do not reuse old links from chat history).');
      } else if (errMsg.includes('expired')) {
        res.status(410).send('This invitation has expired');
      } else {
        res.status(500).send('Error processing invitation');
      }
      return;
    }
    
  } catch (error) {
    console.error('Error handling guest invitation:', error);
    res.status(500).send('Error processing invitation');
  }
});

// Debug endpoints removed for security.

// Export retry queue functions
exports.retryFailedNotifications = retryFailedNotifications;
exports.cleanupOldNotifications = cleanupOldNotifications;

/**
 * Cloud Function: Start LiveKit Egress recording
 * Called by client to start server-side recording of a room
 */
exports.startRecording = functions.https.onCall(async (requestOrData, context) => {
  const request = normalizeCallableRequest(requestOrData, context);
  console.log('=== startRecording Function Called ===');
  
  // Verify user is authenticated
  if (!request.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to start recording'
    );
  }

  const { roomName, fileName, callId } = request.data;
  console.log('Parameters - roomName:', roomName, 'fileName:', fileName, 'callId:', callId);

  if (!roomName || !fileName || !callId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'roomName, fileName, and callId are required'
    );
  }

  try {
    const apiKey = LIVEKIT_API_KEY;
    const apiSecret = LIVEKIT_API_SECRET;
    const httpUrl = LIVEKIT_HTTP_URL;

    if (!apiKey || !apiSecret) {
      throw new Error('LiveKit credentials not configured');
    }

    console.log('Creating Egress client...');
    const egressClient = new EgressClient(httpUrl, apiKey, apiSecret);

    // Start room composite egress (records entire room)
    const fileOutput = new EncodedFileOutput({
      fileType: 'MP4',
      filepath: `recordings/${fileName}`,
    });

    const request = new RoomCompositeEgressRequest({
      roomName,
      layout: 'grid',
      output: fileOutput,
    });

    console.log('Starting room composite egress...');
    const egress = await egressClient.startRoomCompositeEgress(request);
    
    console.log('✅ Recording started, egress ID:', egress.egressId);

    // Save metadata to Firestore
    await admin.firestore().collection('recordings').add({
      callId,
      egressId: egress.egressId,
      roomName,
      fileName,
      userId: request.auth.uid,
      status: 'recording',
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      egressId: egress.egressId,
    };

  } catch (error) {
    console.error('ERROR starting recording:', error.message);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to start recording: ${error.message}`
    );
  }
});

/**
 * Cloud Function: Stop LiveKit Egress recording
 * Called by client to stop an ongoing recording
 */
exports.stopRecording = functions.https.onCall(async (requestOrData, context) => {
  const request = normalizeCallableRequest(requestOrData, context);
  console.log('=== stopRecording Function Called ===');
  
  // Verify user is authenticated
  if (!request.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to stop recording'
    );
  }

  const { egressId } = request.data;
  console.log('Parameters - egressId:', egressId);

  if (!egressId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'egressId is required'
    );
  }

  try {
    const apiKey = LIVEKIT_API_KEY;
    const apiSecret = LIVEKIT_API_SECRET;
    const httpUrl = LIVEKIT_HTTP_URL;

    if (!apiKey || !apiSecret) {
      throw new Error('LiveKit credentials not configured');
    }

    console.log('Creating Egress client...');
    const egressClient = new EgressClient(httpUrl, apiKey, apiSecret);

    console.log('Stopping egress...');
    const egress = await egressClient.stopEgress(egressId);
    
    console.log('✅ Recording stopped, egress ID:', egress.egressId);

    // Update Firestore metadata
    const recordingQuery = await admin.firestore()
      .collection('recordings')
      .where('egressId', '==', egressId)
      .limit(1)
      .get();

    if (!recordingQuery.empty) {
      await recordingQuery.docs[0].ref.update({
        status: 'stopped',
        stoppedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return {
      success: true,
      egressId: egress.egressId,
    };

  } catch (error) {
    console.error('ERROR stopping recording:', error.message);
    throw new functions.https.HttpsError(
      'internal',
      `Failed to stop recording: ${error.message}`
    );
  }
});

exports.cleanupStaleCallSessions = onSchedule('every 15 minutes', async () => {
    const staleThresholdMs = STALE_SESSION_MINUTES * 60 * 1000;
    const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - staleThresholdMs);

    try {
      const snapshot = await admin.firestore()
        .collection('call_sessions')
        .where('status', '==', 'active')
        .where('lastHeartbeat', '<', cutoff)
        .limit(200)
        .get();

      if (snapshot.empty) {
        console.log('No stale call sessions found.');
        return null;
      }

      const batch = admin.firestore().batch();
      snapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: 'ended',
          endTime: admin.firestore.FieldValue.serverTimestamp(),
          endedBy: 'system',
          endedReason: 'heartbeat_timeout',
        });
      });

      await batch.commit();
      console.log(`Cleaned up ${snapshot.docs.length} stale call sessions.`);
      return null;
    } catch (error) {
      console.error('cleanupStaleCallSessions error:', error);
      return null;
    }
  });
