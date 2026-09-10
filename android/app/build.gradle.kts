import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    FileInputStream(localPropertiesFile).use { localProperties.load(it) }
}
val mapsApiKey = localProperties.getProperty("MAPS_API_KEY", "")
val weatherApiKey = localProperties.getProperty("WEATHER_API_KEY", mapsApiKey)
val customSearchApiKey = localProperties.getProperty("CUSTOM_SEARCH_API_KEY", "")
val customSearchEngineId = localProperties.getProperty("CUSTOM_SEARCH_ENGINE_ID", "")
val aiApiKey = localProperties.getProperty("AI_API_KEY", "")
val auth0Domain = localProperties.getProperty("AUTH0_DOMAIN", "")

android {
    namespace = "com.example.tunga"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.tunga"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        manifestPlaceholders["WEATHER_API_KEY"] = weatherApiKey
        manifestPlaceholders["CUSTOM_SEARCH_API_KEY"] = customSearchApiKey
        manifestPlaceholders["CUSTOM_SEARCH_ENGINE_ID"] = customSearchEngineId
        manifestPlaceholders["AI_API_KEY"] = aiApiKey
        // Auth0 login redirect — custom scheme (the app's own package name)
        // instead of "https" to avoid needing Android App Links domain
        // verification, which the auth0_flutter README flags as required
        // for the https scheme.
        manifestPlaceholders["auth0Domain"] = auth0Domain
        // Kept as a literal (not a reference to applicationId above) since
        // Kotlin can't smart-cast that nullable var here — must stay in
        // sync with applicationId and Auth0Service's webAuthentication scheme.
        manifestPlaceholders["auth0Scheme"] = "com.example.tunga"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
