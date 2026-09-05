import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../state/theme_controller.dart';

/// 按设置切换的页面路由（替代 CupertinoPageRoute）
///
/// 在 Cupertino 过渡下走官方 [CupertinoRouteTransitionMixin.buildPageTransitions]，
/// 以恢复 iOS 左侧边缘侧滑返回。
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
    bool maintainState = true,
  }) : super(
          settings: settings,
          fullscreenDialog: fullscreenDialog,
          maintainState: maintainState,
          transitionDuration: ThemeController.instance.transitionDuration,
          reverseTransitionDuration: ThemeController.instance.transitionDuration,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          // 实际过渡在 [buildTransitions]；此处占位即可
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        );

  /// 与 [CupertinoPageRoute] 对齐，保证 iOS 左缘侧滑可用
  @override
  bool get popGestureEnabled {
    if (fullscreenDialog) return false;
    if (isFirst) return false;
    if (animation?.status != AnimationStatus.completed) return false;
    if (secondaryAnimation?.status != AnimationStatus.dismissed) return false;
    if (navigator?.userGestureInProgress ?? false) return false;
    // 有 PopScope(canPop:false) 时系统手势会被禁；页面侧用 IosEdgeBack 补
    if (popDisposition == RoutePopDisposition.doNotPop) return false;
    return ThemeController.instance.pageTransition ==
            AppPageTransition.cupertino &&
        ThemeController.instance.motionEnabled;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _buildTransition(
      route: this,
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
      fullscreenDialog: fullscreenDialog,
    );
  }

  static Widget _buildTransition<T>({
    required PageRoute<T> route,
    required BuildContext context,
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Widget child,
    required bool fullscreenDialog,
  }) {
    final tc = ThemeController.instance;
    if (!tc.motionEnabled ||
        tc.pageTransition == AppPageTransition.none) {
      return child;
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    switch (tc.pageTransition) {
      case AppPageTransition.none:
        return child;
      case AppPageTransition.cupertino:
        // 含 _CupertinoBackGestureDetector，侧滑返回与系统一致
        return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
      case AppPageTransition.fade:
        return FadeTransition(opacity: curved, child: child);
      case AppPageTransition.slideUp:
        return SlideTransition(
          position: Tween<Offset>(
            begin: fullscreenDialog
                ? const Offset(0, 1)
                : const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      case AppPageTransition.zoom:
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      case AppPageTransition.slide:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
    }
  }
}

/// Material 主题用的页面过渡构建器
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppPageRoute._buildTransition(
      route: route,
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
      fullscreenDialog: route.fullscreenDialog,
    );
  }
}
