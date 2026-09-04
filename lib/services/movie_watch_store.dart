import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 观影状态（本地保存，按状态分列表）
enum MovieWatchStatus {
  none,
  want, // 想看
  watching, // 在看
  watched, // 看过
  onHold, // 搁置
  dropped, // 抛弃
}

extension MovieWatchStatusX on MovieWatchStatus {
  String get label => switch (this) {
        MovieWatchStatus.none => '',
        MovieWatchStatus.want => '想看',
        MovieWatchStatus.watching => '在看',
        MovieWatchStatus.watched => '看过',
        MovieWatchStatus.onHold => '搁置',
        MovieWatchStatus.dropped => '抛弃',
      };

  static const selectable = <MovieWatchStatus>[
    MovieWatchStatus.want,
    MovieWatchStatus.watching,
    MovieWatchStatus.watched,
    MovieWatchStatus.onHold,
    MovieWatchStatus.dropped,
  ];
}

class MovieWatchEntry {
  const MovieWatchEntry({
    required this.id,
    required this.name,
    required this.pic,
    required this.status,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String pic;
  final MovieWatchStatus status;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pic': pic,
        'status': status.name,
        'ts': updatedAt,
      };

  static MovieWatchEntry? fromJson(Map<String, dynamic> m) {
    final id = '${m['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final statusName = '${m['status'] ?? ''}';
    final status = MovieWatchStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => MovieWatchStatus.none,
    );
    if (status == MovieWatchStatus.none) return null;
    return MovieWatchEntry(
      id: id,
      name: '${m['name'] ?? ''}'.trim(),
      pic: '${m['pic'] ?? ''}'.trim(),
      status: status,
      updatedAt: int.tryParse('${m['ts'] ?? 0}') ?? 0,
    );
  }
}

class MovieWatchStore {
  MovieWatchStore._();

  static const _prefix = 'movie_watch_status_';
  static const _indexKey = 'movie_watch_index_v1';

  static Future<MovieWatchStatus> get(String movieId) async {
    final id = movieId.trim();
    if (id.isEmpty) return MovieWatchStatus.none;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$id') ?? '';
    return MovieWatchStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MovieWatchStatus.none,
    );
  }

  static Future<void> set(
    String movieId,
    MovieWatchStatus status, {
    String? name,
    String? pic,
  }) async {
    final id = movieId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (status == MovieWatchStatus.none) {
      await prefs.remove('$_prefix$id');
      await _upsertIndex(prefs, removeId: id);
      return;
    }
    await prefs.setString('$_prefix$id', status.name);
    final existing = await _readIndex(prefs);
    MovieWatchEntry? prev;
    for (final e in existing) {
      if (e.id == id) {
        prev = e;
        break;
      }
    }
    await _upsertIndex(
      prefs,
      entry: MovieWatchEntry(
        id: id,
        name: (name ?? '').trim().isNotEmpty
            ? name!.trim()
            : (prev?.name ?? ''),
        pic: (pic ?? '').trim().isNotEmpty ? pic!.trim() : (prev?.pic ?? ''),
        status: status,
        updatedAt: now,
      ),
    );
  }

  /// 按状态分页（新→旧）
  static Future<({List<MovieWatchEntry> items, int total, int pageCount})>
      listPage({
    required MovieWatchStatus status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = (await _readIndex(prefs))
        .where((e) => e.status == status)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final total = all.length;
    final size = pageSize.clamp(1, 100);
    final pageCount = total == 0 ? 1 : ((total + size - 1) ~/ size);
    final p = page.clamp(1, pageCount);
    final start = (p - 1) * size;
    final end = (start + size).clamp(0, total);
    return (
      items: start >= total ? const <MovieWatchEntry>[] : all.sublist(start, end),
      total: total,
      pageCount: pageCount,
    );
  }

  static Future<int> count(MovieWatchStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    return (await _readIndex(prefs)).where((e) => e.status == status).length;
  }

  static Future<List<MovieWatchEntry>> _readIndex(SharedPreferences prefs) async {
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) {
      // 兼容旧版仅存 status 键：无元数据则不出现在列表
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map)
            MovieWatchEntry.fromJson(Map<String, dynamic>.from(e)),
      ].whereType<MovieWatchEntry>().toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _upsertIndex(
    SharedPreferences prefs, {
    MovieWatchEntry? entry,
    String? removeId,
  }) async {
    final list = await _readIndex(prefs);
    final rid = removeId?.trim() ?? '';
    final next = <MovieWatchEntry>[
      for (final e in list)
        if (rid.isNotEmpty
            ? e.id != rid
            : (entry == null || e.id != entry.id))
          e,
      if (entry != null) entry,
    ];
    await prefs.setString(
      _indexKey,
      jsonEncode([for (final e in next) e.toJson()]),
    );
  }
}
