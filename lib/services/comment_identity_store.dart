import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机记住「我发过的评论」昵称/头像，避免刷新后被 CMS 脏数据冲成「会员/访客」
class CommentIdentityStore {
  CommentIdentityStore._();
  static final instance = CommentIdentityStore._();

  static const _key = 'comment_identity_v1';
  Map<String, Map<String, dynamic>> _byKey = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          _byKey = {
            for (final e in j.entries)
              if (e.key is String && e.value is Map)
                e.key as String: Map<String, dynamic>.from(e.value as Map),
          };
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  static String contentKey(String vodId, String content) =>
      '${vodId.trim()}|${content.trim()}';

  Future<void> remember({
    required String vodId,
    required String content,
    required String userName,
    String? avatarUrl,
    int userId = 0,
    String commentId = '',
  }) async {
    await ensureLoaded();
    final name = userName.trim();
    if (name.isEmpty) return;
    final body = content.trim();
    if (body.isEmpty) return;
    final entry = <String, dynamic>{
      'name': name,
      'avatar': (avatarUrl ?? '').trim(),
      'user_id': userId,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _byKey[contentKey(vodId, body)] = entry;
    final cid = commentId.trim();
    if (cid.isNotEmpty && !cid.startsWith('local_')) {
      _byKey['id:$cid'] = entry;
    }
    // 控制体积
    if (_byKey.length > 400) {
      final entries = _byKey.entries.toList()
        ..sort((a, b) =>
            ((a.value['at'] as num?)?.toInt() ?? 0)
                .compareTo((b.value['at'] as num?)?.toInt() ?? 0));
      for (final e in entries.take(_byKey.length - 300)) {
        _byKey.remove(e.key);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_byKey));
  }

  Future<({String name, String avatar, int userId})?> lookup({
    required String vodId,
    required String content,
    String commentId = '',
  }) async {
    await ensureLoaded();
    final cid = commentId.trim();
    if (cid.isNotEmpty) {
      final byId = _byKey['id:$cid'];
      if (byId != null) {
        return (
          name: '${byId['name'] ?? ''}',
          avatar: '${byId['avatar'] ?? ''}',
          userId: (byId['user_id'] as num?)?.toInt() ?? 0,
        );
      }
    }
    final byContent = _byKey[contentKey(vodId, content)];
    if (byContent == null) return null;
    return (
      name: '${byContent['name'] ?? ''}',
      avatar: '${byContent['avatar'] ?? ''}',
      userId: (byContent['user_id'] as num?)?.toInt() ?? 0,
    );
  }
}
