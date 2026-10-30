allprojects {
    repositories {
        google()
        mavenCentral()
    }
    extra.set("compileSdkVersion", 34)
    extra.set("targetSdkVersion", 34)
    extra.set("minSdkVersion", 21)
    extra.set("flutter", mapOf(
        "compileSdkVersion" to 34,
        "targetSdkVersion" to 34,
        "minSdkVersion" to 21
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
