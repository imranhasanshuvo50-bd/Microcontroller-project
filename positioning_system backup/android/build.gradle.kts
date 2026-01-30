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

// Workaround for older plugins that don't declare an Android Gradle "namespace".
// (AGP 8+ requires it.)
subprojects {
    plugins.withId("com.android.library") {
        if (name == "flutter_bluetooth_serial") {
            val androidExt = extensions.findByName("android") ?: return@withId
            try {
                val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                setNamespace.invoke(androidExt, "io.github.edufolly.flutterbluetoothserial")
            } catch (_: Throwable) {
                // Ignore: if the method isn't available, AGP isn't enforcing namespace.
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
