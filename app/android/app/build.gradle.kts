plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.guog962464.aggregate"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.guog962464.aggregate"
        minSdk = 24
        targetSdk = 36
        ndk {
            abiFilters += "arm64-v8a"
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            excludes += setOf("**/armeabi-v7a/**", "**/x86/**", "**/x86_64/**")
        }
    }

    buildTypes {
        debug {
            if (providers.gradleProperty("aggregateIsolatedIntegration").orNull == "true") {
                // Keep Flutter integration-test install/cleanup separate from
                // the user's installed Aggregate app and Android Keystore data.
                applicationIdSuffix = ".integration"
            }
        }
        release {
            // Release artifacts stay unsigned until a production signing key is
            // supplied through a separately managed signing configuration.
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

dependencies {
    if (providers.gradleProperty("a3Probe").orNull == "true") {
        add("debugImplementation", project(":nodebridge"))
    }
}
