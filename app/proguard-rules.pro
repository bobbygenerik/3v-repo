## Keep rules for legacy Jitsi (no longer used, safe to keep)
-keep class org.jitsi.** { *; }

## Keep commonly used third-party packages (broad keep kept from earlier setup)
-keep class com.facebook.** { *; }
-keep class com.** { *; }

## Avoid warnings for legacy HTTP and Facebook
-dontwarn org.apache.http.**
-dontwarn com.facebook.**

## WebRTC: keep all classes and avoid warnings. In release builds, R8 may rename
## or strip members used by native code or reflection inside the library.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
