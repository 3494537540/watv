import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/theme_controller.dart';

/// 统一按压缩放：列表/海报/按钮点下去会「活」一点。
/// 尊重 [ThemeController.motionEnabled]；关闭动效时仅保留点击。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.haptic = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _setDown(bool v) {
    if (!widget.enabled) return;
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final motion = ThemeController.instance.motionEnabled && widget.enabled;
        final dur = ThemeController.instance.scaled(
          const Duration(milliseconds: 120),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setDown(true),
          onTapUp: (_) => _setDown(false),
          onTapCancel: () => _setDown(false),
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.haptic) HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          child: AnimatedScale(
            scale: motion && _down ? widget.scale : 1,
            duration: dur == Duration.zero
                ? const Duration(milliseconds: 1)
                : dur,
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// 海报 → 详情 共享元素 tag
String moviePosterHeroTag(String movieId) => 'poster_$movieId';
