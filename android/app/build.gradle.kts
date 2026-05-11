import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val requiredSigningKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val hasReleaseSigning = keystorePropertiesFile.exists() &&
    requiredSigningKeys.all { key ->
        val value = keystoreProperties.getProperty(key)
        !value.isNullOrBlank()
    }

android {
    namespace = "com.simert.estacionamientotarifado"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.simert.estacionamiento"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (!hasReleaseSigning) {
                throw GradleException(
                    "Falta android/key.properties con keyAlias, keyPassword, storeFile y storePassword para firmar release de Play Store."
                )
            }
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    // Core library desugaring (requerido por flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // AndroidX Activity — necesario para EdgeToEdge.enable() en Android 15+
    // Forzar versión 1.9.0+ que incluye enableEdgeToEdge estable
    implementation("androidx.activity:activity-ktx:1.9.3")
}

flutter {
    source = "../.."
}
