import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/theme_controller.dart';

/// 统一页面路由：基于 [CupertinoPageRoute]，保证 iOS 左缘侧滑与顶栏返回可用。
class AppPageRoute<T> extends CupertinoPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog = false,
    super.maintainState = true,
    super.title,
  });

  bool get _iosLike =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Duration get transitionDuration {
    final d = ThemeController.instance.transitionDuration;
    // Duration.zero 会破坏侧滑手势状态机
    if (d == Duration.zero) {
      return const Duration(milliseconds: 1);
    }
    return d;
  }

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  /// iOS / macOS 始终允许边缘返回（除非 fullscreenDialog / 不可 pop）
  @override
  bool get popGestureEnabled {
    if (fullscreenDialog) return false;
    if (isFirst) return false;
    if (animation?.status != AnimationStatus.completed) return false;
    if (secondaryAnimation?.status != AnimationStatus.dismissed) return false;
    if (navigator?.userGestureInProgress ?? false) return false;
    if (popDisposition == RoutePopDisposition.doNotPop) return false;
    // iOS：动效关闭时仍允许侧滑返回
    if (_iosLike) return true;
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
    final tc = ThemeController.instance;

    // iOS：强制 Cupertino 过渡，保证系统级侧滑 + NavigationBar 返回键
    if (_iosLike) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    if (!tc.motionEnabled || tc.pageTransition == AppPageTransition.none) {
      return child;
    }

    if (tc.pageTransition == AppPageTransition.cupertino) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    return _buildCustomTransition(
      animation: animation,
      child: child,
      fullscreenDialog: fullscreenDialog,
      style: tc.pageTransition,
    );
  }

  static Widget _buildCustomTransition({
    required Animation<double> animation,
    required Widget child,
    required bool fullscreenDialog,
    required AppPageTransition style,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    switch (style) {
      case AppPageTransition.none:
      case AppPageTransition.cupertino:
        return child;
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

/// Material 默认路由过渡：iOS 用系统 Cupertino，其它平台跟随设置
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
    final iosLike = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (iosLike) {
      return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    final style = ThemeController.instance.pageTransition;
    if (style == AppPageTransition.cupertino) {
      return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return AppPageRoute._buildCustomTransition(
      animation: animation,
      child: child,
      fullscreenDialog: route.fullscreenDialog,
      style: style,
    );
  }
}
