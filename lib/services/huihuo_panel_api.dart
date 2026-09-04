import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/api_config.dart';
import 'huihuo_http.dart';
import 'maccms_user_api.dart';

/// 哇TV 扩展面板公开 API（服务端仍用 `huihuo_panel.php` 文件名以兼容已部署站点）
class HuihuoPanelApi {
  HuihuoPanelApi._();

  static String get currentPlatform {
    if (kIsWeb) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// 后台通知 → 站内消息（面板优先，静态 JSON 兜底）
  static Future<List<CmsMessageItem>> fetchNotifies() async {
    Object? lastErr;
    for (final url in [
      ApiConfig.huihuoPanelNotifyUrl,
      ApiConfig.huihuoNotifyStaticUrl,
    ]) {
      try {
        final res = await huihuoHttpGet(url);
        if (res.status < 200 || res.status >= 300) {
          lastErr = 'HTTP ${res.status}';
          continue;
        }
        final body = res.body.trim();
        if (!body.startsWith('{')) {
          lastErr = '非 JSON';
          continue;
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);
        if (map['code'] == 0) {
          lastErr = map['msg'] ?? 'code=0';
          continue;
        }
        final list = map['list'];
        if (list is! List) return const [];
        return _parseNotifyList(list);
      } catch (e) {
        lastErr = e;
      }
    }
    throw StateError('notify_list 失败: $lastErr');
  }

  static int _toInt(Object? v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v'.trim()) ?? fallback;
  }

  static List<CmsMessageItem> _parseNotifyList(List<dynamic> list) {
    final out = <CmsMessageItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final j = Map<String, dynamic>.from(e);
      final rawId = '${j['id'] ?? ''}'.trim();
      if (rawId.isEmpty) continue;
      final title = '${j['title'] ?? ''}'.trim();
      final content = '${j['body'] ?? j['content'] ?? ''}'.trim();
      final link = '${j['link'] ?? ''}'.trim();
      final createdRaw = _toInt(j['created_at']);
      final createdAt = createdRaw <= 0
          ? 0
          : (createdRaw > 1e12 ? createdRaw : createdRaw * 1000);
      out.add(
        CmsMessageItem(
          id: 'hh_$rawId',
          title: title.isEmpty ? '通知' : title,
          content: content,
          timeText: '',
          createdAt: createdAt,
          link: link,
          tag: '${j['tag'] ?? ''}'.trim(),
          subtitle: '${j['subtitle'] ?? ''}'.trim(),
          coverUrl: '${j['cover_url'] ?? j['coverUrl'] ?? ''}'.trim(),
          accent: '${j['accent'] ?? ''}'.trim(),
          style: '${j['style'] ?? 'normal'}'.trim().isEmpty
              ? 'normal'
              : '${j['style'] ?? 'normal'}'.trim(),
        ),
      );
    }
    return out;
  }

