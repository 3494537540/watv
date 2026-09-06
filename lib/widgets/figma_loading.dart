import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../state/theme_controller.dart';
import '../theme/app_colors.dart';

/// 骨架：白底中性灰
abstract final class FigmaSkeletonColors {
  static const bg = Color(0xFFFFFFFF);
  static const bone = Color(0xFFE8E9ED);
  static const icon = Color(0xFFC0C3CB);
  /// 默认加载色（兼容旧调用）
  static Color get blob => AppColors.brand;
  static const blobSoft = Color(0xFF0E9AA1);
  /// Banner 暗底上的浅色环
  static const blobOnDark = Color(0xFFF2F4F7);
  static const blobOnDarkSoft = Color(0xFFAEAEB2);

  static Color pageOf(BuildContext context) => AppPalette.page(context);
  static Color boneOf(BuildContext context) => AppPalette.isDark(context)
      ? const Color(0xFF2C2C2E)
      : bone;
  static Color iconOf(BuildContext context) => AppPalette.isDark(context)
      ? const Color(0xFF636366)
      : icon;
}

/// 四大主页统一全页加载（跟随设置「加载动画」）
class WatvPageLoader extends StatelessWidget {
  const WatvPageLoader({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppLoadingIndicator(
        size: size,
        color: AppColors.brand,
      ),
    );
  }
}

/// 页面加载：跟随设置里的「加载动画」
class FigmaMetaballLoader extends StatelessWidget {
  const FigmaMetaballLoader({
    super.key,
    this.size = 88,
    this.color,
    this.softColor = FigmaSkeletonColors.blobSoft,
  });

  static const asset = 'assets/lottie/loading_spinner.json';

  final double size;
  final Color? color;
  final Color softColor;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brand;
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return AppLoadingIndicator(
          size: size,
          color: c,
          style: ThemeController.instance.loadingStyle,
        );
      },
    );
  }
}

/// 可切换的全局加载指示器
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.style,
  });

  final double size;
  final Color? color;
  final AppLoadingStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.brand;
    final s = style ?? ThemeController.instance.loadingStyle;
    return SizedBox(
      width: size,
      height: size,
      child: switch (s) {
        AppLoadingStyle.spinner => Lottie.asset(
            FigmaMetaballLoader.asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            repeat: true,
            delegates: LottieDelegates(
              values: [
                ValueDelegate.color(const ['**'], value: c),
                ValueDelegate.strokeColor(const ['**'], value: c),
              ],
            ),
          ),
        AppLoadingStyle.ring => Padding(
            padding: EdgeInsets.all(size * 0.18),
            child: CircularProgressIndicator(
              strokeWidth: math.max(2.5, size * 0.07),
              color: c,
            ),
          ),
        AppLoadingStyle.dots => _DotsLoader(size: size, color: c),
        AppLoadingStyle.pulse => _PulseLoader(size: size, color: c),
        AppLoadingStyle.cupertino => Center(
            child: CupertinoActivityIndicator(color: c, radius: size * 0.22),
          ),
      },
    );
  }
}

