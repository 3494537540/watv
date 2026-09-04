import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// 应用设置：自定义 CMS 地址、自动登录等
class AppSettingsController extends ChangeNotifier {
  AppSettingsController._();
  static final AppSettingsController instance = AppSettingsController._();

  static const _kCms = 'custom_cms_base_v1';
  static const _kAutoLogin = 'auto_login_v1';

  String _customCmsBase = '';
  bool _autoLogin = true;
  bool _ready = false;

  bool get isReady => _ready;
  String get customCmsBase => _customCmsBase;
  bool get autoLogin => _autoLogin;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _customCmsBase = (prefs.getString(_kCms) ?? '').trim();
    _autoLogin = prefs.getBool(_kAutoLogin) ?? true;
    ApiConfig.applyRuntimeMacCmsOverride(_customCmsBase);
    _ready = true;
    notifyListeners();
  }

  Future<void> setCustomCmsBase(String raw) async {
    var url = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _customCmsBase = url;
    ApiConfig.applyRuntimeMacCmsOverride(_customCmsBase);
    final prefs = await SharedPreferences.getInstance();
    if (_customCmsBase.isEmpty) {
      await prefs.remove(_kCms);
    } else {
      await prefs.setString(_kCms, _customCmsBase);
    }
    notifyListeners();
  }

  Future<void> resetCmsBase() => setCustomCmsBase('');

  Future<void> setAutoLogin(bool value) async {
    _autoLogin = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoLogin, value);
    notifyListeners();
  }
}
