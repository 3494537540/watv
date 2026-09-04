import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'figma_loading.dart';

/// App 下拉刷新：用户指定 Lottie 加载动画。
class AppPullRefresh extends StatelessWidget {
  const AppPullRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
    this.edgeOffset = 0,
    this.onDark = false,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final Color? color;
  final double edgeOffset;
  /// 首页沉浸 Banner 等深色背景
  final bool onDark;

  static const _armed = 72.0;

  @override
  Widget build(BuildContext context) {
    return CustomRefreshIndicator(
      onRefresh: onRefresh,
      offsetToArmed: _armed,
      leadingScrollIndicatorVisible: false,
      trailingScrollIndicatorVisible: false,
      child: child,
      builder: (context, child, controller) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final v = controller.value.clamp(0.0, 1.25);
            final refreshing = controller.isLoading || controller.isComplete;
            final show = v > 0.04 || refreshing;
            final shift = refreshing
                ? _armed * 0.7
                : (_armed * 0.58) * v.clamp(0.0, 1.0);
            final top = edgeOffset + 8 + (_armed * 0.26) * v.clamp(0.0, 1.0);
            final ball = 48.0 + 12.0 * v.clamp(0.0, 1.0);
            final tint = onDark ? Colors.white : (color ?? AppColors.brand);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Transform.translate(
                  offset: Offset(0, shift),
                  child: child,
                ),
                if (show)
                  Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: refreshing
                              ? 1
                              : (v * 1.35).clamp(0.0, 1.0),
                          child: AppLoadingIndicator(
                            size: ball,
                            color: tint,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
