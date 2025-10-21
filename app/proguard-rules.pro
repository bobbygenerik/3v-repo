# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

## Fix R8 missing class error for Guava reflection
-dontwarn java.lang.reflect.AnnotatedType
-keep class java.lang.reflect.** { *; }

## Keep Google Common (Guava)
-keep class com.google.common.** { *; }
-dontwarn com.google.common.**

## Keep LiveKit
-keep class io.livekit.** { *; }
-dontwarn io.livekit.**

## Keep WebRTC - critical for video calling
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keepclasseswithmembernames class * {
    native <methods>;
}

## Keep Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

## Keep rules for legacy Jitsi (no longer used, safe to keep)
-keep class org.jitsi.** { *; }

## Keep commonly used third-party packages
-keep class com.facebook.** { *; }

## Avoid warnings for legacy HTTP and Facebook
-dontwarn org.apache.http.**
-dontwarn com.facebook.**

## Prevent R8/ProGuard from stripping app activities - FIXED PACKAGE NAME
-keep public class com.example.tres3.MainActivity { *; }
-keep public class com.example.tres3.** { *; }
-keep public class * extends android.app.Activity
-keep public class * extends androidx.activity.ComponentActivity
-keep public class * extends androidx.appcompat.app.AppCompatActivity

## Keep Compose
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**

## Keep Kotlin
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

## Keep serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

## Keep data classes
-keep @kotlinx.serialization.Serializable class com.example.tres3.** {
    *;
}

## Timber logging
-keep class timber.log.** { *; }
-dontwarn timber.log.**

## Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

## Keep custom views
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}