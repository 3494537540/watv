import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../services/app_update_service.dart';
import '../services/huihuo_panel_api.dart';
import '../services/local_notification_service.dart';
import '../services/vod_update_watch_service.dart';
import '../state/app_settings_controller.dart';
import '../state/cms_auth_controller.dart';
import '../state/theme_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/anchored_choice_menu.dart';
import '../widgets/app_onboarding.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/app_page_route.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/figma_loading.dart';
import 'about_page.dart';
import 'open_source_licenses_page.dart';

/// 设置：主题、账号、服务器、关于
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _cmsCtrl;
  bool _vodNotify = true;
  bool _downloadNotify = true;
  bool _inboxNotify = true;
  bool _savingCms = false;
  bool _customServerOn = false;

  @override
  void initState() {
    super.initState();
    final cur = AppSettingsController.instance.customCmsBase;
    _customServerOn = cur.isNotEmpty;
    // 默认地址不回填明文，避免界面泄露
    _cmsCtrl = TextEditingController(text: cur);
    unawaited(_loadNotifyPrefs());
    if (CmsAuthController.instance.isLoggedIn) {
      unawaited(
        CmsAuthController.instance.refreshProfile().then((_) {
          if (mounted) setState(() {});
        }).catchError((_) {}),
      );
    }
  }

  Future<void> _loadNotifyPrefs() async {
    final vod = await VodUpdateWatchService.isEnabled();
    final dl = await LocalNotificationService.isDownloadNotifyEnabled();
    final inbox = await LocalNotificationService.isInboxNotifyEnabled();
    if (!mounted) return;
    setState(() {
      _vodNotify = vod;
      _downloadNotify = dl;
      _inboxNotify = inbox;
    });
  }

  @override
  void dispose() {
    _cmsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCms() async {
    if (_savingCms) return;
    setState(() => _savingCms = true);
    try {
      final raw = _cmsCtrl.text.trim();
      if (raw.isEmpty || _looksMasked(raw)) {
        await AppSettingsController.instance.resetCmsBase();
        _cmsCtrl.text = '';
        setState(() => _customServerOn = false);
        DialogX.showSuccess('已恢复默认服务器');
      } else {
        await AppSettingsController.instance.setCustomCmsBase(raw);
        _cmsCtrl.text = AppSettingsController.instance.customCmsBase;
        setState(() => _customServerOn = true);
        DialogX.showSuccess('服务器地址已保存');
      }
    } catch (e) {
      DialogX.showError('保存失败：$e');
    } finally {
      if (mounted) setState(() => _savingCms = false);
    }
  }

  static bool _looksMasked(String s) => s.contains('*');

  Future<void> _showAnchoredOptions(
    BuildContext anchor, {
    required List<AnchoredChoice> Function() buildOptions,
    Widget? Function(BuildContext context)? previewBuilder,
    bool applyAndClose = true,
  }) {
    return showAnchoredChoiceMenu(
      anchor,
      buildOptions: buildOptions,
      previewBuilder: previewBuilder,
      applyAndClose: applyAndClose,
    );
  }

  Future<void> _showAnchoredMotionMenu(BuildContext anchor) {
    return showAnchoredChoiceMenu(
      anchor,
      applyAndClose: false,
      previewBuilder: (ctx) {
        final tc = ThemeController.instance;
        return MotionPreviewPane(
          enabled: tc.motionEnabled,
          transition: tc.pageTransition,
          speed: tc.motionSpeed,
        );
      },
      buildOptions: () {
        final tc = ThemeController.instance;
        return [
          (
            label: tc.motionEnabled ? '动效：开' : '动效：关',
            subtitle: '点击开关页面过渡与控件动效',
            selected: false,
            leading: null,
            onPick: () => tc.setMotionEnabled(!tc.motionEnabled),
          ),
          for (final s in AppPageTransition.values)
            (
              label: s.label,
              subtitle: s.subtitle,
              selected: tc.pageTransition == s,
              leading: null,
              onPick: () {
                if (!tc.motionEnabled) tc.setMotionEnabled(true);
                tc.setPageTransition(s);
              },
            ),
          for (final s in AppMotionSpeed.values)
            (
              label: '速度 · ${s.label}',
              subtitle: '时长系数 ×${s.factor.toStringAsFixed(2)}',
              selected: tc.motionSpeed == s,
              leading: null,
              onPick: () {
                if (!tc.motionEnabled) tc.setMotionEnabled(true);
                tc.setMotionSpeed(s);
              },
            ),
        ];
      },
    );
  }

  Future<void> _showAnchoredLoadingMenu(BuildContext anchor) {
    return showAnchoredChoiceMenu(
      anchor,
      applyAndClose: false,
      menuWidth: 308,
      previewBuilder: (_) => const LoadingPreviewPane(),
      buildOptions: () {
        final tc = ThemeController.instance;
        // 不把动画塞进左侧窄槽（会裁切 Lottie/圆环），只靠顶部大预览
        return [
          for (final s in AppLoadingStyle.values)
            (
              label: s.label,
              subtitle: s.subtitle,
              selected: tc.loadingStyle == s,
              leading: null,
              onPick: () => tc.setLoadingStyle(s),
            ),
        ];
      },
    );
  }

  /// 默认地址展示用星号遮罩（不泄露真实主机）
  static String get _maskedDefault {
    final u = Uri.tryParse(ApiConfig.productionMacCms);
    if (u == null || u.host.isEmpty) return '********';
    final host = u.host;
    final ip = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$').firstMatch(host);
    if (ip != null) {
      return '${u.scheme}://${ip[1]}.***.***.${ip[4]}';
    }
    final scheme = u.scheme.isEmpty ? 'https' : u.scheme;
    return '$scheme://********';
  }

  @override
  Widget build(BuildContext context) {
    final text = AppPalette.text(context);
    final hint = AppPalette.textHint(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        ThemeController.instance,
        CmsAuthController.instance,
        AppSettingsController.instance,
      ]),
      builder: (context, _) {
        final dark = ThemeController.instance.isDark;
        final cms = CmsAuthController.instance;
        final loggedIn = cms.isLoggedIn;
        final settings = AppSettingsController.instance;
        final usingCustom = settings.customCmsBase.isNotEmpty;
        final pageBg =
            dark ? const Color(0xFF121214) : const Color(0xFFF2F2F7);
        final cardBg = dark ? const Color(0xFF1C1C1E) : Colors.white;
        final line = dark
            ? const Color(0x14FFFFFF)
            : const Color(0x14000000);
        final fieldFill =
            dark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F7);
        final navFg = dark ? Colors.white : AppColors.text;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: pageBg,
            statusBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
          child: CupertinoPageScaffold(
          backgroundColor: pageBg,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: pageBg,
            border: null,
            middle: Text(
              '设置',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontWeight: FontWeight.w600,
                color: navFg,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                _SectionCard(
                  title: '通用',
                  color: cardBg,
                  dark: dark,
                  children: [
                    _Tile(
                      title: '深色模式',
                      subtitle: dark ? '已开启' : '已关闭',
                      trailing: CupertinoSwitch(
                        value: dark,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          ThemeController.instance.setDark(v);
                        },
                      ),
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '自动登录',
                      subtitle: settings.autoLogin
                          ? '下次打开保留登录状态'
                          : '每次打开需重新登录',
                      trailing: CupertinoSwitch(
                        value: settings.autoLogin,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) async {
                          HapticFeedback.selectionClick();
                          await settings.setAutoLogin(v);
                          DialogX.showSuccess(
                            v ? '已开启自动登录' : '已关闭，下次启动需登录',
                          );
                        },
                      ),
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '剧集更新通知',
                      subtitle: _vodNotify
                          ? '收藏/看过的剧更新时推送'
                          : '已关闭',
                      trailing: CupertinoSwitch(
                        value: _vodNotify,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) async {
                          HapticFeedback.selectionClick();
                          if (v) {
                            final ok =
                                await LocalNotificationService.ensurePermission(
                              context: context,
                            );
                            if (!ok) return;
                            await VodUpdateWatchService.setEnabled(true);
                            if (!mounted) return;
                            setState(() => _vodNotify = true);
                            await LocalNotificationService.showTest(
                              context: context,
                            );
                            if (!mounted) return;
                            DialogX.showSuccess('已开启更新通知');
                            unawaited(
                              VodUpdateWatchService.check(
                                context: context,
                                force: true,
                                requestPermission: false,
                              ),
                            );
                          } else {
                            await VodUpdateWatchService.setEnabled(false);
                            if (!mounted) return;
                            setState(() => _vodNotify = false);
                            DialogX.showSuccess('已关闭更新通知');
                          }
                        },
                      ),
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '下载完成通知',
                      subtitle: _downloadNotify
                          ? '缓存下完后系统提醒'
                          : '已关闭',
                      trailing: CupertinoSwitch(
                        value: _downloadNotify,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) async {
                          HapticFeedback.selectionClick();
                          if (v) {
                            final ok =
                                await LocalNotificationService.ensurePermission(
                              context: context,
                            );
                            if (!ok) return;
                          }
                          await LocalNotificationService
                              .setDownloadNotifyEnabled(v);
                          if (!mounted) return;
                          setState(() => _downloadNotify = v);
                          DialogX.showSuccess(v ? '已开启下载通知' : '已关闭下载通知');
                        },
                      ),
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '消息通知',
                      subtitle: _inboxNotify
                          ? '站内信/公告到达时提醒'
                          : '已关闭',
                      trailing: CupertinoSwitch(
                        value: _inboxNotify,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) async {
                          HapticFeedback.selectionClick();
                          if (v) {
                            final ok =
                                await LocalNotificationService.ensurePermission(
                              context: context,
                            );
                            if (!ok) return;
                          }
                          await LocalNotificationService
                              .setInboxNotifyEnabled(v);
                          if (!mounted) return;
                          setState(() => _inboxNotify = v);
                          if (v) {
                            await LocalNotificationService.showTest(
                              context: context,
                            );
                          }
                          if (!mounted) return;
                          DialogX.showSuccess(v ? '已开启消息通知' : '已关闭消息通知');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '外观与动效',
                  color: cardBg,
                  dark: dark,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        '系统配色',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: text,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in AppAccentPreset.values)
                            _AccentChip(
                              preset: preset,
                              selected:
                                  ThemeController.instance.accentPreset ==
                                      preset,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ThemeController.instance
                                    .setAccentPreset(preset);
                              },
                            ),
                        ],
                      ),
                    ),
                    _CardDivider(color: line),
                    Builder(
                      builder: (tileCtx) => _Tile(
                        title: '系统 UI 风格',
                        subtitle: ThemeController.instance.uiStyle.label,
                        onTap: () => _showAnchoredOptions(
                          tileCtx,
                          applyAndClose: true,
                          buildOptions: () => [
                            for (final s in AppUiStyle.values)
                              (
                                label: s.label,
                                subtitle: s.subtitle,
                                selected:
                                    ThemeController.instance.uiStyle == s,
                                leading: null,
                                onPick: () =>
                                    ThemeController.instance.setUiStyle(s),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _CardDivider(color: line),
                    Builder(
                      builder: (tileCtx) => _Tile(
                        title: '加载动画',
                        subtitle: ThemeController.instance.loadingStyle.label,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppLoadingIndicator(
                              size: 28,
                              color: AppColors.brand,
                              style: ThemeController.instance.loadingStyle,
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 16,
                              color: hint,
                            ),
                          ],
                        ),
                        onTap: () => _showAnchoredLoadingMenu(tileCtx),
                      ),
                    ),
                    _CardDivider(color: line),
                    Builder(
                      builder: (tileCtx) => _Tile(
                        title: '动效与过渡',
                        subtitle: ThemeController.instance.motionEnabled
                            ? '${ThemeController.instance.pageTransition.label} · ${ThemeController.instance.motionSpeed.label}'
                            : '已关闭',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 56,
                              height: 36,
                              child: MotionPreviewPane(
                                enabled:
                                    ThemeController.instance.motionEnabled,
                                transition:
                                    ThemeController.instance.pageTransition,
                                speed: ThemeController.instance.motionSpeed,
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 16,
                              color: hint,
                            ),
                          ],
                        ),
                        onTap: () => _showAnchoredMotionMenu(tileCtx),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '账号',
                  color: cardBg,
                  dark: dark,
                  children: [
                    if (loggedIn) ...[
                      _Tile(
                        title: '当前账号',
                        subtitle: cms.user?.displayName ?? '会员',
                        onTap: null,
                      ),
                      _CardDivider(color: line),
                      _Tile(
                        title: '上次登录时间',
                        subtitle: () {
                          final t = cms.user?.loginTimeLabel ?? '';
                          return t.isEmpty ? '暂无记录' : t;
                        }(),
                        onTap: null,
                      ),
                      _CardDivider(color: line),
                      _Tile(
                        title: '上次登录 IP',
                        subtitle: () {
                          final ip = (cms.user?.loginIp ?? '').trim();
                          return ip.isEmpty ? '暂无记录' : ip;
                        }(),
                        onTap: null,
                      ),
                      _CardDivider(color: line),
                      _Tile(
                        title: '退出登录',
                        titleColor: AppColors.danger,
                        onTap: () async {
                          final yes = await DialogX.confirm(
                            context: context,
                            title: '退出登录',
                            message: '确定退出当前会员账号？',
                            confirmLabel: '退出',
                            destructive: true,
                          );
                          if (yes != true) return;
                          await CmsAuthController.instance.logout();
                          DialogX.showSuccess('已退出');
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ] else
                      _Tile(
                        title: '登录会员',
                        subtitle: '同步播放记录与积分',
                        onTap: () => showAuthSheet(context),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '服务器',
                  color: cardBg,
                  dark: dark,
                  children: [
                    _Tile(
                      title: '自定义服务器地址',
                      subtitle: _customServerOn
                          ? (usingCustom ? '已启用自定义地址' : '开启后填写地址并保存')
                          : '当前使用默认服务器',
                      trailing: CupertinoSwitch(
                        value: _customServerOn,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) async {
                          HapticFeedback.selectionClick();
                          if (!v) {
                            await AppSettingsController.instance.resetCmsBase();
                            _cmsCtrl.text = '';
                            if (!mounted) return;
                            setState(() => _customServerOn = false);
                            DialogX.showSuccess('已恢复默认服务器');
                            return;
                          }
                          setState(() => _customServerOn = true);
                        },
                      ),
                    ),
                    if (_customServerOn) ...[
                      _CardDivider(color: line),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              usingCustom
                                  ? '当前使用自定义地址'
                                  : '留空并保存可恢复默认：$_maskedDefault',
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 12,
                                color: hint,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _cmsCtrl,
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 14,
                                color: text,
                              ),
                              cursorColor: AppColors.brand,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                hintText: 'https://你的域名或IP',
                                hintStyle: TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 13,
                                  color: hint,
                                ),
                                filled: true,
                                fillColor: fieldFill,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.brand,
                                    width: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _savingCms ? null : _saveCms,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.brand,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  _savingCms ? '保存中…' : '保存地址',
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '关于',
                  color: cardBg,
                  dark: dark,
                  children: [
                    _Tile(
                      title: '重新导览',
                      subtitle: '回到首页后再次显示功能引导',
                      onTap: () async {
                        await AppOnboardingGate.reset();
                        if (!context.mounted) return;
                        DialogX.showSuccess('已开启新手引导，正在回到首页');
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '检查更新',
                      subtitle:
                          '${HuihuoPanelApi.currentPlatform.toUpperCase()} · ${ApiConfig.appVersionName} (${ApiConfig.appVersionCode})',
                      onTap: () {
                        unawaited(
                          AppUpdateService.check(
                            context: context,
                            silent: false,
                          ),
                        );
                      },
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '更新日志',
                      subtitle: '查看近期版本改动',
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoute<void>(
                            builder: (_) => const _ChangelogPage(),
                          ),
                        );
                      },
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '关于哇TV',
                      subtitle: '开发者 · 软件简介 · 技术栈',
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoute<void>(
                            builder: (_) => const AboutPage(),
                          ),
                        );
                      },
                    ),
                    _CardDivider(color: line),
                    _Tile(
                      title: '开源协议',
                      subtitle: '第三方开源库与许可证',
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoute<void>(
                            builder: (_) => const OpenSourceLicensesPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    required this.color,
    required this.dark,
  });

  final String title;
  final List<Widget> children;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x33000000) : const Color(0x0A000000),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.brand,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, thickness: 0.5, color: color),
    );
  }
}

