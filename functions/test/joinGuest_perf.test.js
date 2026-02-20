const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');
const { joinGuest } = require('../index');

// Mock dependencies
const fft = functionsTest();

// Mock console.log/error to reduce noise
const originalLog = console.log;
const originalError = console.error;
const originalWarn = console.warn;

test.before(() => {
  // console.log = () => {};
  // console.error = () => {};
  // console.warn = () => {};
});

test.after(() => {
  console.log = originalLog;
  console.error = originalError;
  console.warn = originalWarn;
  fft.cleanup();
});

test('joinGuest benchmark', async (t) => {
  // Mock data
  const inviteCode = 'TESTCODE';
  const invitationId = 'invitation-123';
  const hostUserId = 'host-user-123';
  const invitationData = {
    inviteCode,
    hostUserId,
    guestName: 'Guest',
    roomName: 'Room',
    token: 'token-123',
    wsUrl: 'wss://livekit.example.com',
    expiresAt: { toMillis: () => Date.now() + 100000 },
    used: false
  };
  const hostUserData = {
    fcmToken: 'fcm-token-123'
  };

  // Mock Admin SDK
  const mockAdmin = {
    firestore: () => ({
      collection: (name) => {
        if (name === 'guestInvitations') {
          return {
            where: () => ({
              limit: () => ({
                get: async () => {
                  await new Promise(resolve => setTimeout(resolve, 50)); // 50ms delay
                  return {
                    empty: false,
                    docs: [{
                      id: invitationId,
                      data: () => invitationData,
                      ref: { id: invitationId }
                    }]
                  };
                }
              })
            })
          };
        }
        if (name === 'users') {
          return {
            doc: (id) => {
              if (id === hostUserId) {
                return {
                  get: async () => {
                    await new Promise(resolve => setTimeout(resolve, 100)); // 100ms delay for host fetch
                    return {
                      exists: true,
                      data: () => hostUserData
                    };
                  }
                };
              }
              return { get: async () => ({ exists: false }) };
            }
          };
        }
        return { doc: () => ({ get: async () => ({ exists: false }) }) };
      },
      runTransaction: async (callback) => {
        // Simulate transaction delay
        await new Promise(resolve => setTimeout(resolve, 100)); // 100ms delay for transaction overhead

        // Mock transaction object
        const tx = {
          get: async () => {
            return {
              exists: true,
              data: () => invitationData
            };
          },
          update: () => {}
        };
        await callback(tx);
      }
    }),
    messaging: () => ({
      send: async () => {
        await new Promise(resolve => setTimeout(resolve, 10)); // 10ms delay
        return 'message-id';
      }
    })
  };

  // Override admin.firestore and admin.messaging
  const firestoreMockFn = mockAdmin.firestore;
  firestoreMockFn.Timestamp = { fromMillis: (ms) => ({ toMillis: () => ms }) };
  firestoreMockFn.FieldValue = { serverTimestamp: () => 'timestamp' };

  // Save original descriptors
  // Note: admin properties might be getters
  const originalFirestoreDesc = Object.getOwnPropertyDescriptor(admin, 'firestore');
  const originalMessagingDesc = Object.getOwnPropertyDescriptor(admin, 'messaging');

  // If descriptor is undefined, try storing value directly
  const originalFirestoreVal = admin.firestore;
  const originalMessagingVal = admin.messaging;

  // Force override using defineProperty for robustness
  Object.defineProperty(admin, 'firestore', {
    get: () => firestoreMockFn,
    configurable: true
  });

  Object.defineProperty(admin, 'messaging', {
    get: () => mockAdmin.messaging,
    configurable: true
  });

  try {
    const req = {
      method: 'POST',
      path: `/g/${inviteCode}`,
      get: () => 'user-agent',
      ip: '127.0.0.1'
    };

    const res = {
      status: (code) => ({ send: (msg) => {} }),
      redirect: (url) => {},
      set: () => {}
    };

    const start = Date.now();
    await joinGuest(req, res);
    const end = Date.now();
    const duration = end - start;

    console.log(`\n⏱️ joinGuest duration: ${duration}ms`);

  } finally {
    // Restore
    if (originalFirestoreDesc) {
        Object.defineProperty(admin, 'firestore', originalFirestoreDesc);
    } else {
        // If it was just a value or inherited
        try {
            delete admin.firestore; // remove own property
            // admin.firestore = originalFirestoreVal; // this might fail if it's read-only
        } catch(e) {}
    }

    if (originalMessagingDesc) {
        Object.defineProperty(admin, 'messaging', originalMessagingDesc);
    } else {
        try {
            delete admin.messaging;
        } catch(e) {}
    }
  }
});
