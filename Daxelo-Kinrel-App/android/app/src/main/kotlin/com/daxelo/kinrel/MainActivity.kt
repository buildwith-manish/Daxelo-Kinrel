package com.daxelo.kinrel

import android.app.ActivityManager
import android.content.Context
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
                    else -> result.notImplemented()
                }
            }
    }
}
