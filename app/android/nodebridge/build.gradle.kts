plugins {
    id("com.android.library")
}

android {
    namespace = "io.github.guog962464.aggregate.nodebridge"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    val allProbeAbis = providers.gradleProperty("a3ProbeAllAbis").orNull == "true"

    if (allProbeAbis) {
        sourceSets.getByName("main").jniLibs.srcDir("src/allAbis/jniLibs")
    }

    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += if (allProbeAbis) {
                listOf("arm64-v8a", "armeabi-v7a", "x86_64")
            } else {
                listOf("arm64-v8a")
            }
        }
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++20"
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
