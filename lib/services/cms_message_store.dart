import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/relative_time.dart';
import 'huihuo_panel_api.dart';
import 'local_notification_service.dart';
import 'maccms_user_api.dart';

/// CMS 站内消息本地缓存与已读状态（变更时通知角标）
class CmsMessageStore extends ChangeNotifier {
  CmsMessageStore._();
  static final CmsMessageStore instance = CmsMessageStore._();

  static const _cachePrefix = 'cms_messages_v3_';
  static const _readPrefix = 'cms_messages_read_v3_';
  static const _notifiedPrefix = 'cms_messages_notified_v1_';
  static const _legacyKeys = [
    'cms_messages_v1',
    'cms_messages_v2',
    'cms_messages_read_ids_v1',
  ];

  List<CmsMessageItem> _items = const [];
  Set<String> _readIds = {};
  int _unread = 0;
  int _userId = 0;
  String? lastFetchError;

  List<CmsMessageItem> get items => _items;
  int get unreadCount => _unread;

  String get _cacheKey => '$_cachePrefix$_userId';
  String get _readKey => '$_readPrefix$_userId';
  String get _notifiedKey => '$_notifiedPrefix$_userId';

  static bool _isJunk(CmsMessageItem m) {
    // 哇TV 面板通知不过滤
    if (m.id.startsWith('hh_')) return false;
    final t = '${m.title} ${m.content}'.toLowerCase();
    return t.contains('class=') ||
        t.contains('gbook_') ||
        t.contains('name=') ||
        t.contains('data-') ||
        t.contains('aria-') ||
        t.contains('<') ||
        t.contains('cmt-') ||
        t.contains('fed-') ||
        RegExp(r'^\d{9,13}$').hasMatch(m.title.trim());
  }

  static String _prettyTime(CmsMessageItem m) {
    final existing = m.timeText.trim();
    if (existing.contains('前') ||
        existing == '刚刚' ||
        existing == '系统' ||
        existing.contains('昨天') ||
        existing.contains('今天')) {
      return existing;
    }
    if (m.createdAt > 0) {
      final label = formatAgo(m.createdAt);
      if (label.isNotEmpty) return label;
    }
    final asNum = int.tryParse(existing);
    if (asNum != null && asNum > 1e8) {
      final ms = asNum > 1e12 ? asNum : asNum * 1000;
      final label = formatAgo(ms);
      if (label.isNotEmpty) return label;
    }
    return existing;
  }

  Future<void> bootstrap({int userId = 0}) async {
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    for (final k in _legacyKeys) {
      await prefs.remove(k);
    }
    final readRaw = prefs.getStringList(_readKey) ?? const [];
    _readIds = readRaw.toSet();
    final cached = prefs.getString(_cacheKey);
    if (cached != null && cached.isNotEmpty) {
      try {
        final list = jsonDecode(cached);
        if (list is List) {
          _items = [
            for (final e in list)
              if (e is Map)
                CmsMessageItem.fromJson(Map<String, dynamic>.from(e)),
          ].where((m) => !_isJunk(m)).map((m) {
            final t = _prettyTime(m);
            return t == m.timeText
                ? m
                : CmsMessageItem(
                    id: m.id,
                    title: m.title,
                    content: m.content,
                    timeText: t,
                    createdAt: m.createdAt,
                    read: m.read,
                    link: m.link,
                    tag: m.tag,
                    subtitle: m.subtitle,
                    coverUrl: m.coverUrl,
                    accent: m.accent,
                    style: m.style,
                  );
          }).toList();
          _recomputeUnread();
          notifyListeners();
        }
      } catch (_) {}
    } else {
      _items = const [];
      _unread = 0;
      notifyListeners();
    }
  }

  Future<void> clearForLogout() async {
    _items = const [];
    _unread = 0;
    _readIds = {};
    _userId = 0;
    lastFetchError = null;
    notifyListeners();
  }

  /// 并行拉哇TV 面板通知 + CMS 站内信；面板优先，避免 CMS 卡住导致无公告。
  Future<List<CmsMessageItem>> refresh(
    MacCmsUserApi api, {
    int userId = 0,
    bool allowFallback = true,
  }) async {
    await bootstrap(userId: userId);
    lastFetchError = null;

    final panelFuture = () async {
      try {
        return await HuihuoPanelApi.fetchNotifies()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        return e;
      }
    }();

    final cmsFuture = () async {
      try {
        return await api
            .fetchMessages()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        return e;
      }
    }();

    final results = await Future.wait<Object>([panelFuture, cmsFuture]);
    final panelRaw = results[0];
    final cmsRaw = results[1];

    List<CmsMessageItem> panel = const [];
    var panelOk = false;
    if (panelRaw is List<CmsMessageItem>) {
      panel = panelRaw;
      panelOk = true;
    } else {
      lastFetchError = '通知接口: $panelRaw';
    }

    List<CmsMessageItem> remote = const [];
    var remoteOk = false;
    if (cmsRaw is List<CmsMessageItem>) {
      remote = cmsRaw;
      remoteOk = true;
    }

    CmsMessageItem decorate(CmsMessageItem m) {
      final read = m.read || _readIds.contains(m.id);
      final t = _prettyTime(m);
      return CmsMessageItem(
        id: m.id,
        title: m.title,
        content: m.content,
        timeText: t,
        createdAt: m.createdAt,
        read: read,
        link: m.link,
        tag: m.tag,
        subtitle: m.subtitle,
        coverUrl: m.coverUrl,
        accent: m.accent,
        style: m.style,
      );
    }

    final cleaned = remote.where((m) => !_isJunk(m)).map(decorate).toList();
    final panelClean =
        panel.where((m) => !_isJunk(m)).map(decorate).toList();

    final byId = <String, CmsMessageItem>{};
    for (final m in cleaned) {
      byId[m.id] = m;
    }
    for (final m in panelClean) {
      byId[m.id] = m;
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });

