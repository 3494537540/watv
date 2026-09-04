import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'huihuo_http.dart';

/// 底栏一项（可由 CMS 远程配置覆盖）
class AppTabSpec {
  const AppTabSpec({
    required this.id,
    required this.label,
    this.enabled = true,
  });

  final String id;
  final String label;
  final bool enabled;

  factory AppTabSpec.fromJson(Map<String, dynamic> j) => AppTabSpec(
        id: '${j['id'] ?? ''}'.trim(),
        label: '${j['label'] ?? j['name'] ?? ''}'.trim(),
        enabled: j['enabled'] != false && j['enable'] != 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'enabled': enabled,
      };
}

/// 策划栏 / 快捷入口
class AppNavItem {
  const AppNavItem({
    required this.title,
    this.url = '',
    this.action = '',
    this.icon = '',
    this.typeId,
  });

  final String title;
  final String url;
  final String action; // live / sports / filter / short_drama / bt / cloud / art / url / type
  final String icon;
  final int? typeId;

  factory AppNavItem.fromJson(Map<String, dynamic> j) => AppNavItem(
        title: '${j['title'] ?? j['name'] ?? ''}'.trim(),
        url: '${j['url'] ?? j['link'] ?? ''}'.trim(),
        action: '${j['action'] ?? j['type'] ?? ''}'.trim(),
        icon: '${j['icon'] ?? ''}'.trim(),
        typeId: (j['type_id'] as num?)?.toInt() ??
            int.tryParse('${j['type_id'] ?? ''}'),
      );
}

/// 直播源条目（远程配置）
class AppLiveSource {
  const AppLiveSource({
    required this.name,
    required this.url,
    this.group = '默认',
    this.logo = '',
  });

  final String name;
  final String url;
  final String group;
  final String logo;

  factory AppLiveSource.fromJson(Map<String, dynamic> j) => AppLiveSource(
        name: '${j['name'] ?? j['title'] ?? ''}'.trim(),
        url: '${j['url'] ?? j['play_url'] ?? ''}'.trim(),
        group: '${j['group'] ?? j['category'] ?? '默认'}'.trim(),
        logo: '${j['logo'] ?? j['pic'] ?? ''}'.trim(),
      );
}

/// QQ 互联远程开关（审核通过后后台填 app_id / app_key 即可）
class QqLoginRemoteConfig {
  const QqLoginRemoteConfig({
    this.enabled = false,
    this.appId = '',
    this.appKey = '',
    this.universalLink = '',
  });

  final bool enabled;
  final String appId;
  final String appKey;
  final String universalLink;

  bool get isReady =>
      enabled && appId.trim().isNotEmpty && appKey.trim().isNotEmpty;

  factory QqLoginRemoteConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const QqLoginRemoteConfig();
    return QqLoginRemoteConfig(
      enabled: j['enabled'] == true || j['enable'] == 1 || j['enable'] == true,
      appId: '${j['app_id'] ?? j['appId'] ?? j['qq_app_id'] ?? ''}'.trim(),
      appKey: '${j['app_key'] ?? j['appKey'] ?? j['qq_app_key'] ?? ''}'.trim(),
      universalLink:
          '${j['universal_link'] ?? j['universalLink'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'app_id': appId,
        'app_key': appKey,
        if (universalLink.isNotEmpty) 'universal_link': universalLink,
      };
}

/// App 远程配置（CMS 静态 JSON + 本地缓存）
///
/// 后台上传路径建议：`/static/app/app_config.json`
class CmsAppConfig {
  const CmsAppConfig({
    this.tabs = const [],
    this.nav = const [],
    this.liveSources = const [],
    this.liveM3uUrl = '',
    this.torrentParseApi = '',
    this.sportsTypeId = ApiConfig.macCmsSportsTypeId,
    this.sportsEventTypeId = ApiConfig.macCmsSportsEventTypeId,
    this.liveTypeKeywords = const ['直播', 'CCTV', '卫视'],
    this.qqLogin = const QqLoginRemoteConfig(),
    this.updatedAt = 0,
  });

  final List<AppTabSpec> tabs;
  final List<AppNavItem> nav;
  final List<AppLiveSource> liveSources;
  final String liveM3uUrl;
  final String torrentParseApi;
  final int sportsTypeId;
  final int sportsEventTypeId;
  final List<String> liveTypeKeywords;
  final QqLoginRemoteConfig qqLogin;
  final int updatedAt;

