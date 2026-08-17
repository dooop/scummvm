plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ktlint)
}

ktlint {
    android.set(true)
    outputToConsole.set(true)
}

val releaseAar =
    providers
        .gradleProperty("scummvm.releaseAar")
        .orElse(
            layout.projectDirectory
                .file("libs/scummvm-release.aar")
                .asFile.absolutePath,
        )

// Version of io.github.dooop:scummvm resolved from GitHub Packages by the
// "maven" flavor. Defaults to the latest published release; override to test
// against a specific tag, e.g. -Pscummvm.mavenVersion=0.7.0.
val mavenVersion =
    providers
        .gradleProperty("scummvm.mavenVersion")
        .getOrElse("0.7.0")

val scummvmAbis =
    (providers.gradleProperty("scummvm.abis").orNull ?: "arm64-v8a,x86_64")
        .split(",")
        .map(String::trim)
        .filter(String::isNotEmpty)

android {
    // Must differ from the consumed AAR's namespace; AGP rejects duplicate
    // namespaces during manifest merging. The application id and Activity
    // package remain org.scummvm.
    namespace = "org.scummvm.app"
    compileSdk {
        version = release(37)
    }
    enableKotlin = true

    defaultConfig {
        applicationId = "org.scummvm"
        minSdk = 23
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"
        ndk {
            abiFilters += scummvmAbis
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Which ScummVM engine artifact the app links against. Independent of the
    // debug/release build type below, so all four combinations build:
    // localDebug, localRelease, mavenDebug, mavenRelease.
    flavorDimensions += "engineSource"
    productFlavors {
        create("local") {
            dimension = "engineSource"
            // debug uses the :scummvm project directly; release uses a flat
            // prebuilt AAR from disk (see releaseAar / verifyReleaseAar below).
            buildConfigField("String", "ENGINE_SOURCE", "\"local\"")
        }
        create("maven") {
            dimension = "engineSource"
            versionNameSuffix = "-maven"
            buildConfigField("String", "ENGINE_SOURCE", "\"maven:io.github.dooop:scummvm:$mavenVersion\"")
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs.keepDebugSymbols += "**/libscummvm.so"
    }

    lint {
        abortOnError = false
    }
}

dependencies {
    "mavenImplementation"("io.github.dooop:scummvm:$mavenVersion")

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.annotation)
}

// The flavor x build type configurations below (e.g. localDebugImplementation)
// only exist once AGP has finished computing the variant list, which happens
// after this script's dependencies {} block runs.
afterEvaluate {
    dependencies {
        "localDebugImplementation"(project(":scummvm"))
        "localReleaseImplementation"(files(releaseAar))
    }
}

val verifyReleaseAar =
    tasks.register("verifyReleaseAar") {
        group = "verification"
        description = "Checks that the prebuilt ScummVM AAR for the local-flavor release build exists."
        doLast {
            val aar = file(releaseAar.get())
            require(aar.isFile) {
                "The local-flavor release build requires a prebuilt ScummVM AAR at ${aar.path}.\n" +
                    "Copy an uploaded release artifact to app/libs/scummvm-release.aar or pass " +
                    "-Pscummvm.releaseAar=/absolute/path/to/scummvm-release.aar."
            }
        }
    }

tasks.configureEach {
    // Flavors rename the lifecycle task from preReleaseBuild to
    // pre<Flavor>ReleaseBuild; only the "local" flavor reads a flat AAR file.
    if (name == "preLocalReleaseBuild") dependsOn(verifyReleaseAar)
}
