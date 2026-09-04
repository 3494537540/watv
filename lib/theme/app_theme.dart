import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/theme_controller.dart';
import '../widgets/app_page_route.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final accent = ThemeController.instance.accent;
    // 关闭 Material 3；中文只用常规字重，避免 Web 缺字
    const base = TextStyle(
      fontFamily: 'AppSans',
      color: AppColors.text,
      fontWeight: FontWeight.w400,
      height: 1.4,
    );

    return ThemeData(
      useMaterial3: ThemeController.instance.useMaterial3,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
      ),
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.page,
      canvasColor: AppColors.surface,
      dividerColor: AppColors.line,
      fontFamily: 'AppSans',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'AppSans',
          color: AppColors.text,
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: base.copyWith(fontSize: 16),
        bodyMedium: base.copyWith(fontSize: 14),
        bodySmall: base.copyWith(fontSize: 12, color: AppColors.textSecondary),
        titleLarge: base.copyWith(fontSize: 22),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFill,
        contentPadding: EdgeInsets.fromLTRB(0, 12, 0, 12),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.lineStrong, width: 1),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.lineStrong, width: 1),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger, width: 1),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontFamily: 'AppSans',
          color: AppColors.textHint,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final accent = ThemeController.instance.accent;
    const base = TextStyle(
      fontFamily: 'AppSans',
      color: AppColors.textDark,
      fontWeight: FontWeight.w400,
      height: 1.4,
    );

    return ThemeData(
      useMaterial3: ThemeController.instance.useMaterial3,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ),
      primaryColor: AppColors.textDark,
      scaffoldBackgroundColor: AppColors.pageDark,
      canvasColor: AppColors.surfaceDark,
      dividerColor: AppColors.lineDark,
      fontFamily: 'AppSans',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.textDark,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'AppSans',
          color: AppColors.textDark,
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.2,
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: base.copyWith(fontSize: 16),
        bodyMedium: base.copyWith(fontSize: 14),
        bodySmall:
            base.copyWith(fontSize: 12, color: AppColors.textSecondaryDark),
        titleLarge: base.copyWith(fontSize: 22),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.fieldFillDark,
        contentPadding: EdgeInsets.fromLTRB(0, 12, 0, 12),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.lineDark, width: 1),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.lineDark, width: 1),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger, width: 1),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontFamily: 'AppSans',
          color: AppColors.textHintDark,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: AppColors.ember,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.disabled,
          disabledForegroundColor: AppColors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
