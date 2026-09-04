import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../state/theme_controller.dart';

/// 按设置切换的页面路由（替代 CupertinoPageRoute）
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
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _buildTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              child: child,
              fullscreenDialog: fullscreenDialog,
            );
          },
        );

  static Widget _buildTransition({
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
        return CupertinoPageTransition(
          primaryRouteAnimation: animation,
          secondaryRouteAnimation: secondaryAnimation,
          linearTransition: false,
          child: child,
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
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
      fullscreenDialog: route.fullscreenDialog,
    );
  }
}
