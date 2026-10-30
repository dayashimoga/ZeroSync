allprojects {
    repositories {
        google()
        mavenCentral()
    }
    extra.set("compileSdkVersion", 34)
    extra.set("targetSdkVersion", 34)
    extra.set("minSdkVersion", 21)
    extra.set("ndkVersion", "28.2.13676358")
    extra.set("flutter", mapOf(
        "compileSdkVersion" to 34,
        "targetSdkVersion" to 34,
        "minSdkVersion" to 21,
        "ndkVersion" to "28.2.13676358"
    ))
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
    if (project.name != "app") {
        val appAndroid = project(":app").extensions.findByName("android")
        val appNdk = try {
            appAndroid?.javaClass?.getMethod("getNdkVersion")?.invoke(appAndroid) as? String
        } catch (_: Exception) {
            null
        } ?: "28.2.13676358"
        extra.set("flutter", mapOf(
            "compileSdkVersion" to 34,
            "targetSdkVersion" to 34,
            "minSdkVersion" to 21,
            "ndkVersion" to appNdk
        ))
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
