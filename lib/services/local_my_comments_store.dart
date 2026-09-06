import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_models.dart';

/// 本机「我的评论」备份（面板/CMS 不可用时仍能显示）
class LocalMyCommentsStore {
  LocalMyCommentsStore._();

  static const _key = 'my_comments_v1';

  static Future<List<MovieComment>> list({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <MovieComment>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final uid = int.tryParse('${m['owner_uid'] ?? 0}') ?? 0;
        if (userId != null && userId > 0 && uid > 0 && uid != userId) {
          continue;
        }
        final content = '${m['content'] ?? ''}'.trim();
        if (content.isEmpty) continue;
        out.add(
          MovieComment(
            id: '${m['id'] ?? out.length}',
            userName: '${m['user_name'] ?? '我'}',
            content: content,
            timeText: '${m['time_text'] ?? ''}',
            timeMs: int.tryParse('${m['time_ms'] ?? 0}') ?? 0,
            avatarUrl: () {
              final a = '${m['avatar'] ?? ''}'.trim();
              return a.isEmpty ? null : a;
            }(),
            vodId: '${m['vod_id'] ?? ''}',
            vodName: '${m['vod_name'] ?? ''}',
            vodPic: '${m['vod_pic'] ?? ''}',
          ),
        );
      }
      out.sort((a, b) => b.timeMs.compareTo(a.timeMs));
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add({
    required MovieComment comment,
    required int ownerUid,
    String vodName = '',
    String vodPic = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cur = await list();
    final next = <Map<String, dynamic>>[
      {
        'id': comment.id,
        'owner_uid': ownerUid,
        'user_name': comment.userName,
        'content': comment.content,
        'time_text': comment.timeText,
        'time_ms': comment.timeMs > 0
            ? comment.timeMs
            : DateTime.now().millisecondsSinceEpoch,
        'avatar': comment.avatarUrl ?? '',
        'vod_id': comment.vodId.isNotEmpty ? comment.vodId : '',
        'vod_name': vodName.isNotEmpty ? vodName : comment.vodName,
        'vod_pic': vodPic.isNotEmpty ? vodPic : comment.vodPic,
      },
      for (final c in cur)
        if (c.id != comment.id &&
            !(c.content == comment.content &&
                c.vodId == comment.vodId &&
                (c.timeMs - comment.timeMs).abs() < 5000))
          {
            'id': c.id,
            'owner_uid': ownerUid,
            'user_name': c.userName,
            'content': c.content,
            'time_text': c.timeText,
            'time_ms': c.timeMs,
            'avatar': c.avatarUrl ?? '',
            'vod_id': c.vodId,
            'vod_name': c.vodName,
            'vod_pic': c.vodPic,
          },
    ];
    // 最多保留 200 条
    final trimmed = next.take(200).toList();
    await prefs.setString(_key, jsonEncode(trimmed));
  }

  static Future<void> mergeRemote(
    List<MovieComment> remote, {
    required int ownerUid,
  }) async {
    if (remote.isEmpty) return;
    final local = await list(userId: ownerUid);
    final seen = <String>{
      for (final c in local) '${c.vodId}|${c.content.trim()}',
    };
    for (final c in remote.reversed) {
      final key = '${c.vodId}|${c.content.trim()}';
      if (key.length < 3 || !seen.add(key)) continue;
      await add(comment: c, ownerUid: ownerUid);
    }
  }
}
