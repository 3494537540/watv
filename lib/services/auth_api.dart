import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_models.dart';

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String action) {
    final base = ApiConfig.baseUrl;
    final sep = base.contains('?') ? '&' : '?';
    return Uri.parse('$base${sep}action=${Uri.encodeQueryComponent(action)}');
  }

  Future<Map<String, dynamic>> _post(
    String action,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final payload = <String, dynamic>{
      ...body,
      'client': ApiConfig.client,
    };
    if (token != null && token.isNotEmpty) {
      payload['token'] = token;
    }

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri(action),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ApiException('网络连接失败，请检查接口地址与服务是否启动');
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) {
        throw ApiException('服务器返回格式异常');
      }
      json = Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('服务器返回无法解析（HTTP ${res.statusCode}）');
    }

    final code = (json['code'] as num?)?.toInt() ?? -1;
    final msg = '${json['msg'] ?? '请求失败'}';
    if (code != 0) {
      throw ApiException(msg, code: code);
    }
    final data = json['data'];
    if (data == null) return <String, dynamic>{};
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{'value': data};
  }

  Future<AuthSession> login({
    required String account,
    required String password,
  }) async {
    final data = await _post('login', {
      'account': account.trim(),
      'password': password,
    });
    final session = AuthSession.fromLoginData(data);
    if (session.token.isEmpty) {
      throw ApiException('登录成功但未返回 token');
    }
    return session;
  }

  Future<RegisterPendingResult> register({
    required String username,
    required String email,
    required String password,
    String inviteCode = '',
  }) async {
    final data = await _post('register', {
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      if (inviteCode.trim().isNotEmpty) 'invite_code': inviteCode.trim(),
    });
    return RegisterPendingResult(
      email: (data['email'] ?? email).toString(),
      needVerify: data['need_verify'] == true || data['need_verify'] == 1,
      expiresIn: (data['expires_in'] is num)
          ? (data['expires_in'] as num).toInt()
          : 0,
      message: '验证邮件已发送，请点击邮件中的链接完成注册',
    );
  }

  Future<CodeSendResult> resendVerifyEmail(String email) async {
    final data = await _post('resend_verify_email', {
      'email': email.trim(),
    });
    return _codeResult(data, fallback: '验证链接已重新发送');
  }

  Future<CodeSendResult> sendResetCode(String email) async {
    final data = await _post('send_reset_code', {
      'email': email.trim(),
      'target': email.trim(),
    });
    return _codeResult(data, fallback: '验证码已发送');
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    await _post('reset_password', {
      'email': email.trim(),
      'target': email.trim(),
      'code': code.trim(),
      'password': password,
    });
  }

  Future<AuthUser> me(String token) async {
    final data = await _post('me', {}, token: token);
    final userRaw = data['user'] ?? data;
    if (userRaw is! Map) {
      throw ApiException('无法获取用户信息');
    }
    return AuthUser.fromJson(Map<String, dynamic>.from(userRaw));
  }

  Future<void> logout(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await _post('logout', {}, token: token);
    } catch (_) {
      // 本地清会话即可
    }
  }

  /// 登录前头像预览
  Future<String?> previewAvatar(String account) async {
    final data = await _post('avatar_preview', {
      'account': account.trim(),
    });
    final avatar = '${data['avatar'] ?? ''}'.trim();
    return avatar.isEmpty ? null : avatar;
  }

  /// 更新个人资料（昵称 / 手机 / 头像）
  Future<AuthUser> updateProfile({
    required String token,
    String? nickname,
    String? mobile,
    String? avatar,
  }) async {
    final body = <String, dynamic>{
      if (nickname != null) 'nickname': nickname.trim(),
      if (mobile != null) 'mobile': mobile.trim(),
      if (avatar != null) 'avatar': avatar.trim(),
    };
    // 兼容后端多种 action 命名
    Object? lastErr;
    for (final action in ['update_profile', 'profile_update', 'user_update']) {
      try {
        final data = await _post(action, body, token: token);
        final userRaw = data['user'] ?? data;
        if (userRaw is Map) {
          return AuthUser.fromJson(Map<String, dynamic>.from(userRaw));
        }
        return me(token);
      } on ApiException catch (e) {
        lastErr = e;
        // 未知 action 继续尝试下一个
        if (e.code == 404 ||
            e.message.contains('未知') ||
            e.message.contains('不支持') ||
            e.message.contains('action')) {
          continue;
        }
        rethrow;
      }
    }
    if (lastErr is ApiException) throw lastErr;
    throw ApiException('更新资料失败');
  }

  /// 已登录修改密码
  Future<void> changePassword({
    required String token,
    required String oldPassword,
    required String newPassword,
  }) async {
    Object? lastErr;
    for (final action in ['change_password', 'update_password', 'password_update']) {
      try {
        await _post(action, {
          'old_password': oldPassword,
          'password': newPassword,
          'new_password': newPassword,
        }, token: token);
        return;
      } on ApiException catch (e) {
        lastErr = e;
        if (e.code == 404 ||
            e.message.contains('未知') ||
            e.message.contains('不支持') ||
            e.message.contains('action')) {
          continue;
        }
        rethrow;
      }
    }
    if (lastErr is ApiException) throw lastErr;
    throw ApiException('修改密码失败');
  }

  CodeSendResult _codeResult(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final dev = data['dev_code']?.toString();
    final note = data['note']?.toString();
    final msg = note?.isNotEmpty == true
        ? note!
        : (data['mail_sent'] == true ? fallback : fallback);
    return CodeSendResult(
      message: msg,
      devCode: (dev != null && dev.isNotEmpty) ? dev : null,
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 600,
    );
  }
}
