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

// ─── Namespace injection for legacy Flutter plugins ──────────────────────
// AGP 9.0+ requires every Android library to declare a namespace.
// Some older plugins (e.g. isar_flutter_libs 3.1.0) only specify the
// deprecated `package` attribute in AndroidManifest.xml.
// Using pluginManager.withPlugin fires immediately when the library plugin
// is applied — BEFORE the variant builder is created — so the namespace
// is available during AGP's strict configuration check.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.findByType<com.android.build.gradle.LibraryExtension>()
        if (androidExt != null && androidExt.namespace == null) {
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
