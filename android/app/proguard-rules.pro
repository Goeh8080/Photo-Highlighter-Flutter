# Keep plugin / JNI bridge classes that are looked up reflectively from Dart
# (path_provider_android & friends use package:jni at runtime).
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class dev.fluttercommunity.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class androidx.datastore.** { *; }
-keep class androidx.lifecycle.** { *; }
-dontwarn com.google.android.play.core.**
# JNI method signatures reference Kotlin types (Continuation, List, ...) - keep their names.
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.jvm.functions.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod

# ML Kit text recognition (kept even though minify is off, in case it is turned on)
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
