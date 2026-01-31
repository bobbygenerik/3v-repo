const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// Mock data
const users = [
  { id: 'user1' },
  { id: 'user2' },
  { id: 'user3' }
];

const callSignals = {
  'user1': [
    { id: 'sig1_old', data: { timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000) } }, // 2 hours ago
    { id: 'sig1_new', data: { timestamp: new Date() } }
  ],
  'user2': [
    { id: 'sig2_old1', data: { timestamp: new Date(Date.now() - 3 * 60 * 60 * 1000) } }, // 3 hours ago
    { id: 'sig2_old2', data: { timestamp: new Date(Date.now() - 4 * 60 * 60 * 1000) } }  // 4 hours ago
  ],
  'user3': []
};

// Counters
let queriesCount = 0;
let deletedCount = 0;

function createQueryMock(collectionId, parentDocId, isGroup = false) {
  let filteredDocs = [];

  if (collectionId === 'callSignals') {
    if (isGroup) {
      Object.keys(callSignals).forEach(uid => {
        filteredDocs = filteredDocs.concat(callSignals[uid].map(doc => ({...doc, uid})));
      });
    } else if (parentDocId) {
       filteredDocs = callSignals[parentDocId] || [];
       // Add uid to docs for consistency
       filteredDocs = filteredDocs.map(d => ({...d, uid: parentDocId}));
    }
  }

  const queryObj = {
    where: (field, op, value) => {
       if (field === 'timestamp' && op === '<') {
         filteredDocs = filteredDocs.filter(d => d.data.timestamp < value);
       }
       return queryObj; // Return self for chaining if needed, but 'get' is what we want next
    },
    limit: (val) => {
        return queryObj;
    },
    get: async () => {
       queriesCount++;
       return {
         size: filteredDocs.length,
         empty: filteredDocs.length === 0,
         docs: filteredDocs.map(d => ({
           id: d.id,
           ref: { path: `users/${d.uid}/callSignals/${d.id}` },
           data: () => d.data
         })),
         forEach: (cb) => filteredDocs.map(d => ({
           id: d.id,
           ref: { path: `users/${d.uid}/callSignals/${d.id}` },
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
    if (path === 'users') {
      return {
        get: async () => {
          queriesCount++;
          return {
            docs: users.map(u => ({ id: u.id, ref: { id: u.id } })),
            forEach: (cb) => users.map(u => ({ id: u.id, ref: { id: u.id } })).forEach(cb)
          };
        },
        doc: (docId) => {
             return {
               collection: (subPath) => createQueryMock(subPath, docId)
             };
        }
      };
    }
    // Fallback
    return {
      doc: (docId) => ({
        collection: (subPath) => createQueryMock(subPath, docId)
      })
    };
  },
  collectionGroup: (id) => {
    return createQueryMock(id, null, true);
  },
  batch: () => ({
    delete: (ref) => {
      deletedCount++;
    },
    update: (ref, data) => {},
    commit: async () => {}
  })
};

// Load functions first so admin.initializeApp() runs
const functions = require('../index');

// Override admin.firestore AFTER initializeApp
// We use Object.defineProperty because admin.firestore might be a getter or non-writable
try {
  Object.defineProperty(admin, 'firestore', {
    value: () => mockFirestore,
    writable: true,
    configurable: true
  });
} catch (e) {
  console.error('Failed to overwrite admin.firestore', e);
}

admin.firestore.Timestamp = {
    fromMillis: (ms) => new Date(ms),
    now: () => new Date()
};

const fft = functionsTest();

test('cleanupOldCallSignals performance benchmark', async (t) => {
    // Reset counters
    queriesCount = 0;
    deletedCount = 0;

    // Use scheduler wrapper if possible, or just call logic if extracted.
    // onSchedule creates a function that takes an event.
    const wrapped = fft.wrap(functions.cleanupOldCallSignals);

    await wrapped({});

    console.log(`Queries made: ${queriesCount}`);
    console.log(`Documents deleted: ${deletedCount}`);

    // Verify logic correctness
    assert.equal(deletedCount, 3, 'Should delete 3 old signals');

    // Assert the optimized behavior
    console.log(`Optimization check: Made ${queriesCount} queries (expected 1).`);
    assert.equal(queriesCount, 1, 'Should make only 1 query (collectionGroup)');
});

test.after(() => {
  fft.cleanup();
});
