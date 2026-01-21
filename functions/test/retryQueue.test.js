const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');
const admin = require('firebase-admin');

// Initialize mocks
const mockBatch = {
  update: () => {},
  delete: () => {},
  commit: async () => {},
};

const mockDoc = (data, id) => ({
  id: id || 'doc1',
  data: () => data,
  ref: { id: id || 'doc1' },
});

const mockSnapshot = (docs) => ({
  empty: docs.length === 0,
  size: docs.length,
  docs: docs,
});

const mockCollection = {
  add: async (data) => ({ id: 'new-doc-id' }),
  where: function() { return this; },
  limit: function() { return this; },
  get: async () => mockSnapshot([]),
};

const mockFirestore = {
  collection: () => mockCollection,
  batch: () => mockBatch,
};

// Mock Timestamp and FieldValue
mockFirestore.Timestamp = {
  fromMillis: (ms) => ({ toMillis: () => ms }),
  now: () => ({ toMillis: () => Date.now() }),
};
mockFirestore.FieldValue = {
  serverTimestamp: () => 'SERVER_TIMESTAMP',
};

const mockMessaging = {
  send: async () => 'msg-id',
};

// Override admin methods
// Using defineProperty to ensure we overwrite any getters
Object.defineProperty(admin, 'firestore', {
  value: () => mockFirestore,
  writable: true,
  configurable: true,
});
Object.assign(admin.firestore, mockFirestore);

Object.defineProperty(admin, 'messaging', {
  value: () => mockMessaging,
  writable: true,
  configurable: true,
});

// Stub initializeApp to prevent errors if called
admin.initializeApp = () => {};

// Import the module under test AFTER mocking
const retryQueue = require('../retryQueue');
const fft = functionsTest();

test('queueFailedNotification adds document to Firestore', async () => {
  let addedData = null;
  // Override add for this test
  mockCollection.add = async (data) => {
    addedData = data;
    return { id: 'test-id' };
  };

  // Verify mock is active
  try {
    const db = admin.firestore();
    if (db !== mockFirestore) {
      console.log('WARNING: admin.firestore() did not return mockFirestore');
    }
  } catch (e) {
    console.log('ERROR calling admin.firestore():', e.message);
  }

  const id = await retryQueue.queueFailedNotification({ foo: 'bar' }, new Error('test error'));

  assert.equal(id, 'test-id');
  assert.equal(addedData.messagePayload.foo, 'bar');
  assert.equal(addedData.error.message, 'test error');
  assert.equal(addedData.status, 'pending');
});

test('retryFailedNotifications processes pending notifications successfully', async () => {
  // Setup mock data
  const pendingDocs = [
    mockDoc({
      attemptCount: 0,
      maxAttempts: 5,
      messagePayload: { token: 't1' },
      nextRetryAt: { toMillis: () => Date.now() - 1000 },
    }, 'doc1'),
  ];

  // Override get for this test
  mockCollection.get = async () => mockSnapshot(pendingDocs);

  let sentMessage = null;
  mockMessaging.send = async (msg) => {
    sentMessage = msg;
    return 'msg-id-1';
  };

  let batchUpdates = [];
  mockBatch.update = (ref, data) => {
    batchUpdates.push({ ref, data });
  };

  const wrapped = fft.wrap(retryQueue.retryFailedNotifications);
  await wrapped({});

  assert.ok(sentMessage, 'Should have sent a message');
  assert.equal(sentMessage.token, 't1');
  assert.equal(batchUpdates.length, 1, 'Should update 1 document');
  assert.equal(batchUpdates[0].data.status, 'completed');
  assert.equal(batchUpdates[0].data.attemptCount, 1);
});

test('retryFailedNotifications handles failure and schedules retry', async () => {
  // Setup mock data
  const pendingDocs = [
    mockDoc({
      attemptCount: 1,
      maxAttempts: 5,
      messagePayload: { token: 't2' },
      nextRetryAt: { toMillis: () => Date.now() - 1000 },
    }, 'doc2'),
  ];

  mockCollection.get = async () => mockSnapshot(pendingDocs);

  mockMessaging.send = async () => {
    throw new Error('FCM Error');
  };

  let batchUpdates = [];
  mockBatch.update = (ref, data) => {
    batchUpdates.push({ ref, data });
  };

  const wrapped = fft.wrap(retryQueue.retryFailedNotifications);
  await wrapped({});

  assert.equal(batchUpdates.length, 1);
  // Should not be completed or failed, but have nextRetryAt
  assert.equal(batchUpdates[0].data.status, undefined);
  assert.equal(batchUpdates[0].data.attemptCount, 2);
  assert.ok(batchUpdates[0].data.nextRetryAt);
  assert.equal(batchUpdates[0].data.lastError, 'FCM Error');
});

test('retryFailedNotifications marks as failed after max attempts', async () => {
  // Setup mock data
  const pendingDocs = [
    mockDoc({
      attemptCount: 4, // Next will be 5
      maxAttempts: 5,
      messagePayload: { token: 't3' },
      nextRetryAt: { toMillis: () => Date.now() - 1000 },
    }, 'doc3'),
  ];

  mockCollection.get = async () => mockSnapshot(pendingDocs);

  mockMessaging.send = async () => {
    throw new Error('FCM Error');
  };

  let batchUpdates = [];
  mockBatch.update = (ref, data) => {
    batchUpdates.push({ ref, data });
  };

  const wrapped = fft.wrap(retryQueue.retryFailedNotifications);
  await wrapped({});

  assert.equal(batchUpdates.length, 1);
  assert.equal(batchUpdates[0].data.status, 'failed');
  assert.equal(batchUpdates[0].data.attemptCount, 5);
});

test.after(() => {
  fft.cleanup();
});
