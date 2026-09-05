import 'package:flutter/material.dart';

/// 品牌字持续「日照」扫光（首页顶栏等）
class BrandSunlightText extends StatefulWidget {
  const BrandSunlightText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 2200),
  });

  final String text;
  final TextStyle style;
  final Duration duration;

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
    final base = widget.style.color ?? const Color(0xFF00B8C0);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        // 光带从左到右循环扫过
        final x = (t * 2.4) - 0.7;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(x - 0.55, -0.2),
              end: Alignment(x + 0.55, 0.2),
              colors: [
                base,
                Color.lerp(base, Colors.white, 0.72)!,
                base.withValues(alpha: 0.92),
                Color.lerp(base, const Color(0xFFFFF6D0), 0.55)!,
                base,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ).createShader(bounds);
          },
          child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
        );
      },
    );
  }
}
