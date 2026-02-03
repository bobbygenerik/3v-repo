## 2025-12-13 - Avatar Optimization Strategy
**Learning:** The app crops user-uploaded avatars to 400x400 squares before uploading. This allows us to safely use `memCacheWidth` and `memCacheHeight` in `CachedNetworkImage` (set to `radius * 6` to cover high density) without fear of distortion for these images.
**Action:** When optimizing image loading, check if the source aspect ratio is enforced by the uploader logic.

## 2024-05-23 - Firestore N+1 Query Anti-Pattern
**Learning:** The codebase frequently uses sequential `await` loops to fetch related documents (N+1 problem), particularly for loading user details in lists (contacts, call history). This causes significant latency as each document fetch waits for the previous one to complete.
**Action:** Always look for loops containing `await FirebaseFirestore.instance...get()` and replace them with `whereIn` batching (chunks of 10) or `Future.wait` for parallel execution. Prioritize `whereIn` with `FieldPath.documentId` to reduce read operations.

## 2024-05-22 - Periodic Timers on UI Thread
**Learning:** Running high-frequency timers (e.g., 30Hz) on the UI thread to "detect" lag or manage stabilization is an anti-pattern. It adds overhead to the very thread it's trying to monitor and can contribute to the performance issues it aims to solve.
**Action:** Use native frame metrics or low-overhead performance observers instead of polling loops on the main thread. Avoid "optimizations" that do nothing but log.

## 2025-12-14 - Isolate Type Safety
**Learning:** When using `compute` to run code in an isolate, generic types in return values (like `Map<String, double?>`) are lost during serialization and become `Map<dynamic, dynamic>`. This causes runtime errors if strict casting (`as Map<String, double?>`) is used without re-casting the contents.
**Action:** Always explicit cast the contents of Map/List results from isolates, e.g., `(result as Map).cast<String, double?>()`.
