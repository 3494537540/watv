import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_kit/tencent_kit.dart';

import 'cms_app_config.dart';
import 'huihuo_panel_api.dart';

/// QQ 互联登录（tencent_kit 原生 SDK + 面板 qq_oauth 写入 CMS 会话）
class QqLoginService {
  QqLoginService._();
  static final instance = QqLoginService._();

  QqLoginRemoteConfig get config => CmsAppConfigStore.instance.config.qqLogin;

  bool get showEntry => true;

  String? _registeredAppId;
  bool _permissionGranted = false;

  Future<void> ensureRegistered() async {
    if (kIsWeb) return;
    final cfg = config;
    if (!cfg.isReady) return;
    if (!_permissionGranted) {
      await TencentKitPlatform.instance.setIsPermissionGranted(granted: true);
      _permissionGranted = true;
    }
    final appId = cfg.appId.trim();
    if (_registeredAppId == appId) return;
    await TencentKitPlatform.instance.registerApp(
      appId: appId,
      universalLink: cfg.universalLink.trim().isEmpty
          ? null
          : cfg.universalLink.trim(),
    );
    _registeredAppId = appId;
  }

  /// 拉起 QQ 授权，成功后换 CMS Cookie 会话
  Future<QqLoginResult> login() async {
    final cfg = config;
    if (!cfg.isReady) {
      return const QqLoginResult(
        ok: false,
        message: 'QQ登录未配置，请在后台填写 AppID / AppKey 并启用',
      );
    }
    if (kIsWeb) {
      return const QqLoginResult(ok: false, message: 'Web 暂不支持 QQ 登录');
    }

    try {
      await ensureRegistered();
    } catch (e) {
      return QqLoginResult(ok: false, message: 'QQ SDK 初始化失败：$e');
    }

    final completer = Completer<TencentLoginResp>();
    late final StreamSubscription<TencentResp> sub;
    sub = TencentKitPlatform.instance.respStream().listen((resp) {
      if (resp is TencentLoginResp && !completer.isCompleted) {
        completer.complete(resp);
      }
    });

    try {
      await TencentKitPlatform.instance.login(
        scope: <String>[TencentScope.kGetSimpleUserInfo],
      );
      final resp = await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw TimeoutException('QQ 授权超时'),
      );

      if (resp.isCancelled) {
        return const QqLoginResult(ok: false, message: '已取消 QQ 登录');
      }
      if (!resp.isSuccessful) {
        final msg = (resp.msg ?? '').trim();
        return QqLoginResult(
          ok: false,
          message: msg.isEmpty ? 'QQ 授权失败（${resp.ret}）' : msg,
        );
      }

      final openId = (resp.openid ?? '').trim();
      final token = (resp.accessToken ?? '').trim();
      if (openId.isEmpty || token.isEmpty) {
        return const QqLoginResult(ok: false, message: 'QQ 未返回有效凭证');
      }

      // 换 CMS 登录态
      final session = await HuihuoPanelApi.qqOauthLogin(
        openId: openId,
        accessToken: token,
        nickname: '',
        expiresIn: resp.expiresIn ?? 0,
      );

      return QqLoginResult(
        ok: true,
        openId: openId,
        accessToken: token,
        message: session.msg.isEmpty ? '登录成功' : session.msg,
        cookieHeader: session.cookieHeader,
        userId: session.userId,
        userName: session.userName,
        nickName: session.nickName,
        portrait: session.portrait,
      );
    } on TimeoutException {
      return const QqLoginResult(ok: false, message: 'QQ 授权超时，请重试');
    } catch (e) {
      var s = e is StateError ? e.message : '$e';
      s = s.replaceFirst(RegExp(r'^Bad state:\s*'), '').trim();
      if (s.contains('MissingPluginException')) {
        return const QqLoginResult(
          ok: false,
          message: 'QQ SDK 未编译进当前包，请完整重新安装 App 后再试',
        );
      }
      return QqLoginResult(
        ok: false,
        message: s.isEmpty ? 'QQ 登录失败' : s,
      );
    } finally {
      await sub.cancel();
    }
  }
}

class QqLoginResult {
  const QqLoginResult({
    required this.ok,
    this.openId = '',
    this.accessToken = '',
    this.message = '',
    this.cookieHeader = '',
    this.userId = 0,
    this.userName = '',
    this.nickName = '',
    this.portrait = '',
  });

  final bool ok;
  final String openId;
  final String accessToken;
  final String message;
  final String cookieHeader;
  final int userId;
  final String userName;
  final String nickName;
  final String portrait;
}
