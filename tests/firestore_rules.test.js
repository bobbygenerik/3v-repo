const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test, before, after } = require('node:test');
const { doc, setDoc, getDoc } = require('firebase/firestore');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const hasEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const projectId = `rules-${Date.now()}`;
const rulesPath = path.join(__dirname, '..', 'firestore.rules');

let testEnv;

if (!hasEmulator) {
  test('firestore rules (skipped - emulator not running)', { skip: true }, () => {});
} else {
  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId,
      firestore: {
        rules: readFileSync(rulesPath, 'utf8'),
      },
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  test('participants can create call_sessions', async () => {
    const db = testEnv.authenticatedContext('user-1').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'call_sessions', 'session-1'), {
        participants: ['user-1', 'user-2'],
        status: 'active',
        roomName: 'room-1',
      }),
    );
  });

  test('non-participants cannot read call_sessions', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(doc(adminDb, 'call_sessions', 'session-2'), {
        participants: ['user-1'],
        status: 'ended',
        roomName: 'room-2',
      });
    });

    const db = testEnv.authenticatedContext('user-3').firestore();
    await assertFails(getDoc(doc(db, 'call_sessions', 'session-2')));
  });

  test('caller or recipient can read call_invitations', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(doc(adminDb, 'call_invitations', 'invite-1'), {
        callerId: 'user-1',
        recipientId: 'user-2',
        status: 'pending',
      });
    });

    const recipientDb = testEnv.authenticatedContext('user-2').firestore();
    await assertSucceeds(getDoc(doc(recipientDb, 'call_invitations', 'invite-1')));
  });
}
