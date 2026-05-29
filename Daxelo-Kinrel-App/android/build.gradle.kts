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
// All subproject configuration that does NOT require afterEvaluate.
subprojects {
    // ── Force consistent Kotlin JVM target across all subprojects ─────
    // Without this, plugins like sentry_flutter may compile with a
    // different JVM target than the app (e.g., 1.8 vs 17).
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
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
            // Use withPlugin callback instead of afterEvaluate to avoid
            // "project already evaluated" error from evaluationDependsOn.
            if (androidExt.compileSdk ?: 0 < 34) {
                androidExt.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