    final prevIds = {for (final m in _items) m.id};

    final anyOk = remoteOk || panelOk;
    if (anyOk) {
      if (merged.isNotEmpty) {
        _items = merged;
        if (panelOk) lastFetchError = null;
      } else if (allowFallback && userId <= 0) {
        _items = _fallbackNotices();
      } else {
        _items = const [];
      }
    } else if (_items.isEmpty && allowFallback) {
      _items = _fallbackNotices();
    } else {
      _items = _items.where((m) => !_isJunk(m)).toList();
    }

    _recomputeUnread();
    await _persist();
    notifyListeners();

    // 系统公告 / 站内信 → 同步推到系统通知栏（与软件内「公告」列表联动）
    await _pushSystemNotificationsForNew(prevIds);

    return _items;
  }

  /// 剧集更新等本地事件写入软件通知列表，并可选择推系统通知
  Future<void> pushLocalNotice({
    required String id,
    required String title,
    required String content,
    String tag = '通知',
    bool systemNotify = true,
  }) async {
    final nid = id.trim();
    if (nid.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final exists = _items.any((e) => e.id == nid);
    final item = CmsMessageItem(
      id: nid,
      title: title.trim().isEmpty ? '通知' : title.trim(),
      content: content.trim(),
      timeText: '刚刚',
      createdAt: now,
      read: false,
      tag: tag,
      style: 'important',
    );
    if (exists) {
      _items = [for (final m in _items) if (m.id == nid) item else m];
    } else {
      _items = [item, ..._items];
    }
    _recomputeUnread();
    await _persist();
    notifyListeners();

    if (systemNotify) {
      try {
        await LocalNotificationService.showInboxMessage(
          messageId: nid,
          title: item.title,
          body: item.content.isEmpty ? '点击查看详情' : item.content,
        );
        final prefs = await SharedPreferences.getInstance();
        final notified =
            (prefs.getStringList(_notifiedKey) ?? const <String>[]).toSet()
              ..add(nid);
        await prefs.setStringList(_notifiedKey, notified.toList());
      } catch (e) {
        debugPrint('local notice push failed: $e');
      }
    }
  }

  Future<void> _pushSystemNotificationsForNew(Set<String> prevIds) async {
    final prefs = await SharedPreferences.getInstance();
    final notified =
        (prefs.getStringList(_notifiedKey) ?? const <String>[]).toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    final isColdStart = prevIds.isEmpty;

    final candidates = _items.where((m) {
      if (m.read) return false;
      if (notified.contains(m.id)) return false;
      // 冷启动：只推最近 3 天的新公告，避免历史刷屏
      if (isColdStart) {
        final created = m.createdAt <= 0
            ? now
            : (m.createdAt > 2000000000 ? m.createdAt : m.createdAt * 1000);
        if (now - created > const Duration(days: 3).inMilliseconds) {
          notified.add(m.id);
          return false;
        }
      }
      return true;
    }).take(5);

    var changed = false;
    for (final m in candidates) {
      final body = m.content.trim().isNotEmpty
          ? m.content.trim()
          : (m.subtitle.trim().isNotEmpty ? m.subtitle.trim() : '点击查看详情');
      try {
        await LocalNotificationService.showInboxMessage(
          messageId: m.id,
          title: m.title.isEmpty ? '新公告' : m.title,
          body: body,
        );
        notified.add(m.id);
        changed = true;
      } catch (e) {
        debugPrint('inbox notify failed: $e');
      }
    }
    // 把已跳过的历史 id 也记上，避免下次再扫
    if (isColdStart) {
      for (final m in _items) {
        if (!notified.contains(m.id) && m.createdAt > 0) {
          final created =
              m.createdAt > 2000000000 ? m.createdAt : m.createdAt * 1000;
          if (now - created > const Duration(days: 3).inMilliseconds) {
            notified.add(m.id);
            changed = true;
          }
        }
      }
    }
    if (changed || notified.isNotEmpty) {
      await prefs.setStringList(_notifiedKey, notified.toList());
    }
  }

  Future<void> markRead(String id) async {
    _readIds.add(id);
    _items = [
      for (final m in _items)
        if (m.id == id) m.copyWith(read: true) else m,
    ];
    _recomputeUnread();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_readKey, _readIds.toList());
    await _persist();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    for (final m in _items) {
      _readIds.add(m.id);
    }
    _items = [for (final m in _items) m.copyWith(read: true)];
    _recomputeUnread();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_readKey, _readIds.toList());
    await _persist();
    notifyListeners();
  }

  void _recomputeUnread() {
    _unread = _items.where((m) => !m.read).length;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode([for (final m in _items) m.toJson()]),
    );
  }

  List<CmsMessageItem> _fallbackNotices() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      CmsMessageItem(
        id: 'sys_welcome',
        title: '欢迎使用哇TV',
        content: '登录会员后可同步收藏、播放记录，并接收站内通知。',
        timeText: '系统',
        createdAt: now,
        read: _readIds.contains('sys_welcome'),
      ),
    ];
  }
}
