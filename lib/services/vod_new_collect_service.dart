import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'cms_message_store.dart';
import 'huihuo_panel_api.dart';
import 'maccms_api.dart';
import 'maccms_user_api.dart';

/// 采集新增影视 → 站内公告（优先面板同步，失败则本地差分）
abstract final class VodNewCollectService {
  static const _seenKey = 'vod_new_collect_seen_ids_v1';
  static const _lastCheckKey = 'vod_new_collect_last_check_v1';
  static const _minInterval = Duration(minutes: 15);
  static const _maxTitles = 30;

  static bool _running = false;

  /// 冷启动 / 回前台调用。首次只建基线不弹。
  static Future<void> check({
    bool force = false,
    MacCmsUserApi? messageApi,
  }) async {
    if (kIsWeb || _running) return;

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && last > 0 && now - last < _minInterval.inMilliseconds) {
      return;
    }

    _running = true;
    try {
      var announced = false;
      try {
        final titles = await HuihuoPanelApi.syncVodCollectAnnounce();
        if (titles.isNotEmpty) {
          announced = true;
        }
        // 面板写了公告后，刷新站内信列表（系统通知由 store 推送）
        try {
          await CmsMessageStore.instance.refresh(
            messageApi ?? MacCmsUserApi(),
          );
        } catch (_) {}
      } catch (e) {
        debugPrint('VodNewCollectService panel sync: $e');
      }

      if (!announced) {
        await _localDiffAnnounce(prefs);
      }

      await prefs.setInt(_lastCheckKey, now);
    } catch (e, st) {
      debugPrint('VodNewCollectService.check failed: $e\n$st');
    } finally {
      _running = false;
    }
  }

  static Future<void> _localDiffAnnounce(SharedPreferences prefs) async {
    final movies = await MacCmsApi().fetchLatest(limit: 40);
    if (movies.isEmpty) return;

    final seen = (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
    final isBaseline = seen.isEmpty;
    final fresh = <String>[];
    final nextSeen = <String>{...seen};

    for (final m in movies) {
      final id = m.id.trim();
      if (id.isEmpty) continue;
      nextSeen.add(id);
      if (isBaseline) continue;
      if (!seen.contains(id)) {
        final t = m.title.trim();
        if (t.isNotEmpty) fresh.add(t);
      }
    }

    // 控制 seen 体积
    final trimmed = nextSeen.toList();
    if (trimmed.length > 200) {
      trimmed.removeRange(0, trimmed.length - 200);
    }
    await prefs.setStringList(_seenKey, trimmed);

    if (isBaseline || fresh.isEmpty) return;

    final show = fresh.take(_maxTitles).toList();
    final buf = StringBuffer();
    for (var i = 0; i < show.length; i++) {
      buf.writeln('${i + 1}. ${show[i]}');
    }
    if (fresh.length > show.length) {
      buf.writeln('……等共 ${fresh.length} 部');
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    await CmsMessageStore.instance.pushLocalNotice(
      id: 'vod_new_$stamp',
      title: '片库更新 · 新增 ${fresh.length} 部',
      content: buf.toString().trim(),
      tag: '片库更新',
      systemNotify: true,
    );
  }
}
