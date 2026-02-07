const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// Configuration
const NUM_DOCS = 1200;
const BATCH_SIZE = 500;

// Mock data
const callSignals = [];
for (let i = 0; i < NUM_DOCS; i++) {
  callSignals.push({
    id: `sig_${i}`,
    data: { timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000) } // 2 hours ago (old)
  });
}

// Counters
let queriesCount = 0;
let deletedCount = 0;
let maxDocsPerQuery = 0;

function createQueryMock(collectionId, parentDocId, isGroup = false) {
  let filteredDocs = [];

  if (collectionId === 'callSignals') {
    filteredDocs = callSignals.map(d => ({...d, uid: 'user_x'}));
  }

  let limitVal = null;

  const queryObj = {
    where: (field, op, value) => {
       if (field === 'timestamp' && op === '<') {
         filteredDocs = filteredDocs.filter(d => d.data.timestamp < value);
       }
       return queryObj;
    },
    limit: (val) => {
        limitVal = val;
        return queryObj;
    },
    get: async () => {
       queriesCount++;

       // 1. Filter out deleted docs (simulating DB state)
       let resultDocs = filteredDocs.filter(d => !deletedIds.has(d.id));

       // 2. Apply limit
       if (limitVal !== null) {
           resultDocs = resultDocs.slice(0, limitVal);
       }

       if (resultDocs.length > maxDocsPerQuery) {
           maxDocsPerQuery = resultDocs.length;
       }

       return {
         size: resultDocs.length,
         empty: resultDocs.length === 0,
         docs: resultDocs.map(d => ({
           id: d.id,
           ref: { path: `users/${d.uid}/callSignals/${d.id}`, id: d.id },
           data: () => d.data
         })),
         forEach: (cb) => resultDocs.map(d => ({
           id: d.id,
           ref: { path: `users/${d.uid}/callSignals/${d.id}`, id: d.id },
           data: () => d.data
         })).forEach(cb)
       };
    }
  };
  return queryObj;
}

const deletedIds = new Set();

// Mock Firestore
const mockFirestore = {
  collectionGroup: (id) => {
    return createQueryMock(id, null, true);
  },
  batch: () => ({
    delete: (ref) => {
      deletedCount++;
      // Parse ID from path or use ref.id if available
      // In my mock above, ref has .id
      if (ref.id) {
          deletedIds.add(ref.id);
      }
    },
    commit: async () => {}
  })
};

// Load functions
const functions = require('../index');

// Override admin.firestore
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

test('cleanupOldCallSignals pagination benchmark', async (t) => {
    // Reset counters
    queriesCount = 0;
    deletedCount = 0;
    maxDocsPerQuery = 0;
    deletedIds.clear();

    const wrapped = fft.wrap(functions.cleanupOldCallSignals);

    await wrapped({});

    console.log(`Queries made: ${queriesCount}`);
    console.log(`Documents deleted: ${deletedCount}`);
    console.log(`Max docs per query: ${maxDocsPerQuery}`);

    assert.equal(deletedCount, NUM_DOCS, 'Should delete all old signals');

    // AFTER OPTIMIZATION EXPECTATIONS:
    // 1st query: 500 docs -> deleted
    // 2nd query: 500 docs -> deleted
    // 3rd query: 200 docs -> deleted
    // 4th query: 0 docs -> stop
    // Total 4 queries.
    assert.ok(queriesCount >= 3, `Should make multiple queries (got ${queriesCount})`);
    assert.equal(maxDocsPerQuery, BATCH_SIZE, `Max docs per query should be capped at ${BATCH_SIZE}`);
});

test.after(() => {
  fft.cleanup();
});