class _AccentChip extends StatelessWidget {
  const _AccentChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppAccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: selected
              ? preset.color.withValues(alpha: dark ? 0.22 : 0.12)
              : (dark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F7)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              preset.label,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: dark ? Colors.white : AppColors.text,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: preset.color,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final text = titleColor ?? AppPalette.text(context);
    final hint = AppPalette.textHint(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: hint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: hint,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSubScaffold extends StatelessWidget {
  const _SettingsSubScaffold({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    final pageBg = dark ? const Color(0xFF121214) : const Color(0xFFF2F2F7);
    final navFg = dark ? Colors.white : AppColors.text;
    return CupertinoPageScaffold(
      backgroundColor: pageBg,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: pageBg.withValues(alpha: 0.94),
        border: null,
        middle: Text(
          title,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w600,
            color: navFg,
          ),
        ),
      ),
      child: SafeArea(child: child),
    );
  }
}

class _ChangelogPage extends StatefulWidget {
  const _ChangelogPage();

  @override
  State<_ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<_ChangelogPage> {
  bool _loading = true;
  String? _error;
  HuihuoAppUpdate? _update;
  List<HuihuoChangelogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AppUpdateService.fetch(),
        HuihuoPanelApi.fetchChangelogs(),
      ]);
      if (!mounted) return;
      setState(() {
        _update = results[0] as HuihuoAppUpdate?;
        _entries = results[1] as List<HuihuoChangelogEntry>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _timeLabel(int ts) {
    if (ts <= 0) return '近期';
    final ms = ts > 2000000000 ? ts : ts * 1000;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  List<String> _linesOf(String log) {
    if (log.trim().isEmpty) return const [];
    return log
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    final cardBg = dark ? const Color(0xFF1C1C1E) : Colors.white;
    final text = AppPalette.text(context);
    final hint = AppPalette.textHint(context);
    final u = _update;
    final plat = HuihuoPanelApi.currentPlatform.toUpperCase();

    // 有归档用归档；否则用当前端 app_update 拼一条
    final items = <HuihuoChangelogEntry>[
      ..._entries,
    ];
    if (items.isEmpty && u != null) {
      items.add(
        HuihuoChangelogEntry(
          platform: u.platform,
          version: u.version,
          versionCode: u.versionCode,
          downloadUrl: u.downloadUrl,
          changelog: u.changelog,
          appName: u.appName,
          createdAt: u.updatedAt,
        ),
      );
    }

    return _SettingsSubScaffold(
      title: '更新日志',
      child: _loading
          ? const Center(child: AppLoadingIndicator(size: 40))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '拉取失败：$_error',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '当前 $plat ${ApiConfig.appVersionName}',
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 13,
                                color: hint,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _loading ? null : _load,
                            child: const Text(
                              '刷新',
                              style: TextStyle(fontFamily: 'AppSans'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        _ChangelogTimelineItem(
                          title: 'v${ApiConfig.appVersionName}',
                          time: '本机',
                          active: true,
                          isLast: true,
                          children: [
                            Text(
                              '服务器尚未配置 $plat 端更新日志。\n'
                              '请在面板「更新」中保存该端版本与说明后刷新。',
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 14,
                                height: 1.5,
                                color: hint,
                              ),
                            ),
                          ],
                        )
                      else
                        for (var i = 0; i < items.length; i++) ...[
                          _ChangelogTimelineItem(
                            title: items[i].version.isEmpty
                                ? '版本更新'
                                : 'v${items[i].version}',
                            time: _timeLabel(items[i].createdAt),
                            active: i == 0,
                            isLast: i == items.length - 1,
                            children: [
                              if (_linesOf(items[i].changelog).isEmpty)
                                Text(
                                  '暂无更新说明',
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 14,
                                    height: 1.5,
                                    color: hint,
                                  ),
                                )
                              else
                                for (final line
                                    in _linesOf(items[i].changelog))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 7),
                                          child: Container(
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: AppColors.brand
                                                  .withValues(alpha: 0.7),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            line.replaceFirst(
                                              RegExp(r'^[-•·]\s*'),
                                              '',
                                            ),
                                            style: TextStyle(
                                              fontFamily: 'AppSans',
                                              fontSize: 14,
                                              height: 1.45,
                                              color: text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                        ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChangelogTimelineItem extends StatelessWidget {
  const _ChangelogTimelineItem({
    required this.title,
    required this.time,
    required this.children,
    this.active = false,
    this.isLast = false,
  });

  final String title;
  final String time;
  final List<Widget> children;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final hint = AppPalette.textHint(context);
    final text = AppPalette.text(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: active ? AppColors.brand : hint,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: AppColors.brand.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: hint.withValues(alpha: 0.35),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: hint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

