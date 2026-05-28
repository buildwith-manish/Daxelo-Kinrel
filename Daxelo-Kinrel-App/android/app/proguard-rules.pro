# ════════════════════════════════════════════════════════════════════
# DAXELO KINREL — ProGuard / R8 Rules
#
# CRITICAL: This file prevents R8 from stripping classes that are
# accessed via reflection, FFI, or platform channels at runtime.
# Missing rules cause blank screen on release builds!
# ════════════════════════════════════════════════════════════════════

# ── General: Keep all attributes needed for reflection ────────────
-keepattributes Signature
-keepattributes Exceptions
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ── Flutter ──────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── Isar Database (CRITICAL — uses FFI + code generation) ───────
# Isar uses native FFI bindings and generated code that R8 WILL strip
# without these rules, causing instant crash on launch.
-keep class isar.** { *; }
-keep class com.isar.** { *; }
-keep @isar.Collection class * { *; }
-keepclassmembers class * { @isar.* <methods>; }
# Keep all Isar-generated classes (they end in "Schema" or are in isar collections)
-keep class **.isar.** { *; }
-keep class * extends isar.IsarCollection { *; }
-keepclassmembers class * { *** isarId; }
-keepclassmembers class * { *** index; }
# Keep Isar FFI native bindings
-keep class de.isar.** { *; }
-keep class com.github.isar.** { *; }
# Keep all classes with Isar annotations (reflection-based)
-keep @interface isar.** { *; }
-keep class * { @isar.Id <fields>; @isar.Index <fields>; @isar.Collection <fields>; }

# ── Hive ─────────────────────────────────────────────────────────
-keep class * extends com.hivedb.hive.** { *; }
-keepclassmembers class * { @com.hivedb.hive.** <methods>; }
# Hive uses type adapters via reflection
-keep class * extends com.hivedb.hive.TypeAdapter { *; }
-keep class * implements com.hivedb.hive.TypeAdapter { *; }
-dontwarn com.hivedb.**

# ── Dio / OkHttp ────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class com.squareup.okhttp.** { *; }
-dontwarn com.squareup.okhttp.**

# ── Retrofit (if used with Dio) ─────────────────────────────────
-keep class retrofit2.** { *; }

# ── flutter_secure_storage ───────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin { *; }

# ── Socket.io client ────────────────────────────────────────────
-keep class io.socket.** { *; }
-dontwarn io.socket.**

# ── Google Fonts ─────────────────────────────────────────────────
-keep class com.google_fonts.** { *; }
-keep class io.material.material_color_utilities.** { *; }

# ── Supabase (CRITICAL — uses reflection for JSON serialization) ─
-keep class io.supabase.** { *; }
-keep class com.supabase.** { *; }
-keep class com.postgrest.** { *; }
-keep class com.gotrue.** { *; }
-keep class com.storage.** { *; }
-keep class com.realtime.** { *; }
-keep class com.functions.** { *; }
# Supabase Realtime uses Phoenix channels
-keep class com.fasterxml.jackson.** { *; }
-keep class io.phoenix.** { *; }
-dontwarn io.phoenix.**

# ── Firebase (CRITICAL — missing rules cause runtime crashes) ────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.crashlytics.** { *; }
-keep class com.google.firebase.analytics.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.remoteconfig.** { *; }
-keep class com.google.firebase.inject.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class com.google.firebase.platforminfo.** { *; }
# Firebase uses reflection for component discovery
-keepclassmembers class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# ── path_provider (CRITICAL — used by Isar, Hive, etc.) ─────────
# If path_provider's platform channel is stripped, Isar init crashes
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class com.example.pathprovider.** { *; }

# ── connectivity_plus (CRITICAL — used by ConnectivityInterceptor) ─
-keep class dev.connectivity_plus.** { *; }
-keep class com.example.connectivity_plus.** { *; }
-dontwarn dev.connectivity_plus.**

# ── shared_preferences ───────────────────────────────────────────
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.example.shared_preferences.** { *; }

# ── permission_handler ───────────────────────────────────────────
-keep class com.permission_handler.** { *; }
-keep class dev.permission_handler.** { *; }

# ── image_picker ─────────────────────────────────────────────────
-keep class com.example.image_picker.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }

# ── image_cropper ────────────────────────────────────────────────
-keep class com.canhub.cropper.** { *; }
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# ── url_launcher ─────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }

# ── share_plus ───────────────────────────────────────────────────
-keep class dev.share_plus.** { *; }

# ── package_info_plus ────────────────────────────────────────────
-keep class dev.package_info_plus.** { *; }

# ── in_app_review ────────────────────────────────────────────────
-keep class dev.in_app_review.** { *; }

# ── local_auth ───────────────────────────────────────────────────
-keep class io.flutter.plugins.localauth.** { *; }

# ── webview_flutter ──────────────────────────────────────────────
-keep class io.flutter.plugins.webviewflutter.** { *; }

# ── cached_network_image ─────────────────────────────────────────
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**

# ── flutter_local_notifications ──────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class dev.flutter_local_notifications.** { *; }

# ── app_links (deep linking) ─────────────────────────────────────
-keep class com.example.app_links.** { *; }

# ── Gson / JSON serialization ────────────────────────────────────
-keep class sun.misc.Unsafe { *; }

# ── QR Code ──────────────────────────────────────────────────────
-keep class com.example.qr_flutter.** { *; }

# ── General Android ──────────────────────────────────────────────
-keep class * extends java.lang.annotation.Annotation { *; }
-keepclassmembers class **.R$* { public static <fields>; }
-keep class * implements android.os.Parcelable { public static final ** CREATOR; }

# ── Play Core ────────────────────────────────────────────────────
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# ── Kotlin Coroutines (used by many plugins) ─────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

# ── Keep all Dart FFI native bindings (critical for Isar) ────────
-keep class * implements dart.ffi.** { *; }
-keep class **_bindings.** { *; }

# ── Gson / JSON: Prevent stripping model classes used by reflection ─
# Keep all model classes that are serialized/deserialized
-keep class com.daxelo.kinrel.** { *; }
-keep class **.model.** { *; }
-keep class **.models.** { *; }
-keep class **.dto.** { *; }

# ── Disable warnings for libraries we can't control ──────────────
-dontwarn javax.annotation.**
-dontwarn kotlin.Unit
-dontwarn retrofit2.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn sun.misc.**
-dontwarn com.google.common.**
