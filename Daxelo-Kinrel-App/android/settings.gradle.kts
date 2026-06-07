pluginManagement {
    val flutterSdkPath =
        run {
            val localPropertiesFile = file("local.properties")
            var sdkPath: String? = null
            if (localPropertiesFile.exists()) {
                localPropertiesFile.forEachLine { line ->
                    val trimmed = line.trim()
                    if (trimmed.startsWith("flutter.sdk=")) {
                        sdkPath = trimmed.substringAfter("flutter.sdk=").trim()
                    }
                }
            }
            require(sdkPath != null) { "flutter.sdk not set in local.properties" }
            sdkPath!!
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Firebase — Google Services & Crashlytics plugins (Android)
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
}

include(":app")
