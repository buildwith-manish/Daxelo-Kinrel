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
// don't meet these requirements. This block injects namespace from
// AndroidManifest.xml and forces compileSdk = 36 for all library subprojects.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.findByType<com.android.build.gradle.LibraryExtension>()
        if (androidExt != null) {
            // Force compileSdk 36 so transitive deps (androidx.fragment 1.7+,
            // androidx.window 1.2+) don't fail the AAR metadata check.
            androidExt.compileSdk = 36

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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
