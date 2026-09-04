import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import 'app_permission.dart';
import 'app_security.dart';
import 'huihuo_panel_api.dart';

/// 检查哇TV 面板发布的 App 更新（Android / iOS 分端）
class AppUpdateService {
  AppUpdateService._();

  static const _deviceKey = 'watv_device_id_v1';
  static const _reportedKey = 'watv_update_reported_code_v1';
  static const _installChannel = MethodChannel('com.watv.app/apk_installer');

  static Future<HuihuoAppUpdate?> fetch() => HuihuoPanelApi.fetchAppUpdate();

  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceKey) ?? '';
    if (id.isEmpty) {
      id =
          'd_${DateTime.now().millisecondsSinceEpoch}_${Object().hashCode.abs()}';
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

  /// [silent] 启动静默：仅当「有新版本且强制更新」才弹窗。
  static Future<bool> check({
    required BuildContext context,
    bool silent = false,
  }) async {
    if (kIsWeb) {
      if (!silent && context.mounted) {
        DialogX.showWarning('Web 端不支持安装包更新');
      }
      return false;
    }

    HuihuoAppUpdate? remote;
    try {
      remote = await fetch();
    } catch (e) {
      if (!silent && context.mounted) {
        DialogX.showError('检查更新失败：$e');
      }
      return false;
    }

    final localCode = ApiConfig.appVersionCode;
    final localName = ApiConfig.appVersionName;
    final plat = HuihuoPanelApi.currentPlatform;

    if (remote == null) {
      if (!silent && context.mounted) {
        DialogX.showSuccess(
          '服务器暂无 $plat 更新配置（本地 $localName+$localCode）',
        );
      }
      return false;
    }

    final newer = remote.isNewerThan(localCode);

    if (silent && (!newer || !remote.forceUpdate)) {
      if (!newer && remote.versionCode > 0) {
        unawaited(_maybeReportAlreadyOn(remote));
      }
      return false;
    }

    if (!newer) {
      if (!silent && context.mounted) {
        DialogX.showSuccess(
          '已是最新版 $localName ($localCode)\n'
          '服务器 ${remote.platform} ${remote.version} (${remote.versionCode})',
        );
      }
      return false;
    }

    if (!context.mounted) return true;
    await showAppUpdateDownloadDialog(context, remote);
    return true;
  }

  static Future<void> _maybeReportAlreadyOn(HuihuoAppUpdate remote) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_reportedKey${remote.platform}';
      final last = prefs.getInt(key) ?? 0;
      if (last >= remote.versionCode) return;
      final user = CmsAuthController.instance.user;
      await HuihuoPanelApi.reportUpdate(
        remote: remote,
        fromCode: ApiConfig.appVersionCode,
        fromVersion: ApiConfig.appVersionName,
        deviceId: await deviceId(),
        userId: user?.userId ?? 0,
        userName: user?.displayName ?? '',
      );
      await prefs.setInt(key, remote.versionCode);
    } catch (_) {}
  }

  static Future<void> reportClicked(HuihuoAppUpdate u) async {
    try {
      final user = CmsAuthController.instance.user;
      await HuihuoPanelApi.reportUpdate(
        remote: u,
        fromCode: ApiConfig.appVersionCode,
        fromVersion: ApiConfig.appVersionName,
        deviceId: await deviceId(),
        userId: user?.userId ?? 0,
        userName: user?.displayName ?? '',
      );
    } catch (_) {}
  }

  static Future<File> downloadApk(
    HuihuoAppUpdate u, {
    required void Function(double progress, int received, int total) onProgress,
  }) async {
    final uri = Uri.parse(u.downloadUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    AppSecurity.instance.hardenClient(client);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 WaTvAppUpdater',
      );
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw StateError('下载失败 HTTP ${res.statusCode}');
      }
      final total = res.contentLength;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/watv_update_${u.versionCode}.apk');
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        final p = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        onProgress(p, received, total > 0 ? total : received);
      }
      await sink.flush();
      await sink.close();
      onProgress(1, received, total > 0 ? total : received);
      return file;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> installApkFile(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('仅 Android 支持自动安装');
    }
    final allowed = await AppPermission.requestWithRationale(
      AppPermissionKind.installPackages,
      title: '需要安装权限',
      message: '更新完成后需要允许安装应用包，才会开始安装新版本。',
      confirmLabel: '去授权',
    );
    if (!allowed) {
      throw StateError('未授予安装权限');
    }
    await _installChannel.invokeMethod<void>('installApk', {'path': path});
  }
}

