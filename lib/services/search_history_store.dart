import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地搜索历史（关键词）
class SearchHistoryStore {
  SearchHistoryStore._();

  static const _key = 'search_history_keywords_v1';
  static const _max = 24;

  static Future<List<String>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if ('$e'.trim().isNotEmpty) '$e'.trim(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> add(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return list();
    final prefs = await SharedPreferences.getInstance();
    final cur = await list();
    final next = <String>[q, for (final e in cur) if (e != q) e];
    final clipped = next.take(_max).toList();
    await prefs.setString(_key, jsonEncode(clipped));
    return clipped;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<List<String>> remove(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final next = [for (final e in await list()) if (e != keyword) e];
    await prefs.setString(_key, jsonEncode(next));
    return next;
  }
}
