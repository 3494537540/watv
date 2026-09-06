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

  /// 当前用户评论记录
  static Future<List<Map<String, dynamic>>> fetchMyCommentRows({
    required int userId,
    int page = 1,
    int limit = 30,
    String userName = '',
    String nickName = '',
    List<String> aliases = const [],
  }) async {
    if (userId <= 0 &&
        userName.trim().isEmpty &&
        nickName.trim().isEmpty &&
        aliases.isEmpty) {
      return const [];
    }
    final url = ApiConfig.huihuoPanelCommentMineUrl(
      userId: userId,
      page: page,
      limit: limit,
      userName: userName,
      nickName: nickName,
      aliases: aliases,
    );
    final res = await huihuoHttpGet(url);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('comment_mine HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) {
      // 旧面板未部署该接口时返回 HTML
      throw StateError('服务端面板未更新（缺少 comment_mine）');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final map = Map<String, dynamic>.from(decoded);
    if (map['code'] == 0) {
      throw StateError('${map['msg'] ?? 'comment_mine 失败'}');
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
    final download =
        '${data['download_url'] ?? data['apk_url'] ?? data['url'] ?? ''}'
            .trim();
    if (version.isEmpty && code <= 0 && download.isEmpty) return null;
    return HuihuoAppUpdate.fromJson(data, fallbackPlatform: p);
  }

  /// 官网接口：双端包信息 + 更新日志归档
  static Future<HuihuoWebsiteBundle> fetchWebsiteBundle() async {
    final res = await huihuoHttpGet(ApiConfig.huihuoPanelWebsiteUrl);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('website HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) {
      return const HuihuoWebsiteBundle();
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const HuihuoWebsiteBundle();
    final map = Map<String, dynamic>.from(decoded);
    final data = map['data'];
    if (data is! Map) return const HuihuoWebsiteBundle();
    final dm = Map<String, dynamic>.from(data);
    HuihuoAppUpdate? pack(Object? raw, String plat) {
      if (raw is! Map) return null;
      return HuihuoAppUpdate.fromJson(
        Map<String, dynamic>.from(raw),
        fallbackPlatform: plat,
      );
    }

    final logs = <HuihuoChangelogEntry>[];
    final rawLogs = dm['changelogs'];
    if (rawLogs is List) {
      for (final e in rawLogs) {
        if (e is! Map) continue;
        final entry = HuihuoChangelogEntry.fromJson(Map<String, dynamic>.from(e));
        if (entry.version.isNotEmpty || entry.changelog.isNotEmpty) {
          logs.add(entry);
        }
      }
    }
    return HuihuoWebsiteBundle(
      android: pack(dm['android'], 'android'),
      ios: pack(dm['ios'], 'ios'),
      changelogs: logs,
    );
  }

  /// 当前端更新日志（优先归档列表）
  static Future<List<HuihuoChangelogEntry>> fetchChangelogs({
    String? platform,
  }) async {
    final p = (platform ?? currentPlatform).toLowerCase();
    final bundle = await fetchWebsiteBundle();
    final filtered = [
      for (final e in bundle.changelogs)
        if (e.platform.isEmpty || e.platform == p) e,
    ];
    if (filtered.isNotEmpty) return filtered;
    final current = p == 'ios' ? bundle.ios : bundle.android;
    if (current == null) return const [];
    return [
      HuihuoChangelogEntry(
        platform: current.platform,
        version: current.version,
        versionCode: current.versionCode,
        downloadUrl: current.downloadUrl,
        changelog: current.changelog,
        appName: current.appName,
        createdAt: current.updatedAt,
      ),
    ];
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

  /// QQ 授权凭证 → CMS Cookie 会话
  static Future<QqOauthSession> qqOauthLogin({
    required String openId,
    required String accessToken,
    String nickname = '',
    int expiresIn = 0,
  }) async {
    final res = await huihuoHttpPostJson(ApiConfig.huihuoPanelQqOauthUrl, {
      'openid': openId,
      'access_token': accessToken,
      if (nickname.trim().isNotEmpty) 'nickname': nickname.trim(),
      if (expiresIn > 0) 'expires_in': expiresIn,
    });
    if (res.status < 200 || res.status >= 300) {
      throw StateError('QQ 登录失败 HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) throw StateError('QQ 登录接口异常');
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw StateError('QQ 登录接口异常');
    final map = Map<String, dynamic>.from(decoded);
    final ok = map['code'] == 1 || map['code'] == '1';
    final msg = '${map['msg'] ?? ''}'.trim();
    if (!ok) {
      throw StateError(msg.isEmpty ? 'QQ 登录失败' : msg);
    }
    final data = map['data'];
    final d = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final cookie = '${d['cookie'] ?? d['cookie_header'] ?? ''}'.trim();
    if (cookie.isEmpty) {
      throw StateError('QQ 登录未返回会话 Cookie');
    }
    return QqOauthSession(
      cookieHeader: cookie,
      userId: int.tryParse('${d['user_id'] ?? 0}') ?? 0,
      userName: '${d['user_name'] ?? ''}'.trim(),
      nickName: '${d['nick_name'] ?? d['nickname'] ?? ''}'.trim(),
      portrait: '${d['portrait'] ?? ''}'.trim(),
      msg: msg.isEmpty ? '登录成功' : msg,
    );
  }

  /// 触发服务端扫描采集新增 → 写入站内公告
  /// 返回新增片名列表（可能为空）
  static Future<List<String>> syncVodCollectAnnounce() async {
    final res = await huihuoHttpGet(ApiConfig.huihuoPanelVodCollectSyncUrl);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('片库同步失败 HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) return const [];
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const [];
    final map = Map<String, dynamic>.from(decoded);
    if (map['code'] != 1 && map['code'] != '1') {
      throw StateError('${map['msg'] ?? '片库同步失败'}');
    }
    final raw = map['titles'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if ('$e'.trim().isNotEmpty) '$e'.trim(),
    ];
  }

  /// 查询打卡状态
  static Future<HuihuoCheckinStatus> fetchCheckinStatus(int userId) async {
    final res = await huihuoHttpGet(
      ApiConfig.huihuoPanelCheckinStatusUrl(userId),
    );
    if (res.status < 200 || res.status >= 300) {
      throw StateError('打卡状态失败 HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) throw StateError('打卡状态异常');
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw StateError('打卡状态异常');
    final map = Map<String, dynamic>.from(decoded);
    if (map['code'] != 1 && map['code'] != '1') {
      throw StateError('${map['msg'] ?? '打卡状态失败'}');
    }
    final data = map['data'];
    if (data is! Map) return const HuihuoCheckinStatus();
    return HuihuoCheckinStatus.fromJson(Map<String, dynamic>.from(data));
  }

  /// 每日打卡（写入 CMS 积分）
  static Future<HuihuoCheckinStatus> checkIn({required int userId}) async {
    final res = await huihuoHttpPostJson(ApiConfig.huihuoPanelCheckinUrl, {
      'user_id': userId,
    });
    if (res.status < 200 || res.status >= 300) {
      throw StateError('打卡失败 HTTP ${res.status}');
    }
    final body = res.body.trim();
    if (!body.startsWith('{')) throw StateError('打卡接口异常');
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw StateError('打卡接口异常');
    final map = Map<String, dynamic>.from(decoded);
    final msg = '${map['msg'] ?? ''}'.trim();
    final data = map['data'];
    final status = data is Map
        ? HuihuoCheckinStatus.fromJson(Map<String, dynamic>.from(data))
        : const HuihuoCheckinStatus(checkedToday: true);
    final ok = map['code'] == 1 || map['code'] == '1';
    if (!ok) {
      throw StateError(msg.isEmpty ? '今日已打卡' : msg);
    }
    return status.copyWith(message: msg.isEmpty ? '打卡成功' : msg);
  }
}

class HuihuoCheckinStatus {
  const HuihuoCheckinStatus({
    this.checkedToday = false,
    this.streak = 0,
    this.total = 0,
    this.rewardPoints = 10,
    this.userPoints = 0,
    this.message = '',
  });

  final bool checkedToday;
  final int streak;
  final int total;
  final int rewardPoints;
  final int userPoints;
  final String message;

  factory HuihuoCheckinStatus.fromJson(Map<String, dynamic> m) {
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return HuihuoCheckinStatus(
      checkedToday: asInt(m['checked_today']) == 1 || m['checked_today'] == true,
      streak: asInt(m['streak']),
      total: asInt(m['total']),
      rewardPoints: asInt(m['reward_points'] ?? 10),
      userPoints: asInt(m['user_points']),
    );
  }

  HuihuoCheckinStatus copyWith({String? message}) => HuihuoCheckinStatus(
        checkedToday: checkedToday,
        streak: streak,
        total: total,
        rewardPoints: rewardPoints,
        userPoints: userPoints,
        message: message ?? this.message,
      );
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
    this.websiteUrl = '',
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
  /// 官网下载页（空则用 [ApiConfig.officialWebsiteUrl]）
  final String websiteUrl;

  /// 兼容旧字段名
  String get apkUrl => downloadUrl;

  String get displayName =>
      appName.trim().isEmpty ? '哇TV' : appName.trim();

  String get resolvedWebsiteUrl {
    final w = websiteUrl.trim();
    if (w.isNotEmpty) return w;
    return ApiConfig.officialWebsiteUrl;
  }

  bool isNewerThan(int localCode) =>
      versionCode > 0 && versionCode > localCode;

  factory HuihuoAppUpdate.fromJson(
    Map<String, dynamic> data, {
    String fallbackPlatform = 'android',
  }) {
    final version = '${data['version'] ?? ''}'.trim();
    final code = HuihuoPanelApi._toInt(data['version_code']);
    final download =
        '${data['download_url'] ?? data['apk_url'] ?? data['url'] ?? ''}'
            .trim();
    final force = data['force_update'] == true ||
        data['force_update'] == 1 ||
        '${data['force_update']}' == '1';
    final platRaw = '${data['platform'] ?? fallbackPlatform}'.trim();
    return HuihuoAppUpdate(
      platform: platRaw.isEmpty ? fallbackPlatform : platRaw,
      version: version.isEmpty ? '新版本' : version,
      versionCode: code,
      downloadUrl: download,
      changelog: '${data['changelog'] ?? ''}'.trim(),
      forceUpdate: force,
      updatedAt: HuihuoPanelApi._toInt(data['updated_at'] ?? data['created_at']),
      appName: '${data['app_name'] ?? data['title'] ?? ''}'.trim(),
      iconUrl: '${data['icon_url'] ?? data['icon'] ?? ''}'.trim(),
      bgUrl: '${data['bg_url'] ?? data['cover'] ?? data['banner'] ?? ''}'.trim(),
      websiteUrl:
          '${data['website_url'] ?? data['site_url'] ?? data['web_url'] ?? ''}'
              .trim(),
    );
  }
}

class HuihuoWebsiteBundle {
  const HuihuoWebsiteBundle({
    this.android,
    this.ios,
    this.changelogs = const [],
  });

  final HuihuoAppUpdate? android;
  final HuihuoAppUpdate? ios;
  final List<HuihuoChangelogEntry> changelogs;
}

class HuihuoChangelogEntry {
  const HuihuoChangelogEntry({
    this.id = 0,
    this.platform = '',
    this.version = '',
    this.versionCode = 0,
    this.downloadUrl = '',
    this.changelog = '',
    this.appName = '',
    this.createdAt = 0,
  });

  final int id;
  final String platform;
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String changelog;
  final String appName;
  final int createdAt;

  factory HuihuoChangelogEntry.fromJson(Map<String, dynamic> m) {
    return HuihuoChangelogEntry(
      id: HuihuoPanelApi._toInt(m['id']),
      platform: '${m['platform'] ?? ''}'.trim().toLowerCase(),
      version: '${m['version'] ?? ''}'.trim(),
      versionCode: HuihuoPanelApi._toInt(m['version_code']),
      downloadUrl: '${m['download_url'] ?? m['apk_url'] ?? ''}'.trim(),
      changelog: '${m['changelog'] ?? ''}'.trim(),
      appName: '${m['app_name'] ?? ''}'.trim(),
      createdAt: HuihuoPanelApi._toInt(m['created_at'] ?? m['updated_at']),
    );
  }
}

/// QQ OAuth → 面板签发的 CMS 会话
class QqOauthSession {
  const QqOauthSession({
    required this.cookieHeader,
    this.userId = 0,
    this.userName = '',
    this.nickName = '',
    this.portrait = '',
    this.msg = '',
  });

  final String cookieHeader;
  final int userId;
  final String userName;
  final String nickName;
  final String portrait;
  final String msg;
}
