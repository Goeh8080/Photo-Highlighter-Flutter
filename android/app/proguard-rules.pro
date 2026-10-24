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
