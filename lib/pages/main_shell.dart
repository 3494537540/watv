import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../services/app_update_service.dart';
import '../services/cms_app_config.dart';
import '../services/local_notification_service.dart';
import '../services/maccms_api.dart';
import '../services/vod_update_watch_service.dart';
import '../state/cms_auth_controller.dart';
import '../state/theme_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_onboarding.dart';
import '../widgets/app_page_route.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/dialogx/dialogx.dart';
import 'home_page.dart';
import 'cms_articles_page.dart';
import 'cms_messages_page.dart';
import 'movie_detail_page.dart';
import 'profile_page.dart';
import 'vod_cache_list_page.dart';
import 'vod_filter_page.dart';

/// 主框架：底栏可由 CMS app_config.json 自定义
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _authSheetShowing = false;
  List<AppTabSpec> _tabs = CmsAppConfig.defaults.enabledTabs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalNotificationService.onTapPayload = _onNotificationPayload;
    unawaited(_ensurePortraitFriendly());
    unawaited(_loadConfig());
    unawaited(_bootstrapNotifications());
    CmsAppConfigStore.instance.addListener(_onConfig);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (LocalNotificationService.onTapPayload == _onNotificationPayload) {
      LocalNotificationService.onTapPayload = null;
    }
    CmsAppConfigStore.instance.removeListener(_onConfig);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        VodUpdateWatchService.check(
          context: mounted ? context : null,
          requestPermission: false,
        ),
      );
    }
  }

  Future<void> _bootstrapNotifications() async {
    await LocalNotificationService.init();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final ok = await LocalNotificationService.ensurePermission(
      context: context,
    );
    if (!mounted) return;
    if (ok) {
      await LocalNotificationService.maybeSendWelcomeOnce();
    }
    await VodUpdateWatchService.check(
      context: context,
      force: true,
      requestPermission: false,
    );
  }

  Future<void> _onNotificationPayload(String raw) async {
    final parsed = LocalNotificationService.parsePayload(raw);
    switch (parsed.kind) {
      case 'download':
        await _openDownloads();
      case 'inbox':
        await _openInbox();
      case 'vod':
      default:
        await _openVodFromNotification(parsed.id);
    }
  }

  Future<void> _openInbox() async {
    final nav = dialogXNavigatorKey.currentState;
    if (nav == null) return;
    await nav.push(
      AppPageRoute<void>(builder: (_) => const CmsMessagesPage()),
    );
  }

  Future<void> _openDownloads() async {
    final nav = dialogXNavigatorKey.currentState;
    if (nav == null) return;
    await nav.push(
      AppPageRoute<void>(builder: (_) => const VodCacheListPage()),
    );
  }

  Future<void> _openVodFromNotification(String vodId) async {
    final id = vodId.trim();
    if (id.isEmpty) return;
    final nav = dialogXNavigatorKey.currentState;
    if (nav == null) return;
    DialogX.showWait('加载中…');
    try {
      final movie = await MacCmsApi().fetchDetail(id);
      DialogX.dismiss();
      await nav.push(
        AppPageRoute<void>(
          builder: (_) => MovieDetailPage(movie: movie),
        ),
      );
    } catch (e) {
      DialogX.showError('打开失败：$e');
    }
  }

  void _onConfig() {
    if (!mounted) return;
    final next = CmsAppConfigStore.instance.config.enabledTabs;
    if (next.isEmpty) return;
    setState(() {
      _tabs = next;
      if (_index >= _tabs.length) _index = 0;
    });
  }

  Future<void> _loadConfig() async {
    await CmsAppConfigStore.instance.bootstrap();
    if (mounted) {
      setState(() {
        _tabs = CmsAppConfigStore.instance.config.enabledTabs;
      });
    }
    await CmsAppConfigStore.instance.refresh();
    if (!mounted) return;
    unawaited(AppUpdateService.check(context: context, silent: true));
  }

  Future<void> _ensurePortraitFriendly() async {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  Future<void> _onTabSelected(int i) async {
    final was = _index;
    setState(() => _index = i);
    final id = _tabs[i.clamp(0, _tabs.length - 1)].id;
    if (id == 'profile' && !CmsAuthController.instance.isLoggedIn) {
      if (_authSheetShowing) return;
      if (was == i) return;
      _authSheetShowing = true;
      try {
        await showAuthSheet(context);
      } finally {
        _authSheetShowing = false;
      }
    }
  }

  Widget _pageFor(String id) {
    return switch (id) {
      'home' => const HomePage(),
      'filter' => const VodFilterPage(),
      'news' || 'tasks' || 'art' => const CmsArticlesPage(asTabRoot: true),
      'profile' => const ProfilePage(),
      _ => const HomePage(),
    };
  }

  GlassTab _glassTab(AppTabSpec t) {
    final (icon, active) = switch (t.id) {
      'home' => (CupertinoIcons.square_list, CupertinoIcons.square_list_fill),
      'filter' => (
          CupertinoIcons.square_grid_2x2,
          CupertinoIcons.square_grid_2x2_fill
        ),
      'news' || 'tasks' || 'art' => (
          CupertinoIcons.doc_text,
          CupertinoIcons.doc_text_fill
        ),
      'profile' => (CupertinoIcons.person, CupertinoIcons.person_fill),
      _ => (CupertinoIcons.circle, CupertinoIcons.circle_fill),
    };
    return GlassTab(
      icon: Icon(icon),
      activeIcon: Icon(active),
      label: t.label,
    );
  }

  IconData _tabIcon(String id, bool active) {
    return switch (id) {
      'home' => active
          ? CupertinoIcons.square_list_fill
          : CupertinoIcons.square_list,
      'filter' => active
          ? CupertinoIcons.square_grid_2x2_fill
          : CupertinoIcons.square_grid_2x2,
      'news' || 'tasks' || 'art' =>
        active ? CupertinoIcons.doc_text_fill : CupertinoIcons.doc_text,
      'profile' =>
        active ? CupertinoIcons.person_fill : CupertinoIcons.person,
      _ => active ? CupertinoIcons.circle_fill : CupertinoIcons.circle,
    };
  }

  bool get _onDarkChromeTab {
    final id = _tabs[_index.clamp(0, _tabs.length - 1)].id;
    // 首页 / 我的顶栏偏深色，状态栏图标用浅色
    return id == 'home' || id == 'profile';
  }

  SystemUiOverlayStyle _overlayStyle(bool dark) {
    final lightIcons = dark || _onDarkChromeTab;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          lightIcons ? Brightness.light : Brightness.dark,
      statusBarBrightness: lightIcons ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [for (final t in _tabs) _pageFor(t.id)];
    final glassTabs = [for (final t in _tabs) _glassTab(t)];

    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final dark = ThemeController.instance.isDark;
        final style = ThemeController.instance.uiStyle;
        final page = dark ? AppColors.pageDark : AppColors.white;
        final unselected =
            dark ? const Color(0xFFE8E8E8) : const Color(0xFF000000);
        final glassBar =
            dark ? const Color(0xCC1C1C1E) : const Color(0xCCF5F5F7);
        final glassIndicator =
            dark ? const Color(0x66FFFFFF) : const Color(0x99FFFFFF);
        final indicator =
            dark ? const Color(0x33FFFFFF) : const Color(0x1A000000);
        final accent = AppColors.brand;

        final body = Material(
          type: MaterialType.transparency,
          child: IndexedStack(
            index: _index.clamp(0, pages.length - 1),
            children: pages,
          ),
        );

        Widget shell;
        switch (style) {
          case AppUiStyle.glass:
            shell = GlassScaffold(
              background: ColoredBox(color: page),
              backgroundColor: page,
              statusBarStyle: GlassStatusBarStyle.none,
              bottomBarHeight: 100,
              body: body,
              bottomBar: TourTarget(
                id: 'tour_nav',
                child: GlassTabBar.bottom(
                tabs: glassTabs,
                selectedIndex: _index.clamp(0, glassTabs.length - 1),
                onTabSelected: _onTabSelected,
                selectedIconColor: accent,
                selectedLabelColor: accent,
                unselectedIconColor: unselected,
                unselectedLabelColor: unselected,
                showIndicator: true,
                indicatorColor: indicator,
                glowOpacity: 0,
                glowBlurRadius: 0,
                glowSpreadRadius: 0,
                interactionGlowRadius: 0,
                magnification: 1.08,
                interactionBehavior: GlassInteractionBehavior.full,
                pressScale: 1.03,
                horizontalPadding: glassTabs.length > 5 ? 8 : 16,
                verticalPadding: 10,
                barHeight: 64,
                quality: GlassQuality.minimal,
                settings: LiquidGlassSettings(
                  thickness: 20,
                  blur: 24,
                  chromaticAberration: 0.01,
                  lightIntensity: dark ? 0.35 : 0.6,
                  ambientStrength: dark ? 0.15 : 0.25,
                  refractiveIndex: 1.15,
                  saturation: 1.0,
                  glassColor: glassBar,
                ),
                indicatorSettings: LiquidGlassSettings(
                  thickness: 12,
                  blur: 16,
                  chromaticAberration: 0.01,
                  lightIntensity: dark ? 0.3 : 0.5,
                  ambientStrength: dark ? 0.12 : 0.2,
                  refractiveIndex: 1.12,
                  saturation: 1.0,
                  glassColor: glassIndicator,
                ),
                selectedLabelStyle: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: glassTabs.length > 5 ? 10 : 11,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
                unselectedLabelStyle: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: glassTabs.length > 5 ? 10 : 11,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
              ),
            );
          case AppUiStyle.material3:
          case AppUiStyle.flat:
            shell = Scaffold(
              backgroundColor: page,
              // 扁平/M3：内容沉浸到状态栏下，避免顶部白条
              body: body,
              bottomNavigationBar: TourTarget(
                id: 'tour_nav',
                child: NavigationBar(
                height: style == AppUiStyle.material3 ? 72 : 64,
                backgroundColor:
                    dark ? const Color(0xFF1C1C1E) : Colors.white,
                indicatorColor: accent.withValues(
                  alpha: style == AppUiStyle.material3 ? 0.20 : 0.14,
                ),
                selectedIndex: _index.clamp(0, _tabs.length - 1),
                onDestinationSelected: _onTabSelected,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (final t in _tabs)
                    NavigationDestination(
                      icon: Icon(_tabIcon(t.id, false)),
                      selectedIcon: Icon(
                        _tabIcon(t.id, true),
                        color: accent,
                      ),
                      label: t.label,
                    ),
                ],
              ),
              ),
            );
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _overlayStyle(dark),
          child: ColoredBox(color: page, child: shell),
        );
      },
    );
  }
}
