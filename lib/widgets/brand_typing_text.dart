import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 登录引导等场景的品牌字打字机效果
class BrandTypingText extends StatefulWidget {
  const BrandTypingText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
    this.delay = const Duration(milliseconds: 280),
    this.cursorColor,
  });

  final String text;
  final TextStyle style;
  final Duration duration;
  final Duration delay;
  final Color? cursorColor;

  @override
  State<BrandTypingText> createState() => _BrandTypingTextState();
}

class _BrandTypingTextState extends State<BrandTypingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void didUpdateWidget(covariant BrandTypingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.duration != widget.duration) {
      _ctrl
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      return Text(widget.text, style: widget.style);
    }
    final caret = widget.cursorColor ??
        widget.style.color ??
        AppColors.brand;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final n = widget.text.characters.length;
        final count = (_ctrl.value * n).floor().clamp(0, n);
        final shown = widget.text.characters.take(count).toString();
        final done = _ctrl.isCompleted;
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: shown, style: widget.style),
              if (!done)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: _BlinkCaret(
                      color: caret,
                      height: (widget.style.fontSize ?? 24) * 0.85,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BlinkCaret extends StatefulWidget {
  const _BlinkCaret({required this.color, required this.height});
  final Color color;
  final double height;

  @override
  State<_BlinkCaret> createState() => _BlinkCaretState();
}

class _BlinkCaretState extends State<_BlinkCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.15, end: 1.0).animate(_c),
      child: Container(
        width: 3,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
