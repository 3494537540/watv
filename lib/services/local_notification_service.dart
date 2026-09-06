import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_permission.dart';

/// 系统本地通知（剧集更新 / 下载完成 / 站内信），兼容 iOS + Android。
abstract final class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// 点击通知：payload 形如 `vod:123` / `download:xxx` / `inbox`
  static void Function(String payload)? onTapPayload;

  static const _vodChannelId = 'vod_updates';
  static const _vodChannelName = '剧集更新';
  static const _vodChannelDesc = '收藏或看过的内容有更新时提醒';

  static const _dlChannelId = 'downloads';
  static const _dlChannelName = '下载完成';
  static const _dlChannelDesc = '缓存下载完成后提醒';

  static const _inboxChannelId = 'inbox';
  static const _inboxChannelName = '消息通知';
  static const _inboxChannelDesc = '站内信与公告提醒';

  static const _dlEnabledKey = 'notify_download_enabled_v1';
  static const _inboxEnabledKey = 'notify_inbox_enabled_v1';
  static const _welcomeSentKey = 'notify_welcome_sent_v1';

  /// Android 状态栏小图标须为白色剪影 drawable，不能用彩色 launcher
  static const _androidIcon = '@drawable/ic_stat_wa';

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    const android = AndroidInitializationSettings(_androidIcon);
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
    );
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _vodChannelId,
          _vodChannelName,
          description: _vodChannelDesc,
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _dlChannelId,
          _dlChannelName,
          description: _dlChannelDesc,
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _inboxChannelId,
          _inboxChannelName,
          description: _inboxChannelDesc,
          importance: Importance.high,
        ),
      );
    }
    _ready = true;

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final resp = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true &&
        resp?.payload != null &&
        resp!.payload!.isNotEmpty) {
      final payload = resp.payload!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onTapPayload?.call(payload);
      });
    }
  }

  static void _onTap(NotificationResponse response) {
    final p = response.payload?.trim() ?? '';
    if (p.isEmpty) return;
    onTapPayload?.call(p);
  }

  static ({String kind, String id}) parsePayload(String raw) {
    final p = raw.trim();
    if (p.startsWith('vod:')) {
      return (kind: 'vod', id: p.substring(4));
    }
    if (p.startsWith('download:')) {
      return (kind: 'download', id: p.substring(9));
    }
    if (p == 'inbox' || p.startsWith('inbox:')) {
      return (kind: 'inbox', id: '');
    }
    return (kind: 'vod', id: p);
  }

  static Future<bool> isDownloadNotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dlEnabledKey) ?? true;
  }

  static Future<void> setDownloadNotifyEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dlEnabledKey, v);
  }

  static Future<bool> isInboxNotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_inboxEnabledKey) ?? true;
  }

  static Future<void> setInboxNotifyEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_inboxEnabledKey, v);
  }

  /// 先说明再申请通知权限（iOS + Android 13+）
  static Future<bool> ensurePermission({BuildContext? context}) async {
    if (kIsWeb) return false;
    await init();

    // 已可用则直接过
    if (await areNotificationsEnabled()) return true;

    // iOS：优先走 FLN 系统弹窗（比 permission_handler 更准）
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (granted == true) return true;
      // 用户拒绝后再走说明弹窗（引导去设置）
      if (context != null && context.mounted) {
        final ok = await AppPermission.requestWithRationale(
          AppPermissionKind.notifications,
          context: context,
          title: '开启通知',
          message: '用于提醒剧集更新、下载完成和重要消息。可随时在系统设置里关闭。',
          confirmLabel: '去开启',
        );
        if (!ok) return false;
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      }
      return areNotificationsEnabled();
    }

    final ok = await AppPermission.requestWithRationale(
      AppPermissionKind.notifications,
      context: context,
      title: '开启通知',
      message: '用于提醒剧集更新、下载完成和重要消息。可随时在系统设置或本 App 设置里关闭。',
      confirmLabel: '开启',
    );
    if (!ok) return false;

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    }
    return areNotificationsEnabled();
  }

  /// 以系统真实能力为准（比 permission_handler 更靠谱）
  static Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    await init();
    try {
      if (Platform.isAndroid) {
        final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (sdk < 33) return true;
        final enabled = await android?.areNotificationsEnabled();
        return enabled ?? true;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final opts = await ios?.checkPermissions();
        if (opts == null) return true;
        return opts.isEnabled ||
            opts.isAlertEnabled ||
            opts.isBadgeEnabled ||
            opts.isSoundEnabled;
      }
    } catch (e) {
      debugPrint('areNotificationsEnabled failed: $e');
    }
    // 兜底：走 AppPermission
    return AppPermission.isGranted(AppPermissionKind.notifications);
  }

  static Future<bool> _canShow() async {
    if (kIsWeb) return false;
    await init();
    return areNotificationsEnabled();
  }

  static AndroidNotificationDetails _androidDetails(
    String channelId,
    String channelName,
    String channelDesc, {
    Importance importance = Importance.high,
    Priority priority = Priority.high,
    StyleInformation? style,
  }) {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: importance,
      priority: priority,
      icon: _androidIcon,
      styleInformation: style,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
    );
  }

  static const _iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    presentBanner: true,
    presentList: true,
    interruptionLevel: InterruptionLevel.active,
  );

  static Future<void> _showSafe({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
    String? payload,
  }) async {
    try {
      await _plugin.show(
        id: id == 0 ? 1 : id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
      debugPrint('LocalNotification shown: $title');
    } catch (e, st) {
      debugPrint('LocalNotification show failed: $e\n$st');
    }
  }

  static Future<void> showVodUpdate({
    required String vodId,
    required String title,
    required String body,
  }) async {
    if (!await _canShow()) {
      debugPrint('skip vod notify: permission off');
      return;
    }
    await _showSafe(
      id: vodId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      details: NotificationDetails(
        android: _androidDetails(
          _vodChannelId,
          _vodChannelName,
          _vodChannelDesc,
          style: BigTextStyleInformation(body),
        ),
        iOS: _iosDetails,
      ),
      payload: 'vod:$vodId',
    );
  }

  static Future<void> showDownloadDone({
    required String cacheId,
    required String title,
    required String episodeLabel,
  }) async {
    if (!await isDownloadNotifyEnabled()) return;
    if (!await _canShow()) {
      debugPrint('skip download notify: permission off');
      return;
    }
    final body = episodeLabel.trim().isEmpty
        ? '已下载完成，可离线观看'
        : '$episodeLabel 已下载完成，可离线观看';
    await _showSafe(
      id: ('dl_$cacheId').hashCode & 0x7fffffff,
      title: title,
      body: body,
      details: NotificationDetails(
        android: _androidDetails(
          _dlChannelId,
          _dlChannelName,
          _dlChannelDesc,
        ),
        iOS: _iosDetails,
      ),
      payload: 'download:$cacheId',
    );
  }

  static Future<void> showInboxMessage({
    required String messageId,
    required String title,
    required String body,
  }) async {
    if (!await isInboxNotifyEnabled()) return;
    if (!await _canShow()) {
      debugPrint('skip inbox notify: permission off');
      return;
    }
    await _showSafe(
      id: ('inbox_$messageId').hashCode & 0x7fffffff,
      title: title.isEmpty ? '新消息' : title,
      body: body.isEmpty ? '你有一条新消息' : body,
      details: NotificationDetails(
        android: _androidDetails(
          _inboxChannelId,
          _inboxChannelName,
          _inboxChannelDesc,
        ),
        iOS: _iosDetails,
      ),
      payload: 'inbox',
    );
  }

  /// 设置页「发送测试通知」：立刻验证通道是否通
  static Future<bool> showTest({BuildContext? context}) async {
    final ok = await ensurePermission(context: context);
    if (!ok) return false;
    await _showSafe(
      id: 900001,
      title: '哇TV 通知已开启',
      body: '如果你看到这条，说明系统通知工作正常。',
      details: NotificationDetails(
        android: _androidDetails(
          _vodChannelId,
          _vodChannelName,
          _vodChannelDesc,
        ),
        iOS: _iosDetails,
      ),
      payload: 'inbox',
    );
    return true;
  }

  /// 首次授权成功后发一条欢迎通知（只一次）
  static Future<void> maybeSendWelcomeOnce() async {
    if (!await _canShow()) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_welcomeSentKey) == true) return;
    await prefs.setBool(_welcomeSentKey, true);
    await _showSafe(
      id: 900002,
      title: '哇TV',
      body: '通知已开启：剧集更新、下载完成会提醒你。',
      details: NotificationDetails(
        android: _androidDetails(
          _vodChannelId,
          _vodChannelName,
          _vodChannelDesc,
        ),
        iOS: _iosDetails,
      ),
      payload: 'inbox',
    );
  }
}
