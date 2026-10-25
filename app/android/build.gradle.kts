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

// package:jni 1.1.0 pins compileSdk 35. The android-35 platform in this SDK is
// incomplete (no android.jar or core-for-system-modules.jar), so AGP's
// androidJdkImage file provider stays empty and
// :jni:compileDebugJavaWithJavac cannot be configured. Compile that library
// against the app compileSdk, which is a complete platform. Namespace and
// ndkVersion on :jni are already set.
subprojects {
    if (name != "jni") {
        return@subprojects
    }
    afterEvaluate {
        val appAndroid = rootProject.project(":app").extensions.findByName("android")
            ?: return@afterEvaluate
        val appCompileSdk = appAndroid.javaClass.methods
            .firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
            ?.invoke(appAndroid) as? Int
            ?: return@afterEvaluate
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        androidExt.javaClass.methods
            .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
            ?.invoke(androidExt, appCompileSdk)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
