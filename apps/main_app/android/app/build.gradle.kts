import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Names the missing key instead of failing with a bare ClassCastException.
fun keystoreProperty(name: String): String =
    requireNotNull(keystoreProperties.getProperty(name)) {
        "$name is missing from ${keystorePropertiesFile.absolutePath}"
    }

android {
    lint {
        abortOnError = false
        disable.add("ManifestResource")
    }
    namespace = "app.aumazing"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.aumazing"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Only declared when key.properties is present. Reading the keystore
    // unconditionally evaluates at configuration time, so a missing file broke
    // *every* Gradle invocation — debug builds and `flutter analyze` included —
    // with an NPE before any task could run.
    if (hasReleaseKeystore) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
                storeFile = file(keystoreProperty("storeFile"))
                storePassword = keystoreProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug signing so a developer without the release
            // keystore can still produce a local release build; CI and the
            // Play upload path supply key.properties and get the real config.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}






