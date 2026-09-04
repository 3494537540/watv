import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'cms_app_config.dart';

class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.url,
    this.group = '默认',
    this.logo = '',
    this.fromCms = false,
  });

  final String id;
  final String name;
  final String url;
  final String group;
  final String logo;
  final bool fromCms;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'group': group,
        'logo': logo,
        'fromCms': fromCms,
      };

  factory LiveChannel.fromJson(Map<String, dynamic> j) => LiveChannel(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        url: '${j['url'] ?? ''}',
        group: '${j['group'] ?? '默认'}',
        logo: '${j['logo'] ?? ''}',
        fromCms: j['fromCms'] == true,
      );
}

/// 解析 M3U / 文本直播源
class LiveM3uParser {
  static List<LiveChannel> parse(String raw, {String defaultGroup = '导入'}) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return const [];

    // #EXTM3U
    if (text.toUpperCase().contains('#EXTINF')) {
      final out = <LiveChannel>[];
      String name = '';
      String group = defaultGroup;
      String logo = '';
      for (final line in text.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        if (t.startsWith('#EXTINF')) {
          name = t.split(',').length > 1 ? t.split(',').last.trim() : '未命名';
          final gm = RegExp(
            r'group-title="([^"]*)"',
            caseSensitive: false,
          ).firstMatch(t);
          if (gm != null) group = gm.group(1)!.trim().isEmpty ? defaultGroup : gm.group(1)!.trim();
          final lm = RegExp(
            r'tvg-logo="([^"]*)"',
            caseSensitive: false,
          ).firstMatch(t);
          if (lm != null) logo = lm.group(1)!.trim();
          continue;
        }
        if (t.startsWith('#')) continue;
        if (t.startsWith('http') || t.startsWith('rtmp') || t.startsWith('rtsp')) {
          out.add(
            LiveChannel(
              id: 'm3u_${out.length}_${t.hashCode}',
              name: name.isEmpty ? '频道${out.length + 1}' : name,
              url: t,
              group: group,
              logo: logo,
            ),
          );
          name = '';
          logo = '';
        }
      }
      return out;
    }

    // name,url 或 url 每行
    final out = <LiveChannel>[];
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      String n;
      String u;
      if (t.contains(',')) {
        final i = t.indexOf(',');
        n = t.substring(0, i).trim();
        u = t.substring(i + 1).trim();
      } else if (t.contains('|')) {
        final parts = t.split('|');
        n = parts.first.trim();
        u = parts.last.trim();
      } else {
        n = '频道${out.length + 1}';
        u = t;
      }
      if (!(u.startsWith('http') ||
          u.startsWith('rtmp') ||
          u.startsWith('rtsp'))) {
        continue;
      }
      out.add(
        LiveChannel(
          id: 'txt_${out.length}_${u.hashCode}',
          name: n.isEmpty ? '频道${out.length + 1}' : n,
          url: u,
          group: defaultGroup,
        ),
      );
    }
    return out;
  }
}

/// 直播频道聚合：远程配置 + CMS website + 本地导入 + 默认 CCTV 占位
class LiveSourceStore {
  LiveSourceStore._();
  static final instance = LiveSourceStore._();

  static const _importKey = 'live_imported_channels_v1';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';

  List<LiveChannel> _imported = const [];
  List<LiveChannel> _remote = const [];
  List<LiveChannel> _cmsWeb = const [];
  List<LiveChannel> _m3uRemote = const [];

  List<LiveChannel> get all {
    final seen = <String>{};
    final out = <LiveChannel>[];
    void addAll(List<LiveChannel> list) {
      for (final c in list) {
        final key = c.url.trim();
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(c);
      }
    }

    addAll(_imported);
    addAll(_remote);
    addAll(_cmsWeb);
    addAll(_m3uRemote);
    if (out.isEmpty) addAll(_builtinCctvPlaceholders());
    return out;
  }

