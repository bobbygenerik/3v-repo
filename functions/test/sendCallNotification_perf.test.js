const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// Configuration
const DB_READ_LATENCY_MS = 50; // Simulate 50ms database read latency

// Mock data
const recipientId = 'recipient_123';
const fcmToken = 'test_fcm_token_xyz';
const userDocData = {
  fcmToken: fcmToken,
  name: 'Test Recipient'
};

// Counters
let dbReadCount = 0;
let fcmSendCount = 0;

// Mock Firestore
const mockFirestore = {
  collection: (collectionName) => {
    if (collectionName === 'users') {
      return {
        doc: (docId) => {
          if (docId === recipientId) {
            return {
              get: async () => {
                dbReadCount++;
                // Simulate latency
                await new Promise(resolve => setTimeout(resolve, DB_READ_LATENCY_MS));
                return {
                  exists: true,
                  data: () => userDocData
                };
              }
            };
          }
          return {
            get: async () => {
              dbReadCount++;
              return { exists: false };
            }
          };
        }
      };
    } else if (collectionName === 'call_invitations') {
        return {
            doc: (docId) => ({
                update: async () => {}
            })
        }
    }
    return { doc: () => ({ get: async () => ({ exists: false }) }) };
  },
  // Initializer stubs
  settings: () => {},
};

// Mock Messaging
const mockMessaging = {
  send: async (message) => {
    fcmSendCount++;
    return 'projects/test-project/messages/test-message-id';
  }
};

// Preserve original Firestore types for firebase-functions-test
console.log('Original Timestamp:', admin.firestore.Timestamp);
console.log('Original GeoPoint:', admin.firestore.GeoPoint);

const OriginalTimestamp = admin.firestore.Timestamp;
const OriginalGeoPoint = admin.firestore.GeoPoint;
const OriginalFieldValue = admin.firestore.FieldValue;

// Also mock FieldValue
admin.firestore.FieldValue = {
  serverTimestamp: () => 'SERVER_TIMESTAMP'
};

// Load functions
const functions = require('../index');

// Overwrite admin.firestore and admin.messaging
try {
  Object.defineProperty(admin, 'firestore', {
    value: () => mockFirestore,
    writable: true,
    configurable: true
  });
  // Re-attach properties that might be needed
  admin.firestore.FieldValue = OriginalFieldValue || {
      serverTimestamp: () => 'SERVER_TIMESTAMP'
  };
  admin.firestore.Timestamp = OriginalTimestamp || class Timestamp {};
  admin.firestore.GeoPoint = OriginalGeoPoint || class GeoPoint {};

  Object.defineProperty(admin, 'messaging', {
    value: () => mockMessaging,
    writable: true,
    configurable: true
  });
} catch (e) {
  console.error('Failed to overwrite admin services', e);
}


const fft = functionsTest();

test('sendCallNotification performance benchmark', async (t) => {

    // Test Case 1: Baseline (No recipientFcmToken in callData)
    // ---------------------------------------------------------
    dbReadCount = 0;
    fcmSendCount = 0;

    const baselineStart = Date.now();

    // Construct the event manually to bypass fft's dependency on admin.firestore types
    const baselineEvent = {
        params: { invitationId: 'invite_1' },
        data: {
            data: () => ({
                callerName: 'Caller',
                recipientId: recipientId,
                status: 'pending',
                roomName: 'room_1',
                // recipientFcmToken is MISSING
            })
        }
    };

    // Invoke the function directly if possible, or use wrapped but pass specific event structure?
    // v2 functions from onDocumentCreated are just functions that take an event.
    // However, they are wrapped by the Firebase SDK.
    // functions.sendCallNotification is the exported function.

    // Assuming we can just call the handler if we could get it.
    // But since we can't easily extract the handler, we might have to rely on .run if it exists (it's a v2 feature).
    // Or just rely on the fact that the exported function IS the handler (plus some metadata).

    // Let's try calling it directly.
    try {
        await functions.sendCallNotification(baselineEvent);
    } catch (e) {
        // If it fails because it expects a certain structure or context, we'll see.
        console.log('Direct call failed, trying run method if available');
        if (functions.sendCallNotification.run) {
             await functions.sendCallNotification.run(baselineEvent);
        } else {
             throw e;
        }
    }

    const baselineDuration = Date.now() - baselineStart;

    console.log(`[Baseline] Duration: ${baselineDuration}ms`);
    console.log(`[Baseline] DB Reads: ${dbReadCount}`);

    assert.equal(dbReadCount, 1, 'Baseline should perform 1 DB read to fetch user token');
    assert.equal(fcmSendCount, 1, 'Should send notification');
    assert.ok(baselineDuration >= DB_READ_LATENCY_MS, 'Baseline duration should reflect DB latency');


    // Test Case 2: Optimized (With recipientFcmToken in callData)
    // -----------------------------------------------------------
    dbReadCount = 0;
    fcmSendCount = 0;

    const optimizedStart = Date.now();

    const optimizedEvent = {
        params: { invitationId: 'invite_2' },
        data: {
            data: () => ({
                callerName: 'Caller',
                recipientId: recipientId,
                status: 'pending',
                roomName: 'room_2',
                recipientFcmToken: fcmToken // Token provided!
            })
        }
    };

    if (functions.sendCallNotification.run) {
         await functions.sendCallNotification.run(optimizedEvent);
    } else {
         await functions.sendCallNotification(optimizedEvent);
    }

    const optimizedDuration = Date.now() - optimizedStart;

    console.log(`[Optimized] Duration: ${optimizedDuration}ms`);
    console.log(`[Optimized] DB Reads: ${dbReadCount}`);

    // Optimized path should NOT perform DB read
    assert.equal(dbReadCount, 0, 'Optimized path should NOT perform DB read');

    t.diagnostic(`Baseline: ${baselineDuration}ms, Optimized: ${optimizedDuration}ms`);
});

test.after(() => {
  fft.cleanup();
});
