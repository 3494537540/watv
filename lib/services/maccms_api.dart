import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/movie_models.dart';
import '../utils/qq_avatar.dart';
import '../utils/relative_time.dart';
import 'huihuo_http.dart';
import 'huihuo_panel_api.dart';
import 'local_my_comments_store.dart';

/// 苹果 CMS V10 `provide/vod` 客户端
class MacCmsApi {
  MacCmsApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 评论验证码会话 Cookie
  String? _commentCookie;

  /// 复用 CMS 会员登录 Cookie，便于登录态评论
  void adoptCmsSessionCookie(String? cookie) {
    final c = cookie?.trim();
    if (c == null || c.isEmpty) return;
    if (_commentCookie == null || _commentCookie!.isEmpty) {
      _commentCookie = c;
      return;
    }
    final map = <String, String>{};
    for (final part in '$_commentCookie; $c'.split('; ')) {
      final i = part.indexOf('=');
      if (i > 0) map[part.substring(0, i)] = part.substring(i + 1);
    }
    _commentCookie = map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 主流剧分类：国产/台/韩/欧美/日/港/连续剧（排除泰剧等）
  static const _preferredTvTypeIds = {13, 14, 15, 16, 24, 45, 51};

  Uri _vodUri(Map<String, String> query) {
    return Uri.parse(ApiConfig.macCmsVodProvide).replace(queryParameters: {
      if (ApiConfig.useCmsWebProxy) ...{
        'target': 'vod',
      },
      ...query,
    });
  }

  Future<Map<String, dynamic>> _get(Map<String, String> query) async {
    late http.Response res;
    try {
      res = await _client
          .get(
            _vodUri(query),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _ua,
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw MacCmsException('网络连接失败，请检查影视接口');
    }

    final body = utf8.decode(res.bodyBytes).trim();
    if (body == 'closed') {
      throw MacCmsException('开放 API 未开启（closed）');
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw MacCmsException('接口返回无法解析（HTTP ${res.statusCode}）');
    }
    if (decoded is! Map) {
      throw MacCmsException('接口返回格式异常');
    }
    final json = Map<String, dynamic>.from(decoded);
    final code = (json['code'] as num?)?.toInt() ?? 0;
    if (code != 1) {
      throw MacCmsException('${json['msg'] ?? '请求失败'}');
    }
    return json;
  }

  /// 首页轮播 / 热播区：按 Tab 取该分类周热门
  ///
  /// - [tab] 推荐 / 电影 / 电视剧 / 综艺 / 动漫 / 资讯
  /// - 推荐：电影+剧混合周热
  /// - 其它：`/vod/show/id/{type}/by/hits_week.html` 该分类最热
  Future<List<Movie>> fetchBannerMovies({
    int limit = 6,
    String tab = '推荐',
  }) async {
    final typeId = ApiConfig.macCmsHomeTabTypeIds[tab];
    if (typeId == null) {
      // 推荐
      final ranked = await _fetchSiteWeekHot(limit: limit);
      if (ranked.isNotEmpty) return ranked;
      return _fetchBannerMoviesFallback(limit: limit);
    }
    final ranked = await _fetchCategoryWeekHot(typeId, limit: limit);
    if (ranked.isNotEmpty) return ranked;
    // 短剧：不走 Banner 排除，直接按分类拉
    if (tab == '短剧') {
      try {
        return await fetchByType(
          typeId: ApiConfig.macCmsShortDramaTypeId,
          page: 1,
          limit: limit,
          applyBannerExclude: false,
        );
      } catch (_) {
        return const [];
      }
    }
    return _fetchBannerMoviesFallback(limit: limit, typeId: typeId);
  }

  /// 热门列表（轮播 + 「本周热门」共用）
  Future<List<Movie>> fetchHotMovies({
    int limit = 24,
    String tab = '推荐',
  }) =>
      fetchBannerMovies(limit: limit, tab: tab);

  /// 分类周热门（公开，供首页分区用）
  Future<List<Movie>> fetchWeekHot({
    required int typeId,
    int limit = 18,
  }) =>
      _fetchCategoryWeekHot(typeId, limit: limit);

  /// 单分类周热门（保持网页排行顺序）
  Future<List<Movie>> _fetchCategoryWeekHot(
    int typeId, {
    required int limit,
  }) async {
    List<String> ids = const [];
    try {
      ids = await _rankIdsFromHtml(
        ApiConfig.macCmsWeekHotUrl(typeId),
        limit + 8,
      );
    } catch (_) {
      return const [];
    }
    if (ids.isEmpty) return const [];

    final byId = await _fetchDetailsByIds(ids);
    if (byId.isEmpty) return const [];

    final out = <Movie>[];
    for (final id in ids) {
      final m = byId[id];
      if (!_usableHot(m)) continue;
      out.add(movieFromVod(m!));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 从站点周热门页取片：电影为主、主流剧为辅，保持网页排行顺序
  Future<List<Movie>> _fetchSiteWeekHot({required int limit}) async {
    final movieNeed = (limit * 2 / 3).ceil().clamp(1, limit);
    final tvNeed = (limit - movieNeed).clamp(0, limit);

    List<String> movieIds = const [];
    List<String> tvIds = const [];
    try {
      final pages = await Future.wait([
        _rankIdsFromHtml(ApiConfig.macCmsMovieWeekHotUrl, movieNeed + 6),
        _rankIdsFromHtml(ApiConfig.macCmsTvWeekHotUrl, tvNeed + 10),
      ]);
      movieIds = pages[0];
      tvIds = pages[1];
    } catch (_) {
      return const [];
    }

    // 周热门页都空时，试总排行
    if (movieIds.isEmpty && tvIds.isEmpty) {
      try {
        movieIds = await _rankIdsFromHtml(ApiConfig.macCmsRankUrl, limit + 4);
      } catch (_) {
        return const [];
      }
    }
    if (movieIds.isEmpty && tvIds.isEmpty) return const [];

    final byId = await _fetchDetailsByIds({...movieIds, ...tvIds}.toList());
    if (byId.isEmpty) return const [];

    final validMovies = <String>[
      for (final id in movieIds)
        if (_usableHot(byId[id])) id,
    ];
    final validTvs = <String>[];
    for (final id in tvIds) {
      final m = byId[id];
      if (!_usableHot(m)) continue;
      if (!_preferredTvTypeIds.contains(_typeIdOf(m!))) continue;
      validTvs.add(id);
    }
    // 主流剧不够时放宽（仍排除短剧/成人/泰剧）
    if (validTvs.length < tvNeed) {
      for (final id in tvIds) {
        if (validTvs.contains(id)) continue;
        if (!_usableHot(byId[id])) continue;
        validTvs.add(id);
        if (validTvs.length >= tvNeed + 2) break;
      }
    }

    // 两部电影夹一部剧，贴近「热门影视」观感
    final orderedIds = <String>[];
    var i = 0;
    var j = 0;
    while (orderedIds.length < limit &&
        (i < validMovies.length || j < validTvs.length)) {
      if (i < validMovies.length) orderedIds.add(validMovies[i++]);
      if (orderedIds.length >= limit) break;
      if (i < validMovies.length) orderedIds.add(validMovies[i++]);
      if (orderedIds.length >= limit) break;
      if (j < validTvs.length) orderedIds.add(validTvs[j++]);
    }

    // 若剧为空，纯电影补满
    if (orderedIds.length < limit) {
      for (final id in validMovies) {
        if (orderedIds.contains(id)) continue;
        orderedIds.add(id);
        if (orderedIds.length >= limit) break;
      }
    }

    final out = <Movie>[];
    for (final id in orderedIds) {
      final m = byId[id];
      if (m == null) continue;
      out.add(movieFromVod(m));
      if (out.length >= limit) break;
    }
    return out;
  }

  bool _usableHot(Map<String, dynamic>? m) {
    if (m == null) return false;
    if (ApiConfig.macCmsBannerExcludeTypeIds.contains(_typeIdOf(m))) {
      return false;
    }
    final pic = '${m['vod_pic'] ?? m['vod_pic_slide'] ?? ''}'.trim();
    return pic.isNotEmpty;
  }

  Future<List<String>> _rankIdsFromHtml(String url, int limit) async {
    late http.Response res;
    try {
      res = await _client
          .get(
            Uri.parse(url),
            headers: const {
              'Accept': 'text/html,application/xhtml+xml',
              'User-Agent': _ua,
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      return const [];
    }
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final html = utf8.decode(res.bodyBytes);
    final matches = RegExp(r'vod/detail/id/(\d+)\.html').allMatches(html);
    final seen = <String>{};
    final ids = <String>[];
    for (final m in matches) {
      final id = m.group(1)!;
      if (seen.add(id)) {
        ids.add(id);
        if (ids.length >= limit) break;
      }
    }
    return ids;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchDetailsByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final json = await _get({
      'ac': 'detail',
      'ids': ids.join(','),
    });
    final raw = json['list'];
    if (raw is! List) return {};
    final map = <String, Map<String, dynamic>>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = '${m['vod_id'] ?? ''}';
      if (id.isNotEmpty) map[id] = m;
    }
    return map;
  }

  /// 批量拉取详情（收藏/历史更新检测等）
  Future<List<Movie>> fetchMoviesByIds(List<String> ids) async {
    final cleaned = <String>[];
    final seen = <String>{};
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      cleaned.add(id);
    }
    if (cleaned.isEmpty) return const [];
    final out = <Movie>[];
    const chunk = 40;
    for (var i = 0; i < cleaned.length; i += chunk) {
      final end = (i + chunk > cleaned.length) ? cleaned.length : i + chunk;
      final byId = await _fetchDetailsByIds(cleaned.sublist(i, end));
      for (final id in cleaned.sublist(i, end)) {
        final m = byId[id];
        if (m == null) continue;
        out.add(movieFromVod(m));
      }
    }
    return out;
  }

  /// 接口兜底：按周热度排序
  ///
  /// [typeId] 为一级分类时只拉该分类；null 则电影+剧混合。
  Future<List<Movie>> _fetchBannerMoviesFallback({
    int limit = 6,
    int? typeId,
  }) async {
    final exclude = ApiConfig.macCmsBannerExcludeTypeIds;

    Future<List<Map<String, dynamic>>> loadTypes(List<int> typeIds) async {
      final pages = await Future.wait([
        for (final tid in typeIds)
          () async {
            try {
              return await _get({'ac': 'detail', 'pg': '1', 't': '$tid'});
            } catch (_) {
              return <String, dynamic>{};
            }
          }(),
      ]);
      final out = <Map<String, dynamic>>[];
      for (final json in pages) {
        final raw = json['list'];
        if (raw is! List) continue;
        for (final item in raw) {
          if (item is! Map) continue;
          out.add(Map<String, dynamic>.from(item));
        }
      }
      return out;
    }

    List<_ScoredVod> rank(
      List<Map<String, dynamic>> raw, {
      bool tvPreferredOnly = false,
    }) {
      final byId = <String, _ScoredVod>{};
      for (final m in raw) {
        final tid = _typeIdOf(m);
        if (exclude.contains(tid)) continue;
        if (tvPreferredOnly && !_preferredTvTypeIds.contains(tid)) continue;
        final id = '${m['vod_id'] ?? ''}';
        if (id.isEmpty) continue;
        final pic = '${m['vod_pic'] ?? ''}'.trim();
        if (pic.isEmpty) continue;
        final week = (m['vod_hits_week'] as num?)?.toInt() ??
            int.tryParse('${m['vod_hits_week'] ?? '0'}') ??
            0;
        final month = (m['vod_hits_month'] as num?)?.toInt() ??
            int.tryParse('${m['vod_hits_month'] ?? '0'}') ??
            0;
        final score = week * 10 + month;
        final prev = byId[id];
        if (prev == null || score > prev.score) {
          byId[id] = _ScoredVod(score: score, raw: m);
        }
      }
      return byId.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    }

    // 单分类：直接 t=一级分类，或电影/剧子类列表
    if (typeId != null) {
      final typeIds = switch (typeId) {
        1 => ApiConfig.macCmsMovieTypeIds,
        2 => ApiConfig.macCmsTvTypeIds,
        _ => [typeId],
      };
      final raw = await loadTypes(typeIds);
      final ranked = rank(
        raw,
        tvPreferredOnly: typeId == 2,
      );
      final list = ranked.isEmpty && typeId == 2 ? rank(raw) : ranked;
      return [
        for (final s in list.take(limit)) movieFromVod(s.raw),
      ];
    }

    final results = await Future.wait([
      loadTypes(ApiConfig.macCmsMovieTypeIds),
      loadTypes(ApiConfig.macCmsTvTypeIds),
    ]);

    final hotMovies = rank(results[0]);
    var hotTvs = rank(results[1], tvPreferredOnly: true);
    if (hotTvs.isEmpty) hotTvs = rank(results[1]);

    final out = <Movie>[];
    var i = 0;
    var j = 0;
    while (out.length < limit && (i < hotMovies.length || j < hotTvs.length)) {
      if (i < hotMovies.length) {
        out.add(movieFromVod(hotMovies[i++].raw));
        if (out.length >= limit) break;
      }
      if (i < hotMovies.length) {
        out.add(movieFromVod(hotMovies[i++].raw));
        if (out.length >= limit) break;
      }
      if (j < hotTvs.length) {
        out.add(movieFromVod(hotTvs[j++].raw));
      }
    }
    return out;
  }

  /// 按分类拉详情列表（分页）
  ///
  /// 一级分类（电影/剧/综艺/动漫）会展开为子分类再合并，
  /// 因为本站 `t=1/2/3/4` 直接拉详情常返回空。
  Future<List<Movie>> fetchByType({
    required int typeId,
    int page = 1,
    int limit = 20,
    /// 短剧/解说等专区需要关闭 Banner 排除
    bool applyBannerExclude = true,
  }) async {
    final typeIds = ApiConfig.macCmsChildTypeIds(typeId);
    if (typeIds.length == 1 && typeIds.first == typeId) {
      return _fetchDetailPage(
        typeId: typeId,
        page: page,
        limit: limit,
        applyBannerExclude: applyBannerExclude,
      );
    }

    final pages = await Future.wait([
      for (final tid in typeIds)
        _fetchDetailPage(
          typeId: tid,
          page: page,
          limit: limit,
          applyBannerExclude: applyBannerExclude,
        ),
    ]);
    final seen = <String>{};
    final out = <Movie>[];
    // 轮询各子类，避免某一类占满
    var guard = 0;
    while (out.length < limit && guard < limit * typeIds.length) {
      final bucket = guard % pages.length;
      final idx = guard ~/ pages.length;
      guard++;
      final list = pages[bucket];
      if (idx >= list.length) continue;
      final m = list[idx];
      if (!seen.add(m.id)) continue;
      out.add(m);
    }
    return out;
  }

  Future<List<Movie>> _fetchDetailPage({
    required int typeId,
    int page = 1,
    int limit = 20,
    bool applyBannerExclude = true,
  }) async {
    final json = await _get({
      'ac': 'detail',
      'pg': '$page',
      't': '$typeId',
    });
    final raw = json['list'];
    if (raw is! List) return const [];
    final exclude = applyBannerExclude
        ? ({
            ...ApiConfig.macCmsBannerExcludeTypeIds,
          }..remove(typeId))
        : const <int>{};
    final out = <Movie>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      if (exclude.contains(_typeIdOf(m))) continue;
      final movie = movieFromVod(m);
      if ((movie.coverUrl ?? '').isEmpty) continue;
      out.add(movie);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 按关键词搜分类名（如「解说」），返回第一个匹配的一级/子类 id
  Future<int?> findTypeIdByName(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return null;
    final types = await fetchVodTypes();
    for (final t in types) {
      if (t.typeName.contains(kw)) return t.typeId;
    }
    return null;
  }

  /// 拉取详情（含播放地址）
  Future<Movie?> fetchVodDetail(String id) async {
    final vid = id.trim();
    if (vid.isEmpty) return null;
    final json = await _get({'ac': 'detail', 'ids': vid});
    final raw = json['list'];
    if (raw is! List || raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) return null;
    return movieFromVod(Map<String, dynamic>.from(first));
  }

  /// CMS 文章列表 `provide/art`
  Future<List<CmsArticle>> fetchArticles({
    int page = 1,
    int limit = 20,
    int? typeId,
  }) async {
    final uri = Uri.parse(ApiConfig.macCmsArtProvide).replace(
      queryParameters: {
        if (ApiConfig.useCmsWebProxy) ...{
          'target': 'art',
        },
        'ac': 'detail',
        'pg': '$page',
        if (typeId != null) 't': '$typeId',
      },
    );
    late http.Response res;
    try {
      res = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _ua,
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw MacCmsException('文章接口网络失败');
    }
    final body = utf8.decode(res.bodyBytes).trim();
    if (body == 'closed') throw MacCmsException('文章开放 API 未开启');
    late final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw MacCmsException('文章接口无法解析');
    }
    if (decoded is! Map) return const [];
    final code = (decoded['code'] as num?)?.toInt() ?? 0;
    if (code != 1) return const [];
    final raw = decoded['list'];
    if (raw is! List) return const [];
    final out = <CmsArticle>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final art = articleFromCms(Map<String, dynamic>.from(item));
      if (art == null) continue;
      out.add(art);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 单篇详情：provide/art?ac=detail&ids= → 面板 DB 兜底
  Future<CmsArticle?> fetchArticleDetail(String id) async {
    final aid = id.trim();
    if (aid.isEmpty) return null;

    try {
      final uri = Uri.parse(ApiConfig.macCmsArtProvide).replace(
        queryParameters: {
          if (ApiConfig.useCmsWebProxy) ...{
            'target': 'art',
          },
          'ac': 'detail',
          'ids': aid,
        },
      );
      final res = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': _ua,
            },
          )
          .timeout(const Duration(seconds: 20));
      final body = utf8.decode(res.bodyBytes).trim();
      if (body.startsWith('{')) {
        final decoded = jsonDecode(body);
        if (decoded is Map &&
            ((decoded['code'] as num?)?.toInt() ?? 0) == 1) {
          final raw = decoded['list'];
          if (raw is List && raw.isNotEmpty && raw.first is Map) {
            final art = articleFromCms(
              Map<String, dynamic>.from(raw.first as Map),
            );
            if (art != null &&
                (art.content.trim().isNotEmpty ||
                    art.contentHtml.trim().isNotEmpty)) {
              return art;
            }
            if (art != null) {
              final panel = await _fetchArticleFromPanel(aid);
              return panel ?? art;
            }
          }
        }
      }
    } catch (_) {}

    return _fetchArticleFromPanel(aid);
  }

  Future<CmsArticle?> _fetchArticleFromPanel(String id) async {
    try {
      final res = await huihuoHttpGet(
        ApiConfig.huihuoPanelArtDetailUrl(id),
        timeout: const Duration(seconds: 12),
      );
      if (res.status < 200 || res.status >= 300) return null;
      final body = res.body.trim();
      if (!body.startsWith('{')) return null;
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      if (decoded['code'] != 1 && decoded['code'] != '1') return null;
      final data = decoded['data'];
      if (data is! Map) return null;
      return articleFromCms(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// 解析 CMS art 字段（provide / 面板 DB）
  static CmsArticle? articleFromCms(Map<String, dynamic> m) {
    final id = '${m['art_id'] ?? m['id'] ?? ''}'.trim();
    final title = '${m['art_name'] ?? m['name'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) return null;

    final picRaw =
        '${m['art_pic'] ?? m['art_pic_thumb'] ?? m['pic'] ?? m['art_img'] ?? ''}'
            .trim();
    final htmlRaw =
        '${m['art_content'] ?? m['content'] ?? m['art_body'] ?? ''}'.trim();
    final blurb =
        '${m['art_blurb'] ?? m['art_sub'] ?? m['art_remarks'] ?? ''}'.trim();
    final timeRaw =
        '${m['art_time'] ?? m['art_pubdate'] ?? m['time'] ?? ''}'.trim();
    final hits = int.tryParse('${m['art_hits'] ?? m['hits'] ?? 0}') ?? 0;
    final typeId = int.tryParse('${m['type_id'] ?? 0}') ?? 0;

    return CmsArticle(
      id: id,
      title: title,
      subTitle: blurb.isEmpty ? _htmlToPlain(htmlRaw).trim() : _stripHtml(blurb),
      content: _htmlToPlain(htmlRaw),
      contentHtml: htmlRaw,
      coverUrl: _absoluteCmsUrl(picRaw),
      timeText: _formatArtTime(timeRaw),
      author: '${m['art_author'] ?? m['author'] ?? ''}'.trim(),
      typeName: '${m['type_name'] ?? ''}'.trim(),
      typeId: typeId,
      from: '${m['art_from'] ?? m['from'] ?? ''}'.trim(),
      remarks: '${m['art_remarks'] ?? ''}'.trim(),
      hits: hits,
      tag: '${m['art_tag'] ?? m['tag'] ?? ''}'.trim(),
    );
  }

  static String _formatArtTime(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t == '0') return '';
    final ts = int.tryParse(t);
    if (ts != null && ts > 1000000000) {
      final sec = ts > 9999999999 ? ts ~/ 1000 : ts;
      final dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    final m = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(t);
    if (m != null) {
      return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
    }
    return t;
  }

  static String _htmlToPlain(String raw) {
    if (raw.trim().isEmpty) return '';
    var s = raw
        .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n');
    s = _stripHtml(s);
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return s;
  }

  /// 追番表：动漫 + 剧集近期更新，按周几分组
  Future<Map<int, List<Movie>>> fetchBangumiSchedule({int limit = 80}) async {
    final out = <int, List<Movie>>{
      for (var d = 1; d <= 7; d++) d: <Movie>[],
    };
    final seen = <String>{};

    Future<void> ingest(List<Movie> list, {Map<String, int>? weekById}) async {
      for (final m in list) {
        if (!seen.add(m.id)) continue;
        if ((m.coverUrl ?? '').isEmpty) continue;
        // 偏剧集 / 动漫；纯电影（单集且无更新备注）弱优先
        final wd = weekById?[m.id] ??
            weekdayFromRemarks(m.remarks) ??
            weekdayFromRemarks(m.tagline) ??
            _weekdayFallback(m.id);
        out[wd]!.add(m);
      }
    }

    // 动漫分类 + 子类
    final animeIds = {
      ApiConfig.macCmsHomeTabTypeIds['动漫'] ?? 4,
      ...ApiConfig.macCmsChildTypeIds(
        ApiConfig.macCmsHomeTabTypeIds['动漫'] ?? 4,
      ),
    };
    final tvIds = {
      ApiConfig.macCmsHomeTabTypeIds['电视剧'] ?? 2,
      ...ApiConfig.macCmsChildTypeIds(
        ApiConfig.macCmsHomeTabTypeIds['电视剧'] ?? 2,
      ),
    };

    final weekById = <String, int>{};

    Future<void> pullTypes(Set<int> typeIds) async {
      for (final tid in typeIds.take(8)) {
        try {
          final json = await _get({
            'ac': 'detail',
            't': '$tid',
            'pg': '1',
          });
          final raw = json['list'];
          if (raw is! List) continue;
          final movies = <Movie>[];
          for (final item in raw) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            final movie = movieFromVod(m);
            final id = movie.id;
            final fromField = _weekdayFromCmsMap(m);
            if (fromField != null) weekById[id] = fromField;
            movies.add(movie);
            if (movies.length >= limit ~/ 2) break;
          }
          await ingest(movies, weekById: weekById);
        } catch (_) {}
      }
    }

    await pullTypes(animeIds);
    if (out.values.fold<int>(0, (a, b) => a + b.length) < 24) {
      await pullTypes(tvIds);
    }

    // 仍空：全站最近更新兜底
    if (out.values.every((e) => e.isEmpty)) {
      final latest = await fetchLatest(limit: limit);
      await ingest(latest, weekById: weekById);
    }

    // 每天最多 36 条
    for (final e in out.entries) {
      if (e.value.length > 36) {
        out[e.key] = e.value.take(36).toList();
      }
    }
    return out;
  }

  static int? weekdayFromRemarks(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return null;
    const map = {
      '周一': 1,
      '星期一': 1,
      '周二': 2,
      '星期二': 2,
      '周三': 3,
      '星期三': 3,
      '周四': 4,
      '星期四': 4,
      '周五': 5,
      '星期五': 5,
      '周六': 6,
      '星期六': 6,
      '周日': 7,
      '星期日': 7,
      '周天': 7,
    };
    for (final e in map.entries) {
      if (r.contains(e.key)) return e.value;
    }
    return null;
  }

  static int? _weekdayFromCmsMap(Map<String, dynamic> m) {
    final w = int.tryParse('${m['vod_weekday'] ?? m['weekday'] ?? ''}');
    if (w != null && w >= 1 && w <= 7) return w;
    // 0=周日 的站点
    if (w == 0) return 7;

    final fromRemarks = weekdayFromRemarks('${m['vod_remarks'] ?? ''}');
    if (fromRemarks != null) return fromRemarks;

    final timeRaw =
        '${m['vod_time'] ?? m['vod_time_add'] ?? m['vod_pubdate'] ?? ''}'
            .trim();
    final ts = int.tryParse(timeRaw);
    if (ts != null && ts > 1000000000) {
      final sec = ts > 9999999999 ? ts ~/ 1000 : ts;
      return DateTime.fromMillisecondsSinceEpoch(sec * 1000).weekday;
    }
    final dt = DateTime.tryParse(timeRaw.replaceAll('/', '-'));
    return dt?.weekday;
  }

  static int _weekdayFallback(String id) {
    final n = int.tryParse(id) ?? id.hashCode.abs();
    return (n % 7) + 1;
  }

  /// 最新更新（全站或指定分类）
  Future<List<Movie>> fetchLatest({
    int? typeId,
    int page = 1,
    int limit = 18,
  }) async {
    final exclude = ApiConfig.macCmsBannerExcludeTypeIds;
    final allow = typeId == null
        ? null
        : ApiConfig.macCmsChildTypeIds(typeId).toSet();

    // 一级分类接口常空：拉全站最近更新，再按子类过滤（更贴近「最新」）
    final out = <Movie>[];
    final seen = <String>{};
    for (var pg = page; pg < page + 3 && out.length < limit; pg++) {
      final json = await _get({
        'ac': 'detail',
        'pg': '$pg',
      });
      final raw = json['list'];
      if (raw is! List || raw.isEmpty) break;
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final tid = _typeIdOf(m);
        if (exclude.contains(tid)) continue;
        if (allow != null && !allow.contains(tid)) continue;
        final movie = movieFromVod(m);
        if ((movie.coverUrl ?? '').isEmpty) continue;
        if (!seen.add(movie.id)) continue;
        out.add(movie);
        if (out.length >= limit) break;
      }
    }
    if (out.isNotEmpty) return out;

    // 兜底：按子类分页
    if (typeId != null) {
      return fetchByType(typeId: typeId, page: page, limit: limit);
    }
    return const [];
  }

  /// 关键词搜索（详情接口带封面；含短剧，排除成人/里番）
  Future<List<Movie>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
    /// 按一级/子类过滤；一级会展开子类
    int? typeId,
    Set<int>? typeIds,
  }) async {
    final wd = keyword.trim();
    if (wd.isEmpty) return const [];
    final json = await _get({
      'ac': 'detail',
      'wd': wd,
      'pg': '$page',
    });
    final raw = json['list'];
    if (raw is! List) return const [];
    final exclude = ApiConfig.macCmsSearchExcludeTypeIds;
    Set<int>? allow;
    if (typeIds != null && typeIds.isNotEmpty) {
      allow = typeIds;
    } else if (typeId != null && typeId > 0) {
      allow = {typeId, ...await childTypeIdsOf(typeId)};
    }
    final out = <Movie>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final tid = _typeIdOf(m);
      if (exclude.contains(tid)) continue;
      if (allow != null && !allow.contains(tid)) continue;
      out.add(movieFromVod(m));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 拉取 CMS 分类树（ac=list → class[]）
  Future<List<MacCmsTypeNode>> fetchVodTypes() async {
    final json = await _get({'ac': 'list', 'pg': '1'});
    final raw = json['class'];
    if (raw is! List) return const [];
    final out = <MacCmsTypeNode>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = (m['type_id'] as num?)?.toInt() ??
          int.tryParse('${m['type_id'] ?? ''}') ??
          0;
      if (id <= 0) continue;
      final pid = (m['type_pid'] as num?)?.toInt() ??
          int.tryParse('${m['type_pid'] ?? ''}') ??
          0;
      final name = '${m['type_name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      out.add(MacCmsTypeNode(typeId: id, typePid: pid, typeName: name));
    }
    return out;
  }

  /// 某分类及其全部子孙 type_id
  Future<Set<int>> childTypeIdsOf(int rootId) async {
    final types = await fetchVodTypes();
    return typeIdsUnder(rootId, types);
  }

  /// 搜索顶栏频道：全部 + CMS 一级影视分类（含短剧）
  Future<List<MacCmsSearchChannel>> fetchSearchChannels() async {
    try {
      final types = await fetchVodTypes();
      if (types.isEmpty) return ApiConfig.macCmsSearchChannelDefaults;
      final roots = [
        for (final t in types)
          if (t.typePid == 0 &&
              !ApiConfig.macCmsSearchTabExcludeTypeIds.contains(t.typeId))
            t,
      ];
      final preferred = <int, int>{
        for (var i = 0;
            i < ApiConfig.macCmsSearchChannelDefaults.length;
            i++)
          if (ApiConfig.macCmsSearchChannelDefaults[i].typeId != null)
            ApiConfig.macCmsSearchChannelDefaults[i].typeId!: i,
      };
      roots.sort((a, b) {
        final pa = preferred[a.typeId] ?? 1000 + a.typeId;
        final pb = preferred[b.typeId] ?? 1000 + b.typeId;
        return pa.compareTo(pb);
      });
      // 确保短剧在列表里（后台若改名仍用 id=44）
      final hasShort =
          roots.any((t) => t.typeId == ApiConfig.macCmsShortDramaTypeId);
      final channels = <MacCmsSearchChannel>[
        const MacCmsSearchChannel(name: '全部', typeId: null),
        for (final t in roots)
          MacCmsSearchChannel(name: t.typeName, typeId: t.typeId),
      ];
      if (!hasShort) {
        channels.add(
          const MacCmsSearchChannel(
            name: '短剧',
            typeId: ApiConfig.macCmsShortDramaTypeId,
          ),
        );
      }
      return channels;
    } catch (_) {
      return ApiConfig.macCmsSearchChannelDefaults;
    }
  }

  static Set<int> typeIdsUnder(int rootId, List<MacCmsTypeNode> types) {
    final byPid = <int, List<int>>{};
    for (final t in types) {
      byPid.putIfAbsent(t.typePid, () => []).add(t.typeId);
    }
    final out = <int>{rootId};
    final queue = <int>[rootId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      for (final c in byPid[id] ?? const <int>[]) {
        if (out.add(c)) queue.add(c);
      }
    }
    return out;
  }

  /// 把 typeId 归到一级分类名（电影/电视剧/短剧…）
  static String rootCategoryName(
    int typeId,
    List<MacCmsTypeNode> types, {
    String fallback = '影视',
  }) {
    if (typeId <= 0) return fallback;
    final byId = {for (final t in types) t.typeId: t};
    var id = typeId;
    for (var i = 0; i < 10; i++) {
      final n = byId[id];
      if (n == null) break;
      if (n.typePid == 0) return n.typeName;
      id = n.typePid;
    }
    // 无树时的兜底（含短剧）
    if ({6, 7, 8, 9, 10, 11, 12, 31, 32, 33, 34, 35, 36, 37, 38, 39, 1, 65, 69}
        .contains(typeId)) {
      return '电影';
    }
    if ({13, 14, 15, 16, 24, 45, 46, 51, 2, 47, 93}.contains(typeId)) {
      return '电视剧';
    }
    if ({40, 41, 42, 43, 3}.contains(typeId)) return '综艺';
    if ({25, 26, 27, 28, 29, 4, 63, 70, 82}.contains(typeId)) return '动漫';
    if ({44, 64, 74, 75, 76, 77, 78, 79, 91, 92, 94}.contains(typeId)) {
      return '短剧';
    }
    return fallback;
  }

  /// 按首页类型标签拉片（支持排除已展示 ID，避免和热门区重复）
  Future<List<Movie>> fetchByGenreTag(
    MacCmsGenreTag tag, {
    int page = 1,
    int limit = 18,
    Set<String> excludeIds = const {},
  }) async {
    List<Movie> raw;
    final need = limit + excludeIds.length;
    switch (tag.mode) {
      case MacCmsGenreMode.latest:
        raw = await fetchLatest(
          typeId: tag.typeId,
          page: page,
          limit: need,
        );
      case MacCmsGenreMode.weekHot:
        // 周热榜多为单页；第 2 页起改走分类详情分页，保证片库能持续加载
        if (page > 1) {
          final tid = tag.typeId;
          if (tid != null && tid > 0) {
            raw = await fetchByType(typeId: tid, page: page, limit: need);
          } else {
            raw = await fetchLatest(page: page, limit: need);
          }
        } else {
          raw = await fetchWeekHot(
            typeId: tag.typeId ?? 1,
            limit: need,
          );
        }
      case MacCmsGenreMode.byType:
        raw = await fetchByType(
          typeId: tag.typeId ?? 0,
          page: page,
          limit: need,
        );
    }
    if (excludeIds.isEmpty) return raw.take(limit).toList();
    return [
      for (final m in raw)
        if (!excludeIds.contains(m.id)) m,
    ].take(limit).toList();
  }

  /// 片库三维筛选：对齐站点 `/vod/show`（分类 type + area + year）
  ///
  /// - 仅分类：走 provide `ac=detail&t=`（一级会展开子类）
  /// - 含地区/年代：解析站点 show 页（provide 不支持 area，year 无效）
  Future<List<Movie>> fetchLibraryShow({
    int? channelTypeId,
    int? classTypeId,
    String? area,
    String? year,
    int page = 1,
    int limit = 30,
  }) async {
    final areaKey = (area == null || area.isEmpty || area == '全部')
        ? null
        : area.trim();
    final yearKey = (year == null || year.isEmpty || year == '全部')
        ? null
        : year.trim();
    final showId = classTypeId ?? channelTypeId;
    final needShow = areaKey != null || yearKey != null;

    if (!needShow) {
      if (classTypeId != null && classTypeId > 0) {
        return fetchByType(typeId: classTypeId, page: page, limit: limit);
      }
      if (channelTypeId != null && channelTypeId > 0) {
        return fetchByType(typeId: channelTypeId, page: page, limit: limit);
      }
      return fetchLatest(page: page, limit: limit);
    }

    if (showId == null || showId <= 0) {
      // 全部频道 + 地区/年代：拉最近更新后在客户端过滤
      return _filterLibraryClient(
        await fetchLatest(page: page, limit: limit * 3),
        area: areaKey,
        year: yearKey,
        limit: limit,
      );
    }

    final url = _libraryShowUrl(
      typeId: showId,
      area: areaKey,
      year: yearKey,
      page: page,
    );
    final ids = await _rankIdsFromHtml(url, limit + 8);
    if (ids.isEmpty) {
      // show 页空时，provide 兜底再客户端过滤
      final fallback = classTypeId != null
          ? await fetchByType(typeId: classTypeId, page: page, limit: limit * 2)
          : await fetchByType(typeId: showId, page: page, limit: limit * 2);
      return _filterLibraryClient(
        fallback,
        area: areaKey,
        year: yearKey,
        limit: limit,
      );
    }

    final byId = await _fetchDetailsByIds(ids);
    final out = <Movie>[];
    for (final id in ids) {
      final raw = byId[id];
      if (raw == null) continue;
      if (ApiConfig.macCmsBannerExcludeTypeIds.contains(_typeIdOf(raw))) {
        continue;
      }
      final movie = movieFromVod(raw);
      if ((movie.coverUrl ?? '').isEmpty) continue;
      out.add(movie);
      if (out.length >= limit) break;
    }
    return out;
  }

  String _libraryShowUrl({
    required int typeId,
    String? area,
    String? year,
    int page = 1,
  }) {
    final parts = <String>['vod', 'show'];
    if (area != null && area.isNotEmpty) {
      parts.add('area');
      parts.add(Uri.encodeComponent(area));
    }
    parts.add('id');
    parts.add('$typeId');
    if (year != null && year.isNotEmpty) {
      parts.add('year');
      parts.add(year);
    }
    if (page > 1) {
      parts.add('page');
      parts.add('$page');
    }
    return '${ApiConfig.macCmsBase}/index.php/${parts.join('/')}.html';
  }

  List<Movie> _filterLibraryClient(
    List<Movie> raw, {
    String? area,
    String? year,
    required int limit,
  }) {
    final out = <Movie>[];
    for (final m in raw) {
      if (year != null) {
        if ('${m.year}' != year && !m.pubdate.startsWith(year)) continue;
      }
      if (area != null) {
        final a = m.area;
        if (a.isEmpty) continue;
        if (!_areaMatch(a, area)) continue;
      }
      out.add(m);
      if (out.length >= limit) break;
    }
    return out;
  }

  bool _areaMatch(String vodArea, String filter) {
    if (vodArea.contains(filter)) return true;
    // 站点筛选项与字段别名
    const aliases = <String, List<String>>{
      '大陆': ['大陆', '中国大陆', '内地', '中国'],
      '内地': ['内地', '大陆', '中国大陆', '中国'],
      '国产': ['国产', '大陆', '中国大陆', '内地', '中国'],
      '香港': ['香港'],
      '台湾': ['台湾'],
      '美国': ['美国'],
      '日本': ['日本'],
      '韩国': ['韩国'],
      '英国': ['英国'],
      '法国': ['法国'],
      '德国': ['德国'],
      '泰国': ['泰国'],
      '印度': ['印度'],
      '意大利': ['意大利'],
      '西班牙': ['西班牙'],
      '加拿大': ['加拿大'],
      '新加坡': ['新加坡'],
      '日韩': ['日本', '韩国', '日韩'],
      '港台': ['香港', '台湾', '港台'],
      '欧美': ['美国', '英国', '法国', '德国', '欧美', '西方'],
      '其他': [],
    };
    final keys = aliases[filter];
    if (keys == null) return vodArea.contains(filter);
    if (keys.isEmpty) {
      // 「其他」：不在常见列表里
      const known = [
        '大陆',
        '内地',
        '中国',
        '香港',
        '台湾',
        '美国',
        '日本',
        '韩国',
        '英国',
        '法国',
        '德国',
        '泰国',
        '印度',
      ];
      return !known.any(vodArea.contains);
    }
    return keys.any(vodArea.contains);
  }

  /// @Deprecated 保留兼容；首页已改为类型标签
  Future<List<MovieSection>> fetchHomeSections({
    String tab = '推荐',
    int limit = 18,
  }) async {
    final tags = ApiConfig.macCmsGenreTagsFor(tab);
    final parts = <MovieSection>[];
    final seen = <String>{};
    for (final tag in tags.take(2)) {
      final movies = await fetchByGenreTag(tag, limit: limit, excludeIds: seen);
      if (movies.isEmpty) continue;
      for (final m in movies) {
        seen.add(m.id);
      }
      parts.add(MovieSection(title: tag.label, movies: movies));
    }
    return parts;
  }

  /// 按 ID 拉完整详情（含播放地址 + 豆瓣演员头像）
  Future<Movie> fetchDetail(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) throw MacCmsException('无效影片 ID');
    final byId = await _fetchDetailsByIds([trimmed]);
    final raw = byId[trimmed];
    if (raw == null) throw MacCmsException('未找到影片详情');
    var movie = movieFromVod(raw);

    var doubanId = movie.doubanId;
    if (doubanId.isEmpty) {
      try {
        doubanId = await resolveDoubanId(
          title: movie.title,
          year: movie.year,
        );
        if (doubanId.isNotEmpty) {
          movie = movie.copyWith(doubanId: doubanId);
        }
      } catch (_) {}
    }

    if (doubanId.isNotEmpty) {
      try {
        final cast = await enrichCastAvatarsFromDouban(
          doubanId: doubanId,
          cast: movie.cast,
        );
        movie = movie.copyWith(cast: cast);
        assert(() {
          final n = cast.where((c) => (c.avatarUrl ?? '').isNotEmpty).length;
          // ignore: avoid_print
          print('[douban] id=$doubanId cast=${cast.length} withAvatar=$n');
          return true;
        }());
      } catch (_) {
        // 豆瓣失败时保留本地头像
      }
    }
    return movie;
  }

  static const Map<String, String> _doubanHeaders = {
    'Accept': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
    'Referer': 'https://m.douban.com/',
  };

  /// CMS 无豆瓣 ID 时，用片名搜索补全
  Future<String> resolveDoubanId({
    required String title,
    int? year,
  }) async {
    final q = title.trim();
    if (q.isEmpty) return '';

    // 1) subject_suggest（电影/剧均可）
    try {
      final uri = Uri.https(
        'movie.douban.com',
        '/j/subject_suggest',
        {'q': q},
      );
      final res = await _client
          .get(uri, headers: _doubanHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is List && decoded.isNotEmpty) {
          final id = _pickSuggestId(decoded, q, year);
          if (id.isNotEmpty) return id;
        }
      }
    } catch (_) {}

    // 2) rexxar search/movie
    try {
      final uri = Uri.parse(
        'https://m.douban.com/rexxar/api/v2/search/movie',
      ).replace(queryParameters: {'q': q});
      final res = await _client
          .get(uri, headers: _doubanHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map && decoded['items'] is List) {
          final items = decoded['items'] as List;
          for (final raw in items) {
            if (raw is! Map) continue;
            final target = raw['target'];
            if (target is! Map) continue;
            final name = '${target['title'] ?? ''}'.trim();
            final id = '${target['id'] ?? ''}'.trim();
            if (id.isEmpty) continue;
            if (name == q || name.contains(q) || q.contains(name)) {
              return id;
            }
          }
          final first = items.isNotEmpty ? items.first : null;
          if (first is Map) {
            final target = first['target'];
            if (target is Map) {
              final id = '${target['id'] ?? ''}'.trim();
              if (id.isNotEmpty) return id;
            }
          }
        }
      }
    } catch (_) {}

