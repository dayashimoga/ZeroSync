---
name: android-gradle-surgery
description: Diagnose and repair Flutter Kotlin DSL Gradle builds, AGP 8.x namespace rules, and CI environment variable resolution.
---
# Android Gradle Surgery Skill
1. Always inspect `android/settings.gradle.kts`, `android/build.gradle.kts`, and `android/app/build.gradle.kts` together.
2. Ensure `settings.gradle.kts` resolves `flutterSdkPath` via:
   - First: `local.properties` (`flutter.sdk`)
   - Fallback 1: `System.getenv("FLUTTER_ROOT")`
   - Fallback 2: `System.getenv("FLUTTER_SDK")`
3. Never mix legacy imperative `apply(from = ".../flutter.gradle")` with declarative `id("dev.flutter.flutter-gradle-plugin")`.
4. Ensure CI workflows run `flutter pub get` BEFORE `flutter build apk`.

