plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.tavernlite.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Tavern Lite's own id: this app is not DSH Go and cannot be installed
        // over it.
        applicationId = "io.github.tavernlite.app"
        // java.nio.file (the tavern's card unpacking) needs API 26, and
        // sqlite3's native build targets it too.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        // AGP 9.3.1's lint crashes on this toolchain (NoSuchMethodError in
        // JavaDocParser, from the Kotlin 2.4 parser) for the plugin modules'
        // release pass. The tavern is analysed by `flutter analyze`; lint is not
        // part of this build.
        checkReleaseBuilds = false
        checkDependencies = false
        abortOnError = false
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
