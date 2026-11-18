plugins {
    id("com.android.application")
}

android {
    namespace = "io.github.guog962464.aggregate.nodeprobe"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.github.guog962464.aggregate.nodeprobe"
        minSdk = 24
        targetSdk = 36
        versionCode = providers.gradleProperty("a3ProbeVersionCode").orNull?.toInt() ?: 1
        versionName = versionCode.toString()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            // The experimental CLI alias executes the packaged PIE from nativeLibraryDir.
            useLegacyPackaging = true
        }
    }

}

dependencies {
    implementation(project(":nodebridge"))
}
