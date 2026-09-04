import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 单色波浪加载（白/冰蓝，不五颜六色）
class PlayerBufferSpinner extends StatefulWidget {
  const PlayerBufferSpinner({super.key, this.size = 56});

  final double size;

  @override
  State<PlayerBufferSpinner> createState() => _PlayerBufferSpinnerState();
}

class _PlayerBufferSpinnerState extends State<PlayerBufferSpinner>
    with SingleTickerProviderStateMixin {
  static const _barCount = 5;

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size * 0.72,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            size: Size(size, size * 0.72),
            painter: _MonoWavePainter(t: _ctrl.value, barCount: _barCount),
          );
        },
      ),
    );
  }
}

class _MonoWavePainter extends CustomPainter {
  _MonoWavePainter({required this.t, required this.barCount});

  final double t;
  final int barCount;

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width * 0.08;
    final gap = size.width * 0.05;
    final totalW = barCount * barW + (barCount - 1) * gap;
    var x = (size.width - totalW) / 2;
    final cy = size.height * 0.48;
    final minH = size.height * 0.22;
    final maxH = size.height * 0.88;

    for (var i = 0; i < barCount; i++) {
      final phase = t * 2 * math.pi + i * 0.5;
      final wave = 0.5 + 0.5 * math.sin(phase);
      final h = minH + (maxH - minH) * wave;
      final alpha = 0.45 + 0.55 * wave;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barW / 2, cy),
          width: barW,
          height: h,
        ),
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
      x += barW + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MonoWavePainter oldDelegate) =>
      oldDelegate.t != t;
}
