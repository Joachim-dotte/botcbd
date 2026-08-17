plugins {
    id("com.android.library")
    kotlin("android")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

android {
    compileSdk = 36
    buildToolsVersion = "36.1.0"

    namespace = "app.attestation.auditor"

    defaultConfig {
        // Java records are native from API 34. This GrapheneOS/Pixel-only alpha
        // intentionally fails installation on older, unsupported platform releases.
        minSdk = 34
        consumerProguardFiles("proguard-rules.pro")
        resourceConfigurations += listOf("en")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    packaging {
        resources.excludes.addAll(listOf(
            "META-INF/versions/*/OSGI-INF/MANIFEST.MF",
            "org/bouncycastle/pqc/**.properties",
            "org/bouncycastle/x509/**.properties",
        ))
    }

    androidResources {
        noCompress += listOf("dex")
    }
}

// SimpleX v7 registers a root-level KotlinCompile rule with JVM 11 for every
// subproject. Configure the concrete Auditor tasks after that shared rule so
// their Kotlin bytecode remains aligned with the Java 17 toolchain above.
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.core:core:1.18.0")
    implementation("androidx.preference:preference:1.2.1")

    implementation("com.google.android.material:material:1.14.0")
    implementation("com.google.guava:guava:33.6.0-android")
    implementation("com.google.zxing:core:3.5.4")
    implementation("org.bouncycastle:bcprov-jdk18on:1.85.2")

    val cameraVersion = "1.6.1"
    implementation("androidx.camera:camera-core:$cameraVersion")
    implementation("androidx.camera:camera-camera2:$cameraVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraVersion")
    implementation("androidx.camera:camera-view:$cameraVersion")
}
