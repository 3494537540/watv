import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_models.dart';

class AuthStore {
  AuthStore._();

  static const _tokenKey = 'hothub_user_token';
  static const _userKey = 'hothub_user_info';
  static const _expiredKey = 'hothub_token_expired';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      // 新增插件后需完全停止再 Run，热重启不会注册原生通道
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<AuthSession?> load() async {
    final prefs = await _prefs();
    if (prefs == null) return null;

    final token = prefs.getString(_tokenKey);
    final userRaw = prefs.getString(_userKey);
    if (token == null || token.isEmpty || userRaw == null || userRaw.isEmpty) {
      return null;
    }
    try {
      final map = jsonDecode(userRaw) as Map<String, dynamic>;
      return AuthSession(
        token: token,
        tokenExpired: prefs.getInt(_expiredKey),
        user: AuthUser.fromJson(map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AuthSession session) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userKey, jsonEncode(session.user.toJson()));
    if (session.tokenExpired != null) {
      await prefs.setInt(_expiredKey, session.tokenExpired!);
    }
  }

  static Future<void> clear() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_expiredKey);
  }
}
