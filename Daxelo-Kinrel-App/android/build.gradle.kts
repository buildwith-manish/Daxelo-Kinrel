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
// 1) pluginManager.withPlugin: fires when com.android.library is applied,
//    BEFORE the subproject's own android {} block runs — good for namespace
//    injection which only needs a value, not a compileSdk override.
//
// 2) afterEvaluate: fires AFTER the subproject's android {} block has set
//    compileSdk = 30 (or similar). We override it here because the
//    checkReleaseAarMetadata task reads compileSdk at execution time, not
//    configuration time — so late overrides still take effect.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.findByType<com.android.build.gradle.LibraryExtension>()
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

    // Force compileSdk = 36 for all Android library subprojects.
    // Must run AFTER the subproject's own build.gradle so we override
    // any compileSdk < 34 set by legacy plugins.
    afterEvaluate {
        val androidExt = extensions.findByType<com.android.build.gradle.LibraryExtension>()
        if (androidExt != null && androidExt.compileSdk < 34) {
            androidExt.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