class _DotsLoader extends StatefulWidget {
  const _DotsLoader({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  State<_DotsLoader> createState() => _DotsLoaderState();
}

class _DotsLoaderState extends State<_DotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size * 0.18;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: widget.size * 0.08),
              Transform.translate(
                offset: Offset(
                  0,
                  -math.sin((_ctrl.value * 2 * math.pi) + i * 0.9) *
                      widget.size *
                      0.12,
                ),
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(
                      alpha: 0.45 +
                          0.55 *
                              ((math.sin((_ctrl.value * 2 * math.pi) +
                                          i * 0.9) +
                                      1) /
                                  2),
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PulseLoader extends StatefulWidget {
  const _PulseLoader({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  State<_PulseLoader> createState() => _PulseLoaderState();
}

class _PulseLoaderState extends State<_PulseLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Center(
          child: Transform.scale(
            scale: 0.55 + 0.45 * t,
            child: Container(
              width: widget.size * 0.42,
              height: widget.size * 0.42,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.25 + 0.55 * t),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 骨架呼吸 + 扫光（首页 / 观看历史共用，动效要肉眼可见）
class FigmaSkeletonPulse extends StatefulWidget {
  const FigmaSkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<FigmaSkeletonPulse> createState() => _FigmaSkeletonPulseState();
}

class _FigmaSkeletonPulseState extends State<FigmaSkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = _ctrl.value;
        // 明暗呼吸：0.38 ↔ 1.0，灰底上也看得出来
        final breathe = 0.38 + 0.62 * (0.5 - 0.5 * math.cos(t * math.pi * 2));
        // 横向扫光
        final slide = (t * 2) - 0.5;
        return Opacity(
          opacity: breathe,
          child: ClipRect(
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(slide - 1.1, 0),
                          end: Alignment(slide + 0.2, 0),
                          colors: const [
                            Color(0x00FFFFFF),
                            Color(0xB3FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class FigmaSkeletonBone extends StatelessWidget {
  const FigmaSkeletonBone({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
    this.color = FigmaSkeletonColors.bone,
  });

  final double? width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 首页同款媒体占位：灰底 + 山峰图标（骨架/封面加载共用）
class FigmaCoverPlaceholder extends StatelessWidget {
  const FigmaCoverPlaceholder({
    super.key,
    this.iconSize = 32,
    this.radius = 0,
  });

  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final child = ColoredBox(
      color: FigmaSkeletonColors.boneOf(context),
      child: Center(
        child: Icon(
          Icons.landscape_rounded,
          size: iconSize,
          color: FigmaSkeletonColors.iconOf(context),
        ),
      ),
    );
    if (radius <= 0) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }
}

/// 上方两行骨条 + 圆角媒体区（山峰图标）
class FigmaMediaSkeletonCard extends StatelessWidget {
  const FigmaMediaSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaSkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FigmaSkeletonBone(height: 14, radius: 7),
          const SizedBox(height: 8),
          const FigmaSkeletonBone(width: 88, height: 12, radius: 6),
          const SizedBox(height: 12),
          const AspectRatio(
            aspectRatio: 16 / 9,
            child: FigmaCoverPlaceholder(iconSize: 36, radius: 12),
          ),
        ],
      ),
    );
  }
}

/// 首页列表加载：融球 + 双列骨架
class HomeListSkeleton extends StatelessWidget {
  const HomeListSkeleton({super.key, this.count = 6, this.showMetaball = false});

  final int count;
  final bool showMetaball;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppPalette.page(context),
      child: Column(
        children: [
          if (showMetaball)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 20, 14, 10),
              child: Center(
                child: FigmaMetaballLoader(size: 64),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: LayoutBuilder(
              builder: (context, c) {
                const gap = 10.0;
                final w = (c.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: 14,
                  children: [
                    for (var i = 0; i < count; i++)
                      SizedBox(width: w, child: const FigmaMediaSkeletonCard()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 竖海报三列骨架（片库）
class HomePosterGridSkeleton extends StatelessWidget {
  const HomePosterGridSkeleton({
    super.key,
    this.count = 9,
    this.showMetaball = false,
  });

  final int count;
  final bool showMetaball;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showMetaball)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Center(child: FigmaMetaballLoader(size: 56)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 0.52,
            ),
            itemBuilder: (_, _) => const FigmaPosterSkeletonCard(),
          ),
        ),
      ],
    );
  }
}

/// 竖海报骨架卡
class FigmaPosterSkeletonCard extends StatelessWidget {
  const FigmaPosterSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaSkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: FigmaCoverPlaceholder(iconSize: 32, radius: 10),
          ),
          const SizedBox(height: 8),
          const FigmaSkeletonBone(height: 12, radius: 6),
          const SizedBox(height: 6),
          const FigmaSkeletonBone(width: 56, height: 10, radius: 5),
        ],
      ),
    );
  }
}

/// 列表底部：上拉加载融球
class FigmaLoadMoreFooter extends StatelessWidget {
  const FigmaLoadMoreFooter({
    super.key,
    required this.loading,
    this.hasMore = true,
    this.idleText = '上拉加载更多',
    this.endText = '已经到底了',
  });

  final bool loading;
  final bool hasMore;
  final String idleText;
  final String endText;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: FigmaMetaballLoader(size: 48)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          hasMore ? idleText : endText,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 12,
            color: Color(0xFF9499A0),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Banner：中性暗底 + 浅色融球
class HomeBannerMetaballLoading extends StatelessWidget {
  const HomeBannerMetaballLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF2C2C2E),
      child: Center(
        child: FigmaMetaballLoader(
          size: 96,
          color: FigmaSkeletonColors.blobOnDark,
          softColor: Color(0xFF8E8E93),
        ),
      ),
    );
  }
}
