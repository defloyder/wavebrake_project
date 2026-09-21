plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wavebreak.wavebreak"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
