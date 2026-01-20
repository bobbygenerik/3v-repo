## 2024-05-23 - Firestore N+1 Query Anti-Pattern
**Learning:** The codebase frequently uses sequential `await` loops to fetch related documents (N+1 problem), particularly for loading user details in lists (contacts, call history). This causes significant latency as each document fetch waits for the previous one to complete.
**Action:** Always look for loops containing `await FirebaseFirestore.instance...get()` and replace them with `whereIn` batching (chunks of 10) or `Future.wait` for parallel execution. Prioritize `whereIn` with `FieldPath.documentId` to reduce read operations.
