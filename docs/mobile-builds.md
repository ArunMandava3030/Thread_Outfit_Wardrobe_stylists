# Android and iPhone builds

Thread uses one Flutter project for Android, iOS, and the browser. The project is pinned to Flutter 3.35.7 / Dart 3.9.2 in CI; use that version for matching local builds.

| Platform | Minimum version | Installable output |
| --- | --- | --- |
| Android | Android 8.0 / API 26 | `.apk` |
| iPhone / iPad | iOS 13.0 | Signed `.ipa`, distributed through the configured Apple channel |
| Browser | A current browser with WebAssembly | The GitHub Pages website |

## Android demo APK

Install JDK 17 or 21, the Android command-line tools, platform-tools, Android platform 36, build-tools 35.0.0 and 36.0.0, NDK 27.0.12077973, and CMake 3.22.1. Review and accept the Android SDK license during setup. Set `ANDROID_HOME` and `JAVA_HOME` to those installations, then run:

```sh
flutter pub get
flutter build apk --release
```

The universal APK is written to `build/app/outputs/flutter-apk/app-release.apk`. This combines ARM 32-bit, ARM 64-bit, and x86-64 support. For smaller architecture-specific APKs, use `flutter build apk --release --split-per-abi`.

Without `android/key.properties`, this project signs the optimized demo with Android's development certificate. Release downloads should identify it as a **demo APK**. It can be installed directly on an Android device after allowing installation from the browser or file manager used to open it. This is separate from Google Play publishing.

Android updates require the same signing certificate. Keep the same development keystore for repeated demo builds; a fresh CI machine can generate a different development key. If a demo made with another certificate is already installed, Android may require removing it before installing the new demo, which removes its local Thread data.

With a connected device and USB debugging enabled, installation is also possible with:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

For production signing, create a private signing keystore, copy `android/key.properties.example` to `android/key.properties`, and fill in its values. Relative `storeFile` paths are resolved from `android/`. Both `key.properties` and keystore files are ignored by Git. Keep the key and passwords backed up privately; use a secret store when configuring CI. With that file present, release builds use its certificate and reject missing signing fields. Follow Flutter's [Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app) for creating and managing the key.

The development PC can keep SDKs, the JDK, caches, and signing material under the ignored `.tools/` directory. These local tools are not part of the repository or release downloads.

## iPhone preparation

The repository contains the Xcode project, app icons, photo/camera usage descriptions, and a CocoaPods configuration targeting iOS 13.0. The Flutter build configurations include the CocoaPods settings, and release/profile builds preserve global symbols required by `tflite_flutter`.

On a Mac with Xcode and CocoaPods installed:

```sh
flutter pub get
flutter build ios --release --no-codesign
```

This checks compilation and produces `build/ios/iphoneos/Runner.app`. An unsigned `.app` archive is a build artifact; it cannot be installed directly on an iPhone. There is no iPhone APK.

For a signed iPhone build, open `ios/Runner.xcworkspace` in Xcode, choose your Apple signing team, and register or select the bundle identifier (`com.threadstyle.threadStyle` by default). Configure the appropriate certificate and provisioning profile, then run:

```sh
flutter build ipa --release
```

The signed export appears under `build/ios/ipa/` when the Apple configuration is complete. TestFlight/App Store distribution requires Apple Developer Program access; development or ad-hoc installation follows the selected provisioning method. See Flutter's [iOS release guide](https://docs.flutter.dev/deployment/ios). Signing credentials are not included in this repository.

Until Apple signing is configured, open the GitHub Pages version in Safari on the iPhone. Safari's **Share → Add to Home Screen** adds a convenient shortcut. The public demo provides outfit color and layering suggestions without requiring saved personal data.

## Native photo-analysis validation

The bundled MoveNet model runs through `tflite_flutter` on Android/iOS. Its [maintainer's setup notes](https://pub.dev/packages/tflite_flutter#android--ios) require Android API 26 or newer, recommend a physical iPhone for inference, and describe the release symbol-stripping setting applied in this project.

After installing on a real phone, verify photo picking/capture, automatic analysis, manual corrections, and restarting the app with saved preferences. The automatic estimates remain editable. A successful compile or browser inference test does not establish native camera or native inference behavior on every device.
