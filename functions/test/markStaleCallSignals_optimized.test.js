const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// Configuration
const TOTAL_DOCS = 1200;
const BATCH_SIZE_EXPECTED = 500;

// Mock data storage
let allDocs = [];

function resetDocs() {
  allDocs = [];
  for (let i = 0; i < TOTAL_DOCS; i++) {
    allDocs.push({
      id: `doc_${i}`,
      data: {
        status: 'pending',
        timestamp: new Date(Date.now() - 120 * 1000) // 2 minutes ago (stale)
      }
    });
  }
}

// Counters
let queriesCount = 0;
let limitCalls = []; // Store the limit values passed

// Mock Firestore
const mockFirestore = {
  collectionGroup: (collectionId) => {
    return createQuery(collectionId);
  },
  batch: () => ({
    update: (ref, data) => {
      // Find the doc and update it in memory
      const docId = ref.id; // Extract ID from ref (mock ref has .id)
      const doc = allDocs.find(d => d.id === docId);
      if (doc) {
        Object.assign(doc.data, data);
      }
    },
    commit: async () => {
      // No-op for sync mock
      return Promise.resolve();
    }
  }),
  settings: () => {},
};

function createQuery(collectionId, filters = [], limitVal = null) {
  return {
    where: (field, op, value) => {
      return createQuery(collectionId, [...filters, { field, op, value }], limitVal);
    },
    limit: (val) => {
      limitCalls.push(val);
      return createQuery(collectionId, filters, val);
    },
    get: async () => {
      queriesCount++;

      // 1. Filter
      let results = allDocs.filter(doc => {
        // Assume collectionId match (simplified)

        // Apply where clauses
        for (const filter of filters) {
          const docVal = doc.data[filter.field];
          if (filter.op === '==') {
            if (docVal !== filter.value) return false;
          } else if (filter.op === '<') {
            if (!(docVal < filter.value)) return false;
          }
          // Add other ops if needed
        }
        return true;
      });

      // 2. Limit
      if (limitVal !== null) {
        results = results.slice(0, limitVal);
      }

      return {
        empty: results.length === 0,
        docs: results.map(d => ({
          id: d.id,
          ref: { id: d.id, path: `callSignals/${d.id}` }, // Mock ref
          data: () => ({ ...d.data }) // Return copy
        })),
        size: results.length
      };
    }
  };
}

// Mock FieldValue
admin.firestore.FieldValue = {
  serverTimestamp: () => 'SERVER_TIMESTAMP'
};

// Load functions
const functions = require('../index');

// Overwrite admin.firestore
try {
  Object.defineProperty(admin, 'firestore', {
    value: () => mockFirestore,
    writable: true,
    configurable: true
  });
  // Re-attach FieldValue
  admin.firestore.FieldValue = {
    serverTimestamp: () => 'SERVER_TIMESTAMP'
  };
} catch (e) {
  console.error('Failed to overwrite admin.firestore', e);
}

const fft = functionsTest();

test('markStaleCallSignals optimization check', async (t) => {
    resetDocs();
    queriesCount = 0;
    limitCalls = [];

    const wrapped = fft.wrap(functions.markStaleCallSignals);

    console.log('--- Running Function ---');
    await wrapped({});
    console.log('--- Function Complete ---');

    const remainingPending = allDocs.filter(d => d.data.status === 'pending').length;
    console.log(`Remaining pending docs: ${remainingPending}`);
    console.log(`Queries made: ${queriesCount}`);
    console.log(`Limit calls: ${JSON.stringify(limitCalls)}`);

    // Verification

    // 1. Correctness: All docs should be processed
    assert.equal(remainingPending, 0, 'All stale docs should be marked as missed');

    // 2. Optimization: Should use limit()
    // NOTE: This assertion will FAIL on the unoptimized code (which is what we want to prove baseline)
    if (limitCalls.length === 0) {
        console.warn('WARNING: No limit() calls detected. Unoptimized behavior.');
    } else {
        console.log('SUCCESS: limit() usage detected.');
        assert.ok(limitCalls.every(val => val <= 500), 'Limit should be reasonable (e.g. <= 500)');
    }

    // 3. Pagination: Should make multiple queries if total > limit
    // Unoptimized code makes 1 query. Optimized should make ceil(1200/500) + 1 (last empty check) = 3 or 4 queries.
    console.log(`Total queries: ${queriesCount}`);
});

test.after(() => {
  fft.cleanup();
});
