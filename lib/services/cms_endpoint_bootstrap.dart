import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'huihuo_http.dart';

/// 从 QQ/微云收藏分享页解析当前 CMS 根地址，避免 IP 换线后整包失效。
///
/// 分享页示例：https://sharechain.qq.com/646dbbb1493e06a8b6c449b3d272c39e
/// 正文 / brief 里放 `https://x.x.x.x`，App 启动时拉取并写入 [ApiConfig]。
class CmsEndpointBootstrap {
  CmsEndpointBootstrap._();

  static const shareUrl =
      'https://sharechain.qq.com/646dbbb1493e06a8b6c449b3d272c39e';

  /// 换线后升版本，避免旧 IP 缓存长期挡住新线路
  static const _cacheKey = 'cms_share_resolved_v2';
  static const _cacheAtKey = 'cms_share_resolved_at_v2';

  /// 已下线线路：本地缓存命中时直接丢弃，改等分享页 / 内置默认
  static const _retiredHosts = {
    '154.12.29.28',
  };

  static String? _lastResolved;
  static String? get lastResolved => _lastResolved;

  /// 启动：先套用本地缓存，再联网刷新（短超时，失败不挡启动）
  static Future<void> bootstrap({
    Duration networkBudget = const Duration(seconds: 6),
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    var cached = (prefs.getString(_cacheKey) ?? '').trim();
    if (cached.isNotEmpty && _isRetired(cached)) {
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheAtKey);
      cached = '';
    }
    if (cached.isNotEmpty) {
      _lastResolved = cached;
      ApiConfig.applyShareResolvedMacCms(cached);
    }

    try {
      final fresh = await resolveFromShare()
          .timeout(networkBudget, onTimeout: () => null);
      if (fresh == null || fresh.isEmpty) return;
      if (_isRetired(fresh)) return;
      if (fresh == cached) return;
      _lastResolved = fresh;
      ApiConfig.applyShareResolvedMacCms(fresh);
      await prefs.setString(_cacheKey, fresh);
      await prefs.setInt(
        _cacheAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('[cms] share endpoint → $fresh');
    } catch (e) {
      debugPrint('[cms] share resolve skip: $e');
    }
  }

  static bool _isRetired(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.isNotEmpty && _retiredHosts.contains(host);
  }

  /// 拉取分享页并解析出 CMS 根地址
  static Future<String?> resolveFromShare({String? url}) async {
    if (kIsWeb) return null;
    final pageUrl = (url ?? shareUrl).trim();
    if (pageUrl.isEmpty) return null;

    final res = await huihuoHttpGet(
      pageUrl,
      timeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'text/html,application/xhtml+xml,application/json,*/*',
        'Referer': 'https://sharechain.qq.com/',
      },
    );
    if (res.status < 200 || res.status >= 400) return null;
    return parseServerUrlFromHtml(res.body);
  }

  /// 从微云 HTML / syncData JSON 抽出可用 CMS 根
  static String? parseServerUrlFromHtml(String html) {
    if (html.trim().isEmpty) return null;

    // 1) window.syncData = {...};
    final sync = RegExp(
      r'window\.syncData\s*=\s*(\{[\s\S]*?\})\s*;\s*</script>',
      caseSensitive: false,
    ).firstMatch(html);
    if (sync != null) {
      final rawJson = sync.group(1) ?? '';
      final fromJson = _parseFromSyncData(rawJson);
      if (fromJson != null) return fromJson;
    }

    // 2) 全文兜底：找 http(s)://IP 或域名，排除腾讯站
    return _pickBestUrl(_extractCandidateUrls(html));
  }

  static String? _parseFromSyncData(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final share = map['shareData'];
      final texts = <String>[];
      if (share is Map) {
        final s = Map<String, dynamic>.from(share);
        texts.add('${s['html_content'] ?? ''}');
        texts.add('${s['share_name'] ?? ''}');
        final coll = s['collection'];
        if (coll is Map) {
          final c = Map<String, dynamic>.from(coll);
          texts.add('${c['summary'] ?? ''}');
          final summary = c['summary'];
          if (summary is Map) {
            final sum = Map<String, dynamic>.from(summary);
            texts.add('${sum['rich_media_summary'] ?? ''}');
            final rich = sum['rich_media_summary'];
            if (rich is Map) {
              texts.add('${rich['brief'] ?? ''}');
              texts.add('${rich['title'] ?? ''}');
            }
          }
        }
        // 文件名也可能直接是地址
        _collectFileNames(s, texts);
      }
      final joined = texts.join('\n');
      final hit = _pickBestUrl(_extractCandidateUrls(joined));
      if (hit != null) return hit;
      // syncData 字符串里再扫一遍
      return _pickBestUrl(_extractCandidateUrls(rawJson));
    } catch (_) {
      return _pickBestUrl(_extractCandidateUrls(rawJson));
    }
  }

  static void _collectFileNames(Map<String, dynamic> share, List<String> out) {
    void walk(dynamic node) {
      if (node is Map) {
        final m = Map<String, dynamic>.from(node);
        for (final k in [
          'file_name',
          'filename',
          'dir_name',
          'name',
          'note_name',
          'title',
          'brief',
        ]) {
          final v = '${m[k] ?? ''}'.trim();
          if (v.isNotEmpty) out.add(v);
        }
        for (final v in m.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final e in node) {
          walk(e);
        }
      }
    }

    walk(share);
  }

  static final _urlRe = RegExp(
    r'''https?://[^\s"'<>\\]+''',
    caseSensitive: false,
  );

  static List<String> _extractCandidateUrls(String text) {
    if (text.isEmpty) return const [];
    // 解码常见 unicode 转义（html_content）
    var work = text
        .replaceAll(r'\u003C', '<')
        .replaceAll(r'\u003E', '>')
        .replaceAll(r'\u002F', '/')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    final out = <String>[];
    for (final m in _urlRe.allMatches(work)) {
      var u = m.group(0)!.trim();
      u = u.replaceAll(RegExp(r'[),.;]+$'), '');
      if (u.isEmpty) continue;
      out.add(u);
    }
    // 裸 IP（无协议）也认
    for (final m in RegExp(
      r'(?<![0-9A-Za-z./:])((?:\d{1,3}\.){3}\d{1,3})(?::\d{2,5})?(?![0-9A-Za-z])',
    ).allMatches(work)) {
      out.add('https://${m.group(1)}');
    }
    return out;
  }

  static String? _pickBestUrl(List<String> urls) {
    final scored = <(String, int)>[];
    for (final raw in urls) {
      final n = _normalizeCmsRoot(raw);
      if (n == null) continue;
      scored.add((n, _scoreUrl(n)));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.first.$1;
  }

  static int _scoreUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return -1;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return -1;
    // IP 直连最符合当前用法
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return 100;
    if (host.contains('.')) return 50;
    return 10;
  }

  static String? _normalizeCmsRoot(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return null;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    if (_retiredHosts.contains(host)) return null;
    // 排除分享站自身与腾讯静态资源
    const blocked = [
      'qq.com',
      'weiyun.com',
      'qlogo.cn',
      'gtimg.cn',
      'tencent.com',
      'myapp.com',
      'idqqimg.com',
    ];
    for (final b in blocked) {
      if (host == b || host.endsWith('.$b')) return null;
    }
    // 只要根：scheme + host + optional port
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }
}
