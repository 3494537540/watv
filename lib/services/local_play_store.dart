import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机播放记录（含集数与进度）
class LocalPlayItem {
  const LocalPlayItem({
    required this.vodId,
    required this.name,
    this.pic = '',
    this.remarks = '',
    required this.playedAt,
    this.episodeIndex = 0,
    this.episodeLabel = '',
    this.positionMs = 0,
    this.durationMs = 0,
  });

  final String vodId;
  final String name;
  final String pic;
  final String remarks;
  final int playedAt;
  final int episodeIndex;
  final String episodeLabel;
  final int positionMs;
  final int durationMs;

  double get progress {
    if (durationMs <= 0) return 0;
    final p = positionMs / durationMs;
    if (p.isNaN || p.isInfinite) return 0;
    return p.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'vod_id': vodId,
        'name': name,
        'pic': pic,
        'remarks': remarks,
        'played_at': playedAt,
        'episode_index': episodeIndex,
        'episode_label': episodeLabel,
        'position_ms': positionMs,
        'duration_ms': durationMs,
      };

  factory LocalPlayItem.fromJson(Map<String, dynamic> json) {
    return LocalPlayItem(
      vodId: '${json['vod_id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      pic: '${json['pic'] ?? ''}',
      remarks: '${json['remarks'] ?? ''}',
      playedAt: (json['played_at'] as num?)?.toInt() ?? 0,
      episodeIndex: (json['episode_index'] as num?)?.toInt() ?? 0,
      episodeLabel: '${json['episode_label'] ?? ''}',
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class LocalPlayStore {
  LocalPlayStore._();

  static const _key = 'local_play_history_v1';
  static const _max = 40;

  static Future<List<LocalPlayItem>> list({int limit = 24}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final items = [
        for (final e in list)
          if (e is Map)
            LocalPlayItem.fromJson(Map<String, dynamic>.from(e)),
      ];
      items.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      if (items.length <= limit) return items;
      return items.sublist(0, limit);
    } catch (_) {
      return const [];
    }
  }

  static Future<LocalPlayItem?> get(String vodId) async {
    final id = vodId.trim();
    if (id.isEmpty) return null;
    final items = await list(limit: _max);
    for (final e in items) {
      if (e.vodId == id) return e;
    }
    return null;
  }

  static Future<void> add({
    required String vodId,
    required String name,
    String pic = '',
    String remarks = '',
    int episodeIndex = 0,
    String episodeLabel = '',
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    final id = vodId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await list(limit: _max);
    LocalPlayItem? prev;
    for (final e in existing) {
      if (e.vodId == id) {
        prev = e;
        break;
      }
    }
    final nextPos = positionMs > 0 ? positionMs : (prev?.positionMs ?? 0);
    final nextDur = durationMs > 0 ? durationMs : (prev?.durationMs ?? 0);
    final nextEp = episodeLabel.trim().isNotEmpty
        ? episodeLabel.trim()
        : (prev?.episodeLabel ?? '');
    final next = <LocalPlayItem>[
      LocalPlayItem(
        vodId: id,
        name: name.trim().isEmpty ? '影片$id' : name.trim(),
        pic: pic.isNotEmpty ? pic : (prev?.pic ?? ''),
        remarks: remarks.isNotEmpty ? remarks : (prev?.remarks ?? ''),
        playedAt: DateTime.now().millisecondsSinceEpoch,
        episodeIndex: episodeIndex,
        episodeLabel: nextEp,
        positionMs: nextPos,
        durationMs: nextDur,
      ),
      ...existing.where((e) => e.vodId != id),
    ];
    final trimmed = next.length > _max ? next.sublist(0, _max) : next;
    await prefs.setString(
      _key,
      jsonEncode([for (final e in trimmed) e.toJson()]),
    );
  }

  /// 仅更新封面（补图后回写，避免下次仍空白）
  static Future<void> updatePic({
    required String vodId,
    required String pic,
  }) async {
    final id = vodId.trim();
    final cover = pic.trim();
    if (id.isEmpty || cover.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await list(limit: _max);
    var changed = false;
    final next = <LocalPlayItem>[
      for (final e in existing)
        if (e.vodId == id)
          () {
            changed = true;
            return LocalPlayItem(
              vodId: e.vodId,
              name: e.name,
              pic: cover,
              remarks: e.remarks,
              playedAt: e.playedAt,
              episodeIndex: e.episodeIndex,
              episodeLabel: e.episodeLabel,
              positionMs: e.positionMs,
              durationMs: e.durationMs,
            );
          }()
        else
          e,
    ];
    if (!changed) return;
    await prefs.setString(
      _key,
      jsonEncode([for (final e in next) e.toJson()]),
    );
  }

  static Future<void> removeIds(Iterable<String> vodIds) async {
    final ids = {for (final e in vodIds) e.trim()}.where((e) => e.isNotEmpty);
    if (ids.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await list(limit: _max);
    final next = [for (final e in existing) if (!ids.contains(e.vodId)) e];
    await prefs.setString(
      _key,
      jsonEncode([for (final e in next) e.toJson()]),
    );
  }
}