    return '';
  }

  static String _pickSuggestId(List decoded, String title, int? year) {
    String? exact;
    String? yearMatch;
    String? first;
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final name = '${raw['title'] ?? ''}'.trim();
      final id = '${raw['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      first ??= id;
      final y = '${raw['year'] ?? ''}'.trim();
      if (name == title) {
        if (year != null && y == '$year') return id;
        exact ??= id;
      }
      if (year != null && y == '$year' && (name.contains(title) || title.contains(name))) {
        yearMatch ??= id;
      }
    }
    return exact ?? yearMatch ?? first ?? '';
  }

  static int _typeIdOf(Map<String, dynamic> m) {
    return (m['type_id'] as num?)?.toInt() ??
        int.tryParse('${m['type_id'] ?? ''}') ??
        0;
  }

  /// 将 CMS vod 字段映射为 App [Movie]
  static Movie movieFromVod(Map<String, dynamic> m) {
    final id = '${m['vod_id'] ?? ''}';
    final name = '${m['vod_name'] ?? ''}'.trim();
    final remarks = '${m['vod_remarks'] ?? ''}'.trim();
    final typeName = '${m['type_name'] ?? ''}'.trim();
    final vodClass = '${m['vod_class'] ?? ''}'.trim();
    final blurb = _stripHtml('${m['vod_blurb'] ?? m['vod_content'] ?? ''}');
    final slide = '${m['vod_pic_slide'] ?? ''}'.trim();
    final pic = '${m['vod_pic'] ?? ''}'.trim();
    final cover = pic.isNotEmpty ? pic : slide;
    final yearRaw = '${m['vod_year'] ?? ''}'.trim();
    final year = int.tryParse(yearRaw) ?? DateTime.now().year;
    final scoreCms = double.tryParse('${m['vod_score'] ?? '0'}') ?? 0;
    final scoreDouban =
        double.tryParse('${m['vod_douban_score'] ?? '0'}') ?? 0;
    final score = scoreDouban > 0 ? scoreDouban : scoreCms;
    final scoreCount = int.tryParse('${m['vod_score_num'] ?? '0'}') ?? 0;
    final area = '${m['vod_area'] ?? ''}'.trim();
    final lang = '${m['vod_lang'] ?? ''}'.trim();
    final director = _cleanPeople('${m['vod_director'] ?? ''}');
    final writerRaw = _cleanPeople('${m['vod_writer'] ?? ''}');
    final writer = (writerRaw == '暂无') ? '' : writerRaw;
    final actor = '${m['vod_actor'] ?? ''}'.trim();
    final durationText = '${m['vod_duration'] ?? ''}'.trim();
    final totalEpisodes = int.tryParse('${m['vod_total'] ?? '0'}') ?? 0;
    final pubdate = '${m['vod_pubdate'] ?? ''}'.trim();
    final subTitle = '${m['vod_sub'] ?? ''}'.trim();
    final nameEn = '${m['vod_en'] ?? ''}'.trim();
    final playFrom = '${m['vod_play_from'] ?? ''}'.trim();
    final playUrl = '${m['vod_play_url'] ?? ''}'.trim();
    final doubanIdRaw = '${m['vod_douban_id'] ?? ''}'.trim();
    final doubanId =
        (doubanIdRaw.isEmpty || doubanIdRaw == '0') ? '' : doubanIdRaw;
    final parsed = _parsePlaySources(playFrom, playUrl);
    final playEpisodes = parsed.defaultEpisodes;
    final episodes = [for (final e in playEpisodes) e.name];

    final genres = <String>[];
    void addGenre(String s) {
      final t = s.trim();
      if (t.isEmpty || genres.contains(t)) return;
      genres.add(t);
    }

    for (final part in vodClass.split(RegExp(r'[,，、/|\s]+'))) {
      addGenre(part);
    }
    addGenre(typeName);
    addGenre(area);

    final tagline = remarks.isNotEmpty
        ? remarks
        : (blurb.isNotEmpty
            ? blurb
            : (area.isNotEmpty ? area : typeName));

    final cast = _parseCast(actor);

    final durationMinutes = _parseDurationMinutes(durationText);

    return Movie(
      id: id.isEmpty ? name : id,
      title: name.isEmpty ? '未命名' : name,
      subtitle: typeName.isNotEmpty
          ? typeName
          : (genres.isNotEmpty ? genres.first : '影视'),
      year: year,
      score: score,
      scoreCount: scoreCount,
      genres: genres.isEmpty ? const ['影视'] : genres,
      coverColor: _colorForId(id.isEmpty ? name : id),
      tagline: tagline.isEmpty ? name : tagline,
      synopsis: blurb.isEmpty ? tagline : blurb,
      coverUrl: cover.isEmpty ? null : _absoluteCmsUrl(cover),
      icon: CupertinoIcons.film,
      cast: cast,
      remarks: remarks,
      episodes: episodes,
      playEpisodes: playEpisodes,
      playSourceNames: [for (final s in parsed.sources) s.name],
      playSources: parsed.sources,
      slideUrl: slide.isEmpty ? null : _absoluteCmsUrl(slide),
      director: director,
      area: area,
      lang: lang,
      durationText: durationText,
      durationMinutes: durationMinutes,
      totalEpisodes: totalEpisodes,
      pubdate: pubdate,
      writer: writer,
      subTitle: (subTitle.isNotEmpty && subTitle != name) ? subTitle : '',
      doubanId: doubanId,
      typeId: _typeIdOf(m),
      nameEn: nameEn,
    );
  }

  /// 豆瓣 celebrities / credits：按姓名匹配真人头像与角色
  Future<List<MovieCast>> enrichCastAvatarsFromDouban({
    required String doubanId,
    required List<MovieCast> cast,
  }) async {
    final id = doubanId.trim();
    if (id.isEmpty) return cast;

    final byName = <String, ({String avatar, String role})>{};

    // 1) celebrities：演员更全
    for (final kind in ['tv', 'movie']) {
      try {
        final uri = Uri.parse(
          'https://m.douban.com/rexxar/api/v2/$kind/$id/celebrities',
        ).replace(queryParameters: const {'ck': ''});
        final res = await _client
            .get(uri, headers: _doubanHeaders)
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is! Map) continue;
        final actors = decoded['actors'];
        if (actors is! List || actors.isEmpty) continue;
        _mergeDoubanPeople(byName, actors);
        if (byName.isNotEmpty) break;
      } catch (_) {
        continue;
      }
    }

    // 2) credits 兜底（主演卡片）
    if (byName.isEmpty) {
      for (final kind in ['tv', 'movie']) {
        try {
          final uri = Uri.parse(
            'https://m.douban.com/rexxar/api/v2/$kind/$id/credits',
          ).replace(queryParameters: const {'ck': ''});
          final res = await _client
              .get(uri, headers: _doubanHeaders)
              .timeout(const Duration(seconds: 10));
          if (res.statusCode != 200) continue;
          final decoded = jsonDecode(utf8.decode(res.bodyBytes));
          if (decoded is! Map) continue;
          final items = decoded['items'];
          if (items is! List || items.isEmpty) continue;
          _mergeDoubanPeople(byName, items);
          if (byName.isNotEmpty) break;
        } catch (_) {
          continue;
        }
      }
    }

    if (byName.isEmpty) return cast;

    // CMS 无演员名单时，直接用豆瓣演员
    if (cast.isEmpty) {
      return [
        for (final e in byName.entries.take(16))
          MovieCast(
            name: e.key,
            role: e.value.role,
            color: _colorForId(e.key),
            avatarUrl: e.value.avatar,
          ),
      ];
    }

    return [
      for (final c in cast)
        if (_matchDoubanPerson(c.name, byName) case final hit?)
          c.copyWith(avatarUrl: hit.avatar, role: hit.role)
        else
          c,
    ];
  }

  static void _mergeDoubanPeople(
    Map<String, ({String avatar, String role})> byName,
    List items,
  ) {
    for (final raw in items) {
      if (raw is! Map) continue;
      final name = '${raw['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final avatarMap = raw['avatar'];
      String avatar = '';
      if (avatarMap is Map) {
        avatar = '${avatarMap['large'] ?? avatarMap['normal'] ?? ''}'.trim();
      }
      if (!_isRealDoubanAvatar(avatar)) continue;

      var role = '${raw['simple_character'] ?? ''}'.trim();
      if (role.isEmpty) {
        final character = '${raw['character'] ?? ''}'.trim();
        final m = RegExp(r'饰\s*(.+)').firstMatch(character);
        if (m != null) {
          role = '饰 ${m.group(1)!.trim()}';
        } else if (character.isNotEmpty &&
            character != '演员' &&
            character != '导演') {
          role = character.startsWith('饰') ? character : '饰 $character';
        } else {
          role = '主演';
        }
      } else if (!role.startsWith('饰')) {
        role = '饰 $role';
      }

      byName.putIfAbsent(name, () => (avatar: avatar, role: role));
    }
  }

  static bool _isRealDoubanAvatar(String url) {
    if (url.isEmpty) return false;
    final u = url.toLowerCase();
    return !(u.contains('personage-default') ||
        u.contains('default-medium') ||
        u.contains('default-large') ||
        u.contains('celebrity-default') ||
        u.contains('icon/user'));
  }

  static ({String avatar, String role})? _matchDoubanPerson(
    String cmsName,
    Map<String, ({String avatar, String role})> byName,
  ) {
    final n = cmsName.trim();
    if (n.isEmpty) return null;
    final exact = byName[n];
    if (exact != null) return exact;

    final compact = n.replaceAll(RegExp(r'[\s·•.．]'), '');
    for (final e in byName.entries) {
      final k = e.key.replaceAll(RegExp(r'[\s·•.．]'), '');
      if (k == compact) return e.value;
      if (k.contains(compact) || compact.contains(k)) {
        // 避免过短误匹配（如「王」）
        if (compact.length >= 2 && k.length >= 2) return e.value;
      }
    }
    return null;
  }

  static String _cleanPeople(String raw) {
    return raw
        .split(RegExp(r'[,，、/|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(' / ');
  }

  static List<MovieCast> _parseCast(String actor) {
    if (actor.isEmpty) return const [];
    final names = actor
        .split(RegExp(r'[,，、/|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '暂无' && e != '内详')
        .take(20)
        .toList();
    return [
      for (final n in names)
        MovieCast(
          name: n,
          role: '主演',
          color: _colorForId(n),
          // CMS 无演员照片；详情页本地绘制头像
          avatarUrl: null,
        ),
    ];
  }

  static int? _parseDurationMinutes(String raw) {
    if (raw.isEmpty) return null;
    final mins = RegExp(r'(\d+)\s*分').firstMatch(raw);
    if (mins != null) return int.tryParse(mins.group(1)!);
    final hm = RegExp(r'(\d+):(\d+)(?::(\d+))?').firstMatch(raw);
    if (hm != null) {
      final a = int.tryParse(hm.group(1)!) ?? 0;
      final b = int.tryParse(hm.group(2)!) ?? 0;
      if (hm.group(3) != null) return a * 60 + b; // HH:MM:SS → 分钟
      return a * 60 + b;
    }
    return int.tryParse(raw);
  }

  /// 解析多线路播放串：from / url 均用 $$$ 分组，集用 #，名$url
  static ({
    List<MoviePlaySource> sources,
    List<MoviePlayEpisode> defaultEpisodes,
  }) _parsePlaySources(String from, String url) {
    if (url.isEmpty) {
      return (
        sources: const <MoviePlaySource>[],
        defaultEpisodes: const <MoviePlayEpisode>[],
      );
    }
    final fromList = from.isEmpty ? <String>['默认'] : from.split(r'$$$');
    final groups = url.split(r'$$$');
    final sources = <MoviePlaySource>[];

    for (var i = 0; i < groups.length; i++) {
      final name = i < fromList.length && fromList[i].trim().isNotEmpty
          ? fromList[i].trim()
          : '线路${i + 1}';
      final episodes = _parseEpisodeGroup(groups[i]);
      if (episodes.isEmpty) continue;
      sources.add(MoviePlaySource(name: name, episodes: episodes));
    }

    if (sources.isEmpty) {
      return (
        sources: const <MoviePlaySource>[],
        defaultEpisodes: const <MoviePlayEpisode>[],
      );
    }

    int scoreSource(MoviePlaySource s) {
      final name = s.name.toLowerCase();
      var sc = 0;
      // 清晰度优先
      if (name.contains('4k') ||
          name.contains('2160') ||
          name.contains('超清') ||
          name.contains('蓝光') ||
          name.contains('1080')) {
        sc += 55;
      } else if (name.contains('高清') ||
          name.contains('hd') ||
          name.contains('720')) {
        sc += 35;
      } else if (name.contains('标清') || name.contains('流畅')) {
        sc += 8;
      }
      // 直链流更稳（优先 m3u8 / mp4）
      if (name.contains('m3u8') ||
          name.contains('hls') ||
          name.contains('modu')) {
        sc += 40;
      }
      final joined =
          s.episodes.map((e) => e.url).join('|').toLowerCase();
      if (joined.contains('.m3u8')) sc += 50;
      if (joined.contains('.mp4')) sc += 28;
      if (joined.contains('https://')) sc += 12;
      else if (joined.contains('http://')) sc += 6;
      // 解析/套壳/云播源：测速常「假绿」，降权
      if (name.contains('解析') ||
          name.contains('parse') ||
          name.contains('iframe') ||
          name.contains('jump') ||
          name.contains('yun') ||
          name.contains('云播') ||
          name.contains('json')) {
        sc -= 45;
      }
      // 无真实后缀的壳地址再降
      if (!joined.contains('.m3u8') &&
          !joined.contains('.mp4') &&
          !joined.contains('.ts') &&
          (joined.contains('url=') || name.contains('yun'))) {
        sc -= 40;
      }
      // 集数更全略加分（封顶）
      sc += s.episodes.length.clamp(0, 30);
      return sc;
    }

    sources.sort((a, b) => scoreSource(b).compareTo(scoreSource(a)));
    return (sources: sources, defaultEpisodes: sources.first.episodes);
  }

  static List<MoviePlayEpisode> _parseEpisodeGroup(String group) {
    final episodes = <MoviePlayEpisode>[];
    for (final part in group.split('#')) {
      final chunk = part.trim();
      if (chunk.isEmpty) continue;
      final i = chunk.indexOf(r'$');
      if (i < 0) {
        if (chunk.startsWith('http')) {
          episodes.add(MoviePlayEpisode(
            name: '第${episodes.length + 1}集',
            url: chunk,
          ));
        }
        continue;
      }
      final name = chunk.substring(0, i).trim();
      final epUrl = chunk.substring(i + 1).trim();
      if (epUrl.isEmpty || !epUrl.startsWith('http')) continue;
      episodes.add(MoviePlayEpisode(
        name: name.isEmpty ? '第${episodes.length + 1}集' : name,
        url: epUrl,
      ));
    }
    return episodes;
  }

  static String _stripHtml(String raw) {
    return raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 相对路径封面补全为绝对 URL（文章 / 点播图常见 `/upload/...`）
  static String _absoluteCmsUrl(String raw) {
    final p = raw.trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('//')) return 'https:$p';
    final base = ApiConfig.macCmsBase.replaceAll(RegExp(r'/+$'), '');
    if (p.startsWith('/')) return '$base$p';
    return '$base/$p';
  }

  /// 封面占位统一中性灰，避免加载失败时出现彩色块
  static Color _colorForId(String id) => const Color(0xFFE8E9ED);

  // ───────── 站内评论 ─────────

  Uri _cmsUri(String path, [Map<String, String>? query]) {
    return Uri.parse('${ApiConfig.macCmsBase}$path').replace(
      queryParameters: query,
    );
  }

  void _captureCookies(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    // 只保留 name=value
    final parts = <String>[];
    for (final seg in raw.split(',')) {
      final nv = seg.split(';').first.trim();
      if (nv.contains('=')) parts.add(nv);
    }
    if (parts.isEmpty) return;
    final map = <String, String>{};
    if (_commentCookie != null) {
      for (final p in _commentCookie!.split('; ')) {
        final i = p.indexOf('=');
        if (i > 0) map[p.substring(0, i)] = p.substring(i + 1);
      }
    }
    for (final p in parts) {
      final i = p.indexOf('=');
      if (i > 0) map[p.substring(0, i)] = p.substring(i + 1);
    }
    _commentCookie = map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Map<String, String> get _commentHeaders => {
        'Accept': 'text/html,application/json,*/*',
        'User-Agent': _ua,
        'Referer': '${ApiConfig.macCmsBase}/',
        'X-Requested-With': 'XMLHttpRequest',
        'Cookie': ?_commentCookie,
      };

  /// 拉取评论：严格按影片 ID，避免主题 ajax / 片名模糊匹配串台
  Future<List<MovieComment>> fetchComments(
    String vodId, {
    String? title,
    int page = 1,
  }) async {
    final id = vodId.trim();
    if (id.isEmpty || !RegExp(r'^\d+$').hasMatch(id)) {
      // 无可用数字 id 时不按片名猜，防止串到别的片
      return const [];
    }

    // 1) 面板按 comment_rid 精确过滤（主题 ajax 常串台）
    try {
      final rows = await HuihuoPanelApi.fetchCommentRows(
        rid: id,
        name: '', // 禁止带片名，面板 OR 条件会串片
        mid: 1,
        page: page,
      ).timeout(const Duration(seconds: 10));
      if (rows.isNotEmpty) {
        return [
          for (final c in _parseCommentJsonList(rows)) _withQqAvatar(c),
        ];
      }
    } catch (e) {
      debugPrint('panel comment_list: $e');
    }

    // 2) CMS ajax / 详情页（仍只用精确 rid）
    try {
      final ajax = await _fetchCommentsCmsAjax(id, page: page);
      if (ajax.isNotEmpty) {
        return [for (final c in ajax) _withQqAvatar(c)];
      }
    } catch (e) {
      debugPrint('cms comment ajax $id: $e');
    }
    try {
      final pageList = await _fetchCommentsFromDetailHtml(id);
      if (pageList.isNotEmpty) {
        return [for (final c in pageList) _withQqAvatar(c)];
      }
    } catch (e) {
      debugPrint('cms comment detail $id: $e');
    }
    return const [];
  }

  static MovieComment _withQqAvatar(MovieComment c) {
    if ((c.avatarUrl ?? '').trim().isNotEmpty) return c;
    final qq = QqAvatar.urlFromCandidates([
      c.userName,
      c.id,
    ]);
    if (qq == null) return c;
    return MovieComment(
      id: c.id,
      userName: c.userName,
      content: c.content,
      timeText: c.timeText,
      timeMs: c.timeMs,
      avatarUrl: qq,
      up: c.up,
      down: c.down,
      replyCount: c.replyCount,
      vodId: c.vodId,
      vodName: c.vodName,
      vodPic: c.vodPic,
    );
  }

  Future<List<MovieComment>> _fetchCommentsCmsAjax(
    String rid, {
    int page = 1,
  }) async {
    final id = rid.trim();
    if (id.isEmpty) return const [];
    final paths = <String>[
      '/index.php/comment/ajax.html',
      '/index.php/comment/ajax',
      '/index.php/ajax/comment.html',
      '/index.php/ajax/comment',
    ];
    for (final path in paths) {
      try {
        final res = await _client
            .get(
              _cmsUri(path, {
                'rid': id,
                'mid': '1',
                'page': '$page',
                'limit': '40',
              }),
              headers: _commentHeaders,
            )
            .timeout(const Duration(seconds: 10));
        _captureCookies(res);
        if (res.statusCode < 200 || res.statusCode >= 300) continue;
        final body = utf8.decode(res.bodyBytes);
        final fromJson = _tryParseCommentJsonBody(body);
        if (fromJson.isNotEmpty) return fromJson;
        final html = _unwrapCommentHtml(body);
        final parsed = _parseCommentHtml(html);
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('comment ajax $path: $e');
      }
    }
    return const [];
  }

  Future<List<MovieComment>> _fetchCommentsFromDetailHtml(String rid) async {
    final id = rid.trim();
    if (id.isEmpty) return const [];
    final uris = <Uri>[
      _cmsUri('/index.php/vod/detail/id/$id.html'),
      _cmsUri('/index.php/vod/detail/id/$id'),
      Uri.parse('${ApiConfig.macCmsBase}/voddetail/$id.html'),
    ];
    for (final uri in uris) {
      try {
        final res = await _client
            .get(uri, headers: {
              ..._commentHeaders,
              'Accept': 'text/html,*/*',
            })
            .timeout(const Duration(seconds: 12));
        _captureCookies(res);
        if (res.statusCode < 200 || res.statusCode >= 300) continue;
        final html = utf8.decode(res.bodyBytes);
        final parsed = _parseCommentHtml(html);
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('comment detail $uri: $e');
      }
    }
    return const [];
  }

  List<MovieComment> _tryParseCommentJsonBody(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const [];
    try {
      final decoded = jsonDecode(t);
      if (decoded is List) {
        return _parseCommentJsonList(decoded);
      }
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final list = map['list'] ??
            map['data'] ??
            map['comments'] ??
            (map['data'] is Map ? (map['data'] as Map)['list'] : null);
        if (list is List) return _parseCommentJsonList(list);
        for (final key in ['html', 'content', 'msg', 'data']) {
          final v = map[key];
          if (v is String && v.contains('<')) {
            final p = _parseCommentHtml(_unwrapCommentHtml(v));
            if (p.isNotEmpty) return p;
          }
        }
      }
    } catch (_) {}
    return const [];
  }

  /// 我的评论：面板 → CMS → 本机备份（面板 500/未部署时仍能显示）
  Future<List<MovieComment>> fetchMyComments({
    required int userId,
    int page = 1,
    String userName = '',
    String nickName = '',
  }) async {
    if (userId <= 0 &&
        userName.trim().isEmpty &&
        nickName.trim().isEmpty &&
        (_commentCookie == null || _commentCookie!.isEmpty)) {
      return LocalMyCommentsStore.list(userId: userId);
    }

    final aliases = <String>{
      if (userName.trim().isNotEmpty) userName.trim(),
      if (nickName.trim().isNotEmpty) nickName.trim(),
      if (userId > 0) '$userId',
      if (userId > 0) '用户$userId',
    };

    final remote = <MovieComment>[];

    // 1) 面板
    try {
      final rows = await HuihuoPanelApi.fetchMyCommentRows(
        userId: userId,
        page: page,
        userName: userName,
        nickName: nickName,
        aliases: aliases.toList(),
      ).timeout(const Duration(seconds: 12));
      remote.addAll([
        for (final c in _parseCommentJsonList(rows)) _withQqAvatar(c),
      ]);
    } catch (e) {
      debugPrint('panel comment_mine: $e');
    }

    // 2) CMS 会员中心（面板空/失败时）
    if (remote.isEmpty) {
      final paths = <(String, Map<String, String>)>[
        ('/index.php/user/comment.html', {'page': '$page'}),
        ('/index.php/user/comments.html', {'page': '$page'}),
        ('/index.php/user/ajax_data', {'ac': 'comment', 'page': '$page'}),
        ('/index.php/user/ajax_comment', {'page': '$page'}),
      ];

      for (final (path, q) in paths) {
        try {
          final res = await _client
              .get(
                _cmsUri(path, q),
                headers: {
                  ..._commentHeaders,
                  'Accept': 'text/html,application/json,*/*',
                  'Referer':
                      '${ApiConfig.macCmsBase}/index.php/user/index.html',
                },
              )
              .timeout(const Duration(seconds: 12));
          _captureCookies(res);
          if (res.statusCode < 200 || res.statusCode >= 300) continue;
          final body = utf8.decode(res.bodyBytes);
          if (body.contains('login') &&
              body.contains('password') &&
              !body.contains('comment') &&
              !body.contains('评论')) {
            continue;
          }
          final fromJson = _tryParseCommentJsonBody(body);
          if (fromJson.isNotEmpty) {
            remote.addAll([for (final c in fromJson) _withQqAvatar(c)]);
            break;
          }
          final fromUser = _parseUserCommentHtml(body);
          if (fromUser.isNotEmpty) {
            remote.addAll([for (final c in fromUser) _withQqAvatar(c)]);
            break;
          }
        } catch (e) {
          debugPrint('my comments $path: $e');
        }
      }
    }

    // 3) 别名再试面板
    if (remote.isEmpty) {
      for (final alias in aliases) {
        if (alias == userName.trim() || alias == nickName.trim()) continue;
        try {
          final rows = await HuihuoPanelApi.fetchMyCommentRows(
            userId: 0,
            page: page,
            userName: alias,
            nickName: '',
          ).timeout(const Duration(seconds: 8));
          if (rows.isNotEmpty) {
            remote.addAll([
              for (final c in _parseCommentJsonList(rows)) _withQqAvatar(c),
            ]);
            break;
          }
        } catch (_) {}
      }
    }

    // 4) 本机备份合并
    final local = await LocalMyCommentsStore.list(userId: userId);
    if (remote.isNotEmpty && userId > 0) {
      unawaited(
        LocalMyCommentsStore.mergeRemote(remote, ownerUid: userId),
      );
    }

    if (remote.isEmpty) return local;
    if (local.isEmpty) return remote;

    final seen = <String>{};
    final merged = <MovieComment>[];
    for (final c in [...remote, ...local]) {
      final key = '${c.vodId}|${c.content.trim()}';
      if (key.length < 2 || !seen.add(key)) continue;
      merged.add(c);
    }
    merged.sort((a, b) => b.timeMs.compareTo(a.timeMs));
    return merged;
  }

  /// 会员中心「我的评论」列表
  static List<MovieComment> _parseUserCommentHtml(String html) {
    if (html.trim().isEmpty) return const [];
    final blocks = <String>[];
    final liRe = RegExp(
      r'''<li\b[^>]*class=["'][^"']*(?:comment|comm|cmt)[^"']*["'][^>]*>([\s\S]*?)</li>''',
      caseSensitive: false,
    );
    blocks.addAll([for (final m in liRe.allMatches(html)) m.group(1) ?? '']);
    if (blocks.isEmpty) {
      final trRe = RegExp(
        r'''<tr\b[^>]*>([\s\S]*?)</tr>''',
        caseSensitive: false,
      );
      for (final m in trRe.allMatches(html)) {
        final b = m.group(1) ?? '';
        if (b.contains('/vod/detail') ||
            b.contains('comment') ||
            RegExp(r'第\s*\d+\s*集').hasMatch(b)) {
          blocks.add(b);
        }
      }
    }
    if (blocks.isEmpty) {
      final cardRe = RegExp(
        r'''<(?:div|li|tr)\b[^>]*>[\s\S]*?/vod/detail/[\s\S]*?</(?:div|li|tr)>''',
        caseSensitive: false,
      );
      blocks.addAll([for (final m in cardRe.allMatches(html)) m.group(0) ?? '']);
    }

    final out = <MovieComment>[];
    var i = 0;
    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final content = _cleanCommentBody(
        _stripHtml(
          _matchGroup(block, [
                r'''<p\b[^>]*>([\s\S]*?)</p>''',
                r'''class=["'][^"']*content[^"']*["'][^>]*>([\s\S]*?)</''',
                r'''class=["'][^"']*text[^"']*["'][^>]*>([\s\S]*?)</''',
              ]) ??
              '',
        ),
      );
      var body = content;
      if (body.isEmpty) {
        body = _cleanCommentBody(_stripHtml(block));
      }
      if (body.length < 2) continue;

      final vodId = _matchGroup(block, [
            r'''/vod/detail/id/(\d+)''',
            r'''voddetail/(\d+)''',
            r'''data-id=["'](\d+)["']''',
          ]) ??
          '';
      final vodName = _stripHtml(
        _matchGroup(block, [
              r'''/vod/detail/[^"']*["'][^>]*>([^<]{1,40})</a>''',
              r'''title=["']([^"']+)["']''',
            ]) ??
            '',
      ).trim();
      final vodPic = _matchGroup(block, [
            r'''<img[^>]+src=["']([^"']+)["']''',
          ]) ??
          '';
      final time = _stripHtml(
        _matchGroup(block, [
              r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:\s+\d{1,2}:\d{2})?)',
              r'(\d+\s*(?:秒|分钟|小时|天)前)',
            ]) ??
            '',
      );

      if (vodName.isNotEmpty) {
        body = body.replaceFirst(vodName, '').trim();
      }
      if (body.isEmpty) continue;

      out.add(
        MovieComment(
          id: 'mine_${vodId}_${i++}',
          userName: '我',
          content: body,
          timeText: time,
          timeMs: _parseCommentTimeMs(time),
          avatarUrl: null,
          vodId: vodId,
          vodName: vodName,
          vodPic: () {
            final p = vodPic.trim();
            if (p.isEmpty) return '';
            return _resolveCommentAvatar(p) ?? p;
          }(),
        ),
      );
    }
    return out;
  }

  static bool _isDefaultCommentAvatar(String p) {
    final low = p.toLowerCase();
    // 仅过滤明确占位图，勿误伤 /user/xxx/avatar 等真实路径
    return low.contains('duface') ||
        low.contains('touxiang.png') ||
        low.contains('nopic') ||
        low.contains('noavatar') ||
        low.endsWith('/avatar.png') ||
        low.endsWith('/avatar.gif') ||
        low.contains('default_avatar') ||
        low.contains('default-avatar') ||
        (low.contains('static') &&
            low.contains('avatar') &&
            low.contains('default'));
  }

  static String? _resolveCommentAvatar(dynamic raw) {
    final p = '$raw'.trim();
    if (p.isEmpty || p == 'null') return null;
    if (_isDefaultCommentAvatar(p)) return null;
    final url = () {
      if (p.startsWith('http://') || p.startsWith('https://')) return p;
      if (p.startsWith('//')) return 'https:$p';
      if (p.startsWith('/')) return '${ApiConfig.macCmsBase}$p';
      return '${ApiConfig.macCmsBase}/$p';
    }();
    if (_isDefaultCommentAvatar(url)) return null;
    return url;
  }

  /// 优先昵称，避免把登录账号/数字 ID 当成展示名
  static String _commentDisplayName(Map<String, dynamic> m) {
    final candidates = <String>[
      '${m['display_name'] ?? ''}',
      '${m['user_nick_name'] ?? ''}',
      '${m['nick_name'] ?? ''}',
      '${m['nickname'] ?? ''}',
      '${m['user_name'] ?? ''}',
      '${m['name'] ?? ''}',
      '${m['comment_name'] ?? ''}',
    ];
    String? numericFallback;
    for (final raw in candidates) {
      final name = raw.trim();
      if (name.isEmpty || name == 'null') continue;
      if (RegExp(r'^\d+$').hasMatch(name)) {
        numericFallback ??= name;
        continue;
      }
      return name;
    }
    if (numericFallback != null) return '用户$numericFallback';
    return '访客';
  }

  static int _toInt(dynamic raw, [int fallback = 0]) {
    if (raw == null) return fallback;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw'.trim()) ?? fallback;
  }

  static List<MovieComment> _parseCommentJsonList(List<dynamic> list) {
    final out = <MovieComment>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final content =
          _cleanCommentBody('${m['comment_content'] ?? m['content'] ?? ''}'.trim());
      if (content.isEmpty) continue;
      final id = '${m['comment_id'] ?? m['id'] ?? out.length}'.trim();
      final name = _commentDisplayName(m);
      final timeRaw = m['comment_time'] ?? m['time'] ?? '';
      final timeMs = toEpochMs(timeRaw);
      final portrait = _resolveCommentAvatar(
            m['user_portrait'] ?? m['avatar'] ?? m['portrait'] ?? '',
          ) ??
          QqAvatar.urlFromCandidates([
            '${m['user_login'] ?? ''}',
            '${m['user_name'] ?? ''}',
            '${m['comment_name'] ?? ''}',
            name,
            '${m['user_id'] ?? ''}',
            '${m['user_qq'] ?? m['qq'] ?? ''}',
          ]);
      out.add(
        MovieComment(
          id: id.isEmpty ? '${out.length}' : id,
          userName: name,
          content: content,
          timeText: '$timeRaw',
          timeMs: timeMs,
          avatarUrl: portrait,
          up: _toInt(m['comment_up'] ?? m['up']),
          down: _toInt(m['comment_down'] ?? m['down']),
          replyCount: _toInt(m['comment_reply'] ?? m['reply']),
          vodId: '${m['comment_rid'] ?? m['vod_id'] ?? m['rid'] ?? ''}'.trim(),
          vodName: '${m['vod_name'] ?? ''}'.trim(),
          vodPic: () {
            final p = '${m['vod_pic'] ?? m['pic'] ?? ''}'.trim();
            if (p.isEmpty) return '';
            if (p.startsWith('http://') || p.startsWith('https://')) return p;
            if (p.startsWith('//')) return 'https:$p';
            if (p.startsWith('/')) return '${ApiConfig.macCmsBase}$p';
            return '${ApiConfig.macCmsBase}/$p';
          }(),
        ),
      );
    }
    return out;
  }

  /// 评论验证码图片
  Future<Uint8List> fetchCommentCaptcha() async {
    final uri = _cmsUri('/index.php/verify/index.html', {
      'r': '${DateTime.now().millisecondsSinceEpoch}',
    });
    final res = await _client
        .get(uri, headers: _commentHeaders)
        .timeout(const Duration(seconds: 8));
    _captureCookies(res);
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw MacCmsException('验证码获取失败');
    }
    return res.bodyBytes;
  }

  /// 发表评论：仅走官方 saveData，避免多地址轮询卡死
  Future<void> postComment({
    required String vodId,
    required String content,
    required String verify,
  }) async {
    final id = vodId.trim();
    final text = content.trim();
    final code = verify.trim();
    if (id.isEmpty) throw MacCmsException('无效影片');
    if (text.isEmpty) throw MacCmsException('请输入评论内容');
    if (code.isEmpty) throw MacCmsException('请输入验证码');

    late http.Response res;
    try {
      res = await _client
          .post(
            _cmsUri('/index.php/comment/saveData'),
            headers: {
              ..._commentHeaders,
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'Accept': 'application/json, text/javascript, */*; q=0.01',
            },
            body: {
              'comment_pid': '0',
              'comment_content': text,
              'verify': code,
              'comment_mid': '1',
              'comment_rid': id,
            },
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw MacCmsException('发表超时，请检查网络后重试');
    }
    _captureCookies(res);
    final raw = utf8.decode(res.bodyBytes).trim();
    if (raw.isEmpty) return;

    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final c = (j['code'] as num?)?.toInt() ?? -1;
        final msg = '${j['msg'] ?? j['message'] ?? ''}'.trim();
        if (c == 1) return;
        throw MacCmsException(msg.isEmpty ? '发表失败' : msg, code: c);
      }
    } catch (e) {
      if (e is MacCmsException) rethrow;
    }

    if (raw.contains('成功')) return;
    throw MacCmsException(_commentPostMessage(raw) ?? '发表失败');
  }

  /// 评论赞成/反对 mid=4（评论模块）
  Future<int> diggComment({
    required String commentId,
    required String type, // up | down
  }) async {
    final id = commentId.trim();
    final t = type.trim().toLowerCase();
    if (id.isEmpty) throw MacCmsException('无效评论');
    if (t != 'up' && t != 'down') throw MacCmsException('无效操作');

    final res = await _client
        .get(
          _cmsUri('/index.php/ajax/digg.html', {
            'mid': '4',
            'id': id,
            'type': t,
          }),
          headers: _commentHeaders,
        )
        .timeout(const Duration(seconds: 10));
    _captureCookies(res);
    final raw = utf8.decode(res.bodyBytes).trim();
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final code = int.tryParse('${j['code']}') ?? -1;
        final msg = '${j['msg'] ?? j['message'] ?? ''}'.trim();
        if (code == 1) {
          final data = j['data'];
          if (data is num) return data.toInt();
          return int.tryParse('$data') ?? 0;
        }
        throw MacCmsException(msg.isEmpty ? '操作失败' : msg, code: code);
      }
    } catch (e) {
      if (e is MacCmsException) rethrow;
    }
    if (raw.contains('成功') || raw.contains('感谢')) return 0;
    throw MacCmsException(_commentPostMessage(raw) ?? '操作失败');
  }

  /// 播放报错 → CMS 留言本（与模板 MAC.Gbook.Report 同源）
  /// POST `/index.php/gbook/saveData`
  Future<void> reportPlayError({
    required String vodId,
    required String content,
    String verify = '',
  }) =>
      submitGbook(
        rid: vodId,
        content: content,
        verify: verify,
      );

  /// 求片 / 通用留言
  Future<void> submitGbook({
    required String content,
    String rid = '0',
    String verify = '',
  }) async {
    final text = content.trim();
    if (text.isEmpty) throw MacCmsException('请填写内容');

    final body = <String, String>{
      'gbook_rid': rid.trim().isEmpty ? '0' : rid.trim(),
      'gbook_content': text,
    };
    final code = verify.trim();
    if (code.isNotEmpty) {
      body['verify'] = code;
    }

    late http.Response res;
    try {
      res = await _client
          .post(
            _cmsUri('/index.php/gbook/saveData'),
            headers: {
              ..._commentHeaders,
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'Accept': 'application/json, text/javascript, */*; q=0.01',
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': '${ApiConfig.macCmsBase}/',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      throw MacCmsException('提交超时，请检查网络后重试');
    }
    _captureCookies(res);
    final raw = utf8.decode(res.bodyBytes).trim();
    if (raw.isEmpty) return;

    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final c = (j['code'] as num?)?.toInt() ?? -1;
        final msg = '${j['msg'] ?? j['message'] ?? ''}'.trim();
        if (c == 1) return;
        throw MacCmsException(
          msg.isEmpty ? '提交失败' : msg,
          code: c,
        );
      }
    } catch (e) {
      if (e is MacCmsException) rethrow;
    }

    if (raw.contains('成功') || raw.contains('感谢')) return;
    throw MacCmsException(_gbookPostMessage(raw) ?? '提交失败');
  }

  /// 搜索无结果 → 求片
  Future<void> requestMissingVod({
    required String keyword,
    String verify = '',
  }) {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      return Future.error(MacCmsException('请输入片名'));
    }
    return submitGbook(
      content: '【App求片】\n关键词：$kw\n站内暂无资源，请尽快收录，谢谢！',
      rid: '0',
      verify: verify,
    );
  }

  /// 留言/报错验证码（与评论共用 verify 入口，依赖同一 Cookie 会话）
  Future<Uint8List> fetchGbookCaptcha() => fetchCommentCaptcha();

  static String? _gbookPostMessage(String raw) {
    try {
      final j = jsonDecode(raw.trim());
      if (j is Map) {
        final msg = '${j['msg'] ?? j['message'] ?? ''}'.trim();
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    if (raw.contains('验证码')) return '验证码错误或需填写验证码';
    if (raw.contains('登录')) return '请先登录后再提交';
    if (raw.contains('关闭')) return '站点已关闭留言功能';
    return null;
  }

  static String _unwrapCommentHtml(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    if (t.startsWith('"') || t.startsWith("'")) {
      try {
        final decoded = jsonDecode(t);
        if (decoded is String) return decoded;
      } catch (_) {}
    }
    return t;
  }

  static String? _commentPostMessage(String raw) {
    try {
      final j = jsonDecode(raw.trim());
      if (j is Map) {
        final msg = '${j['msg'] ?? j['message'] ?? ''}'.trim();
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    if (raw.contains('验证码')) return '验证码错误';
    if (raw.contains('登录')) return '请先登录后再评论';
    return null;
  }

  /// myui / styu 主题评论块（div.styu-message__list，无 li）
  static List<MovieComment> _parseStyuCommentBlocks(String html) {
    if (!html.contains('styu-message__list') &&
        !html.contains('myui-comment') &&
        !html.contains('class="face"') &&
        !html.contains("class='face'")) {
      return const [];
    }

    final chunks = html.split(
      RegExp(
        r'''<div[^>]*class=["'][^"']*styu-message__list[^"']*["'][^>]*>''',
        caseSensitive: false,
      ),
    );
    if (chunks.length < 2) return const [];

    final out = <MovieComment>[];
    for (var i = 1; i < chunks.length; i++) {
      final block = chunks[i];
      if (block.contains('name="comment_content"') ||
          block.contains('comment_form')) {
        continue;
      }
      final avatar = _matchGroup(block, [
            r'''class=["']face["'][^>]*src=["']([^"']+)["']''',
            r'''src=["']([^"']+)["'][^>]*class=["']face["']''',
            r'''<img[^>]+src=["']([^"']+)["']''',
          ]) ??
          '';
      final nameRaw = _stripHtml(
        _matchGroup(block, [
              r'''<h5[^>]*class=["'][^"']*name[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([^<]+)</a>''',
              r'''class=["'][^"']*font-bold[^"']*["'][^>]*>([^<]+)</a>''',
              r'''<h5[^>]*>[\s\S]*?<a[^>]*>([^<]+)</a>''',
            ]) ??
            '',
      ).trim();
      final name = () {
        if (nameRaw.isEmpty) return '访客';
        if (RegExp(r'^\d+$').hasMatch(nameRaw)) return '用户$nameRaw';
        return nameRaw;
      }();
      final time = _stripHtml(
        _matchGroup(block, [
              r'''class=["'][^"']*text-muted[^"']*pull-right[^"']*["'][^>]*>([^<]+)</span>''',
              r'''class=["'][^"']*pull-right[^"']*text-muted[^"']*["'][^>]*>([^<]+)</span>''',
              r'(\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?)',
            ]) ??
            '',
      ).trim();
      final content = _cleanCommentBody(
        _stripHtml(
          _matchGroup(block, [
                r'''<p[^>]*class=["'][^"']*content[^"']*["'][^>]*>([\s\S]*?)</p>''',
                r'''class=["']content["'][^>]*>([\s\S]*?)</p>''',
              ]) ??
              '',
        ),
      );
      if (content.isEmpty) continue;
      final commentId = _matchGroup(block, [
            r'''data-id=["'](\d+)["'][^>]*data-type=["']up["']''',
            r'''data-type=["']up["'][^>]*data-id=["'](\d+)["']''',
            r'''my_comment_report[^>]*data-id=["'](\d+)["']''',
            r'''data-id=["'](\d+)["']''',
          ]) ??
          '${out.length}';
      final up = int.tryParse(
            _matchGroup(block, [
                  r'''data-type=["']up["'][\s\S]*?digg_num[^>]*>(\d+)''',
                ]) ??
                '0',
          ) ??
          0;
      final down = int.tryParse(
            _matchGroup(block, [
                  r'''data-type=["']down["'][\s\S]*?digg_num[^>]*>(\d+)''',
                ]) ??
                '0',
          ) ??
          0;

      out.add(
        MovieComment(
          id: commentId,
          userName: name,
          content: content,
          timeText: time,
          timeMs: _parseCommentTimeMs(time),
          avatarUrl: _resolveCommentAvatar(avatar) ??
              QqAvatar.urlFromAccount(name),
          up: up,
          down: down,
        ),
      );
    }
    return out;
  }

  static List<MovieComment> _parseCommentHtml(String html) {
    // 新主题：ul.part_rows > li.comm_each；旧主题：fed-comm-list 等
    // myui / styu：div.styu-message__list（无 li）
    // 注意：不可用 </div> 截断列表，li 内有多层 div 会提前结束
    var work = html;
    // 去掉发表表单，避免误解析
    work = work.replaceAll(
      RegExp(
        r'''<(?:div|form)[^>]*class=["'][^"']*(?:part_rows_fa|comment_form|cmt_form|fed-comm-form|myui-comment__form)[^"']*["'][^>]*>[\s\S]*?</(?:div|form)>''',
        caseSensitive: false,
      ),
      '',
    );

    // —— myui / styu 主题：div.styu-message__list ——
    final styuParsed = _parseStyuCommentBlocks(work);
    if (styuParsed.isNotEmpty) return styuParsed;

    final itemRe = RegExp(
      r'''<li\b[^>]*class=["'][^"']*(?:comm_each|cmt-thread|comm-item|comment-item|fed-comm-item)[^"']*["'][^>]*>([\s\S]*?)</li>''',
      caseSensitive: false,
    );
    var matches = itemRe.allMatches(work).toList();
    if (matches.isEmpty) {
      // 兜底：只在评论 ul 内扫 li
      final listM = RegExp(
        r'''<ul[^>]*class=["'][^"']*(?:part_rows(?!_fa)|fed-comm-list|mac_comment_list|comment_list|cmt-list)[^"']*["'][^>]*>([\s\S]*?)</ul>''',
        caseSensitive: false,
      ).firstMatch(work);
      if (listM != null) {
        matches = RegExp(
          r'<li\b[^>]*>([\s\S]*?)</li>',
          caseSensitive: false,
        ).allMatches(listM.group(1) ?? '').toList();
      }
    }
    if (matches.isEmpty) {
      if (html.contains('还没有人评论') || html.contains('暂无评论')) {
        return const [];
      }
      return const [];
    }

    final list = <MovieComment>[];
    var i = 0;
    for (final m in matches) {
      final block = m.group(1) ?? '';
      if (block.contains('fed-comm-form') ||
          block.contains('cmt_form') ||
          block.contains('comment_form') ||
          block.contains('name="comment_content"') ||
          block.contains("name='comment_content'") ||
          block.contains('还没有人评论') ||
          block.contains('name="verify"')) {
        continue;
      }
      final text = _stripHtml(block);
      if (text.isEmpty || text.length < 2) continue;

      final commentId = _matchGroup(
            block,
            [
              r'''data-id=["'](\d+)["']''',
              r'''comment[_-]?id=["'](\d+)["']''',
              r'''id=["']comm(?:ent)?[_-]?(\d+)["']''',
            ],
          ) ??
          '${i++}';

      var name = _matchGroup(
            block,
            [
              r'cmt-name[^>]*>([^<]+)',
              r'''data-user-name=["']([^"']+)["']''',
              r'fed-user-name[^>]*>([^<]+)',
              r'''class=["'][^"']*user-name[^"']*["'][^>]*>([^<]+)''',
              r'<strong[^>]*>([^<]{1,32})</strong>',
            ],
          ) ??
          '';
      name = _stripHtml(name).trim();
      if (name.isEmpty ||
          name.contains('验证') ||
          name == '发表' ||
          name == '发布' ||
          name == '赞成' ||
          name == '反对') {
        name = '访客';
      }

      final time = _matchGroup(
            block,
            [
              r'''data-ts=["'](\d{9,13})["']''',
              r'''data-time=["'](\d{9,13})["']''',
              r'''datetime=["']([^"']+)["']''',
              r'cmt-time[^>]*>([^<]+)',
              r'comment-time[^>]*>([^<]+)',
              r'(\d{4}[-/年]\d{1,2}[-/月]\d{1,2}[日]?(?:\s+\d{1,2}:\d{2})?)',
              r'(\d+\s*(?:秒|分钟|小时|天)前)',
            ],
          ) ??
          '';

      var content = _matchGroup(
            block,
            [
              r'cmt-text[^>]*>([\s\S]*?)</(?:div|p)',
              r'comm_content[^>]*>([\s\S]*?)</(?:div|p)',
              r'fed-comm-cont[^>]*>([\s\S]*?)</(?:p|div)',
              r'''class=["'][^"']*comm(?:ent)?[_-]?cont[^"']*["'][^>]*>([\s\S]*?)</''',
              r'<p\b[^>]*>([\s\S]*?)</p>',
            ],
          ) ??
          '';
      content = _cleanCommentBody(_stripHtml(content));
      if (content.isEmpty) {
        content = _cleanCommentBody(
          text
              .replaceFirst(name, '')
              .replaceFirst(_stripHtml(time), '')
              .trim(),
        );
      }
      if (content.isEmpty) continue;

      final avatar = _matchGroup(block, [
        r'''class=["'][^"']*face[^"']*["'][^>]*src=["']([^"']+)["']''',
        r'''src=["']([^"']+)["'][^>]*class=["'][^"']*face[^"']*["']''',
        r'''class=["'][^"']*avatar[^"']*["'][^>]*src=["']([^"']+)["']''',
        r'''src=["']([^"']+)["'][^>]*class=["'][^"']*avatar[^"']*["']''',
        r'''<img[^>]+src=["']([^"']+(?:upload|user|avatar|portrait)[^"']*)["']''',
        r'''<img[^>]+src=["']([^"']+)["']''',
      ]);

      final plain = _stripHtml(block);
      final up = int.tryParse(
            _matchGroup(block, [
                  r'''data-type=["']up["'][^>]*>[\s\S]*?digg_num[^>]*>(\d+)''',
                  r'''data-type=["']up["'][^>]*>[\s\S]*?<em[^>]*>(\d+)''',
                  r'''class=["'][^"']*digg_num[^"']*["'][^>]*>(\d+)''',
                  r'赞成\s*[\(（]?\s*(\d+)',
                  r'支持\s*[\(（]?\s*(\d+)',
                ]) ??
                _matchGroup(plain, [
                  r'赞成\s*[\(（]?\s*(\d+)',
                  r'支持\s*[\(（]?\s*(\d+)',
                ]) ??
                '0',
          ) ??
          0;
      final down = int.tryParse(
            _matchGroup(block, [
                  r'''data-type=["']down["'][^>]*>[\s\S]*?digg_num[^>]*>(\d+)''',
                  r'''data-type=["']down["'][^>]*>[\s\S]*?<em[^>]*>(\d+)''',
                  r'反对\s*[\(（]?\s*(\d+)',
                ]) ??
                _matchGroup(plain, [r'反对\s*[\(（]?\s*(\d+)']) ??
                '0',
          ) ??
          0;
      final replyCount = int.tryParse(
            _matchGroup(block, [
                  r'回复\s*[\(（]?\s*(\d+)',
                  r'reply[_-]?num[^>]*>(\d+)',
                ]) ??
                _matchGroup(plain, [r'回复\s*[\(（]?\s*(\d+)']) ??
                '0',
          ) ??
          0;

      final timeRaw = _stripHtml(time);
      var timeMs = 0;
      final asNum = int.tryParse(timeRaw);
      if (asNum != null && asNum > 1e8) {
        timeMs = toEpochMs(asNum);
      } else {
        timeMs = _parseCommentTimeMs(timeRaw);
      }

      list.add(
        MovieComment(
          id: commentId,
          userName: name,
          content: content,
          timeText: timeRaw,
          timeMs: timeMs,
          avatarUrl: () {
            final fromImg = avatar == null || avatar.isEmpty
                ? null
                : _resolveCommentAvatar(avatar);
            return fromImg ?? QqAvatar.urlFromAccount(name);
          }(),
          up: up,
          down: down,
          replyCount: replyCount,
        ),
      );
    }

    // 模板 HTML 常把同一条评论解析两次（嵌套 li / 列表重复）
    final seenId = <String>{};
    final seenBody = <String>{};
    final deduped = <MovieComment>[];
    for (final c in list) {
      final id = c.id.trim();
      final body = '${c.userName}|${c.content}'.trim();
      if (id.isNotEmpty && !seenId.add(id)) continue;
      if (!seenBody.add(body)) continue;
      deduped.add(c);
    }
    return deduped;
  }

  static int _parseCommentTimeMs(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final m = RegExp(
      r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})[日]?(?:\s+(\d{1,2}):(\d{2}))?',
    ).firstMatch(t);
    if (m != null) {
      final dt = DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.tryParse(m.group(4) ?? '') ?? 0,
        int.tryParse(m.group(5) ?? '') ?? 0,
      );
      return dt.millisecondsSinceEpoch;
    }
    final parsed = DateTime.tryParse(t.replaceAll('/', '-'));
    return parsed?.millisecondsSinceEpoch ?? 0;
  }

  /// 去掉 CMS 评论 HTML 里拼进来的「举报/支持/反对/回复」操作文案
  static String _cleanCommentBody(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(
      RegExp(
        r'(?:^|[\s\|·•]*)(?:举报|支持|赞成|反对|回复)\s*[\(（]?\s*\d*\s*[\)）]?',
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'[\s\|·•]+'), ' ').trim();
    return s;
  }

  static String? _matchGroup(String src, List<String> patterns) {
    for (final p in patterns) {
      final m = RegExp(p, caseSensitive: false).firstMatch(src);
      if (m != null) {
        final g = m.group(1)?.trim();
        if (g != null && g.isNotEmpty) return g;
      }
    }
    return null;
  }
}

