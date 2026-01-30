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
    if (name != "flutter_bluetooth_serial") return@subprojects

    fun configureBluetoothSerialProject() {
        val androidExt = extensions.findByName("android") ?: return

        // Ensure the plugin has a namespace (AGP 8+ requirement).
        try {
            val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
            setNamespace.invoke(androidExt, "io.github.edufolly.flutterbluetoothserial")
        } catch (_: Throwable) {
            // Ignore: if the method isn't available, AGP isn't enforcing namespace.
        }

        // The plugin declares compileSdkVersion 30, which breaks with newer AndroidX resources
        // (e.g. android:attr/lStar). Force it to match the app's compileSdk.
        val appAndroid = rootProject.project(":app").extensions.findByName("android")
        val appCompileSdk: Int? =
            try {
                val getCompileSdk = appAndroid?.javaClass?.getMethod("getCompileSdk") ?: throw NoSuchMethodException()
                getCompileSdk.invoke(appAndroid) as? Int
            } catch (_: Throwable) {
                try {
                    val getCompileSdkVersion =
                        appAndroid?.javaClass?.getMethod("getCompileSdkVersion") ?: throw NoSuchMethodException()
                    val raw = getCompileSdkVersion.invoke(appAndroid)?.toString()
                    raw?.removePrefix("android-")?.toIntOrNull()
                } catch (_: Throwable) {
                    null
                }
            }

        val compileSdkToUse = appCompileSdk ?: 33
        val androidCompileSdkString = "android-$compileSdkToUse"

        fun tryInvoke(methodName: String, arg: Any) {
            try {
                val method = androidExt.javaClass.getMethod(methodName, arg.javaClass)
                method.invoke(androidExt, arg)
            } catch (_: Throwable) {
                // Ignore and try another API shape.
            }
        }

        fun tryInvokeInt(methodName: String, value: Int) {
            try {
                val method = androidExt.javaClass.getMethod(methodName, Int::class.javaPrimitiveType)
                method.invoke(androidExt, value)
            } catch (_: Throwable) {
                // Ignore and try another API shape.
            }
        }

        // Different AGP versions expose different APIs here.
        tryInvokeInt("setCompileSdk", compileSdkToUse)
        tryInvokeInt("setCompileSdkVersion", compileSdkToUse)
        tryInvokeInt("compileSdkVersion", compileSdkToUse)
        tryInvoke("setCompileSdkVersion", androidCompileSdkString)
        tryInvoke("compileSdkVersion", androidCompileSdkString)
    }

    if (state.executed) {
        configureBluetoothSerialProject()
    } else {
        afterEvaluate { configureBluetoothSerialProject() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
