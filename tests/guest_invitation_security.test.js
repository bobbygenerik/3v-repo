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
const projectId = `rules-sentinel-${Date.now()}`;
const rulesPath = path.join(__dirname, '..', 'firestore.rules');

let testEnv;

if (!hasEmulator) {
  test('sentinel security tests (skipped - emulator not running)', { skip: true }, () => {});
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

  test('public user CANNOT read guest invitations', async () => {
    // Setup: Create an invitation as admin
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(doc(adminDb, 'guestInvitations', 'invite-public-test'), {
        hostUserId: 'host-123',
        token: 'secret-token',
        roomName: 'secret-room'
      });
    });

    // Attempt to read as unauthenticated user
    const unauthedDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(unauthedDb, 'guestInvitations', 'invite-public-test')));
  });

  test('host CAN read their own guest invitations', async () => {
     // Setup: Create an invitation as admin
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(doc(adminDb, 'guestInvitations', 'invite-host-test'), {
        hostUserId: 'host-123',
        token: 'secret-token'
      });
    });

    const hostDb = testEnv.authenticatedContext('host-123').firestore();
    await assertSucceeds(getDoc(doc(hostDb, 'guestInvitations', 'invite-host-test')));
  });
}
