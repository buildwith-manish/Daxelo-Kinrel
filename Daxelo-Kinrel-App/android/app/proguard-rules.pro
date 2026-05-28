# ── Flutter ──────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── Isar ─────────────────────────────────────────────────────────
-keep class isar.** { *; }
-keep class com.isar.** { *; }
-keep @isar.Collection class * { *; }
-keepclassmembers class * { @isar.* <methods>; }

# ── Hive ─────────────────────────────────────────────────────────
-keep class * extends com.hivedb.hive.** { *; }
-keepclassmembers class * { @com.hivedb.hive.** <methods>; }

# ── Dio / OkHttp ────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class com.squareup.okhttp.** { *; }
-dontwarn com.squareup.okhttp.**

# ── Retrofit (if used with Dio) ─────────────────────────────────
-keepattributes Signature
-keepattributes Exceptions
-keep class retrofit2.** { *; }

# ── flutter_secure_storage ───────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin { *; }

# ── Socket.io client ────────────────────────────────────────────
-keep class io.socket.** { *; }
-keep class com.squareup.okhttp.** { *; }
-dontwarn io.socket.**

# ── Google Fonts ─────────────────────────────────────────────────
-keep class com.google_fonts.** { *; }
-keep class io.material.material_color_utilities.** { *; }

# ── Supabase ─────────────────────────────────────────────────────
-keep class io.supabase.** { *; }
-keep class com.supabase.** { *; }
-keep class com.postgrest.** { *; }
-keep class com.gotrue.** { *; }
-keep class com.storage.** { *; }
-keep class com.realtime.** { *; }
-keep class com.functions.** { *; }

# ── Gson / JSON serialization ────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }

# ── General Android ──────────────────────────────────────────────
-keep class * extends java.lang.annotation.Annotation { *; }
-keepclassmembers class **.R$* { public static <fields>; }
-keep class * implements android.os.Parcelable { public static final ** CREATOR; }
