# Flutter / 第三方插件保留规则（R8 混淆）
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class com.watv.app.** { *; }

-dontwarn io.flutter.embedding.**
-dontwarn android.window.**
