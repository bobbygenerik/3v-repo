# Sentinel Journal 🛡️

## 2024-05-22 - Public Read Access to Guest Tokens
**Vulnerability:** The `guestInvitations` collection in `firestore.rules` allowed public read access (`allow read: if true;`). This collection contains sensitive `token` fields (LiveKit JWTs) that allow anyone to join a video call if they can guess or list the invitation ID.
**Learning:** Comments like "token validation happens in client" are dangerous red flags. While the client might validate the token *after* reading it, the act of reading it exposes the secret. Security must be enforced at the database level (Firestore Rules), not just the client.
**Prevention:** Never allow public read access to collections containing secrets (tokens, keys, PII). Use Cloud Functions for public-facing "join" flows where validation is required before granting access.
---
## 2024-05-23 - [Unsecured Debug Endpoints]
**Vulnerability:** Publicly accessible HTTP Cloud Functions (`onRequest`) were created for debugging purposes (`debugGetFcmToken`, `debugSendTestNotification`) that exposed sensitive user data (FCM tokens) and functionality (sending notifications) without any authentication or authorization.
**Learning:** Developers often create "temporary" debug endpoints to bypass auth complexities during development but forget to remove them or secure them. `onRequest` functions are public by default.
**Prevention:**
1. Never commit debug endpoints to the main branch.
2. If debug endpoints are needed in dev, use `if (process.env.FUNCTIONS_EMULATOR)` checks or dedicated auth middleware.
3. Use `onCall` instead of `onRequest` where possible as it provides built-in auth context.