  List<String> get groups {
    final g = <String>{};
    for (final c in all) {
      g.add(c.group.isEmpty ? '默认' : c.group);
    }
    final list = g.toList()..sort();
    return list;
  }

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_importKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          _imported = [
            for (final e in list)
              if (e is Map)
                LiveChannel.fromJson(Map<String, dynamic>.from(e)),
          ];
        }
      } catch (_) {}
    }
  }

  Future<void> refreshFromConfig(CmsAppConfig cfg) async {
    _remote = [
      for (final s in cfg.liveSources)
        if (s.url.isNotEmpty && s.name.isNotEmpty)
          LiveChannel(
            id: 'cfg_${s.url.hashCode}',
            name: s.name,
            url: s.url,
            group: s.group.isEmpty ? '配置' : s.group,
            logo: s.logo,
            fromCms: true,
          ),
    ];

    final m3uUrl = cfg.liveM3uUrl.isNotEmpty
        ? cfg.liveM3uUrl
        : ApiConfig.macCmsLiveM3uUrl;
    _m3uRemote = await _fetchM3u(m3uUrl);
    _cmsWeb = await _fetchCmsWebsite();
  }

  Future<List<LiveChannel>> _fetchM3u(String url) async {
    try {
      final res = await http
          .get(
            Uri.parse(url),
            headers: const {'User-Agent': _ua, 'Accept': '*/*'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) return const [];
      final body = utf8.decode(res.bodyBytes);
      return LiveM3uParser.parse(body, defaultGroup: '远程M3U');
    } catch (_) {
      return const [];
    }
  }

  Future<List<LiveChannel>> _fetchCmsWebsite() async {
    try {
      final uri = Uri.parse(ApiConfig.macCmsWebsiteProvide).replace(
        queryParameters: {
          if (ApiConfig.useCmsWebProxy) ...{
            'target': 'website',
          },
          'ac': 'detail',
          'pg': '1',
        },
      );
      final res = await http
          .get(
            uri,
            headers: const {'Accept': 'application/json', 'User-Agent': _ua},
          )
          .timeout(const Duration(seconds: 15));
      final body = utf8.decode(res.bodyBytes).trim();
      if (!body.startsWith('{')) return const [];
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final raw = decoded['list'];
      if (raw is! List) return const [];
      final out = <LiveChannel>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final name =
            '${m['website_name'] ?? m['name'] ?? m['title'] ?? ''}'.trim();
        final jump =
            '${m['website_jumpurl'] ?? m['website_url'] ?? m['url'] ?? ''}'
                .trim();
        if (name.isEmpty || jump.isEmpty) continue;
        if (!(jump.startsWith('http') ||
            jump.startsWith('rtmp') ||
            jump.startsWith('rtsp'))) {
          continue;
        }
        // 仅收录像直播流的链接
        final lower = jump.toLowerCase();
        final looksStream = lower.contains('.m3u8') ||
            lower.contains('.flv') ||
            lower.contains('rtmp') ||
            lower.contains('live') ||
            lower.endsWith('.ts');
        if (!looksStream && !lower.contains('cctv')) continue;
        out.add(
          LiveChannel(
            id: 'web_${m['website_id'] ?? out.length}',
            name: name,
            url: jump,
            group: '${m['type_name'] ?? '网址'}',
            logo: '${m['website_logo'] ?? m['website_pic'] ?? ''}',
            fromCms: true,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> importText(String raw, {String group = '导入'}) async {
    final parsed = LiveM3uParser.parse(raw, defaultGroup: group);
    if (parsed.isEmpty) return;
    final map = {for (final c in _imported) c.url: c};
    for (final c in parsed) {
      map[c.url] = c;
    }
    _imported = map.values.toList();
    await _persistImported();
  }

  Future<void> clearImported() async {
    _imported = const [];
    await _persistImported();
  }

  Future<void> _persistImported() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _importKey,
      jsonEncode([for (final c in _imported) c.toJson()]),
    );
  }

  /// 无后台配置时的占位（需替换为真实可播源）
  List<LiveChannel> _builtinCctvPlaceholders() {
    // 占位说明频道：引导用户导入 / 配置 m3u
    return const [
      LiveChannel(
        id: 'hint_cctv',
        name: '请导入 CCTV 直播源',
        url: 'https://example.invalid/live-placeholder',
        group: 'CCTV',
      ),
    ];
  }
}