Future<void> showAppUpdateDownloadDialog(
  BuildContext context,
  HuihuoAppUpdate update,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: !update.forceUpdate,
    barrierLabel: 'update',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, a1, a2) => _AppUpdateDownloadDialog(update: update),
    transitionBuilder: (c, anim, _, child) {
      final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: t,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(t),
          child: child,
        ),
      );
    },
  );
}

class _AppUpdateDownloadDialog extends StatefulWidget {
  const _AppUpdateDownloadDialog({required this.update});
  final HuihuoAppUpdate update;

  @override
  State<_AppUpdateDownloadDialog> createState() =>
      _AppUpdateDownloadDialogState();
}

class _AppUpdateDownloadDialogState extends State<_AppUpdateDownloadDialog> {
  bool _downloading = false;
  bool _installing = false;
  double _progress = 0;
  int _received = 0;
  int _total = 0;
  String? _error;
  File? _apk;

  HuihuoAppUpdate get u => widget.update;

  String _fmtBytes(int n) {
    if (n <= 0) return '0 B';
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _startDownload() async {
    HapticFeedback.mediumImpact();
    if (u.downloadUrl.isEmpty) {
      setState(() => _error = '服务器未配置下载地址');
      return;
    }
    if (!Platform.isAndroid) {
      await Clipboard.setData(ClipboardData(text: u.downloadUrl));
      DialogX.showSuccess('已复制下载链接，请用 Safari / TestFlight 安装');
      unawaited(AppUpdateService.reportClicked(u));
      if (mounted && !u.forceUpdate) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
      _received = 0;
      _total = 0;
    });
    unawaited(AppUpdateService.reportClicked(u));
    try {
      final file = await AppUpdateService.downloadApk(
        u,
        onProgress: (p, r, t) {
          if (!mounted) return;
          setState(() {
            _progress = p;
            _received = r;
            _total = t;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _apk = file;
        _downloading = false;
        _installing = true;
      });
      await AppUpdateService.installApkFile(file.path);
      if (!mounted) return;
      setState(() => _installing = false);
      HapticFeedback.lightImpact();
      DialogX.showSuccess('已调起系统安装');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = false;
        _error = '$e';
      });
    }
  }

  Future<void> _retryInstall() async {
    final f = _apk;
    if (f == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await AppUpdateService.installApkFile(f.path);
      if (!mounted) return;
      setState(() => _installing = false);
      DialogX.showSuccess('已调起系统安装');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppPalette.text(context);
    final secondary = AppPalette.textSecondary(context);
    final hint = AppPalette.textHint(context);
    final soft = AppPalette.softFill(context);
    final surface = AppPalette.surface(context);
    final line = AppPalette.line(context);
    final busy = _downloading || _installing;
    final pct = (_progress * 100).clamp(0, 100).toStringAsFixed(0);
    final icon = CmsCoverImage.resolve(u.iconUrl);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CmsCoverImage(url: icon, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                u.displayName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                u.forceUpdate ? '需要更新到 ${u.version}' : '新版本 ${u.version}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  color: hint,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${ApiConfig.appVersionName} → ${u.version} (${u.versionCode})',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  color: hint,
                ),
              ),
              if (u.changelog.trim().isNotEmpty) ...[
                SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: SingleChildScrollView(
                    child: Text(
                      u.changelog.trim(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        height: 1.45,
                        color: secondary,
                      ),
                    ),
                  ),
                ),
              ],
              if (busy || _progress > 0 || _apk != null) ...[
                SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _downloading
                        ? (_total > 0 ? _progress : null)
                        : (_installing ? null : (_apk != null ? 1.0 : 0)),
                    minHeight: 4,
                    backgroundColor: soft,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _installing
                      ? '正在调起安装…'
                      : _downloading
                          ? '${_fmtBytes(_received)}'
                              '${_total > 0 ? ' / ${_fmtBytes(_total)}' : ''}'
                              '${_total > 0 ? '  $pct%' : ''}'
                          : '下载完成',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 11,
                    color: hint,
                  ),
                ),
              ],
              if (_error != null) ...[
                SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.danger,
                  ),
                ),
              ],
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : (_apk != null ? _retryInstall : _startDownload),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    disabledBackgroundColor:
                        AppColors.brand.withValues(alpha: 0.4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    busy
                        ? (_installing ? '安装中…' : '下载中…')
                        : _apk != null
                            ? '重新安装'
                            : (Platform.isAndroid ? '立即更新' : '复制下载链接'),
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              if (!u.forceUpdate && !busy)
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    '稍后',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: hint,
                    ),
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
