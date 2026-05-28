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
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.daxelo.kinrel"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    splits {
        // ABI splits configuration for smaller APKs
        // Using the new AGP 9.0 compatible syntax
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = false
        }
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

flutter {
    source = "../.."
}