  static const defaults = CmsAppConfig(
    tabs: [
      AppTabSpec(id: 'home', label: '首页'),
      AppTabSpec(id: 'filter', label: '筛选'),
      AppTabSpec(id: 'news', label: '资讯'),
      AppTabSpec(id: 'profile', label: '我的'),
    ],
    nav: [
      AppNavItem(title: '短剧', action: 'short_drama'),
      AppNavItem(title: '体育', action: 'sports'),
      AppNavItem(title: '文章', action: 'art'),
    ],
  );

  List<AppTabSpec> get enabledTabs {
    final src = tabs.isEmpty ? defaults.tabs : tabs;
    final out = <AppTabSpec>[];
    var hasNews = false;
    for (final t in src) {
      if (!t.enabled || t.id.isEmpty) continue;
      // 去掉短视频 / 直播 / 体育底栏；旧「功能」改成资讯
      if (t.id == 'short' || t.id == 'sports' || t.id == 'live') continue;
      if (t.id == 'tasks') {
        out.add(const AppTabSpec(id: 'news', label: '资讯'));
        hasNews = true;
        continue;
      }
      if (t.id == 'news' || t.id == 'art') {
        hasNews = true;
        out.add(AppTabSpec(id: 'news', label: t.label.isEmpty ? '资讯' : t.label));
        continue;
      }
      out.add(t);
    }
    if (!hasNews) {
      final insertAt = out.indexWhere((t) => t.id == 'filter');
      const news = AppTabSpec(id: 'news', label: '资讯');
      if (insertAt >= 0) {
        out.insert(insertAt + 1, news);
      } else {
        out.insert((out.length / 2).floor().clamp(0, out.length), news);
      }
    }
    return out.isEmpty ? defaults.tabs : out;
  }

  factory CmsAppConfig.fromJson(Map<String, dynamic> j) {
    final tabsRaw = j['tabs'] ?? j['bottom_tabs'];
    final navRaw = j['nav'] ?? j['menu'] ?? j['planning'];
    final liveRaw = j['live_sources'] ?? j['lives'];
    return CmsAppConfig(
      tabs: [
        if (tabsRaw is List)
          for (final e in tabsRaw)
            if (e is Map)
              AppTabSpec.fromJson(Map<String, dynamic>.from(e)),
      ],
      nav: [
        if (navRaw is List)
          for (final e in navRaw)
            if (e is Map)
              AppNavItem.fromJson(Map<String, dynamic>.from(e)),
      ],
      liveSources: [
        if (liveRaw is List)
          for (final e in liveRaw)
            if (e is Map)
              AppLiveSource.fromJson(Map<String, dynamic>.from(e)),
      ],
      liveM3uUrl: '${j['live_m3u_url'] ?? j['m3u_url'] ?? ''}'.trim(),
      torrentParseApi:
          '${j['torrent_parse_api'] ?? j['bt_parse'] ?? ''}'.trim(),
      sportsTypeId: (j['sports_type_id'] as num?)?.toInt() ??
          ApiConfig.macCmsSportsTypeId,
      sportsEventTypeId: (j['sports_event_type_id'] as num?)?.toInt() ??
          ApiConfig.macCmsSportsEventTypeId,
      liveTypeKeywords: [
        if (j['live_type_keywords'] is List)
          for (final e in j['live_type_keywords']) '$e',
      ],
      qqLogin: QqLoginRemoteConfig.fromJson(
        j['qq_login'] is Map
            ? Map<String, dynamic>.from(j['qq_login'] as Map)
            : (j['qq'] is Map
                ? Map<String, dynamic>.from(j['qq'] as Map)
                : null),
      ),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'tabs': [for (final t in tabs) t.toJson()],
        'nav': [
          for (final n in nav)
            {
              'title': n.title,
              'url': n.url,
              'action': n.action,
              'icon': n.icon,
              if (n.typeId != null) 'type_id': n.typeId,
            },
        ],
        'live_sources': [
          for (final s in liveSources)
            {
              'name': s.name,
              'url': s.url,
              'group': s.group,
              'logo': s.logo,
            },
        ],
        'live_m3u_url': liveM3uUrl,
        'torrent_parse_api': torrentParseApi,
        'sports_type_id': sportsTypeId,
        'sports_event_type_id': sportsEventTypeId,
        'live_type_keywords': liveTypeKeywords,
        'qq_login': qqLogin.toJson(),
      };
}

/// 拉取 / 缓存 App 配置
class CmsAppConfigStore {
  CmsAppConfigStore._();
  static final instance = CmsAppConfigStore._();

