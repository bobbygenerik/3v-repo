const test = require('node:test');
const assert = require('node:assert/strict');
const functionsTest = require('firebase-functions-test');

process.env.LIVEKIT_API_KEY = 'test-key';
process.env.LIVEKIT_API_SECRET = 'test-secret';

const admin = require('firebase-admin');
const functions = require('../index');

admin.firestore = () => ({
  collection: () => ({
    doc: () => ({
      get: async () => ({
        data: () => ({ displayName: 'Test User' }),
      }),
    }),
  }),
});

const fft = functionsTest();
const wrapped = fft.wrap(functions.getLiveKitToken);

test('getLiveKitToken rejects unauthenticated calls', async () => {
  await assert.rejects(
    () => wrapped({ calleeId: 'user-2', roomName: 'room-1' }, {}),
    (err) => err && err.code === 'unauthenticated',
  );
});

test('getLiveKitToken rejects missing parameters', async () => {
  await assert.rejects(
    () => wrapped({ roomName: 'room-1' }, { auth: { uid: 'user-1' } }),
    (err) => err && err.code === 'invalid-argument',
  );
});

test('getLiveKitToken returns token for valid request', async () => {
  const result = await wrapped(
    { calleeId: 'user-2', roomName: 'room-1' },
    { auth: { uid: 'user-1' } },
  );

  assert.ok(result.token);
  assert.equal(result.wsUrl, 'wss://livekit.iptvsubz.fun');
});

test.after(() => {
  fft.cleanup();
});
