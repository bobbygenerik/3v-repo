# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# LiveKit optimizations
-keep class org.webrtc.** { *; }
-keep class io.livekit.** { *; }

# Firebase optimizations
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Remove debug logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
}

# Keep Play Core classes
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# LiteRT (on-device ML — formerly TensorFlow Lite)
-keep class com.google.ai.edge.litert.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn com.google.ai.edge.litert.**

# LiteRT GPU delegate native bindings
-keep class com.google.ai.edge.litert.gpu.** { *; }
-dontwarn com.google.ai.edge.litert.gpu.**

# LiteRT support library (TensorImage, ImageProcessor, etc.)
-keep class com.google.ai.edge.litert.support.** { *; }

# Suppress stale AutoValue/javax warnings from LiteRT transitive deps
-dontwarn javax.lang.model.SourceVersion
-dontwarn javax.lang.model.element.Element
-dontwarn javax.lang.model.element.ElementKind
-dontwarn javax.lang.model.type.TypeMirror
-dontwarn javax.lang.model.type.TypeVisitor
-dontwarn javax.lang.model.util.SimpleTypeVisitor8
