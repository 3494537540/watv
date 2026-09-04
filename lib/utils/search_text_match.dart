import 'package:lpinyin/lpinyin.dart';

import '../models/movie_models.dart';

/// 搜索/联想：中文、拼音、英文统一匹配
abstract final class SearchTextMatch {
  static String normalize(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// 纯字母数字（拼音 / 英文 / 数字编号）
  static bool isLatinQuery(String query) {
    final q = normalize(query);
    if (q.isEmpty) return false;
    return RegExp(r'^[a-z0-9]+$').hasMatch(q);
  }

  static String pinyinCompact(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    try {
      return PinyinHelper.getPinyinE(t, separator: '', defPinyin: '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
    } catch (_) {
      return '';
    }
  }

  static String pinyinShort(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    try {
      return PinyinHelper.getShortPinyin(t)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
    } catch (_) {
      return '';
    }
  }

  static bool _latinHitsText(String q, String text) {
    if (q.isEmpty || text.isEmpty) return false;
    final n = normalize(text);
    if (n.contains(q)) return true;
    final full = pinyinCompact(text);
    if (full.isNotEmpty && (full.contains(q) || full.startsWith(q))) {
      return true;
    }
    final short = pinyinShort(text);
    if (short.isNotEmpty &&
        (short == q ||
            short.startsWith(q) ||
            q.startsWith(short) ||
            short.contains(q))) {
      return true;
    }
    return false;
  }

  /// 片名 / 副标题 / 英文名 / 拼音全拼 / 首字母
  static bool matchesMovie(Movie m, String query) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    final title = normalize(m.title);
    if (title.contains(q)) return true;
    final sub = normalize(m.subtitle);
    if (sub.isNotEmpty && sub.contains(q)) return true;
    final en = normalize(m.nameEn);
    if (en.isNotEmpty && en.contains(q)) return true;
    final tag = normalize(m.tagline);
    if (tag.isNotEmpty && tag.contains(q)) return true;

    // 拼音 / 英文：扫片名、副标、英文名、tagline
    if (isLatinQuery(query)) {
      if (_latinHitsText(q, m.title)) return true;
      if (m.subtitle.trim().isNotEmpty && _latinHitsText(q, m.subtitle)) {
        return true;
      }
      if (en.isNotEmpty && (en.contains(q) || q.contains(en))) return true;
      if (m.nameEn.trim().isNotEmpty && _latinHitsText(q, m.nameEn)) {
        return true;
      }
      if (m.tagline.trim().isNotEmpty && _latinHitsText(q, m.tagline)) {
        return true;
      }
      // 演员名拼音（热门搜人）
      for (final c in m.cast.take(8)) {
        if (_latinHitsText(q, c.name)) return true;
      }
    }
    return false;
  }

  static int rankMovie(Movie m, String query) {
    final q = normalize(query);
    if (q.isEmpty) return 0;
    final title = normalize(m.title);
    if (title == q) return 100;
    if (title.startsWith(q)) return 90;
    if (title.contains(q)) return 80;
    final en = normalize(m.nameEn);
    if (en == q) return 85;
    if (en.startsWith(q)) return 75;
    if (en.contains(q)) return 65;
    final sub = normalize(m.subtitle);
    if (sub.isNotEmpty && (sub == q || sub.startsWith(q))) return 72;
    if (sub.isNotEmpty && sub.contains(q)) return 58;

    if (isLatinQuery(query)) {
      final full = pinyinCompact(m.title);
      if (full == q) return 95;
      if (full.startsWith(q)) return 88;
      if (full.contains(q)) return 70;
      final short = pinyinShort(m.title);
      if (short == q) return 92;
      if (short.startsWith(q)) return 82;
      if (short.contains(q)) return 62;
      if (en.isNotEmpty) {
        if (en == q) return 85;
        if (en.startsWith(q)) return 75;
      }
    } else {
      final full = pinyinCompact(m.title);
      if (full == q) return 78;
      if (full.startsWith(q)) return 70;
      if (full.contains(q)) return 55;
      final short = pinyinShort(m.title);
      if (short == q || short.startsWith(q)) return 60;
    }

    final tag = normalize(m.tagline);
    if (tag.isNotEmpty && tag.contains(q)) return 40;
    return 10;
  }

  /// 匹配分优先，同分按评分
  static int compareMovies(Movie a, Movie b, String query) {
    final ra = rankMovie(a, query);
    final rb = rankMovie(b, query);
    if (ra != rb) return rb.compareTo(ra);
    final sc = b.score.compareTo(a.score);
    if (sc != 0) return sc;
    return a.title.compareTo(b.title);
  }
}