  static const _cacheKey = 'cms_app_config_v1';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';

  CmsAppConfig _config = CmsAppConfig.defaults;
  CmsAppConfig get config => _config;

  final List<void Function()> _listeners = [];

  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);
  void _notify() {
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }

  Future<CmsAppConfig> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          _config = CmsAppConfig.fromJson(Map<String, dynamic>.from(j));
          if (_config.tabs.isEmpty) {
            _config = CmsAppConfig(
              tabs: CmsAppConfig.defaults.tabs,
              nav: _config.nav.isEmpty ? CmsAppConfig.defaults.nav : _config.nav,
              liveSources: _config.liveSources,
              liveM3uUrl: _config.liveM3uUrl,
              torrentParseApi: _config.torrentParseApi,
              sportsTypeId: _config.sportsTypeId,
              sportsEventTypeId: _config.sportsEventTypeId,
              liveTypeKeywords: _config.liveTypeKeywords.isEmpty
                  ? CmsAppConfig.defaults.liveTypeKeywords
                  : _config.liveTypeKeywords,
              qqLogin: _config.qqLogin,
            );
          }
        }
      } catch (_) {}
    }
    return _config;
  }

  Future<CmsAppConfig> refresh() async {
    await bootstrap();
    // 仅请求真实存在的源；static/app/app_config.json 线上常无，避免 H5 Network 一堆 404
    final urls = <String>[
      ApiConfig.huihuoPanelAppConfigUrl,
    ];
    for (final u in urls) {
      try {
        String body;
        int status;
        if (kIsWeb) {
          final res = await http
              .get(
                Uri.parse(u),
                headers: const {'Accept': 'application/json', 'User-Agent': _ua},
              )
              .timeout(const Duration(seconds: 12));
          status = res.statusCode;
          body = utf8.decode(res.bodyBytes).trim();
        } else {
          final res = await huihuoHttpGet(u);
          status = res.status;
          body = res.body.trim();
        }
        if (status < 200 || status >= 300) continue;
        if (!body.startsWith('{')) continue;
        final decoded = jsonDecode(body);
        final unwrapped = _unwrapConfigMap(decoded);
        if (unwrapped == null || unwrapped.isEmpty) continue;
        // 空 data{} 不算有效配置，继续用本地默认
        final looksEmpty = !unwrapped.containsKey('tabs') &&
            !unwrapped.containsKey('bottom_tabs') &&
            !unwrapped.containsKey('nav') &&
            !unwrapped.containsKey('menu') &&
            !unwrapped.containsKey('planning') &&
            !unwrapped.containsKey('qq_login') &&
            !unwrapped.containsKey('qq');
        if (looksEmpty) continue;
        var next = CmsAppConfig.fromJson(unwrapped);
        if (next.tabs.isEmpty) {
          next = CmsAppConfig(
            tabs: CmsAppConfig.defaults.tabs,
            nav: next.nav.isEmpty ? CmsAppConfig.defaults.nav : next.nav,
            liveSources: next.liveSources,
            liveM3uUrl: next.liveM3uUrl,
            torrentParseApi: next.torrentParseApi,
            sportsTypeId: next.sportsTypeId,
            sportsEventTypeId: next.sportsEventTypeId,
            liveTypeKeywords: next.liveTypeKeywords.isEmpty
                ? CmsAppConfig.defaults.liveTypeKeywords
                : next.liveTypeKeywords,
            qqLogin: next.qqLogin,
          );
        }
        _config = next;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(_config.toJson()));
        _notify();
        return _config;
      } catch (_) {}
    }
    _notify();
    return _config;
  }

  static Map<String, dynamic>? _unwrapConfigMap(Object? decoded) {
    if (decoded is! Map) return null;
    final m = Map<String, dynamic>.from(decoded);
    final data = m['data'];
    if (data is Map &&
        (m.containsKey('code') || m.containsKey('msg')) &&
        !m.containsKey('tabs') &&
        !m.containsKey('bottom_tabs')) {
      return Map<String, dynamic>.from(data);
    }
    return m;
  }
}
