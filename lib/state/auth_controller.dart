import 'package:flutter/foundation.dart';

import '../models/auth_models.dart';
import '../services/auth_api.dart';
import '../services/auth_store.dart';

/// 全局登录态
class AuthController extends ChangeNotifier {
  AuthController({AuthApi? api}) : _api = api ?? AuthApi();

  static final AuthController instance = AuthController();

  final AuthApi _api;

  AuthSession? _session;
  bool _ready = false;
  bool _busy = false;

  bool get isReady => _ready;
  bool get isBusy => _busy;
  bool get isLoggedIn => _session != null && _session!.token.isNotEmpty;
  AuthSession? get session => _session;
  AuthUser? get user => _session?.user;
  String? get token => _session?.token;

  Future<void> bootstrap() async {
    final saved = await AuthStore.load();
    if (saved != null) {
      _session = saved;
      notifyListeners();
      // 后台刷新用户信息；失败则保留本地缓存
      try {
        final me = await _api.me(saved.token);
        _session = AuthSession(
          token: saved.token,
          tokenExpired: saved.tokenExpired,
          user: me,
        );
        await AuthStore.save(_session!);
      } on ApiException catch (e) {
        if (e.code == 401 || e.code == 403) {
          await AuthStore.clear();
          _session = null;
        }
      } catch (_) {}
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> login({
    required String account,
    required String password,
  }) async {
    _busy = true;
    notifyListeners();
    try {
      final session = await _api.login(account: account, password: password);
      _session = session;
      await AuthStore.save(session);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<RegisterPendingResult> register({
    required String username,
    required String email,
    required String password,
    String inviteCode = '',
  }) async {
    _busy = true;
    notifyListeners();
    try {
      return await _api.register(
        username: username,
        email: email,
        password: password,
        inviteCode: inviteCode,
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<CodeSendResult> resendVerifyEmail(String email) {
    return _api.resendVerifyEmail(email);
  }

  Future<CodeSendResult> sendResetCode(String email) {
    return _api.sendResetCode(email);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) {
    return _api.resetPassword(email: email, code: code, password: password);
  }

  Future<void> logout() async {
    final t = _session?.token;
    await _api.logout(t);
    await AuthStore.clear();
    _session = null;
    notifyListeners();
  }

  Future<void> refreshMe() async {
    final saved = _session;
    if (saved == null || saved.token.isEmpty) return;
    final me = await _api.me(saved.token);
    _session = AuthSession(
      token: saved.token,
      tokenExpired: saved.tokenExpired,
      user: me,
    );
    await AuthStore.save(_session!);
    notifyListeners();
  }

  Future<void> applyUser(AuthUser user) async {
    final saved = _session;
    if (saved == null) return;
    _session = AuthSession(
      token: saved.token,
      tokenExpired: saved.tokenExpired,
      user: user,
    );
    await AuthStore.save(_session!);
    notifyListeners();
  }

  Future<String?> previewAvatar(String account) {
    return _api.previewAvatar(account);
  }

  Future<void> updateProfile({
    String? nickname,
    String? mobile,
    String? avatar,
  }) async {
    final saved = _session;
    if (saved == null || saved.token.isEmpty) {
      throw ApiException('请先登录');
    }
    _busy = true;
    notifyListeners();
    try {
      final user = await _api.updateProfile(
        token: saved.token,
        nickname: nickname,
        mobile: mobile,
        avatar: avatar,
      );
      _session = AuthSession(
        token: saved.token,
        tokenExpired: saved.tokenExpired,
        user: user,
      );
      await AuthStore.save(_session!);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final saved = _session;
    if (saved == null || saved.token.isEmpty) {
      throw ApiException('请先登录');
    }
    await _api.changePassword(
      token: saved.token,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }
}
