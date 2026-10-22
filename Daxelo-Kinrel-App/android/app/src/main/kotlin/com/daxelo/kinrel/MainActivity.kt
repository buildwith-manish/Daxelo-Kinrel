package com.daxelo.kinrel

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "kinrel/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "memoryInfo" -> {
                        try {
                            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                            val mi = ActivityManager.MemoryInfo()
                            am.getMemoryInfo(mi)
                            // isLowRamDevice is the ActivityManager API
                            // (Android 8.0+ / API 26+) that returns true on
                            // Android-Go / low-RAM devices. Older devices
                            // fall through to the totalRamMb threshold check
                            // on the Dart side.
                            val isLowRamDevice = am.isLowRamDevice
                            // totalMem is in bytes; convert to MB.
                            val totalRamMb = (mi.totalMem / (1024L * 1024L)).toInt()
                            result.success(
                                mapOf(
                                    "totalRamMb" to totalRamMb,
                                    "isLowRamDevice" to isLowRamDevice
                                )
                            )
                        } catch (e: Exception) {
                            // Any failure (rare — only on extremely broken
                            // Android images) returns null so the Dart side
                            // falls back to lowRam=false.
                            result.error("MEMORY_INFO_FAILED", e.message, null)
                        }
                    }
                    // Phase 5: enable/disable the prediction-widget
                    // BroadcastReceiver + AppWidgetProvider at runtime via
                    // PackageManager.setComponentEnabledSetting.
                    //
                    // `enabled` corresponds to:
                    //   PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                    // `disabled` corresponds to:
                    //   PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                    //
                    // The component name is the AppWidgetProvider class
                    // (declared in AndroidManifest.xml). The Flutter side
                    // passes the fully-qualified class name; the Kotlin
                    // side constructs a ComponentName from it.
                    //
                    // This is the only way to fully hide a home-screen
                    // widget — adding/removing the widget from users'
                    // home screens can't be done programmatically, but
                    // disabling the component makes Android treat the
                    // widget as not installed, so it stops appearing in
                    // the widget picker and existing instances stop
                    // updating.
                    "setPredictionWidgetEnabled" -> {
                        val className = call.argument<String>("className")
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        if (className == null) {
                            result.error(
                                "INVALID_ARGUMENT",
                                "className is required",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val component = ComponentName(packageName, className)
                            val newState = if (enabled)
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                            else
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                            // DONT_KILL_APP avoids restarting the app
                            // process when toggling the component state.
                            packageManager.setComponentEnabledSetting(
                                component,
                                newState,
                                PackageManager.DONT_KILL_APP
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "PREDICTION_WIDGET_TOGGLE_FAILED",
                                e.message,
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
