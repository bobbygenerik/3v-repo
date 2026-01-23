const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// Configuration
const NUM_DOCS = 1200; // Enough for 3 batches (500 + 500 + 200)
const COMMIT_DELAY_MS = 50; // Delay per commit to simulate latency

// Mock data
const staleDocs = [];
for (let i = 0; i < NUM_DOCS; i++) {
  staleDocs.push({
    id: `doc_${i}`,
    data: {
      status: 'pending',
      timestamp: new Date(Date.now() - 120 * 1000) // 2 minutes ago (stale)
    }
  });
}

// Counters
let queriesCount = 0;
let updatedCount = 0;
let commitCount = 0;
let maxConcurrentCommits = 0;
let currentConcurrentCommits = 0;

// Mock Firestore
const mockFirestore = {
  collectionGroup: (id) => {
    return {
      where: (field, op, value) => {
        return {
           where: (field2, op2, value2) => {
              return {
                 get: async () => {
                    queriesCount++;
                    return {
                      empty: staleDocs.length === 0,
                      docs: staleDocs.map(d => ({
                        id: d.id,
                        ref: { path: `callSignals/${d.id}` },
                        data: () => d.data
                      }))
                    };
                 }
              }
           }
        }
      }
    };
  },
  batch: () => ({
    update: (ref, data) => {
      updatedCount++;
    },
    commit: async () => {
      currentConcurrentCommits++;
      if (currentConcurrentCommits > maxConcurrentCommits) {
        maxConcurrentCommits = currentConcurrentCommits;
      }
      commitCount++;
      await new Promise(resolve => setTimeout(resolve, COMMIT_DELAY_MS));
      currentConcurrentCommits--;
    }
  }),
  // Initializer stubs
  settings: () => {},
};

// Also mock FieldValue
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
  // Re-attach properties that might be needed
  admin.firestore.FieldValue = {
      serverTimestamp: () => 'SERVER_TIMESTAMP'
  };
} catch (e) {
  console.error('Failed to overwrite admin.firestore', e);
}


const fft = functionsTest();

test('markStaleCallSignals performance benchmark', async (t) => {
    // Reset counters
    queriesCount = 0;
    updatedCount = 0;
    commitCount = 0;
    maxConcurrentCommits = 0;
    currentConcurrentCommits = 0;

    const wrapped = fft.wrap(functions.markStaleCallSignals);

    const start = Date.now();
    await wrapped({});
    const duration = Date.now() - start;

    console.log(`Execution time: ${duration}ms`);
    console.log(`Docs updated: ${updatedCount}`);
    console.log(`Commits made: ${commitCount}`);
    console.log(`Max concurrent commits: ${maxConcurrentCommits}`);

    assert.equal(updatedCount, NUM_DOCS, 'Should update all stale docs');
    assert.ok(commitCount >= 3, 'Should have multiple commits (chunks)');

    // We expect sequential execution for now
    // duration should be >= commitCount * COMMIT_DELAY_MS

    t.diagnostic(`Duration: ${duration}ms, MaxConcurrency: ${maxConcurrentCommits}`);
});

test.after(() => {
  fft.cleanup();
});
