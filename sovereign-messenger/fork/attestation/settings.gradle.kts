pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "sovereign-attestation-alpha"

include(":auditor-alpha")
project(":auditor-alpha").projectDir = file("vendor/Auditor/app")

include(":smoke")