  /// 按影片 ID / 片名拉取评论（DB）
  static Future<List<Map<String, dynamic>>> fetchCommentRows({
    String rid = '',
    String name = '',
    int mid = 1,
    int page = 1,
  }) async {
    final id = rid.trim();
    final title = name.trim();
    if (id.isEmpty && title.isEmpty) return const [];
    final url = ApiConfig.huihuoPanelCommentListUrl(
      rid: id,
      name: title,
      mid: mid,
      page: page,
    );
    final res = await huihuoHttpGet(url);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('comment_list HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) throw StateError('comment_list 非 JSON');
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final map = Map<String, dynamic>.from(decoded);
    if (map['code'] == 0) {
      throw StateError('${map['msg'] ?? 'comment_list 失败'}');
    }
    final list = map['list'];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  /// 当前端最新版本；[platform] 默认本机 android/ios
  static Future<HuihuoAppUpdate?> fetchAppUpdate({String? platform}) async {
    final p = (platform ?? currentPlatform).toLowerCase();
    final url = '${ApiConfig.huihuoPanelUpdateUrl}&platform=$p';
    final res = await huihuoHttpGet(url);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('app_update HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) return null;
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    Map<String, dynamic>? data;
    if (map['data'] is Map) {
      data = Map<String, dynamic>.from(map['data'] as Map);
    } else if (map.containsKey('version') || map.containsKey('version_code')) {
      data = map;
    }
    if (data == null || data.isEmpty) return null;
    final version = '${data['version'] ?? ''}'.trim();
    final code = _toInt(data['version_code']);
    final download = '${data['download_url'] ?? data['apk_url'] ?? data['url'] ?? ''}'
        .trim();
    if (version.isEmpty && code <= 0 && download.isEmpty) return null;
    final force = data['force_update'] == true ||
        data['force_update'] == 1 ||
        '${data['force_update']}' == '1';
    return HuihuoAppUpdate(
      platform: '${data['platform'] ?? p}'.trim().isEmpty
          ? p
          : '${data['platform'] ?? p}'.trim(),
      version: version.isEmpty ? '新版本' : version,
      versionCode: code,
      downloadUrl: download,
      changelog: '${data['changelog'] ?? ''}'.trim(),
      forceUpdate: force,
      updatedAt: _toInt(data['updated_at']),
      appName: '${data['app_name'] ?? data['title'] ?? ''}'.trim(),
      iconUrl: '${data['icon_url'] ?? data['icon'] ?? ''}'.trim(),
      bgUrl: '${data['bg_url'] ?? data['cover'] ?? data['banner'] ?? ''}'.trim(),
    );
  }

  /// 上报用户已更新 / 点击更新（后台「更新记录」）
  static Future<void> reportUpdate({
    required HuihuoAppUpdate remote,
    required int fromCode,
    required String fromVersion,
    required String deviceId,
    int userId = 0,
    String userName = '',
  }) async {
    final url = ApiConfig.huihuoPanelReportUrl;
    await huihuoHttpPostJson(url, {
      'platform': remote.platform,
      'device_id': deviceId,
      'user_id': userId,
      'user_name': userName,
      'from_code': fromCode,
      'from_version': fromVersion,
      'to_code': remote.versionCode,
      'to_version': remote.version,
    });
  }

  /// 兑换码：积分 / 会员天数
  static Future<({String msg, String rewardText})> redeemCode({
    required String code,
    required int userId,
    String userName = '',
  }) async {
    final res = await huihuoHttpPostJson(ApiConfig.huihuoPanelRedeemUrl, {
      'code': code.trim(),
      'user_id': userId,
      'user_name': userName,
    });
    if (res.status < 200 || res.status >= 300) {
      throw StateError('兑换失败 HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) throw StateError('兑换接口异常');
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw StateError('兑换接口异常');
    final map = Map<String, dynamic>.from(decoded);
    final ok = map['code'] == 1 || map['code'] == '1';
    final msg = '${map['msg'] ?? ''}'.trim();
    if (!ok) {
      throw StateError(msg.isEmpty ? '兑换失败' : msg);
    }
    final reward = '${map['reward_text'] ?? msg}'.trim();
    return (msg: msg.isEmpty ? '兑换成功' : msg, rewardText: reward);
  }
}

class HuihuoAppUpdate {
  const HuihuoAppUpdate({
    required this.platform,
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    this.changelog = '',
    this.forceUpdate = false,
    this.updatedAt = 0,
    this.appName = '',
    this.iconUrl = '',
    this.bgUrl = '',
  });

  final String platform;
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;
  final int updatedAt;
  /// 弹窗展示名（后台可配）
  final String appName;
  final String iconUrl;
  final String bgUrl;

  /// 兼容旧字段名
  String get apkUrl => downloadUrl;

  String get displayName =>
      appName.trim().isEmpty ? '哇TV' : appName.trim();

  bool isNewerThan(int localCode) =>
      versionCode > 0 && versionCode > localCode;
}
