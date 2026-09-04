import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_models.dart';

/// 首页热门列表磁盘缓存：冷启动先出缓存，后台再刷新（体感秒开）
abstract final class HomeFeedCache {
  static const _keyPrefix = 'home_feed_v1_';

  static String _key(String tab) => '$_keyPrefix$tab';

  static Future<List<Movie>?> load(String tab) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(tab));
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw);
      if (list is! List) return null;
      final out = <Movie>[];
      for (final e in list) {
        if (e is! Map) continue;
        final m = _movieFromJson(Map<String, dynamic>.from(e));
        if (m != null) out.add(m);
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String tab, List<Movie> movies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = [
        for (final m in movies.take(24)) _movieToJson(m),
      ];
      await prefs.setString(_key(tab), jsonEncode(payload));
    } catch (_) {}
  }

  static Map<String, dynamic> _movieToJson(Movie m) => {
        'id': m.id,
        'title': m.title,
        'subtitle': m.subtitle,
        'year': m.year,
        'score': m.score,
        'scoreCount': m.scoreCount,
        'genres': m.genres,
        'coverColor': m.coverColor.toARGB32(),
        'tagline': m.tagline,
        'synopsis': m.synopsis,
        'coverUrl': m.coverUrl,
        'remarks': m.remarks,
        'slideUrl': m.slideUrl,
        'area': m.area,
        'lang': m.lang,
        'typeId': m.typeId,
        'nameEn': m.nameEn,
        'totalEpisodes': m.totalEpisodes,
      };

  static Movie? _movieFromJson(Map<String, dynamic> j) {
    final id = '${j['id'] ?? ''}'.trim();
    final title = '${j['title'] ?? ''}'.trim();
    if (id.isEmpty || title.isEmpty) return null;
    final colorVal = (j['coverColor'] as num?)?.toInt() ?? 0xFFE8E9ED;
    final genresRaw = j['genres'];
    final genres = genresRaw is List
        ? [for (final g in genresRaw) '$g']
        : const <String>['影视'];
    return Movie(
      id: id,
      title: title,
      subtitle: '${j['subtitle'] ?? ''}',
      year: (j['year'] as num?)?.toInt() ?? DateTime.now().year,
      score: (j['score'] as num?)?.toDouble() ?? 0,
      scoreCount: (j['scoreCount'] as num?)?.toInt() ?? 0,
      genres: genres,
      coverColor: Color(colorVal),
      tagline: '${j['tagline'] ?? title}',
      synopsis: '${j['synopsis'] ?? ''}',
      icon: CupertinoIcons.film,
      coverUrl: (j['coverUrl'] as String?)?.trim().isEmpty == true
          ? null
          : j['coverUrl'] as String?,
      remarks: '${j['remarks'] ?? ''}',
      slideUrl: j['slideUrl'] as String?,
      area: '${j['area'] ?? ''}',
      lang: '${j['lang'] ?? ''}',
      typeId: (j['typeId'] as num?)?.toInt() ?? 0,
      nameEn: '${j['nameEn'] ?? ''}',
      totalEpisodes: (j['totalEpisodes'] as num?)?.toInt() ?? 0,
    );
  }
}
