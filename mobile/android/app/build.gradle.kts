import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Yükleme (upload) anahtarı: android/key.properties (repoya girmez; şablon: key.properties.example).
// Dosya yoksa release derlemesi debug anahtarıyla imzalanır ve mağazaya yüklenemez.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.rebiovil.rebi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications zamanlanmış bildirimler için gerektirir.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.rebiovil.rebi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Sürüm numaraları pubspec.yaml'daki `version: 1.0.0+1` değerinden gelir (+ sonrası versionCode).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Yayın hattında anahtar zorunlu: REBI_REQUIRE_RELEASE_SIGNING=true ile eksikse derleme durur.
            if (!hasReleaseKey && System.getenv("REBI_REQUIRE_RELEASE_SIGNING") == "true") {
                throw GradleException("android/key.properties yok: release derlemesi imzalanamaz.")
            }
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

// Firebase proje dosyası eklenmediyse (push kapalı) Google Services eklentisi uygulanmaz;
// uygulama yalnızca yerel bildirimlerle derlenir ve çalışır.
// Crashlytics eklentisi google-services ile birlikte uygulanmalı (derleme kimliği + R8 eşleme dosyası yükleme).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}

flutter {
    source = "../.."
}
