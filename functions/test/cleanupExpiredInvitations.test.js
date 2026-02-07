const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// 1. Mock Setup
let limitCalledWith = null;
let batchCommitCalled = 0;
let docsDeleted = 0;

const mockDocs = Array.from({ length: 10 }).map((_, i) => ({
  id: `doc_${i}`,
  ref: { id: `doc_${i}` },
  data: () => ({})
}));

const mockQuery = {
  where: function() { return this; },
  limit: function(n) {
    limitCalledWith = n;
    return this;
  },
  get: async function() {
    return {
      size: mockDocs.length,
      empty: mockDocs.length === 0,
      docs: mockDocs,
      forEach: (cb) => mockDocs.forEach(cb)
    };
  }
};

const mockCollection = {
  where: function() { return mockQuery; } // initial where
};

const mockFirestore = {
  collection: (name) => {
    if (name === 'guestInvitations') return mockCollection;
    return { where: () => ({ get: async () => ({ empty: true }) }) };
  },
  batch: () => ({
    delete: (ref) => { docsDeleted++; },
    commit: async () => { batchCommitCalled++; }
  }),
  Timestamp: {
    now: () => 'NOW'
  }
};

// Override admin.firestore
try {
  Object.defineProperty(admin, 'firestore', {
    value: () => mockFirestore,
    writable: true,
    configurable: true
  });
  Object.assign(admin.firestore, mockFirestore);
} catch (e) {}

admin.initializeApp = () => {};

// Import functions
const myFunctions = require('../index');
const fft = functionsTest();

test('cleanupExpiredInvitations should be optimized', async (t) => {
  // Reset spies
  limitCalledWith = null;
  batchCommitCalled = 0;
  docsDeleted = 0;

  const wrapped = fft.wrap(myFunctions.cleanupExpiredInvitations);
  await wrapped({});

  // Current behavior (Unoptimized)
  // It fetches all docs and deletes them.
  assert.equal(docsDeleted, 10);
  assert.equal(batchCommitCalled, 1);

  // OPTIMIZATION TARGET:
  // We want to see limit() being called.
  console.log(`Limit called with: ${limitCalledWith}`);

  assert.equal(limitCalledWith, 300, 'Should use limit(300)');
  assert.equal(docsDeleted, 10, 'Should delete all 10 documents');
});

test.after(() => {
  fft.cleanup();
});
