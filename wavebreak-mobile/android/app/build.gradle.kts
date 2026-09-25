import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real-world bug this fixes: release builds were signed with each
// machine's own auto-generated `~/.android/debug.keystore` (a different,
// random certificate per machine/user) — anyone who'd installed a build
// from a DIFFERENT machine than whichever one produced the next release
// hit Android's own signature-mismatch install rejection: the system
// installer dialog just closes with no clear error and nothing gets
// installed, which is exactly what surfaced as "update downloads, tap
// Update, dialog vanishes, nothing happens" on a colleague's device. One
// fixed keystore, reused for every future release regardless of which
// machine builds it, is what makes in-app updates actually apply instead
// of silently no-op'ing for anyone not on the exact machine that built
// the previous release. `key.properties` (gitignored, like the .jks
// itself) holds the passwords — loaded here rather than hardcoded so the
// actual secret never has to be a committed file.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.wavebreak.wavebreak"
    compileSdk = flutter.compileSdkVersion
    // Pinned above flutter.ndkVersion: several plugins (connectivity_plus,
    // device_info_plus, flutter_secure_storage, etc.) require NDK
    // 28.2.13676358, higher than the version Flutter's template defaults to.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wavebreak.wavebreak"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Falls back to the debug key (old behavior) only when
            // key.properties genuinely doesn't exist yet — e.g. a fresh
            // clone that hasn't run the one-time keystore setup — so
            // `flutter run --release` still works out of the box rather
            // than hard-failing the build. Every real release build must
            // have key.properties present; see this file's own doc
            // comment above on why a consistent key matters.
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Minification disabled for now: the AGP 9.1.0 default of
            // isMinifyEnabled = true for release builds requires a
            // proguard-rules.pro that doesn't exist yet, and R8 stripping
            // classes it can't see used (the hysteria_bridge.aar's Go<->Java
            // bridge is invoked via go.Seq reflection) is a real risk of
            // shipping a release build that silently breaks at runtime.
            // Revisit with proper -keep rules for go.** and
            // app.wavebreak.bridge.** before re-enabling.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Historical note, kept because it's a real gotcha worth remembering:
    // this app used to bundle a standalone tun2socks ELF binary
    // (libtun2socks.so — really an executable, launched via
    // ProcessBuilder, not a JNI library) and needed legacy packaging so
    // AGP would extract it to a real filesystem path instead of leaving it
    // zipped inside the APK. That binary is gone now (see
    // WaveEngineVpnService's doc comment — tun2socks runs in-process via
    // native/hysteria_bridge/tun2socks.go instead, for unrelated reasons:
    // Android's phantom-process killer was terminating the subprocess a
    // few seconds after every connection). libhysteriabridge.so is a real
    // JNI library and loads fine either way, but there's no reason to flip
    // this back to modern packaging for the sake of it.
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
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
    implementation("androidx.core:core-ktx:1.13.1")
    // Built from native/hysteria_bridge via `gomobile bind` — one gomobile
    // binding covering both Xray-core (VLESS/VMess/Trojan/Shadowsocks/
    // REALITY — MPL-2.0) and the MIT-licensed apernet/hysteria client
    // (Hysteria2). This app has no other gomobile-bound native dependency
    // (flutter_v2ray, which used to provide Xray-core, was removed):
    // two independently gomobile-bound libraries in one process turned out
    // not to be binary-compatible with each other even with matching
    // Java-level signatures (confirmed via on-device logcat — both native
    // libraries loaded fine, then the process died with no Java exception
    // the moment one touched the other's shared go.Seq bridge). Re-run
    // native/hysteria_bridge/build_aar.sh and don't reintroduce a second
    // gomobile-bound native library here.
    implementation(files("libs/hysteria_bridge.aar"))
}
