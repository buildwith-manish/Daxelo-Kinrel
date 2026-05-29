# =============================================================================
# DAXELO KINREL — ProGuard / R8 Rules
# =============================================================================
# CRITICAL: The app namespace is com.daxelo.kinrel (see build.gradle.kts)
# With isMinifyEnabled=true + isShrinkResources=true, R8 will strip
# any classes not explicitly kept or reachable from entry points.
# =============================================================================

# ── Flutter ──────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── App Classes ──────────────────────────────────────────────────────────────
# MUST match the namespace in build.gradle.kts: com.daxelo.kinrel
-keep class com.daxelo.kinrel.** { *; }
-dontwarn com.daxelo.kinrel.**

# ── Firebase ─────────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Supabase / OkHttp / Retrofit ────────────────────────────────────────────
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class retrofit2.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**

# ── Kotlin ───────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ── Drift (SQLite ORM) ──────────────────────────────────────────────────────
# Drift generates .g.dart code that uses runtime type checks and mirrors.
# R8 must NOT strip the generated query classes or database classes.
-keep class * extends com.squareup.sqldelight.** { *; }
-keep class **.app_database.** { *; }
-keep class **.database.** { *; }
-keepclassmembers class **.app_database.** { *; }
-keepclassmembers class **.database.** { *; }
# Drift uses dart:ffi to call SQLite — keep JNI bridge classes
-keep class com.sqlite3_flutter_libs.** { *; }
-dontwarn com.sqlite3_flutter_libs.**

# ── SharedPreferences / Flutter Secure Storage ──────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ── Gson (used by some Firebase plugins) ────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-dontwarn sun.misc.Unsafe

# ── Protobuf / Protocol Buffers (used by Firebase) ─────────────────────────
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# ── AndroidX ─────────────────────────────────────────────────────────────────
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# ── Keep serialization-related annotations ──────────────────────────────────
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# ── WebRTC / Socket.IO ──────────────────────────────────────────────────────
-keep class io.socket.** { *; }
-dontwarn io.socket.**
-keep class org.json.** { *; }
-dontwarn org.json.**

# ── Desugaring (coreLibraryDesugaringEnabled) ───────────────────────────────
-dontwarn java.lang.invoke.StringConcatFactory
