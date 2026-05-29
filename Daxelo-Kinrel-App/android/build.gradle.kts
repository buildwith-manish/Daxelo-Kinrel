allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// ─── Compatibility fixes for Flutter plugins ────────────────────────
subprojects {
    // ── Force consistent JVM 17 target across all subprojects ──────────
    // Using Kotlin JVM Toolchain to ensure Java and Kotlin compile
    // with the same target. This prevents "Inconsistent JVM-target
    // compatibility" errors from plugins like in_app_review and
    // sentry_flutter that default to JVM 11 for Java.
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        extensions.findByType<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>()
            ?.jvmToolchain(17)
    }

    // ── Inject namespace for older Flutter plugins ────────────────────
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
        if (androidExt != null) {
            if (androidExt.namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val manifestText = manifestFile.readText()
                    val packageMatch = Regex("""package\s*=\s*"([^"]+)"""").find(manifestText)
                    if (packageMatch != null) {
                        androidExt.namespace = packageMatch.groupValues[1]
                    }
                }
            }

            // ── Force compileSdk = 36 for subprojects with old SDK ────
            // Flutter 3.44.0 requires compileSdk 36.
            if (androidExt.compileSdk ?: 0 < 34) {
                androidExt.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
