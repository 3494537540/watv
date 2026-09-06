import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_models.dart';
import 'cms_fav_store.dart';
import 'cms_message_store.dart';
import 'local_notification_service.dart';
import 'local_play_store.dart';
import 'maccms_api.dart';
import 'movie_watch_store.dart';

/// 检测收藏 / 观看记录对应剧集是否更新，并发送系统通知
abstract final class VodUpdateWatchService {
  static const _fpKey = 'vod_update_fp_v1';
  static const _lastCheckKey = 'vod_update_last_check_v1';
  static const _enabledKey = 'vod_update_notify_enabled_v1';
  static const _minInterval = Duration(minutes: 30);
  static const _maxIds = 48;

  static bool _running = false;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, v);
  }

  /// 冷启动 / 回到前台时调用。首次会先建立指纹基线（不弹通知）。
  static Future<void> check({
    BuildContext? context,
    bool force = false,
    bool requestPermission = true,
  }) async {
    if (kIsWeb || _running) return;
    if (!await isEnabled()) return;

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && last > 0 && now - last < _minInterval.inMilliseconds) {
      return;
    }

    _running = true;
    try {
      final ids = await _collectIds();
      if (ids.isEmpty) {
        await prefs.setInt(_lastCheckKey, now);
        return;
      }

      if (requestPermission) {
        final ok = await LocalNotificationService.ensurePermission(
          context: context,
        );
        if (!ok) {
          // 未授权时不写 lastCheck，下次仍可再请求
          return;
        }
      } else if (!await LocalNotificationService.areNotificationsEnabled()) {
        return;
      }

      final movies = await MacCmsApi().fetchMoviesByIds(ids);
      final fps = await _loadFingerprints(prefs);
      final isBaseline = fps.isEmpty;
      var changed = false;

      for (final movie in movies) {
        final id = movie.id.trim();
        if (id.isEmpty) continue;
        final next = _fingerprint(movie);
        final prev = fps[id];
        fps[id] = next;

        if (isBaseline || prev == null) continue;
        if (!_isUpdate(prev, next)) continue;
        if (!_looksLikeSeries(movie, next)) continue;

        changed = true;
        final body = next.remarks.isNotEmpty
            ? '已更新：${next.remarks}'
            : (next.epCount > prev.epCount
                ? '更新至第 ${next.epCount} 集'
                : '内容有更新，快来看看');
        await LocalNotificationService.showVodUpdate(
          vodId: id,
          title: movie.title,
          body: body,
        );
        // 同步写入软件内「公告/通知」列表
        await CmsMessageStore.instance.pushLocalNotice(
          id: 'vod_up_$id',
          title: movie.title,
          content: body,
          tag: '剧集更新',
          systemNotify: false, // 系统栏已由 showVodUpdate 发送
        );
      }

      await _saveFingerprints(prefs, fps);
      await prefs.setInt(_lastCheckKey, now);
      if (changed) {
        // no-op: notifications already posted
      }
    } catch (e, st) {
      debugPrint('VodUpdateWatchService.check failed: $e\n$st');
    } finally {
      _running = false;
    }
  }

  static Future<List<String>> _collectIds() async {
    final seen = <String>{};
    final out = <String>[];

    void add(String id) {
      final t = id.trim();
      if (t.isEmpty || !seen.add(t)) return;
      out.add(t);
    }

    final favs = await CmsFavStore.list();
    for (final e in favs) {
      add(e.vodId);
      if (out.length >= _maxIds) return out;
    }

    final plays = await LocalPlayStore.list(limit: 40);
    for (final e in plays) {
      add(e.vodId);
      if (out.length >= _maxIds) return out;
    }

    for (final status in const [
      MovieWatchStatus.watching,
      MovieWatchStatus.want,
      MovieWatchStatus.watched,
    ]) {
      final page = await MovieWatchStore.listPage(
        status: status,
        page: 1,
        pageSize: 24,
      );
      for (final e in page.items) {
        add(e.id);
        if (out.length >= _maxIds) return out;
      }
    }

    return out;
  }

  static _Fp _fingerprint(Movie m) {
    var epCount = 0;
    for (final s in m.playSources) {
      if (s.episodes.length > epCount) epCount = s.episodes.length;
    }
    if (epCount <= 0) epCount = m.episodeLabels.length;
    return _Fp(
      remarks: m.remarks.trim(),
      epCount: epCount,
      total: m.totalEpisodes,
      name: m.title,
    );
  }

  static bool _looksLikeSeries(Movie m, _Fp fp) {
    if (m.isSeries) return true;
    if (fp.epCount > 1 || fp.total > 1) return true;
    final r = fp.remarks;
    return r.contains('更新') ||
        r.contains('集') ||
        r.contains('期') ||
        r.contains('话');
  }

  static bool _isUpdate(_Fp prev, _Fp next) {
    if (prev.remarks != next.remarks && next.remarks.isNotEmpty) return true;
    if (next.epCount > prev.epCount && prev.epCount > 0) return true;
    if (next.total > prev.total && prev.total > 0) return true;
    return false;
  }

  static Future<Map<String, _Fp>> _loadFingerprints(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_fpKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, _Fp>{};
      decoded.forEach((k, v) {
        if (v is! Map) return;
        final id = '$k'.trim();
        if (id.isEmpty) return;
        out[id] = _Fp.fromJson(Map<String, dynamic>.from(v));
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveFingerprints(
    SharedPreferences prefs,
    Map<String, _Fp> fps,
  ) async {
    final map = <String, dynamic>{
      for (final e in fps.entries) e.key: e.value.toJson(),
    };
    await prefs.setString(_fpKey, jsonEncode(map));
  }
}

class _Fp {
  const _Fp({
    required this.remarks,
    required this.epCount,
    required this.total,
    required this.name,
  });

  final String remarks;
  final int epCount;
  final int total;
  final String name;

  Map<String, dynamic> toJson() => {
        'r': remarks,
        'e': epCount,
        't': total,
        'n': name,
      };

  factory _Fp.fromJson(Map<String, dynamic> m) => _Fp(
        remarks: '${m['r'] ?? ''}',
        epCount: int.tryParse('${m['e'] ?? 0}') ?? 0,
        total: int.tryParse('${m['t'] ?? 0}') ?? 0,
        name: '${m['n'] ?? ''}',
      );
}
