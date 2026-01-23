const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// Mock data
const staleThresholdMs = 2 * 60 * 1000; // 2 minutes
const now = Date.now();
const staleTime = new Date(now - staleThresholdMs - 1000); // 1 second older than cutoff
const freshTime = new Date(now - 1000); // 1 second ago

const callSessions = [
  {
    id: 'session_stale',
    data: {
      status: 'active',
      lastHeartbeat: admin.firestore.Timestamp.fromMillis(staleTime.getTime())
    }
  },
  {
    id: 'session_fresh',
    data: {
      status: 'active',
      lastHeartbeat: admin.firestore.Timestamp.fromMillis(freshTime.getTime())
    }
  }
];

// Counters
let queriesCount = 0;
let updatedCount = 0;
let updatedDocs = [];

function createQueryMock(collectionId) {
  let filteredDocs = [];

  if (collectionId === 'call_sessions') {
     filteredDocs = callSessions;
  }

  const queryObj = {
    where: (field, op, value) => {
       if (field === 'status' && op === '==' && value === 'active') {
         filteredDocs = filteredDocs.filter(d => d.data.status === 'active');
       }
       if (field === 'lastHeartbeat' && op === '<') {
         // value is a Timestamp object
         const cutoffMillis = value.toMillis();
         filteredDocs = filteredDocs.filter(d => d.data.lastHeartbeat.toMillis() < cutoffMillis);
       }
       return queryObj;
    },
    limit: (n) => {
        // Mock limit
        return queryObj;
    },
    get: async () => {
       queriesCount++;
       return {
         size: filteredDocs.length,
         empty: filteredDocs.length === 0,
         docs: filteredDocs.map(d => ({
           id: d.id,
           ref: { path: `call_sessions/${d.id}` },
           data: () => d.data
         })),
         forEach: (cb) => filteredDocs.map(d => ({
           id: d.id,
           ref: { path: `call_sessions/${d.id}` },
           data: () => d.data
         })).forEach(cb)
       };
    }
  };
  return queryObj;
}

// Mock Firestore
const mockFirestore = {
  collection: (path) => {
    return createQueryMock(path);
  },
  batch: () => ({
    update: (ref, data) => {
      updatedCount++;
      updatedDocs.push({ path: ref.path, data });
    },
    commit: async () => {}
  })
};

// Load functions first so admin.initializeApp() runs
const functions = require('../index');

// Override admin.firestore
try {
  Object.defineProperty(admin, 'firestore', {
    value: () => mockFirestore,
    writable: true,
    configurable: true
  });
  // Also need to support Timestamp on the function call
  admin.firestore.Timestamp = {
      fromMillis: (ms) => ({ toMillis: () => ms }),
      now: () => ({ toMillis: () => Date.now() })
  };
  admin.firestore.FieldValue = {
      serverTimestamp: () => 'SERVER_TIMESTAMP'
  };
} catch (e) {
  console.error('Failed to overwrite admin.firestore', e);
}

const fft = functionsTest();

test('cleanupStaleCallSessions logic check', async (t) => {
    // Reset counters
    queriesCount = 0;
    updatedCount = 0;
    updatedDocs = [];

    const wrapped = fft.wrap(functions.cleanupStaleCallSessions);

    await wrapped({});

    console.log(`Queries made: ${queriesCount}`);
    console.log(`Documents updated: ${updatedCount}`);

    // Verify logic correctness
    assert.equal(updatedCount, 1, 'Should update 1 stale session');
    assert.equal(updatedDocs[0].path, 'call_sessions/session_stale', 'Should update the stale session');
    assert.equal(updatedDocs[0].data.status, 'ended', 'Should mark status as ended');
    assert.equal(updatedDocs[0].data.endedReason, 'heartbeat_timeout', 'Should have correct ended reason (from second declaration)');
});

test.after(() => {
  fft.cleanup();
});