class _ScoredVod {
  const _ScoredVod({required this.score, required this.raw});
  final int score;
  final Map<String, dynamic> raw;
}

class MacCmsException implements Exception {
  MacCmsException(this.message, {this.code = -1});
  final String message;
  final int code;

  @override
  String toString() => message;
}

/// CMS 文章（provide/art）
class CmsArticle {
  const CmsArticle({
    required this.id,
    required this.title,
    this.subTitle = '',
    this.content = '',
    this.contentHtml = '',
    this.coverUrl = '',
    this.timeText = '',
    this.author = '',
    this.typeName = '',
    this.typeId = 0,
    this.from = '',
    this.remarks = '',
    this.hits = 0,
    this.tag = '',
  });

  final String id;
  final String title;
  final String subTitle;
  /// 纯文本正文
  final String content;
  /// 原始 HTML 正文
  final String contentHtml;
  final String coverUrl;
  final String timeText;
  final String author;
  final String typeName;
  final int typeId;
  final String from;
  final String remarks;
  final int hits;
  final String tag;

  bool get hasBody =>
      content.trim().isNotEmpty || contentHtml.trim().isNotEmpty;

  CmsArticle copyWith({
    String? title,
    String? subTitle,
    String? content,
    String? contentHtml,
    String? coverUrl,
    String? timeText,
    String? author,
    String? typeName,
    int? typeId,
    String? from,
    String? remarks,
    int? hits,
    String? tag,
  }) {
    return CmsArticle(
      id: id,
      title: title ?? this.title,
      subTitle: subTitle ?? this.subTitle,
      content: content ?? this.content,
      contentHtml: contentHtml ?? this.contentHtml,
      coverUrl: coverUrl ?? this.coverUrl,
      timeText: timeText ?? this.timeText,
      author: author ?? this.author,
      typeName: typeName ?? this.typeName,
      typeId: typeId ?? this.typeId,
      from: from ?? this.from,
      remarks: remarks ?? this.remarks,
      hits: hits ?? this.hits,
      tag: tag ?? this.tag,
    );
  }
}
