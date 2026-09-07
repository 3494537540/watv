import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cms_message_store.dart';
import '../services/huihuo_panel_api.dart';
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
        // 启动刷新必须与下拉刷新同一套合并逻辑，禁止整份覆盖本地 QQ 头像/积分
        await refreshProfile();
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
    if (nick.isNotEmpty && !CmsUser.isJunkDisplayName(nick)) {
      u = u.copyWith(nickName: nick);
    }
    if (portrait.isNotEmpty && !CmsUser.isJunkPortrait(portrait)) {
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

  /// QQ 互联：面板已签发 Cookie，注入后拉资料
  /// QQ 无 PHPSESSID 时主题会员页常解析不出积分，必须以面板 / oauth 积分为准。
  Future<void> loginWithQq({
    required String cookieHeader,
    int userId = 0,
    String userName = '',
    String nickName = '',
    String portrait = '',
    int points = 0,
  }) async {
    final cookie = cookieHeader.trim();
    if (cookie.isEmpty) {
      throw CmsUserException('QQ 登录未返回会话');
    }
    _busy = true;
    notifyListeners();
    try {
      await _api.applySessionCookies(cookie);
      final cookieUid =
          int.tryParse(_api.sessionCookieUserId) ?? 0;
      var uid = userId > 0 ? userId : cookieUid;

      // 先用 oauth 返回值建档（积分直接带来，不依赖主题 HTML）
      var user = CmsUser(
        userId: uid,
        userName: userName.trim().isEmpty ? 'QQ用户' : userName.trim(),
        nickName: nickName.trim(),
        portrait: portrait.trim(),
        points: points > 0 ? points : 0,
      );

      // 再拉面板 DB（最准）
      if (uid > 0) {
        final panel = await _api.fetchPanelUser(uid);
        if (panel != null) {
          user = user.copyWith(
            userId: panel.userId > 0 ? panel.userId : user.userId,
            points: panel.points,
            groupName: panel.groupName.trim().isNotEmpty &&
                    panel.groupName.trim() != '游客'
                ? panel.groupName
                : user.groupName,
            endTime: panel.endTime.trim().isNotEmpty
                ? panel.endTime
                : user.endTime,
            loginTime: panel.loginTime.trim().isNotEmpty
                ? panel.loginTime
                : user.loginTime,
            loginIp: panel.loginIp.trim().isNotEmpty
                ? panel.loginIp
                : user.loginIp,
          );
          final pp = panel.portrait.trim();
          if (pp.isNotEmpty && !CmsUser.isJunkPortrait(pp)) {
            user = user.copyWith(portrait: pp);
          }
          final pn = panel.nickName.trim();
          if (pn.isNotEmpty && !CmsUser.isJunkDisplayName(pn)) {
            if (user.nickName.trim().isEmpty ||
                CmsUser.isJunkDisplayName(user.nickName)) {
              user = user.copyWith(nickName: pn);
            }
          }
          final pu = panel.userName.trim();
          if (pu.isNotEmpty && !CmsUser.isJunkDisplayName(pu)) {
            user = user.copyWith(userName: pu);
          }
        } else {
          // 面板失败时用打卡状态接口兜底积分
          try {
            final s = await HuihuoPanelApi.fetchCheckinStatus(uid);
            if (s.userPoints > 0) {
              user = user.copyWith(points: s.userPoints);
            }
          } catch (_) {}
        }
      }

      // 主题页可选补全（失败忽略；绝不能冲掉积分/QQ头像/昵称）
      try {
        final profile = await _api.fetchProfile();
        final keepPoints = user.points;
        final keepPortrait = user.portrait;
        final keepNick = user.nickName;
        user = user.merge(profile);
        if (profile.points > keepPoints) {
          user = user.copyWith(points: profile.points);
        } else if (keepPoints > 0) {
          user = user.copyWith(points: keepPoints);
        }
        if (keepPortrait.trim().isNotEmpty &&
            !CmsUser.isJunkPortrait(keepPortrait)) {
          user = user.copyWith(portrait: keepPortrait);
        }
        if (keepNick.trim().isNotEmpty &&
            !CmsUser.isJunkDisplayName(keepNick)) {
          user = user.copyWith(nickName: keepNick);
        }
        if (user.userId <= 0 && uid > 0) {
          user = user.copyWith(userId: uid);
        }
      } catch (_) {}

      if (nickName.trim().isNotEmpty &&
          !CmsUser.isJunkDisplayName(nickName)) {
        user = user.copyWith(nickName: nickName.trim());
      } else if (CmsUser.isJunkDisplayName(user.nickName)) {
        user = user.copyWith(nickName: '');
      }
      if (portrait.trim().isNotEmpty &&
          !CmsUser.isJunkPortrait(portrait)) {
        user = user.copyWith(portrait: portrait.trim());
      }

      // QQ 头像/昵称写入覆盖层：重启/主题页空资料时仍能还原
      await _clearOverrides();
      final qqNick = user.nickName.trim();
      final qqPortrait = user.portrait.trim();
      if (qqNick.isNotEmpty && !CmsUser.isJunkDisplayName(qqNick)) {
        _overrideNick = qqNick;
      }
      if (qqPortrait.isNotEmpty && !CmsUser.isJunkPortrait(qqPortrait)) {
        _overridePortrait = qqPortrait;
      }
      await _saveOverrides();
      _user = _applyOverrides(user);
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
      final merged = CmsUser(
        userId: me.userId > 0 ? me.userId : local.userId,
        userName: _preferText(me.userName, local.userName),
        nickName: _preferNick(me.nickName, local.nickName),
        email: _preferText(me.email, local.email),
        qq: _preferText(me.qq, local.qq),
        phone: _preferText(me.phone, local.phone),
        // 头像：优先保留本地/QQ 有效 https 图，不被主题空图冲掉
        portrait: _preferPortrait(me.portrait, local.portrait),
        // 积分：主题页常解析成 0，0 时保留本地
        points: me.points > 0 ? me.points : local.points,
        extend: me.extend > 0 ? me.extend : local.extend,
        groupName: me.groupName.trim().isNotEmpty && me.groupName.trim() != '游客'
            ? me.groupName
            : local.groupName,
        endTime:
            me.endTime.trim().isNotEmpty ? me.endTime : local.endTime,
        loginTime: me.loginTime.trim().isNotEmpty
            ? me.loginTime
            : local.loginTime,
        loginIp:
            me.loginIp.trim().isNotEmpty ? me.loginIp : local.loginIp,
      );
      _user = _applyOverrides(merged);

      final uid = _user?.userId ?? 0;
      if (uid > 0) {
        try {
          final panel = await _api.fetchPanelUser(uid);
          if (panel != null) {
            var u = _user!;
            if (panel.points > 0 || u.points <= 0) {
              u = u.copyWith(points: panel.points);
            }
            final pp = panel.portrait.trim();
            if (pp.isNotEmpty && !CmsUser.isJunkPortrait(pp)) {
              u = u.copyWith(portrait: pp);
            }
            final pn = panel.nickName.trim();
            if (pn.isNotEmpty && !CmsUser.isJunkDisplayName(pn)) {
              if (CmsUser.isJunkDisplayName(u.nickName)) {
                u = u.copyWith(nickName: pn);
              }
            }
            if (panel.groupName.trim().isNotEmpty &&
                panel.groupName.trim() != '游客') {
              u = u.copyWith(groupName: panel.groupName);
            }
            _user = _applyOverrides(u);
          }
        } catch (_) {}
      }

      if ((_user?.points ?? 0) <= 0 && uid > 0) {
        try {
          final s = await HuihuoPanelApi.fetchCheckinStatus(uid);
          if (s.userPoints > 0) {
            _user = _user!.copyWith(points: s.userPoints);
          }
        } catch (_) {}
      }
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

  /// 打卡等接口直接回写积分（面板 DB 值）
  Future<void> applyLocalPoints(int points) async {
    final u = _user;
    if (u == null || points < 0) return;
    _user = u.copyWith(points: points);
    await _persist();
    notifyListeners();
  }

  static String _preferText(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.isNotEmpty && !CmsUser.isJunkDisplayName(x)) return x;
    if (y.isNotEmpty && !CmsUser.isJunkDisplayName(y)) return y;
    return x.isNotEmpty ? x : y;
  }

  static String _preferNick(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.isNotEmpty && !CmsUser.isJunkDisplayName(x)) return x;
    if (y.isNotEmpty && !CmsUser.isJunkDisplayName(y)) return y;
    return '';
  }

  static String _preferPortrait(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    final xOk = x.isNotEmpty && !CmsUser.isJunkPortrait(x);
    final yOk = y.isNotEmpty && !CmsUser.isJunkPortrait(y);
    // 两边都有效时，优先 https QQ/远程头像，其次本地已有
    if (xOk && yOk) {
      final xHttp = x.startsWith('http://') || x.startsWith('https://');
      final yHttp = y.startsWith('http://') || y.startsWith('https://');
      if (yHttp && !xHttp) return y;
      if (xHttp) return x;
      return y;
    }
    if (yOk) return y;
    if (xOk) return x;
    return '';
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
