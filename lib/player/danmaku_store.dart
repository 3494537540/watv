import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
/// 单条弹幕
class DanmakuItem {
  const DanmakuItem({
    required this.timeSec,
    required this.text,
    this.color = 0xFFFFFFFF,
    this.self = false,
  });

  final double timeSec;
  final String text;
  final int color;
  final bool self;

  Map<String, dynamic> toJson() => {
        't': timeSec,
        'x': text,
        'c': color,
        's': self,
      };

  factory DanmakuItem.fromJson(Map<String, dynamic> j) => DanmakuItem(
        timeSec: (j['t'] as num?)?.toDouble() ?? 0,
        text: '${j['x'] ?? ''}',
        color: (j['c'] as num?)?.toInt() ?? 0xFFFFFFFF,
        self: j['s'] == true,
      );
}

/// 本地弹幕缓存（第三方拉取后的离线备份）
class DanmakuStore {
  DanmakuStore._();

  static String _key(String vodId, int ep) => 'danmaku_${vodId}_$ep';

  static Future<List<DanmakuItem>> load(String vodId, int ep) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(vodId, ep));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map) DanmakuItem.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save({
    required String vodId,
    required int ep,
    required List<DanmakuItem> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = [...items]..sort((a, b) => a.timeSec.compareTo(b.timeSec));
    await prefs.setString(
      _key(vodId, ep),
      jsonEncode([for (final d in sorted) d.toJson()]),
    );
  }

  static Future<void> append({
    required String vodId,
    required int ep,
    required DanmakuItem item,
  }) async {
    final current = await load(vodId, ep);
    await save(vodId: vodId, ep: ep, items: [...current, item]);
  }
}
