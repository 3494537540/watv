import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cms_app_config.dart';

/// QQ 互联登录（参数走后台 app_config.qq_login，审核通过后填入即可）
class QqLoginService {
  QqLoginService._();
  static final instance = QqLoginService._();

  static const _channel = MethodChannel('com.watv.app/qq_login');

  QqLoginRemoteConfig get config => CmsAppConfigStore.instance.config.qqLogin;

  /// 登录引导页是否展示 QQ 入口（默认展示，方便审核/联调）
  bool get showEntry => true;

  Future<QqLoginResult> login() async {
    final cfg = config;
    if (!cfg.isReady) {
      return const QqLoginResult(
        ok: false,
        message: 'QQ登录审核中，通过后将在后台自动启用',
      );
    }
    if (kIsWeb) {
      return const QqLoginResult(ok: false, message: 'Web 暂不支持 QQ 登录');
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>('login', {
        'app_id': cfg.appId,
        'app_key': cfg.appKey,
        'universal_link': cfg.universalLink,
      });
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        final ok = m['ok'] == true;
        return QqLoginResult(
          ok: ok,
          openId: '${m['openid'] ?? m['open_id'] ?? ''}',
          accessToken: '${m['access_token'] ?? m['token'] ?? ''}',
          message: '${m['message'] ?? m['msg'] ?? (ok ? '登录成功' : '登录失败')}',
        );
      }
      return const QqLoginResult(ok: false, message: 'QQ 登录无返回');
    } on PlatformException catch (e) {
      final code = e.code;
      if (code == 'sdk_missing' || code == 'not_implemented') {
        return QqLoginResult(
          ok: false,
          message: '原生 QQ SDK 待接入（AppID ${cfg.appId} 已配置）',
        );
      }
      if (code == 'cancelled') {
        return const QqLoginResult(ok: false, message: '已取消 QQ 登录');
      }
      return QqLoginResult(
        ok: false,
        message: e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'QQ 登录失败',
      );
    } catch (e) {
      return QqLoginResult(ok: false, message: '$e');
    }
  }
}

class QqLoginResult {
  const QqLoginResult({
    required this.ok,
    this.openId = '',
    this.accessToken = '',
    this.message = '',
  });

  final bool ok;
  final String openId;
  final String accessToken;
  final String message;
}
