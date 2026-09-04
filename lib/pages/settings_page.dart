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
import '../widgets/app_onboarding.dart';
import '../widgets/app_page_route.dart';
import '../widgets/auth_sheet.dart';
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
  bool _savingCms = false;

  @override
  void initState() {
    super.initState();
    final cur = AppSettingsController.instance.customCmsBase;
    // 默认地址不回填明文，避免界面泄露
    _cmsCtrl = TextEditingController(text: cur);
    unawaited(_loadVodNotify());
  }

  Future<void> _loadVodNotify() async {
    final v = await VodUpdateWatchService.isEnabled();
    if (mounted) setState(() => _vodNotify = v);
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
        DialogX.showSuccess('已恢复默认服务器');
      } else {
        await AppSettingsController.instance.setCustomCmsBase(raw);
        _cmsCtrl.text = AppSettingsController.instance.customCmsBase;
        DialogX.showSuccess('服务器地址已保存');
      }
    } catch (e) {
      DialogX.showError('保存失败：$e');
    } finally {
      if (mounted) setState(() => _savingCms = false);
    }
  }

  static bool _looksMasked(String s) => s.contains('*');

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

        return CupertinoPageScaffold(
          backgroundColor: pageBg,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: pageBg.withValues(alpha: 0.94),
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
                  ],
                ),
                const SizedBox(height: 14),
                _ExpandableSectionCard(
                  title: '系统配色',
                  subtitle: ThemeController.instance.accentPreset.label,
                  color: cardBg,
                  dark: dark,
                  initiallyExpanded: true,
                  children: [
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
                  ],
                ),
                const SizedBox(height: 14),
                _ExpandableSectionCard(
                  title: '系统 UI 风格',
                  subtitle: ThemeController.instance.uiStyle.label,
                  color: cardBg,
                  dark: dark,
                  initiallyExpanded: true,
                  children: [
                    for (final (i, style) in AppUiStyle.values.indexed) ...[
                      if (i > 0) _CardDivider(color: line),
                      _Tile(
                        title: style.label,
                        subtitle: style.subtitle,
                        trailing: Icon(
                          ThemeController.instance.uiStyle == style
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 22,
                          color: ThemeController.instance.uiStyle == style
                              ? AppColors.brand
                              : hint,
                        ),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ThemeController.instance.setUiStyle(style);
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _ExpandableSectionCard(
                  title: '加载动画',
                  subtitle: ThemeController.instance.loadingStyle.label,
                  color: cardBg,
                  dark: dark,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final style in AppLoadingStyle.values)
                            _LoadingStyleChip(
                              style: style,
                              selected:
                                  ThemeController.instance.loadingStyle ==
                                  style,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ThemeController.instance
                                    .setLoadingStyle(style);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ExpandableSectionCard(
                  title: '动效与过渡',
                  subtitle: ThemeController.instance.motionEnabled
                      ? '${ThemeController.instance.pageTransition.label} · ${ThemeController.instance.motionSpeed.label}'
                      : '已关闭',
                  color: cardBg,
                  dark: dark,
                  children: [
                    _Tile(
                      title: '开启动效',
                      subtitle: '页面过渡、控件动效与列表动画',
                      trailing: CupertinoSwitch(
                        value: ThemeController.instance.motionEnabled,
                        activeTrackColor: AppColors.brand,
                        onChanged: (v) {
                          HapticFeedback.selectionClick();
                          ThemeController.instance.setMotionEnabled(v);
                        },
                      ),
                    ),
                    _CardDivider(color: line),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Text(
                        '页面过渡',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hint,
                        ),
                      ),
                    ),
                    for (final (i, style) in AppPageTransition.values.indexed) ...[
                      if (i > 0) _CardDivider(color: line),
                      _Tile(
                        title: style.label,
                        subtitle: style.subtitle,
                        trailing: Icon(
                          ThemeController.instance.pageTransition == style
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 22,
                          color:
                              ThemeController.instance.pageTransition == style
                                  ? AppColors.brand
                                  : hint,
                        ),
                        onTap: ThemeController.instance.motionEnabled
                            ? () {
                                HapticFeedback.selectionClick();
                                ThemeController.instance
                                    .setPageTransition(style);
                              }
                            : null,
                      ),
                    ],
                    _CardDivider(color: line),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Text(
                        '动画速度',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hint,
                        ),
                      ),
                    ),
                    for (final (i, speed) in AppMotionSpeed.values.indexed) ...[
                      if (i > 0) _CardDivider(color: line),
                      _Tile(
                        title: speed.label,
                        subtitle: '时长系数 ×${speed.factor.toStringAsFixed(2)}',
                        trailing: Icon(
                          ThemeController.instance.motionSpeed == speed
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 22,
                          color: ThemeController.instance.motionSpeed == speed
                              ? AppColors.brand
                              : hint,
                        ),
                        onTap: ThemeController.instance.motionEnabled
                            ? () {
                                HapticFeedback.selectionClick();
                                ThemeController.instance.setMotionSpeed(speed);
                              }
                            : null,
                      ),
                    ],
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
                SizedBox(height: 14),
                _SectionCard(
                  title: '自定义服务器',
                  color: cardBg,
                  dark: dark,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usingCustom
                                ? '当前使用自定义地址'
                                : '当前使用默认：$_maskedDefault',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              color: hint,
                            ),
                          ),
                          SizedBox(height: 10),
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
                              hintText: usingCustom
                                  ? 'https://你的域名或IP'
                                  : _maskedDefault,
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
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: _savingCms
                                      ? null
                                      : () async {
                                          await AppSettingsController.instance
                                              .resetCmsBase();
                                          _cmsCtrl.text = '';
                                          setState(() {});
                                          DialogX.showSuccess('已恢复默认');
                                        },
                                  style: TextButton.styleFrom(
                                    foregroundColor: text,
                                    backgroundColor: fieldFill,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: Text(
                                    '恢复默认',
                                    style: TextStyle(fontFamily: 'AppSans'),
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
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
                                    _savingCms ? '保存中…' : '保存',
                                    style: const TextStyle(
                                      fontFamily: 'AppSans',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: '关于',
                  color: cardBg,
                  dark: dark,
                  children: [
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
                      title: '产品导览',
                      subtitle: '重新高亮首页关键功能',
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await AppOnboardingGate.reset();
                        if (!context.mounted) return;
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        DialogX.showSuccess('已开始产品导览');
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

/// 默认折叠的设置分组，避免外观/动效选项把页面撑得很臃肿
class _ExpandableSectionCard extends StatefulWidget {
  const _ExpandableSectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.color,
    required this.dark,
    this.initiallyExpanded = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Color color;
  final bool dark;
  final bool initiallyExpanded;

  @override
  State<_ExpandableSectionCard> createState() => _ExpandableSectionCardState();
}

class _ExpandableSectionCardState extends State<_ExpandableSectionCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final hint = AppPalette.textHint(context);
    return Container(
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: widget.dark
                ? const Color(0x33000000)
                : const Color(0x0A000000),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _open = !_open);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brand,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            color: hint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: ThemeController.instance.scaled(
                      const Duration(milliseconds: 200),
                    ),
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 16,
                      color: hint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: ThemeController.instance.scaled(
              const Duration(milliseconds: 220),
            ),
            sizeCurve: Curves.easeOutCubic,
          ),
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
              const SizedBox(width: 6),
              Icon(CupertinoIcons.checkmark_alt, size: 16, color: preset.color),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadingStyleChip extends StatelessWidget {
  const _LoadingStyleChip({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AppLoadingStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 104,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand.withValues(alpha: dark ? 0.22 : 0.12)
              : (dark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F7)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 36,
              child: AppLoadingIndicator(
                size: 34,
                style: style,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              style.label,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: dark ? Colors.white : AppColors.text,
              ),
            ),
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
