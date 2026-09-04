import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 系统强调色预设
enum AppAccentPreset {
  teal(Color(0xFF1ECAD3), '薄荷绿'),
  ocean(Color(0xFF2F80ED), '海洋蓝'),
  violet(Color(0xFF7C5CFF), '经典紫'),
  orange(Color(0xFFFF8A3D), '活力橙'),
  rose(Color(0xFFFF4D6D), '玫红'),
  ink(Color(0xFF1A1A1A), '墨黑');

  const AppAccentPreset(this.color, this.label);
  final Color color;
  final String label;
}

/// 系统 UI 风格
enum AppUiStyle {
  glass('毛玻璃', '底栏毛玻璃，沉浸边缘'),
  flat('扁平', '纯色底栏，轻量省电'),
  material3('Material 3', 'Google M3 指示条与圆角');

  const AppUiStyle(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

/// 全局加载动画风格
enum AppLoadingStyle {
  spinner('旋转环', 'Lottie 品牌色旋转'),
  ring('圆环', 'Material 进度环'),
  dots('三点', '三点弹跳动效'),
  pulse('呼吸', '圆点呼吸缩放'),
  cupertino('系统转圈', 'iOS 风格转圈');

  const AppLoadingStyle(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

/// 页面过渡动画
enum AppPageTransition {
  cupertino('侧滑', '类 iOS 左右推入'),
  slide('右滑', '从右侧滑入'),
  fade('淡入', '透明度过渡'),
  slideUp('上滑', '自下而上浮入'),
  zoom('缩放', '轻微放大淡入'),
  none('无动画', '瞬时切换');

  const AppPageTransition(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

/// 动画速度
enum AppMotionSpeed {
  slow('较慢', 1.35),
  normal('标准', 1.0),
  fast('较快', 0.7);

  const AppMotionSpeed(this.label, this.factor);
  final String label;
  final double factor;
}

/// 明暗主题 + 强调色 + UI / 加载 / 动效（持久化）
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _kDark = 'app_theme_dark';
  static const _kAccent = 'app_accent_preset_v1';
  static const _kUi = 'app_ui_style_v1';
  static const _kLoading = 'app_loading_style_v1';
  static const _kMotion = 'app_motion_enabled_v1';
  static const _kTransition = 'app_page_transition_v1';
  static const _kSpeed = 'app_motion_speed_v1';

  bool _dark = false;
  AppAccentPreset _accent = AppAccentPreset.teal;
  AppUiStyle _uiStyle = AppUiStyle.glass;
  AppLoadingStyle _loadingStyle = AppLoadingStyle.spinner;
  bool _motionEnabled = true;
  AppPageTransition _pageTransition = AppPageTransition.cupertino;
  AppMotionSpeed _motionSpeed = AppMotionSpeed.normal;
  bool _ready = false;

  bool get isDark => _dark;
  bool get ready => _ready;
  ThemeMode get mode => _dark ? ThemeMode.dark : ThemeMode.light;
  AppAccentPreset get accentPreset => _accent;
  Color get accent => _accent.color;
  AppUiStyle get uiStyle => _uiStyle;
  AppLoadingStyle get loadingStyle => _loadingStyle;
  bool get motionEnabled => _motionEnabled;
  AppPageTransition get pageTransition => _pageTransition;
  AppMotionSpeed get motionSpeed => _motionSpeed;
  bool get useGlassUi => _uiStyle == AppUiStyle.glass;
  bool get useMaterial3 => _uiStyle == AppUiStyle.material3;

  Duration get transitionDuration {
    if (!_motionEnabled || _pageTransition == AppPageTransition.none) {
      return Duration.zero;
    }
    final ms = (280 * _motionSpeed.factor).round().clamp(120, 480);
    return Duration(milliseconds: ms);
  }

  Duration scaled(Duration base) {
    if (!_motionEnabled) return Duration.zero;
    final ms = (base.inMilliseconds * _motionSpeed.factor).round();
    return Duration(milliseconds: ms.clamp(0, 2000));
  }

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _dark = prefs.getBool(_kDark) ?? false;
    final accentName = prefs.getString(_kAccent) ?? AppAccentPreset.teal.name;
    _accent = AppAccentPreset.values.firstWhere(
      (e) => e.name == accentName,
      orElse: () => AppAccentPreset.teal,
    );
    final uiName = prefs.getString(_kUi) ?? AppUiStyle.glass.name;
    _uiStyle = AppUiStyle.values.firstWhere(
      (e) => e.name == uiName,
      orElse: () => AppUiStyle.glass,
    );
    final loadingName =
        prefs.getString(_kLoading) ?? AppLoadingStyle.spinner.name;
    _loadingStyle = AppLoadingStyle.values.firstWhere(
      (e) => e.name == loadingName,
      orElse: () => AppLoadingStyle.spinner,
    );
    _motionEnabled = prefs.getBool(_kMotion) ?? true;
    final transitionName =
        prefs.getString(_kTransition) ?? AppPageTransition.cupertino.name;
    _pageTransition = AppPageTransition.values.firstWhere(
      (e) => e.name == transitionName,
      orElse: () => AppPageTransition.cupertino,
    );
    final speedName = prefs.getString(_kSpeed) ?? AppMotionSpeed.normal.name;
    _motionSpeed = AppMotionSpeed.values.firstWhere(
      (e) => e.name == speedName,
      orElse: () => AppMotionSpeed.normal,
    );
    _ready = true;
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    if (_dark == value) return;
    _dark = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDark, value);
  }

  Future<void> toggle() => setDark(!_dark);

  Future<void> setAccentPreset(AppAccentPreset value) async {
    if (_accent == value) return;
    _accent = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, value.name);
  }

  Future<void> setUiStyle(AppUiStyle value) async {
    if (_uiStyle == value) return;
    _uiStyle = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUi, value.name);
  }

  Future<void> setLoadingStyle(AppLoadingStyle value) async {
    if (_loadingStyle == value) return;
    _loadingStyle = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLoading, value.name);
  }

  Future<void> setMotionEnabled(bool value) async {
    if (_motionEnabled == value) return;
    _motionEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMotion, value);
  }

  Future<void> setPageTransition(AppPageTransition value) async {
    if (_pageTransition == value) return;
    _pageTransition = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTransition, value.name);
  }

  Future<void> setMotionSpeed(AppMotionSpeed value) async {
    if (_motionSpeed == value) return;
    _motionSpeed = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSpeed, value.name);
  }
}
