import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep this file and its keystore private. Without it, the downloadable demo
// remains installable using Android's development certificate.
val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties()
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach { name ->
        require(!signingProperties.getProperty(name).isNullOrBlank()) {
            "Missing $name in android/key.properties"
        }
    }
}

android {
    namespace = "com.threadstyle.thread_style"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.threadstyle.thread_style"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingPropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Demo APKs use a development certificate. Supply key.properties
            // with a stable private key before publishing production releases.
            signingConfig = signingConfigs.getByName(
                if (signingPropertiesFile.exists()) "release" else "debug",
            )
        }
    }
}

flutter {
    source = "../.."
}
