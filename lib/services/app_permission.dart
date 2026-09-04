import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/dialogx/dialogx.dart';

/// 应用内权限类型（先说明用途，再调系统申请）
enum AppPermissionKind {
  photos(
    '访问相册',
    '用于选择头像、发布图片或从相册挑选内容，不会在后台读取你的照片。',
  ),
  saveMedia(
    '保存到相册',
    '用于把图片或视频保存到本地相册，方便你离线查看与分享。',
  ),
  camera(
    '使用相机',
    '用于拍摄头像或发布内容时拍照，仅在你主动拍摄时使用。',
  ),
  notifications(
    '通知权限',
    '用于提醒你收藏或看过的剧集有更新，以及重要站内消息，可随时在系统设置中关闭。',
  ),
  installPackages(
    '安装应用',
    '用于下载并安装应用更新包，仅在你确认更新时使用。',
  );

  const AppPermissionKind(this.title, this.rationale);
  final String title;
  final String rationale;
}

/// 权限申请：未授权时先弹窗解释，用户同意后再调系统权限。
abstract final class AppPermission {
  static const _ackPrefix = 'app_perm_ack_v1_';

  static Future<int> _androidSdk() async {
    if (kIsWeb || !Platform.isAndroid) return 0;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> _wasAcked(AppPermissionKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_ackPrefix${kind.name}') ?? false;
  }

  static Future<void> _markAcked(AppPermissionKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_ackPrefix${kind.name}', true);
  }

  /// Android 13+ 选图走系统 Photo Picker，无需运行时权限。
  static Future<bool> _runtimeOptional(AppPermissionKind kind) async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return false;
    final sdk = await _androidSdk();
    if (sdk < 33) return false;
    return kind == AppPermissionKind.photos;
  }

  /// 是否已具备该权限（不弹系统框、不弹说明）
  static Future<bool> isGranted(AppPermissionKind kind) async {
    if (kIsWeb) return true;
    if (await _runtimeOptional(kind)) {
      return _wasAcked(kind);
    }

    if (kind == AppPermissionKind.saveMedia) {
      try {
        if (await Gal.hasAccess(toAlbum: true)) return true;
      } catch (_) {}
    }

    final statuses = await _statusOf(kind);
    if (statuses.isEmpty) return true;
    return statuses.every(_ok);
  }

  /// 先说明用途，再申请。返回是否可用。
  ///
  /// [context] 建议传入当前页 context，避免弹窗找不到 Navigator。
  static Future<bool> requestWithRationale(
    AppPermissionKind kind, {
    BuildContext? context,
    String? title,
    String? message,
    String confirmLabel = '允许',
    String cancelLabel = '暂不',
  }) async {
    if (kIsWeb) return true;

    // —— Photo Picker：无系统权限，但首次仍要说明 ——
    if (await _runtimeOptional(kind)) {
      if (await _wasAcked(kind)) return true;
      final ok = await DialogX.confirm(
        context: context,
        title: title ?? kind.title,
        message: message ?? kind.rationale,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      );
      if (!ok) return false;
      await _markAcked(kind);
      return true;
    }

    if (await isGranted(kind)) return true;

    final permanentlyDenied = await _anyPermanentlyDenied(kind);
    final ok = await DialogX.confirm(
      context: context,
      title: title ?? kind.title,
      message: message ??
          (permanentlyDenied
              ? '${kind.rationale}\n\n你之前拒绝了该权限，需要到系统设置中手动开启。'
              : kind.rationale),
      confirmLabel: permanentlyDenied ? '去设置' : confirmLabel,
      cancelLabel: cancelLabel,
    );
    if (!ok) return false;

    if (permanentlyDenied) {
      await openAppSettings();
      return isGranted(kind);
    }

    if (kind == AppPermissionKind.saveMedia) {
      try {
        if (await Gal.hasAccess(toAlbum: true)) return true;
        return await Gal.requestAccess(toAlbum: true);
      } catch (_) {
        // 回退 permission_handler
      }
    }

    final results = await _requestOf(kind);
    if (results.every(_ok)) return true;

    if (results.any((s) => s.isPermanentlyDenied)) {
      final go = await DialogX.confirm(
        context: context,
        title: '权限未开启',
        message: '没有${kind.title}将无法使用相关功能，可在系统设置中重新开启。',
        confirmLabel: '去设置',
        cancelLabel: '取消',
      );
      if (go) {
        await openAppSettings();
        return isGranted(kind);
      }
    } else {
      DialogX.showWarning('未获得${kind.title}');
    }
    return false;
  }

  static bool _ok(PermissionStatus s) =>
      s.isGranted || s.isLimited || s.isRestricted;

  static Future<bool> _anyPermanentlyDenied(AppPermissionKind kind) async {
    final list = await _statusOf(kind);
    return list.any((s) => s.isPermanentlyDenied);
  }

  static Future<List<PermissionStatus>> _statusOf(
    AppPermissionKind kind,
  ) async {
    final perms = await _permissionsFor(kind);
    if (perms.isEmpty) return const [PermissionStatus.granted];
    return [for (final p in perms) await p.status];
  }

  static Future<List<PermissionStatus>> _requestOf(
    AppPermissionKind kind,
  ) async {
    final perms = await _permissionsFor(kind);
    if (perms.isEmpty) return const [PermissionStatus.granted];
    final map = await perms.request();
    return map.values.toList();
  }

  static Future<List<Permission>> _permissionsFor(
    AppPermissionKind kind,
  ) async {
    if (kIsWeb) return const [];
    final sdk = await _androidSdk();
    switch (kind) {
      case AppPermissionKind.photos:
        if (Platform.isIOS) return [Permission.photos];
        if (Platform.isAndroid) {
          if (sdk >= 33) return const [];
          return [Permission.storage];
        }
        return [Permission.photos];
      case AppPermissionKind.saveMedia:
        if (Platform.isIOS) return [Permission.photos];
        if (Platform.isAndroid) {
          if (sdk >= 33) return [Permission.photos];
          if (sdk >= 29) return const [];
          return [Permission.storage];
        }
        return [Permission.photos];
      case AppPermissionKind.camera:
        return [Permission.camera];
      case AppPermissionKind.notifications:
        return [Permission.notification];
      case AppPermissionKind.installPackages:
        if (Platform.isAndroid) return [Permission.requestInstallPackages];
        return const [];
    }
  }
}
