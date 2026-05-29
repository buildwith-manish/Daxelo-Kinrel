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

    // ── Force Kotlin language version 1.8+ for all subprojects ─────
    // Kotlin 2.x no longer supports language version 1.6.
    // Some Flutter plugins (e.g. sentry_flutter) still declare
    // languageVersion = "1.6", which causes compilation failures.
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            languageVersion.set(
                org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
