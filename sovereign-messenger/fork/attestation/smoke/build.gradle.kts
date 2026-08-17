plugins {
    id("com.android.application")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

android {
    namespace = "org.example.sovereign.attestation.smoke"
    compileSdk = 36
    buildToolsVersion = "36.1.0"

    defaultConfig {
        applicationId = "org.example.sovereign.attestation.smoke"
        minSdk = 33
        targetSdk = 36
        versionCode = 1
        versionName = "0.1-alpha"
    }
}

dependencies {
    implementation(project(":auditor-alpha"))
}

