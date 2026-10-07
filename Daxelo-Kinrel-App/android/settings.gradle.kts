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
        // PERF (raster audit): the maplibre_android 0.3.6 plugin's
        // build.gradle.kts applies `org.jlleitschuh.gradle.ktlint` —
        // a ktlint-enforcement plugin hosted on the
        // gradle-pluginguide.mozilla.org maven (a Mozilla-hosted
        // mirror) and on the ktlint plugin's own repository.
        // Without this entry the GitHub Actions profile-APK build
        // fails with "Plugin [id: 'org.jlleitschuh.gradle.ktlint']
        // was not found in any of the following sources".
        // Reference: https://github.com/JLLeitschuh/ktlint-gradle#installation
        maven("https://plugins.gradle.org/m2/")
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Firebase — Google Services & Crashlytics plugins (Android)
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
    // PERF (raster audit): maplibre_android 0.3.6's build.gradle.kts
    // applies `org.jlleitschuh.gradle.ktlint` WITHOUT a version. The
    // version must be declared here in the root project's plugins
    // block so the subproject plugin request resolves. Without this,
    // the GitHub Actions profile-APK build fails with:
    //   Plugin [id: 'org.jlleitschuh.gradle.ktlint'] was not found in
    //   any of the following sources … Plugin Repositories (plugin
    //   dependency must include a version number for this source).
    // 12.3.0 is the latest stable of ktlint-gradle as of Oct 2026.
    id("org.jlleitschuh.gradle.ktlint") version "12.3.0" apply false
}

include(":app")
