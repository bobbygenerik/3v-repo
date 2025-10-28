const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

/**
 * Firebase Function to generate guest call tokens
 * Call from Android app:
 * 
 * val functions = Firebase.functions
 * val result = functions.getHttpsCallable("generateGuestToken")
 *     .call(mapOf(
 *         "roomName" to "room_123",
 *         "guestName" to "John Doe"
 *     ))
 *     .await()
 */
exports.generateGuestToken = functions.https.onCall(async (data, context) => {
    // Verify caller is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated', 
            'Must be logged in to generate guest links'
        );
    }

    const { roomName, guestName } = data;
    
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
        // Get LiveKit credentials from Firebase config
        // Set these with: firebase functions:config:set livekit.api_key="YOUR_KEY"
        const apiKey = functions.config().livekit?.api_key;
        const apiSecret = functions.config().livekit?.api_secret;
        const wsUrl = functions.config().livekit?.ws_url;
        const webUrl = functions.config().app?.web_url;

        if (!apiKey || !apiSecret || !wsUrl || !webUrl) {
            console.error('Missing LiveKit configuration');
            throw new functions.https.HttpsError(
                'failed-precondition',
                'LiveKit is not properly configured'
            );
        }

        // Create guest identity
        const guestIdentity = `guest_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        
        // Generate LiveKit access token
        const at = new AccessToken(apiKey, apiSecret, {
            identity: guestIdentity,
            name: guestName,
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

        const token = at.toJwt();
        
        // Generate shareable web link
        const link = `${webUrl}/join.html?token=${encodeURIComponent(token)}&url=${encodeURIComponent(wsUrl)}`;

        // Save invitation record to Firestore
        const invitationRef = await admin.firestore().collection('guestInvitations').add({
            roomName,
            guestName,
            guestIdentity,
            hostUserId: context.auth.uid,
            link,
            used: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400 * 1000) // 24 hours
        });

        console.log(`Generated guest token for ${guestName} in room ${roomName}`);

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
 * Optional: Cleanup expired guest invitations
 * Scheduled to run daily at midnight
 */
exports.cleanupExpiredInvitations = functions.pubsub
    .schedule('0 0 * * *')
    .timeZone('UTC')
    .onRun(async (context) => {
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
        console.log(`Cleaned up ${expiredQuery.size} expired guest invitations`);
        return null;
    });
