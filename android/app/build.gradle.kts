import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningFile.exists()) {
        releaseSigningFile.inputStream().use(::load)
    }
}

fun releaseSigningValue(name: String): String =
    releaseSigningProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("Missing '$name' in android/key.properties")

android {
    namespace = "com.savebite.savebite"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.savebite.savebite"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // webview_flutter dan checkout Snap memakai WebView modern dengan
        // JavaScript/DOM storage. API 24 menjadi baseline yang didukung.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningFile.exists()) {
            create("release") {
                keyAlias = releaseSigningValue("keyAlias")
                keyPassword = releaseSigningValue("keyPassword")
                storeFile = rootProject.file(releaseSigningValue("storeFile"))
                storePassword = releaseSigningValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Never let a distributable artifact silently fall back to the debug key.
gradle.taskGraph.whenReady {
    val requestsReleaseArtifact = allTasks.any {
        it.project == project &&
            (it.name.startsWith("assembleRelease") ||
                it.name.startsWith("bundleRelease") ||
                it.name.startsWith("packageRelease"))
    }
    if (requestsReleaseArtifact && !releaseSigningFile.exists()) {
        throw GradleException(
            "Release signing is not configured. Copy android/key.properties.example " +
                "to android/key.properties and provide the upload-keystore values.",
        )
    }
}

flutter {
    source = "../.."
}
