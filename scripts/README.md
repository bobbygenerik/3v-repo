Cleanup scripts
----------------

`cleanup-duplicate-contacts.js` — scan Firestore `users/{uid}/contacts` for duplicate contacts and optionally remove duplicates.

Usage
-----

1. Ensure you have a Firebase service account JSON and set the environment variable:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
```

2. Install dependencies (this script uses `firebase-admin` and `minimist`):

```bash
# from repo root
cd scripts
npm install firebase-admin minimist
```

3. Dry-run (report only):

```bash
node cleanup-duplicate-contacts.js
```

4. To actually delete duplicates (keeps earliest entry):

```bash
node cleanup-duplicate-contacts.js --fix
```

Notes
-----
- The script resolves contact documents to an email by either treating the document id as the referenced user id or by checking common fields (`uid`, `contactUid`, `email`).
- It is best to run a dry-run first to review changes the script will make.
