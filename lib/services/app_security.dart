import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';

/// 运行时安全策略：防系统代理抓包、限制坏证书放行。
///
/// 完整商业 VMP（VMProtect 等）需对 APK/so 二次加壳，无法在纯 Dart 内复刻；
/// Release 请配合：`flutter build apk --release --obfuscate --split-debug-info=build/debug-info`
/// 以及 Android R8 minify（已开启）。
class AppSecurity {
  AppSecurity._();
  static final AppSecurity instance = AppSecurity._();

  static const _channel = MethodChannel('com.watv.app/security');

  bool _installed = false;
  bool proxyForcedDirect = true;
  bool _nativeProxy = false;

  /// 启动时安装全局 HttpOverrides（尽早调用）
  void install() {
    if (_installed || kIsWeb) return;
    _installed = true;
    if (kReleaseMode) {
      HttpOverrides.global = _WatvHttpOverrides(this);
    }
  }

  /// 刷新原生层代理检测（MainActivity 就绪后调用）
  Future<void> refreshNativeProxyFlag() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      final v = await _channel.invokeMethod<bool>('isHttpProxyEnabled');
      _nativeProxy = v == true;
    } catch (_) {
      _nativeProxy = false;
    }
  }

  /// 仅允许业务站自签/IP 证书；抓包工具伪造证书一律拒绝
  bool allowBadCertificate(X509Certificate cert, String host, int port) {
    if (kDebugMode) return true;
    if (isSystemProxyLikely()) return false;
    return _isTrustedCmsHost(host);
  }

  bool _isTrustedCmsHost(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    try {
      final cms = Uri.parse(ApiConfig.macCmsBase).host.toLowerCase();
      if (cms.isNotEmpty && (h == cms || h.endsWith('.$cms'))) return true;
    } catch (_) {}
    try {
      final panel = Uri.parse(ApiConfig.productionMacCms).host.toLowerCase();
      if (panel.isNotEmpty && h == panel) return true;
    } catch (_) {}
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h)) {
      try {
        return h == Uri.parse(ApiConfig.productionMacCms).host;
      } catch (_) {}
    }
    return false;
  }

  /// 是否疑似开启了系统 HTTP(S) 代理（Charles / Fiddler / mitmproxy 等）
  bool isSystemProxyLikely() {
    if (kIsWeb) return false;
    if (_nativeProxy) return true;
    try {
      final env = Platform.environment;
      for (final key in const [
        'HTTP_PROXY',
        'HTTPS_PROXY',
        'http_proxy',
        'https_proxy',
        'ALL_PROXY',
        'all_proxy',
      ]) {
        final v = env[key]?.trim() ?? '';
        if (v.isNotEmpty && v.toLowerCase() != 'direct') return true;
      }
    } catch (_) {}
    return false;
  }

  /// 给显式创建的 HttpClient 套上同一策略
  void hardenClient(HttpClient client) {
    if (kIsWeb) return;
    client.badCertificateCallback = allowBadCertificate;
    if (kReleaseMode && proxyForcedDirect) {
      client.findProxy = (_) => 'DIRECT';
    }
  }

  String get securitySummary {
    final bits = <String>[
      '代理直连',
      '证书白名单',
      if (kReleaseMode) 'Release 混淆/R8',
    ];
    return bits.join(' · ');
  }
}

class _WatvHttpOverrides extends HttpOverrides {
  _WatvHttpOverrides(this.security);

  final AppSecurity security;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    security.hardenClient(client);
    return client;
  }
}
