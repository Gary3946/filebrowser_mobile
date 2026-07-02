# Flutter's Gradle plugin contributes the engine/embedding keep rules, so app
# Dart code (AOT-compiled) is unaffected by R8. These keeps cover the native
# side of plugins that use reflection / annotations.

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
# local_auth (BiometricPrompt / crypto)
-keep class androidx.biometric.** { *; }
