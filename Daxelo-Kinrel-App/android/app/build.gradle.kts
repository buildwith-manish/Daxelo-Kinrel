plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase — Google Services & Crashlytics
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// ─── Signing Config ──────────────────────────────────────────────────────
// Read key.properties for release signing (CI / local builds)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystorePropertiesMap = mutableMapOf<String, String>()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.forEachLine { line ->
        val trimmed = line.trim()
        if (trimmed.isNotEmpty() && !trimmed.startsWith("#")) {
            val keyValue = trimmed.split("=", limit = 2)
            if (keyValue.size == 2) {
                keystorePropertiesMap[keyValue[0].trim()] = keyValue[1].trim()
            }
        }
    }
}

android {
    namespace = "com.daxelo.kinrel"
    compileSdk = 36

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.daxelo.kinrel"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Let Flutter handle ABI filtering automatically via --split-per-abi
        // or --target-platform flags. DO NOT set ndk.abiFilters here —
        // it conflicts with the Flutter Gradle plugin's own ABI filtering.
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystorePropertiesMap["keyAlias"]
                keyPassword = keystorePropertiesMap["keyPassword"]
                storeFile = file(keystorePropertiesMap["storeFile"] ?: "keystore.jks")
                storePassword = keystorePropertiesMap["storePassword"]
            }
        }
    }

    buildTypes {
        release {
            // Use release signing when key.properties exists; fall back to debug
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // ProGuard / R8 minification enabled for smaller APK
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
