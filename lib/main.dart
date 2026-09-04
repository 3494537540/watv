import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'services/app_security.dart';
import 'state/app_settings_controller.dart';
import 'state/auth_controller.dart';
import 'state/cms_auth_controller.dart';
import 'state/theme_controller.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_gate.dart';
import 'widgets/brand_splash.dart';
import 'widgets/dialogx/dialogx.dart';

void _disableDebugBorders() {
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugPaintPointersEnabled = false;
  debugRepaintRainbowEnabled = false;
  debugProfileBuildsEnabled = false;
  debugProfilePaintsEnabled = false;
  debugPaintLiquidGlassGeometry = false;
}

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  AppSecurity.instance.install();
  _disableDebugBorders();

  // 尽早开始初始化，与首帧绘制并行
  final boot = _initApp();

  runApp(_BootstrapApp(boot: boot));

  // 首帧后预缓存开屏图，缩短二次进入青底空等
  widgetsBinding.addPostFrameCallback((_) async {
    final ctx = widgetsBinding.rootElement;
    if (ctx == null) return;
    await Future.wait([
      precacheImage(const AssetImage('assets/images/splash_brand_stack.png'), ctx),
      precacheImage(const AssetImage('assets/images/splash_wa_plate.png'), ctx),
      precacheImage(const AssetImage('assets/images/splash_wordmark.png'), ctx),
    ]);
  });
}

Future<bool> _initApp() async {
  // LiquidGlass 最慢：最多等 500ms，超时先不包，后台继续
  final liquidFuture = () async {
    try {
      await LiquidGlassWidgets.initialize();
      return true;
    } catch (e, st) {
      debugPrint('LiquidGlass init skipped: $e\n$st');
      return false;
    }
  }();

  await Future.wait<void>([
    AppSettingsController.instance.bootstrap(),
    ThemeController.instance.bootstrap(),
    AuthController.instance.bootstrap(),
  ]);

  await CmsAuthController.instance.bootstrap(
    restoreSession: AppSettingsController.instance.autoLogin,
  );

  unawaited(AppSecurity.instance.refreshNativeProxyFlag());
  if (!kIsWeb) {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _applySystemUi(ThemeController.instance.isDark);
  }
  _disableDebugBorders();

  final liquidReady = await Future.any<bool>([
    liquidFuture,
    Future<bool>.delayed(const Duration(milliseconds: 480), () => false),
  ]);
  if (!liquidReady) {
    // 后台继续完成，不影响下次热更新；本次先不包以免拖启动
    unawaited(liquidFuture);
  }
  return liquidReady;
}

void _applySystemUi(bool dark) {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    ),
  );
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp({required this.boot});

  final Future<bool> boot;

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: widget.boot,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: BrandSplashView()),
          );
        }
        final liquidReady = snap.data ?? false;
        const app = WaTvApp();
        return liquidReady
            ? LiquidGlassWidgets.wrap(
                child: app,
                adaptiveQuality: true,
              )
            : app;
      },
    );
  }
}

class WaTvApp extends StatelessWidget {
  const WaTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final dark = ThemeController.instance.isDark;
        if (!kIsWeb) _applySystemUi(dark);
        _disableDebugBorders();
        return MaterialApp(
          title: '哇TV',
          navigatorKey: dialogXNavigatorKey,
          debugShowCheckedModeBanner: false,
          showSemanticsDebugger: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeController.instance.mode,
          builder: (context, child) {
            _disableDebugBorders();
            final motionOn = ThemeController.instance.motionEnabled;
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(disableAnimations: !motionOn),
              child: ClipRect(
                child: ColoredBox(
                  color: dark ? AppColors.pageDark : Colors.white,
                  child: Material(
                    type: MaterialType.transparency,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
          home: const AuthGate(),
        );
      },
    );
  }
}
