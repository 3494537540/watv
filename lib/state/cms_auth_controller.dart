import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cms_message_store.dart';
import '../services/maccms_user_api.dart';

/// CMS 站内会员登录态（与旧 admin 火苗体系无关）
class CmsAuthController extends ChangeNotifier {
  CmsAuthController({MacCmsUserApi? api}) : _api = api ?? MacCmsUserApi();

  static final CmsAuthController instance = CmsAuthController();

  final MacCmsUserApi _api;
  static const _userKey = 'maccms_user_json';
  static const _overrideKey = 'maccms_profile_overrides_v1';

  CmsUser? _user;
  bool _ready = false;
  bool _busy = false;

  /// 本地编辑覆盖（刷新/启动不会被空的服务端资料冲掉）
  String? _overrideNick;
  String? _overridePortrait;

  bool get isReady => _ready;
  bool get isBusy => _busy;
  bool get isLoggedIn => _user != null;
  CmsUser? get user => _user;
  MacCmsUserApi get api => _api;

  Future<void> bootstrap({bool restoreSession = true}) async {
    await _api.loadCookie();
    final prefs = await SharedPreferences.getInstance();
    await _loadOverrides(prefs);
    if (!restoreSession) {
      _user = null;
      _ready = true;
      notifyListeners();
      return;
    }
    final raw = prefs.getString(_userKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _user = _applyOverrides(
          CmsUser.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        );
        notifyListeners();
      } catch (_) {}
    }
    if (_user != null) {
      try {
        final me = await _api.fetchProfile();
        _user = _applyOverrides(me);
        await _persist();
      } on CmsUserException catch (e) {
        if (e.code == 401) {
          _user = null;
          await _clearOverrides();
          await prefs.remove(_userKey);
        }
      } catch (_) {}
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_user == null) {
      await prefs.remove(_userKey);
    } else {
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
    }
  }

  Future<void> _loadOverrides(SharedPreferences prefs) async {
    final raw = prefs.getString(_overrideKey);
    if (raw == null || raw.isEmpty) {
      _overrideNick = null;
      _overridePortrait = null;
      return;
    }
    try {
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final nick = '${j['nick'] ?? ''}'.trim();
      final portrait = '${j['portrait'] ?? ''}'.trim();
      _overrideNick = nick.isEmpty ? null : nick;
      _overridePortrait = portrait.isEmpty ? null : portrait;
    } catch (_) {
      _overrideNick = null;
      _overridePortrait = null;
    }
  }

  Future<void> _saveOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    if ((_overrideNick == null || _overrideNick!.isEmpty) &&
        (_overridePortrait == null || _overridePortrait!.isEmpty)) {
      await prefs.remove(_overrideKey);
      return;
    }
    await prefs.setString(
      _overrideKey,
      jsonEncode({
        'nick': _overrideNick ?? '',
        'portrait': _overridePortrait ?? '',
      }),
    );
  }

  Future<void> _clearOverrides() async {
    _overrideNick = null;
    _overridePortrait = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_overrideKey);
  }

  CmsUser _applyOverrides(CmsUser base) {
    var u = base;
    final nick = _overrideNick?.trim() ?? '';
    final portrait = _overridePortrait?.trim() ?? '';
    if (nick.isNotEmpty) {
      u = u.copyWith(nickName: nick);
    }
    if (portrait.isNotEmpty) {
      u = u.copyWith(portrait: portrait);
    }
    return u;
  }

  Future<Uint8List> fetchCaptcha() => _api.fetchCaptcha();

  Future<void> login({
    required String userName,
    required String password,
    required String verify,
  }) async {
    _busy = true;
    notifyListeners();
    try {
      var user = await _api.login(
        userName: userName,
        password: password,
        verify: verify,
      );
      if (user.userName.trim().isEmpty || user.userName == '会员') {
        user = user.copyWith(userName: userName.trim());
      }
      await _clearOverrides();
      _user = user;
      await _persist();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> register({
    required String userName,
    required String password,
    required String password2,
    required String verify,
  }) async {
    _busy = true;
    notifyListeners();
    try {
      await _api.register(
        userName: userName,
        password: password,
        password2: password2,
        verify: verify,
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshProfile() async {
    if (_user == null) return;
    try {
      final me = await _api.fetchProfile();
      final local = _user!;
      // 服务端积分/组名等照常更新；昵称头像优先用本地覆盖
      final merged = CmsUser(
        userId: me.userId > 0 ? me.userId : local.userId,
        userName: _preferText(me.userName, local.userName),
        nickName: _preferText(me.nickName, local.nickName),
        email: _preferText(me.email, local.email),
        qq: _preferText(me.qq, local.qq),
        phone: _preferText(me.phone, local.phone),
        portrait: _preferText(me.portrait, local.portrait),
        points: me.points > 0 ? me.points : local.points,
        extend: me.extend > 0 ? me.extend : local.extend,
        groupName: _preferText(me.groupName, local.groupName),
        endTime: _preferText(me.endTime, local.endTime),
      );
      _user = _applyOverrides(merged);
      await _persist();
      notifyListeners();
    } on CmsUserException catch (e) {
      if (e.code == 401) {
        _user = null;
        await _clearOverrides();
        await _persist();
        notifyListeners();
      }
      rethrow;
    }
  }

  static String _preferText(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.isNotEmpty && x != '会员') return x;
    if (y.isNotEmpty && y != '会员') return y;
    return x.isNotEmpty ? x : y;
  }

  /// 本地保存昵称/头像，并作为覆盖层持久化（不会被下拉刷新冲掉）
  Future<void> updateLocalProfile({
    String? nickName,
    String? portrait,
  }) async {
    final cur = _user;
    if (cur == null) {
      throw CmsUserException('请先登录', code: 401);
    }
    if (nickName != null) {
      final n = nickName.trim();
      _overrideNick = n.isEmpty ? null : n;
    }
    if (portrait != null) {
      final p = portrait.trim();
      _overridePortrait = p.isEmpty ? null : p;
    }
    await _saveOverrides();
    _user = _applyOverrides(
      cur.copyWith(
        nickName: nickName ?? cur.nickName,
        portrait: portrait ?? cur.portrait,
      ),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    await _api.logout();
    _user = null;
    await _clearOverrides();
    await CmsMessageStore.instance.clearForLogout();
    await _persist();
    notifyListeners();
  }
}
