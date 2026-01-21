## 2025-12-13 - Avatar Optimization Strategy
**Learning:** The app crops user-uploaded avatars to 400x400 squares before uploading. This allows us to safely use `memCacheWidth` and `memCacheHeight` in `CachedNetworkImage` (set to `radius * 6` to cover high density) without fear of distortion for these images.
**Action:** When optimizing image loading, check if the source aspect ratio is enforced by the uploader logic.
