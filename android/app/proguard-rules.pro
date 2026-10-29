# ==============================================================================
# ZeroSync AirDrop-QR: Production R8 & ProGuard Obfuscation Rules
# Optimized for maximum binary shrinking, symbol stripping & reverse engineering prevention
# ==============================================================================

# --- 1. General Optimization & Obfuscation Controls ---
-optimizations !code/simplification/arithmetic,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification
-mergeinterfacesaggressively
-repackageclasses 'org.zerosync.obfuscated'
-overloadaggressively

# Strip line numbers and source file names for zero reverse engineering metadata
-renamesourcefileattribute 'SourceFile'
-keepattributes SourceFile,LineNumberTable

# Preserve runtime annotations and generic signatures necessary for reflection
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Strip all android.util.Log calls in production release builds to prevent data leakage
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static int wtf(...);
}

# --- 2. Flutter Framework & JNI Native Interface ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve native JNI method bindings
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- 3. Google ML Kit Optical Barcode Scanning Pipeline ---
# Essential: Preserve ML Kit vision and detector reflection boundaries
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.android.gms.vision.barcode.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }

# MobileScanner plugin bridge
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.camera2.** { *; }

# --- 4. SQLCipher AES-256 Encrypted Database Engine ---
# Preserve native JNI entrypoints and database models for SQLCipher
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-keep class net.sqlcipher.database.SQLiteDatabase { *; }
-keep class io.sqlc.** { *; }

# --- 5. Android Keystore & Hardware Cryptographic Storage ---
# Preserve AndroidX Security Crypto MasterKeys and FlutterSecureStorage
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class javax.crypto.** { *; }
-keep class java.security.** { *; }

# --- 6. Archive & Compression Codecs ---
-dontwarn java.nio.file.**
-dontwarn org.brotli.**

# --- 7. Don't Warn for Unused Transitive Stubs ---
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**

