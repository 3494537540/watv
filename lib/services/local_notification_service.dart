import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_permission.dart';

/// 系统本地通知（剧集更新等）
abstract final class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static void Function(String vodId)? onOpenVod;

  static const _channelId = 'vod_updates';
  static const _channelName = '剧集更新';
  static const _channelDesc = '收藏或看过的内容有更新时提醒';

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
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
          _channelId,
          _channelName,
          description: _channelDesc,
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
        onOpenVod?.call(payload);
      });
    }
  }

  static void _onTap(NotificationResponse response) {
    final id = response.payload?.trim() ?? '';
    if (id.isEmpty) return;
    onOpenVod?.call(id);
  }

  /// 先说明再申请通知权限；成功返回 true
  static Future<bool> ensurePermission({BuildContext? context}) async {
    if (kIsWeb) return false;
    await init();
    return AppPermission.requestWithRationale(
      AppPermissionKind.notifications,
      context: context,
      title: '开启更新通知',
      message:
          '当你收藏或看过的剧集更新时，会通过系统通知提醒你，不会骚扰你其他无关内容。',
      confirmLabel: '开启',
    );
  }

  static Future<void> showVodUpdate({
    required String vodId,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await init();
    final id = vodId.hashCode & 0x7fffffff;
    await _plugin.show(
      id: id == 0 ? 1 : id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: vodId,
    );
  }
}
