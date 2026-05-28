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

// ─── Compatibility fixes for legacy Flutter plugins ─────────────────────
// AGP 9.0+ requires every Android library to declare a namespace and
// compile against API 34+. Some older plugins (e.g. isar_flutter_libs 3.1.0)
// don't meet these requirements.
//
// Strategy: use pluginManager.withPlugin for namespace injection (fires when
// the library plugin is applied, before the subproject's android block runs),
// and a guarded afterEvaluate for compileSdk override (fires after the
// subproject's android block sets compileSdk=30, so our override wins).
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
        if (androidExt != null) {
            // Inject namespace from AndroidManifest.xml if not declared.
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
        }
    }

    // Force compileSdk = 36 for all Android library subprojects whose
    // compileSdk < 34 (e.g. isar_flutter_libs at 30). Must run AFTER the
    // subproject's own android {} block to win the override.
    // Guard: evaluationDependsOn(":app") can cause :app to be already
    // evaluated when we reach this point, so skip afterEvaluate for it.
    if (project.state.executed) {
        val androidExt = extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
        if (androidExt != null && (androidExt.compileSdk ?: 0) < 34) {
            androidExt.compileSdk = 36
        }
    } else {
        afterEvaluate {
            val androidExt = extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
            if (androidExt != null && (androidExt.compileSdk ?: 0) < 34) {
                androidExt.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
