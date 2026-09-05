import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../player/danmaku_store.dart';

class _DmTarget {
  const _DmTarget({
    required this.url,
    this.cid,
    this.tag = '',
    this.useZxz = true,
  });

  final String url;
  final int? cid;
  final String tag;
  /// 多 P 投稿时 zxz 忽略 ?p=，只拉 XML，避免串集
  final bool useZxz;
}

/// 第三方弹幕：[danmu.zxz.ee](https://danmu.zxz.ee/) + B 站分集匹配 / XML 兜底
class DanmakuRemoteApi {
  DanmakuRemoteApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const _maxItems = 1200;

  static String md5Hex(String key) =>
      md5.convert(utf8.encode(key.trim())).toString();

  static String poolIdFor(String key) => md5Hex(key);

  static String? extractOfficialUrl(String playUrl) {
    final raw = playUrl.trim();
    if (raw.isEmpty) return null;
    if (_isOfficialPage(raw)) return raw;
    Uri? uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      return null;
    }
    for (final key in ['url', 'v', 'vid', 'ww']) {
      final v = uri.queryParameters[key]?.trim() ?? '';
      if (v.isEmpty) continue;
      final decoded = Uri.decodeComponent(v);
      if (_isOfficialPage(decoded)) return decoded;
      final nested = extractOfficialUrl(decoded);
      if (nested != null) return nested;
    }
    return null;
  }

  static bool _isOfficialPage(String url) {
    final u = url.toLowerCase();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    const hosts = [
      'v.qq.com',
      'iqiyi.com',
      'youku.com',
      'mgtv.com',
      'bilibili.com',
      'b23.tv',
      'sohu.com',
      'le.com',
      'pptv.com',
    ];
    return hosts.any(u.contains);
  }

  Future<List<DanmakuItem>> fetch({
    required String vodId,
    required int episode,
    required String playUrl,
    String title = '',
    String episodeLabel = '',
  }) async {
    final merged = <DanmakuItem>[];
    final seen = <String>{};

    void addAll(Iterable<DanmakuItem> list) {
      for (final d in list) {
        if (merged.length >= _maxItems) break;
        final t = d.text.trim();
        if (t.isEmpty || _isNoise(t)) continue;
        final key = '${d.timeSec.toStringAsFixed(1)}|$t';
        if (!seen.add(key)) continue;
        merged.add(d);
      }
    }

    final futures = <Future<List<DanmakuItem>>>[];
    final official = extractOfficialUrl(playUrl);
    if (official != null) {
      futures.add(_fetchZxz(official));
      futures.add(_fetchZxz(md5Hex(official)));
    }

    final clean = _cleanTitle(title);
    final label = episodeLabel.trim();
    if (clean.isNotEmpty) {
      final targets = await _resolveTargets(
        title: clean,
        episode: episode,
        episodeLabel: label,
      );
      debugPrint(
        '[danmaku] targets=${targets.length} title=$clean ep=$episode label=$label',
      );
      for (final t in targets) {
        debugPrint('[danmaku] target ${t.tag} url=${t.url} cid=${t.cid}');
        if (t.useZxz) {
          futures.add(_fetchZxz(t.url));
          futures.add(_fetchZxz(md5Hex(t.url)));
        }
        if (t.cid != null) {
          futures.add(_fetchBilibiliXml(t.cid!));
        }
      }
    }

    final localKey = _localPoolKey(vodId, episode, playUrl);
    futures.add(_fetchZxz(localKey));
    futures.add(_fetchZxz(md5Hex(localKey)));

    final results = await Future.wait(
      futures.map((f) async {
        try {
          return await f;
        } catch (e) {
          debugPrint('[danmaku] source fail: $e');
          return const <DanmakuItem>[];
        }
      }),
    );
    for (final r in results) {
      addAll(r);
    }

    merged.sort((a, b) => a.timeSec.compareTo(b.timeSec));
    debugPrint('[danmaku] total=${merged.length}');
    return merged;
  }

  Future<bool> send({
    required String vodId,
    required int episode,
    required String playUrl,
    required DanmakuItem item,
    String title = '',
    String episodeLabel = '',
    String author = '游客',
  }) async {
    final official = extractOfficialUrl(playUrl);
    var matchUrl = official;
    if (matchUrl == null && title.trim().isNotEmpty) {
      final targets = await _resolveTargets(
        title: _cleanTitle(title),
        episode: episode,
        episodeLabel: episodeLabel,
      );
      if (targets.isNotEmpty) matchUrl = targets.first.url;
    }
    final playerKey = matchUrl ?? _localPoolKey(vodId, episode, playUrl);
    return _sendZxz(
      player: md5Hex(playerKey),
      item: item,
      author: author,
    );
  }

  String _localPoolKey(String vodId, int ep, String playUrl) {
    final id = vodId.trim();
    if (id.isNotEmpty) return 'watv://${ApiConfig.macCmsBase}/vod/$id/$ep';
    return playUrl.trim();
  }

  /// 解析当前集对应的 B 站 / 番剧目标（含正确分 P / ep）
  Future<List<_DmTarget>> _resolveTargets({
    required String title,
    required int episode,
    required String episodeLabel,
  }) async {
    final out = <_DmTarget>[];
    final seenUrl = <String>{};

    void add(_DmTarget t) {
      if (t.url.isEmpty || !seenUrl.add(t.url)) return;
      out.add(t);
    }

    // 1) 番剧 / 国创（分集最准）
    final bangumi = await _matchBangumi(title, episode, episodeLabel);
    if (bangumi != null) add(bangumi);

    // 2) 投稿多 P / 单集视频
    final video = await _matchVideoCollection(title, episode, episodeLabel);
    if (video != null) add(video);

    // 3) 电影：偏正片
    if (episode == 0 && episodeLabel.isEmpty) {
      final movie = await _matchMovie(title);
      if (movie != null) add(movie);
    }

    // 4) 单独搜「第 N 集」——仅在上面没命中分 P 时
    if (out.isEmpty && episode > 0) {
      final epOnly = await _matchEpisodeVideo(title, episode, episodeLabel);
      if (epOnly != null) add(epOnly);
    }

    return out;
  }

  Future<_DmTarget?> _matchBangumi(
    String title,
    int episode,
    String episodeLabel,
  ) async {
    final seasonId = await _searchBangumiSeasonId(title);
    if (seasonId == null) return null;

    final hit = await _pickFromSeason(
      seasonId: seasonId,
      episode: episode,
      episodeLabel: episodeLabel,
    );
    if (hit != null) return hit;

    // 同一片名单季集数不够 → 试第二季、第三季（CMS 常把多季连在一起）
    if (episode <= 0) return null;
    var skip = 0;
    final firstEps = await _fetchSeasonEpisodes(seasonId);
    skip = firstEps.length;
    if (skip <= 0 || episode < skip) return null;

    for (final suffix in ['第二季', '第2季', '第三季', '第3季', '第四季', '第4季']) {
      if (title.contains(suffix)) continue;
      final sid = await _searchBangumiSeasonId('$title $suffix') ??
          await _searchBangumiSeasonId('$title$suffix');
      if (sid == null || sid == seasonId) continue;
      final eps = await _fetchSeasonEpisodes(sid);
      if (eps.isEmpty) continue;
      if (episode < skip + eps.length) {
        return _pickFromSeason(
          seasonId: sid,
          episode: episode - skip,
          episodeLabel: episodeLabel,
        );
      }
      skip += eps.length;
    }
    return null;
  }

  Future<_DmTarget?> _pickFromSeason({
    required int seasonId,
    required int episode,
    required String episodeLabel,
  }) async {
    final eps = await _fetchSeasonEpisodes(seasonId);
    if (eps.isEmpty) return null;

    final idx = _pickEpisodeIndex(
      titles: [for (final e in eps) e.$1],
      episode: episode,
      episodeLabel: episodeLabel,
      allowClamp: false,
    );
    if (idx == null) {
      debugPrint(
        '[danmaku] bangumi season=$seasonId eps=${eps.length} '
        'no page for ep=$episode',
      );
      return null;
    }
    final hit = eps[idx];
    final epId = hit.$2;
    final cid = hit.$3;
    final bvid = hit.$4;
    final url = epId > 0
        ? 'https://www.bilibili.com/bangumi/play/ep$epId'
        : (bvid.isNotEmpty
            ? 'https://www.bilibili.com/video/$bvid'
            : '');
    if (url.isEmpty) return null;
    return _DmTarget(
      url: url,
      cid: cid > 0 ? cid : null,
      tag: 'bangumi',
      useZxz: true,
    );
  }

  Future<_DmTarget?> _matchVideoCollection(
    String title,
    int episode,
    String episodeLabel,
  ) async {
    final queries = <String>[
      title,
      '$title 全集',
      '$title 合集',
    ];
    for (final q in queries) {
      final bvid = await _searchBilibiliBvid(q, preferCollection: true);
      if (bvid == null) continue;
      final view = await _fetchView(bvid);
      if (view == null) continue;
      final pages = view.$1;
      final titles = [for (final p in pages) p.$1];
      final idx = _pickEpisodeIndex(
        titles: titles,
        episode: episode,
        episodeLabel: episodeLabel,
        allowClamp: pages.length > 1 && episode < pages.length,
      );
      if (idx == null) {
        // 多 P 但本集超出 —— 换下个候选，不要 clamp 到最后一集
        if (pages.length > 1 && episode >= pages.length) continue;
        if (pages.length == 1 && episode > 0) continue;
        // 单 P 且第 1 集
        if (pages.isNotEmpty && episode == 0) {
          final cid = pages.first.$2;
          return _DmTarget(
            url: 'https://www.bilibili.com/video/$bvid',
            cid: cid,
            tag: 'video',
          );
        }
        continue;
      }
      final cid = pages[idx].$2;
      final p = idx + 1;
      final multi = pages.length > 1;
      final url = multi
          ? 'https://www.bilibili.com/video/$bvid?p=$p'
          : 'https://www.bilibili.com/video/$bvid';
      return _DmTarget(
        url: url,
        cid: cid,
        tag: 'video-p$p',
        // zxz 不区分分 P，多 P 时只用 XML，避免后面集串到 P1 弹幕
        useZxz: !multi || p == 1,
      );
    }
    return null;
  }

  Future<_DmTarget?> _matchEpisodeVideo(
    String title,
    int episode,
    String episodeLabel,
  ) async {
    final epNo = episode + 1;
    final queries = <String>[
      if (episodeLabel.isNotEmpty) '$title $episodeLabel',
      '$title 第$epNo集',
      '$title 第$epNo话',
      '$title EP$epNo',
    ];
    for (final q in queries) {
      final bvid = await _searchBilibiliBvid(q);
      if (bvid == null) continue;
      final view = await _fetchView(bvid);
      final cid = view?.$1.isNotEmpty == true ? view!.$1.first.$2 : null;
      return _DmTarget(
        url: 'https://www.bilibili.com/video/$bvid',
        cid: cid,
        tag: 'ep-search',
      );
    }
    return null;
  }

  Future<_DmTarget?> _matchMovie(String title) async {
    final queries = <String>[
      '$title 正片',
      '$title 电影',
      title,
    ];
    for (final q in queries) {
      final bvid = await _searchBilibiliBvid(q, preferMovie: true);
      if (bvid == null) continue;
      final view = await _fetchView(bvid);
      final cid = view?.$1.isNotEmpty == true ? view!.$1.first.$2 : null;
      return _DmTarget(
        url: 'https://www.bilibili.com/video/$bvid',
        cid: cid,
        tag: 'movie',
      );
    }
    return null;
  }

  /// titles: 分集标题；返回 0-based 下标。找不到且不允许 clamp 时返回 null
  int? _pickEpisodeIndex({
    required List<String> titles,
    required int episode,
    required String episodeLabel,
    required bool allowClamp,
  }) {
    if (titles.isEmpty) return null;
    final epNo = episode + 1;
    final label = episodeLabel.trim();

    int? scoredBest;
    var scored = -999;
    for (var i = 0; i < titles.length; i++) {
      final part = titles[i];
      var s = 0;
      if (label.isNotEmpty && part.contains(label)) s += 12;
      if (RegExp('第\\s*0*$epNo\\s*[集话期]').hasMatch(part)) s += 10;
      if (RegExp('(^|\\s|E|EP|P)$epNo(\\s|\$|[^0-9])', caseSensitive: false)
          .hasMatch(part)) {
        s += 6;
      }
      if (part.trim() == '$epNo') s += 8;
      if (s > scored) {
        scored = s;
        scoredBest = i;
      }
    }
    if (scoredBest != null && scored >= 6) return scoredBest;

    if (episode >= 0 && episode < titles.length) return episode;
    if (allowClamp) return episode.clamp(0, titles.length - 1);
    return null;
  }

  Future<int?> _searchBangumiSeasonId(String title) async {
    final endpoints = <Uri>[
      Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
        'search_type': 'media_bangumi',
        'keyword': title,
        'page': '1',
      }),
      Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
        'search_type': 'media_ft',
        'keyword': title,
        'page': '1',
      }),
    ];
    for (final uri in endpoints) {
      try {
        final res = await _client
            .get(uri, headers: _biliHeaders)
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is! Map || (decoded['code'] as num?)?.toInt() != 0) {
          continue;
        }
        final data = decoded['data'];
        if (data is! Map) continue;
        final result = data['result'];
        if (result is! List || result.isEmpty) continue;
        final id = _pickBestSeasonId(result, title);
        if (id != null) return id;
      } catch (e) {
        debugPrint('[danmaku] bangumi search fail: $e');
      }
    }

    // HTML 兜底：搜番剧页
    try {
      final uri = Uri.https('search.bilibili.com', '/bangumi', {
        'keyword': title,
      });
      final res = await _client
          .get(uri, headers: _biliHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final html = utf8.decode(res.bodyBytes);
        final m = RegExp(r'"season_id"\s*:\s*(\d+)').firstMatch(html) ??
            RegExp(r'/bangumi/play/ss(\d+)').firstMatch(html);
        if (m != null) return int.tryParse(m.group(1)!);
      }
    } catch (e) {
      debugPrint('[danmaku] bangumi html fail: $e');
    }
    return null;
  }

  int? _pickBestSeasonId(List<dynamic> result, String title) {
    final kw = title.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    int? best;
    var bestScore = -999;
    for (final e in result.take(12)) {
      if (e is! Map) continue;
      final sid = (e['season_id'] as num?)?.toInt() ??
          (e['media_id'] as num?)?.toInt();
      if (sid == null || sid <= 0) continue;
      final t = '${e['title'] ?? e['org_title'] ?? ''}'
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), '')
          .toLowerCase();
      var score = 0;
      if (t == kw) {
        score += 12;
      } else if (t.contains(kw) || kw.contains(t)) {
        score += 8;
      } else {
        final head = kw.substring(0, math.min(4, kw.length));
        if (head.isNotEmpty && t.contains(head)) score += 3;
      }
      final st = '${e['season_type_name'] ?? e['styles'] ?? ''}';
      if (st.contains('国产') || st.contains('国创') || st.contains('番剧')) {
        score += 2;
      }
      if (score > bestScore) {
        bestScore = score;
        best = sid;
      }
    }
    return bestScore >= 3 ? best : null;
  }

  /// [(title, epId, cid, bvid)]
  Future<List<(String, int, int, String)>> _fetchSeasonEpisodes(
    int seasonId,
  ) async {
    final uris = <Uri>[
      Uri.https('api.bilibili.com', '/pgc/view/web/season', {
        'season_id': '$seasonId',
      }),
      Uri.https('api.bilibili.com', '/pgc/web/season/section', {
        'season_id': '$seasonId',
      }),
    ];
    for (final uri in uris) {
      try {
        final res = await _client
            .get(uri, headers: _biliHeaders)
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is! Map) continue;
        final list = _parseSeasonEpisodes(decoded);
        if (list.isNotEmpty) {
          debugPrint('[danmaku] season=$seasonId episodes=${list.length}');
          return list;
        }
      } catch (e) {
        debugPrint('[danmaku] season fail: $e');
      }
    }
    return const [];
  }

  List<(String, int, int, String)> _parseSeasonEpisodes(Map decoded) {
    final out = <(String, int, int, String)>[];
    final result = decoded['result'] ?? decoded['data'];
    if (result is! Map) return out;

    void eat(dynamic ep) {
      if (ep is! Map) return;
      final title = '${ep['long_title'] ?? ep['title'] ?? ep['show_title'] ?? ''}';
      final epId = (ep['id'] as num?)?.toInt() ??
          (ep['ep_id'] as num?)?.toInt() ??
          0;
      final cid = (ep['cid'] as num?)?.toInt() ?? 0;
      final bvid = '${ep['bvid'] ?? ''}';
      if (cid <= 0 && epId <= 0 && bvid.isEmpty) return;
      out.add((title, epId, cid, bvid));
    }

    final episodes = result['episodes'];
    if (episodes is List) {
      for (final e in episodes) {
        eat(e);
      }
    }
    final section = result['section'];
    if (section is List) {
      for (final sec in section) {
        if (sec is! Map) continue;
        final eps = sec['episodes'];
        if (eps is! List) continue;
        for (final e in eps) {
          eat(e);
        }
      }
    }
    final main = result['main_section'];
    if (main is Map) {
      final eps = main['episodes'];
      if (eps is List) {
        for (final e in eps) {
          eat(e);
        }
      }
    }
    return out;
  }

  /// (pages: [(part, cid)], aid)
  Future<(List<(String, int)>, int)?> _fetchView(String bvid) async {
    final uri = Uri.https('api.bilibili.com', '/x/web-interface/view', {
      'bvid': bvid,
    });
    try {
      final res = await _client
          .get(uri, headers: _biliHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map || (decoded['code'] as num?)?.toInt() != 0) {
        return null;
      }
      final data = decoded['data'];
      if (data is! Map) return null;
      final pages = <(String, int)>[];
      final rawPages = data['pages'];
      if (rawPages is List) {
        for (final p in rawPages) {
          if (p is! Map) continue;
          final cid = (p['cid'] as num?)?.toInt() ?? 0;
          if (cid <= 0) continue;
          pages.add(('${p['part'] ?? ''}', cid));
        }
      }
      if (pages.isEmpty) {
        final cid = (data['cid'] as num?)?.toInt() ?? 0;
        if (cid > 0) pages.add(('', cid));
      }
      final aid = (data['aid'] as num?)?.toInt() ?? 0;
      return (pages, aid);
    } catch (_) {
      return null;
    }
  }

  Future<List<DanmakuItem>> _fetchZxz(String idOrUrl) async {
    final base = ApiConfig.danmakuApi.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(base).replace(queryParameters: {
      'type': 'json',
      'id': idOrUrl,
    });
    debugPrint('[danmaku] GET $uri');
    final res = await _client
        .get(uri, headers: const {
          'Accept': 'application/json',
          'User-Agent': _ua,
        })
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('[danmaku] zxz http=${res.statusCode}');
      return const [];
    }
    final list = _parseZxz(jsonDecode(utf8.decode(res.bodyBytes)));
    debugPrint('[danmaku] zxz items=${list.length}');
    return list;
  }

  Future<bool> _sendZxz({
    required String player,
    required DanmakuItem item,
    required String author,
  }) async {
    final base = ApiConfig.danmakuApi.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(base);
    final payload = {
      'player': player,
      'text': item.text,
      'color': _colorHex(item.color),
      'time': item.timeSec,
      'type': 0,
      'author': author,
    };
    try {
      final res = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'User-Agent': _ua,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = utf8.decode(res.bodyBytes).trim();
        if (body.isEmpty) return true;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            final code = (decoded['code'] as num?)?.toInt();
            if (code != null) {
              return code == 200 || code == 0 || code == 1 || code == 23;
            }
          }
        } catch (_) {}
        return true;
      }
      final form = await _client.post(
        uri,
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': _ua,
        },
        body: {
          'player': player,
          'text': item.text,
          'color': _colorHex(item.color),
          'time': '${item.timeSec}',
          'type': '0',
        },
      ).timeout(const Duration(seconds: 12));
      return form.statusCode >= 200 && form.statusCode < 300;
    } catch (e) {
      debugPrint('[danmaku] send fail: $e');
      return false;
    }
  }

  List<DanmakuItem> _parseZxz(dynamic decoded) {
    if (decoded is! Map) return const [];
    final map = Map<String, dynamic>.from(decoded);
    final code = (map['code'] as num?)?.toInt();
    if (code != null && code != 200 && code != 0 && code != 1 && code != 23) {
      return const [];
    }
    final raw = map['danmuku'] ?? map['danmaku'] ?? map['data'];
    if (raw is! List) return const [];
    final out = <DanmakuItem>[];
    for (final row in raw) {
      if (out.length >= _maxItems) break;
      final item = _parseRow(row);
      if (item != null) out.add(item);
    }
    return out;
  }

  DanmakuItem? _parseRow(dynamic row) {
    if (row is Map) {
      final text = '${row['text'] ?? ''}'.trim();
      if (text.isEmpty) return null;
      return DanmakuItem(
        timeSec: _asDouble(row['time'] ?? 0),
        text: text,
        color: _parseColor('${row['color'] ?? '#FFFFFF'}'),
      );
    }
    if (row is! List || row.length < 4) return null;

    if ('${row[2]}'.contains('#')) {
      final text = '${row[3]}'.trim();
      if (text.isEmpty) return null;
      return DanmakuItem(
        timeSec: _asDouble(row[0]),
        text: text,
        color: _parseColor('${row[2]}'),
      );
    }

    if (row.length >= 5) {
      final text = '${row[4]}'.trim();
      if (text.isEmpty || RegExp(r'^\d{8,}$').hasMatch(text)) {
        final alt = '${row[3]}'.trim();
        if (alt.isEmpty || alt.startsWith('#')) return null;
        return DanmakuItem(
          timeSec: _asDouble(row[0]),
          text: alt,
          color: _parseColor('${row[2]}'),
        );
      }
      return DanmakuItem(
        timeSec: _asDouble(row[0]),
        text: text,
        color: _parseColor('${row[2]}'),
      );
    }
    return null;
  }

  static String _cleanTitle(String title) {
    var t = title.trim();
    if (t.isEmpty) return '';
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll(RegExp(r'[\(（\[【].{0,24}[\)）\]】]'), ' ');
    t = t.replaceAll(
      RegExp(
        r'(国语|粤语|中字|双语|高清|蓝光|超清|抢先|完整版|未删减|HD|4K|1080P|720P)',
        caseSensitive: false,
      ),
      ' ',
    );
    t = t.replaceAll(RegExp(r'[·•|_／/]+'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  Map<String, String> get _biliHeaders => const {
        'Accept': 'application/json,text/html,*/*',
        'User-Agent': _ua,
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com',
      };

  Future<String?> _searchBilibiliBvid(
    String keyword, {
    bool preferCollection = false,
    bool preferMovie = false,
  }) async {
    final fromApi = await _searchBilibiliApi(
      keyword,
      preferCollection: preferCollection,
      preferMovie: preferMovie,
    );
    if (fromApi != null) return fromApi;
    final fromHtml = await _searchBilibiliHtml(
      keyword,
      preferCollection: preferCollection,
      preferMovie: preferMovie,
    );
    if (fromHtml != null) return fromHtml;
    return _searchBilibiliMobile(keyword);
  }

  Future<String?> _searchBilibiliApi(
    String keyword, {
    bool preferCollection = false,
    bool preferMovie = false,
  }) async {
    final uri = Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
      'search_type': 'video',
      'keyword': keyword,
      'page': '1',
    });
    try {
      final res = await _client
          .get(uri, headers: _biliHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map || (decoded['code'] as num?)?.toInt() != 0) {
        return null;
      }
      final data = decoded['data'];
      if (data is! Map) return null;
      final result = data['result'];
      if (result is! List || result.isEmpty) return null;
      return _pickBestBvid(
        result,
        keyword,
        preferCollection: preferCollection,
        preferMovie: preferMovie,
      );
    } catch (e) {
      debugPrint('[danmaku] bili api fail: $e');
      return null;
    }
  }

  Future<String?> _searchBilibiliHtml(
    String keyword, {
    bool preferCollection = false,
    bool preferMovie = false,
  }) async {
    final uri = Uri.https('search.bilibili.com', '/video', {
      'keyword': keyword,
    });
    try {
      final res = await _client
          .get(uri, headers: _biliHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final html = utf8.decode(res.bodyBytes);
      final scored = _scoreBvidsFromHtml(
        html,
        keyword,
        preferCollection: preferCollection,
        preferMovie: preferMovie,
      );
      if (scored != null) return scored;
      return _firstGoodBvid(html);
    } catch (e) {
      debugPrint('[danmaku] bili html fail: $e');
      return null;
    }
  }

  Future<String?> _searchBilibiliMobile(String keyword) async {
    final uri = Uri.https('m.bilibili.com', '/search', {
      'keyword': keyword,
    });
    try {
      final res = await _client
          .get(uri, headers: _biliHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      return _firstGoodBvid(utf8.decode(res.bodyBytes));
    } catch (e) {
      debugPrint('[danmaku] bili mobile fail: $e');
      return null;
    }
  }

  String? _scoreBvidsFromHtml(
    String html,
    String keyword, {
    required bool preferCollection,
    required bool preferMovie,
  }) {
    final kw = keyword.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final re = RegExp(
      r'"bvid"\s*:\s*"(BV[a-zA-Z0-9]{10})"[^}]{0,400}?"title"\s*:\s*"([^"]*)"',
      caseSensitive: false,
    );
    final re2 = RegExp(
      r'"title"\s*:\s*"([^"]*)"[^}]{0,400}?"bvid"\s*:\s*"(BV[a-zA-Z0-9]{10})"',
      caseSensitive: false,
    );
    String? best;
    var bestScore = -999;

    void consider(String bvid, String titleRaw) {
      final t = titleRaw
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(r'\u003c', '<')
          .replaceAll(RegExp(r'\s+'), '')
          .toLowerCase();
      var score = 0;
      if (t.contains(kw)) {
        score += 8;
      } else {
        final head = kw.substring(0, math.min(4, kw.length));
        if (head.isNotEmpty && t.contains(head)) score += 3;
      }
      if (preferCollection &&
          (t.contains('合集') || t.contains('全集') || t.contains('全话'))) {
        score += 5;
      }
      if (preferMovie && (t.contains('正片') || t.contains('高清'))) score += 5;
      if (t.contains('剪辑') ||
          t.contains('解说') ||
          t.contains('预告') ||
          t.contains('混剪') ||
          t.contains('万字') ||
          t.contains('电影解析')) {
        score -= 10;
      }
      if (score > bestScore) {
        bestScore = score;
        best = bvid;
      }
    }

    for (final m in re.allMatches(html).take(20)) {
      consider(m.group(1)!, m.group(2) ?? '');
    }
    for (final m in re2.allMatches(html).take(20)) {
      consider(m.group(2)!, m.group(1) ?? '');
    }
    return bestScore >= 3 ? best : null;
  }

  String? _firstGoodBvid(String html) {
    final matches = RegExp(r'BV[a-zA-Z0-9]{10}').allMatches(html);
    final seen = <String>{};
    for (final m in matches) {
      final bv = m.group(0)!;
      if (!seen.add(bv)) continue;
      if (bv == 'BV1xx411c7mD' || bv == 'BV1GJ411x7h7') continue;
      return bv;
    }
    return null;
  }

  String? _pickBestBvid(
    List<dynamic> result,
    String keyword, {
    bool preferCollection = false,
    bool preferMovie = false,
  }) {
    String? best;
    var bestScore = -999;
    final kw = keyword.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    for (final e in result.take(15)) {
      if (e is! Map) continue;
      final bvid = '${e['bvid'] ?? ''}'.trim();
      if (bvid.isEmpty) continue;
      final t = '${e['title'] ?? ''}'
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), '')
          .toLowerCase();
      var score = 0;
      if (t.contains(kw)) {
        score += 8;
      } else {
        final head = kw.substring(0, math.min(4, kw.length));
        if (head.isNotEmpty && t.contains(head)) score += 3;
      }
      final pages = (e['page'] as num?)?.toInt() ??
          (e['videos'] as num?)?.toInt() ??
          0;
      if (preferCollection && pages > 1) score += 4;
      if (preferCollection &&
          (t.contains('合集') || t.contains('全集') || t.contains('全话'))) {
        score += 4;
      }
      if (preferMovie && (t.contains('正片') || t.contains('高清'))) score += 4;
      if (t.contains('正片') || t.contains('全集')) score += 2;
      if (t.contains('剪辑') ||
          t.contains('解说') ||
          t.contains('预告') ||
          t.contains('混剪') ||
          t.contains('万字')) {
        score -= 10;
      }
      if (score > bestScore) {
        bestScore = score;
        best = bvid;
      }
    }
    return bestScore >= 3 ? best : null;
  }

  Future<List<DanmakuItem>> _fetchBilibiliXml(int cid) async {
    final uris = <Uri>[
      Uri.parse('https://comment.bilibili.com/$cid.xml'),
      Uri.https('api.bilibili.com', '/x/v1/dm/list.so', {'oid': '$cid'}),
    ];
    for (final uri in uris) {
      try {
        final res = await _client
            .get(uri, headers: {
              'Accept': 'application/xml,text/xml,*/*',
              'User-Agent': _ua,
              'Referer': 'https://www.bilibili.com/',
            })
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final items = _parseBilibiliXml(utf8.decode(res.bodyBytes));
        if (items.isNotEmpty) {
          debugPrint('[danmaku] bili xml cid=$cid items=${items.length}');
          return items;
        }
      } catch (e) {
        debugPrint('[danmaku] bili xml fail: $e');
      }
    }
    return const [];
  }

  List<DanmakuItem> _parseBilibiliXml(String xml) {
    final out = <DanmakuItem>[];
    final re = RegExp(
      r'''<d\s+p="([^"]+)"[^>]*>([^<]*)</d>''',
      caseSensitive: false,
    );
    for (final m in re.allMatches(xml)) {
      if (out.length >= _maxItems) break;
      final p = m.group(1) ?? '';
      final text = _decodeXml(m.group(2) ?? '').trim();
      if (text.isEmpty) continue;
      final parts = p.split(',');
      if (parts.isEmpty) continue;
      final time = double.tryParse(parts[0]) ?? 0;
      var color = 0xFFFFFFFF;
      if (parts.length > 3) {
        final c = int.tryParse(parts[3]);
        if (c != null) color = 0xFF000000 | (c & 0xFFFFFF);
      }
      out.add(DanmakuItem(timeSec: time, text: text, color: color));
    }
    return out;
  }

  static String _decodeXml(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static int _parseColor(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return 0xFFFFFFFF;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
    }
    final n = int.tryParse(s, radix: 16);
    if (n == null) return 0xFFFFFFFF;
    if (s.length <= 6) return 0xFF000000 | n;
    return n;
  }

  static String _colorHex(int color) {
    final rgb = color & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static bool _isNoise(String text) {
    const tips = [
      '一条弹幕都没有',
      '弹幕正在袭来',
      '弹幕正在路上',
      '请遵守弹幕礼仪',
      '禁止发送',
      '祝观影愉快',
      '欢迎来到',
    ];
    if (tips.any(text.contains)) return true;
    if (RegExp(r'^\d{9,}$').hasMatch(text)) return true;
    return false;
  }
}
