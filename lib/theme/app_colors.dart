import 'package:flutter/material.dart';

import '../state/theme_controller.dart';

/// 哇TV — 白底扁平配色，无渐变。
class AppColors {
  AppColors._();

  static const Color white = Color(0xFFFFFFFF);
  static const Color page = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5C5C5C);
  static const Color textHint = Color(0xFF9A9A9A);
  static const Color line = Color(0xFFE8E8E8);
  static const Color lineStrong = Color(0xFFD0D0D0);
  static const Color fieldFill = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF1A1A1A);
  /// 品牌强调色默认值（const 场景用）
  static const Color brandSeed = Color(0xFF1ECAD3);
  /// 品牌强调色（跟随设置里的系统配色）
  static Color get brand => ThemeController.instance.accent;
  /// 个人中心等强调：与 brand 统一
  static Color get ember => brand;
  /// 播放页强调色（与品牌青统一）
  static Color get mango => brand;
  static const Color danger = Color(0xFFB42318);
  static const Color disabled = Color(0xFFBDBDBD);

  /// 选中态强调（底栏 / 标签）
  static Color get iosBlue => brand;
  /// 毛玻璃底栏半透明白（冷色，避免暖色内容染色）
  static const Color glassFill = Color(0xD9FFFFFF);
  static const Color glassBorder = Color(0x99FFFFFF);
  /// 未选中：近黑，保证浅色玻璃上可读
  static const Color tabInactive = Color(0xFF1C1C1E);
  static const Color tabPill = Color(0x14000000);

  /// 封面图未加载 / 失败时的中性占位（禁止五颜六色）
  static const Color posterPlaceholder = Color(0xFFE8E9ED);
  static const Color posterPlaceholderIcon = Color(0xFFB0B3BB);
  static const Color bannerPlaceholder = Color(0xFF2C2C2E);
  static const Color bannerPlaceholderIcon = Color(0x66FFFFFF);

  // —— 暗色 ——
  static const Color pageDark = Color(0xFF0E0E0F);
  static const Color surfaceDark = Color(0xFF1A1A1C);
  static const Color textDark = Color(0xFFF2F2F2);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);
  static const Color textHintDark = Color(0xFF7A7A7A);
  static const Color lineDark = Color(0xFF2C2C2E);
  static const Color fieldFillDark = Color(0xFF1A1A1C);
  static const Color posterPlaceholderDark = Color(0xFF2A2A2C);
}

/// 按当前 Theme 取色（明暗自适应）
abstract final class AppPalette {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color page(BuildContext context) =>
      isDark(context) ? AppColors.pageDark : AppColors.page;

  static Color surface(BuildContext context) =>
      isDark(context) ? AppColors.surfaceDark : AppColors.surface;

  static Color text(BuildContext context) =>
      isDark(context) ? AppColors.textDark : AppColors.text;

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? AppColors.textSecondaryDark : AppColors.textSecondary;

  static Color textHint(BuildContext context) =>
      isDark(context) ? AppColors.textHintDark : AppColors.textHint;

  static Color line(BuildContext context) =>
      isDark(context) ? AppColors.lineDark : AppColors.line;

  static Color softFill(BuildContext context) =>
      isDark(context) ? const Color(0xFF242426) : const Color(0xFFF3F3F5);
}
