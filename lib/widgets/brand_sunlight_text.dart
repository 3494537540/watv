import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 品牌字持续「日照」扫光（首页顶栏等）
///
/// 深色字：扫过偏白/暖黄高光；浅色/白字：扫过系统品牌强调色，避免白上加白看不见。
class BrandSunlightText extends StatefulWidget {
  const BrandSunlightText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 2200),
    /// 扫光高光色；默认跟设置里的系统配色 [AppColors.brand]
    this.highlightColor,
  });

  final String text;
  final TextStyle style;
  final Duration duration;
  final Color? highlightColor;

  @override
  State<BrandSunlightText> createState() => _BrandSunlightTextState();
}

class _BrandSunlightTextState extends State<BrandSunlightText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant BrandSunlightText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _ctrl
        ..duration = widget.duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style.color ?? AppColors.brand;
    final accent = widget.highlightColor ?? AppColors.brand;
    // 白字 / 近白字时不能再往白插值，否则日照消失
    final lightBase = base.computeLuminance() > 0.72;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        // 光带从左到右循环扫过
        final x = (t * 2.4) - 0.7;
        final List<Color> colors;
        if (lightBase) {
          final mid = Color.lerp(base, accent, 0.82)!;
          final soft = Color.lerp(base, accent, 0.42)!;
          colors = [
            base,
            soft,
            mid,
            Color.lerp(accent, Colors.white, 0.28)!,
            soft,
            base,
          ];
        } else {
          colors = [
            base,
            Color.lerp(base, Colors.white, 0.72)!,
            base.withValues(alpha: 0.92),
            Color.lerp(base, const Color(0xFFFFF6D0), 0.55)!,
            base,
          ];
        }
        final stops = lightBase
            ? const [0.0, 0.28, 0.45, 0.55, 0.72, 1.0]
            : const [0.0, 0.35, 0.5, 0.65, 1.0];

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(x - 0.55, -0.2),
              end: Alignment(x + 0.55, 0.2),
              colors: colors,
              stops: stops,
            ).createShader(bounds);
          },
          child: Text(
            widget.text,
            style: widget.style.copyWith(color: Colors.white),
          ),
        );
      },
    );
  }
}
