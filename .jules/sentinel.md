## 2024-05-23 - [Unsecured Debug Endpoints]
**Vulnerability:** Publicly accessible HTTP Cloud Functions (`onRequest`) were created for debugging purposes (`debugGetFcmToken`, `debugSendTestNotification`) that exposed sensitive user data (FCM tokens) and functionality (sending notifications) without any authentication or authorization.
**Learning:** Developers often create "temporary" debug endpoints to bypass auth complexities during development but forget to remove them or secure them. `onRequest` functions are public by default.
**Prevention:**
1. Never commit debug endpoints to the main branch.
2. If debug endpoints are needed in dev, use `if (process.env.FUNCTIONS_EMULATOR)` checks or dedicated auth middleware.
3. Use `onCall` instead of `onRequest` where possible as it provides built-in auth context.
