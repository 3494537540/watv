import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地收藏镜像：CMS 同步不稳定时，打开详情仍能正确显示「已收藏」
class CmsFavEntry {
  const CmsFavEntry({
    required this.vodId,
    required this.name,
    required this.pic,
    this.ulogId = '',
    this.updatedAt = 0,
  });

  final String vodId;
  final String name;
  final String pic;
  final String ulogId;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'vodId': vodId,
        'name': name,
        'pic': pic,
        'ulogId': ulogId,
        'ts': updatedAt,
      };

  static CmsFavEntry? fromJson(Map<String, dynamic> m) {
    final id = '${m['vodId'] ?? m['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    return CmsFavEntry(
      vodId: id,
      name: '${m['name'] ?? ''}'.trim(),
      pic: '${m['pic'] ?? ''}'.trim(),
      ulogId: '${m['ulogId'] ?? ''}'.trim(),
      updatedAt: int.tryParse('${m['ts'] ?? 0}') ?? 0,
    );
  }
}

class CmsFavStore {
  CmsFavStore._();

  static const _key = 'cms_fav_index_v1';

  static String normId(String id) => id.trim();

  static Future<List<CmsFavEntry>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final items = [
        for (final e in decoded)
          if (e is Map) CmsFavEntry.fromJson(Map<String, dynamic>.from(e)),
      ].whereType<CmsFavEntry>().toList();
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> contains(String vodId) async {
    final id = normId(vodId);
    if (id.isEmpty) return false;
    final all = await list();
    return all.any((e) => e.vodId == id);
  }

  static Future<void> add({
    required String vodId,
    String name = '',
    String pic = '',
    String ulogId = '',
  }) async {
    final id = normId(vodId);
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = await list();
    CmsFavEntry? prev;
    for (final e in all) {
      if (e.vodId == id) {
        prev = e;
        break;
      }
    }
    final next = <CmsFavEntry>[
      for (final e in all)
        if (e.vodId != id) e,
      CmsFavEntry(
        vodId: id,
        name: name.trim().isNotEmpty ? name.trim() : (prev?.name ?? ''),
        pic: pic.trim().isNotEmpty ? pic.trim() : (prev?.pic ?? ''),
        ulogId:
            ulogId.trim().isNotEmpty ? ulogId.trim() : (prev?.ulogId ?? ''),
        updatedAt: now,
      ),
    ];
    await prefs.setString(
      _key,
      jsonEncode([for (final e in next) e.toJson()]),
    );
  }

  static Future<void> remove(String vodId) async {
    final id = normId(vodId);
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final next = [for (final e in await list()) if (e.vodId != id) e];
    await prefs.setString(
      _key,
      jsonEncode([for (final e in next) e.toJson()]),
    );
  }

  /// 用服务端列表校准本地（保留本地独有项，补全 pic/name）
  static Future<void> mergeFromRemote(
    Iterable<({String vodId, String name, String pic, String ulogId})>
        remote,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final local = await list();
    final byId = {for (final e in local) e.vodId: e};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in remote) {
      final id = normId(r.vodId);
      if (id.isEmpty) continue;
      final prev = byId[id];
      byId[id] = CmsFavEntry(
        vodId: id,
        name: r.name.trim().isNotEmpty ? r.name.trim() : (prev?.name ?? ''),
        pic: r.pic.trim().isNotEmpty ? r.pic.trim() : (prev?.pic ?? ''),
        ulogId:
            r.ulogId.trim().isNotEmpty ? r.ulogId.trim() : (prev?.ulogId ?? ''),
        updatedAt: prev?.updatedAt ?? now,
      );
    }
    final next = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await prefs.setString(
      _key,
      jsonEncode([for (final e in next) e.toJson()]),
    );
  }
}
