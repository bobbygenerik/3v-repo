# Sentinel Journal 🛡️

## 2024-05-22 - Public Read Access to Guest Tokens
**Vulnerability:** The `guestInvitations` collection in `firestore.rules` allowed public read access (`allow read: if true;`). This collection contains sensitive `token` fields (LiveKit JWTs) that allow anyone to join a video call if they can guess or list the invitation ID.
**Learning:** Comments like "token validation happens in client" are dangerous red flags. While the client might validate the token *after* reading it, the act of reading it exposes the secret. Security must be enforced at the database level (Firestore Rules), not just the client.
**Prevention:** Never allow public read access to collections containing secrets (tokens, keys, PII). Use Cloud Functions for public-facing "join" flows where validation is required before granting access.
