# ── mobile_scanner (MLKit + CameraX) ──
# Keep Google MLKit barcode scanning classes (used by mobile_scanner plugin).
# Without these rules, R8 strips them in release builds, causing camera
# scanner to show a black/blank screen even though permission is granted.

-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }

# Keep CameraX classes used by mobile_scanner
-keep class androidx.camera.** { *; }
-keep class androidx.lifecycle.** { *; }

# Keep mobile_scanner plugin classes
-keep class dev.steenbakker.mobile_scanner.** { *; }

# General Flutter rules
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**
