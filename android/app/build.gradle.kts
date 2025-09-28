// File: android/app/build.gradle.kts

import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

// 1. Carga de propiedades de keystore desde /key.properties en la raíz del proyecto
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    } else {
        throw GradleException("No se encontró key.properties en: $keystorePropertiesFile")
    }
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.plantillalogin"
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
        applicationId = "com.example.plantillalogin"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 2. Añadimos el signingConfig “release” leyendo las props cargadas
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: throw GradleException("keyAlias no está definido en key.properties")
            keyPassword = keystoreProperties.getProperty("keyPassword")
                ?: throw GradleException("keyPassword no está definido en key.properties")
            storeFile = file(
                keystoreProperties.getProperty("storeFile")
                    ?: throw GradleException("storeFile no está definido en key.properties")
            )
            storePassword = keystoreProperties.getProperty("storePassword")
                ?: throw GradleException("storePassword no está definido en key.properties")
        }
    }

    buildTypes {
        getByName("release") {
            // Opcionales: ofuscación y minimización
            isMinifyEnabled   = true
            isShrinkResources = true

            // Asignamos nuestro release signingConfig
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            // Mantenemos la firma de debug por defecto
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
