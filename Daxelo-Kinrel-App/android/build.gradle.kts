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
// Some Flutter plugins may not declare a namespace or compile against
// a recent enough SDK. Inject namespace and bump compileSdk if needed.
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

    // Force compileSdk = 35 for all Android library subprojects whose
    // compileSdk < 34. Must run AFTER the subproject's own android {} block.
    if (project.state.executed) {
        val androidExt = extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
        if (androidExt != null && (androidExt.compileSdk ?: 0) < 34) {
            androidExt.compileSdk = 35
        }
    } else {
        afterEvaluate {
            val androidExt = extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
            if (androidExt != null && (androidExt.compileSdk ?: 0) < 34) {
                androidExt.compileSdk = 35
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
