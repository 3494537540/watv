import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
/// 长按快进提示：显示实际倍率
class PlayerHoldBoostHud extends StatefulWidget {
  const PlayerHoldBoostHud({super.key, required this.rate});

  final double rate;

  @override
  State<PlayerHoldBoostHud> createState() => _PlayerHoldBoostHudState();
}

class _PlayerHoldBoostHudState extends State<PlayerHoldBoostHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _label {
    final r = widget.rate;
    if (r == r.roundToDouble()) return '${r.toInt()}x 快进中';
    return '${r}x 快进中';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 16,
                child: CustomPaint(
                  painter: _ChevronPainter(t: _ctrl.value),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _label,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  shadows: [
                    Shadow(color: Color(0x88000000), blurRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.28) % 1.0;
      final alpha = 0.3 + 0.7 * phase;
      paint.color = AppColors.brand.withValues(alpha: alpha);

      final x = 4.0 + i * 10.0;
      final path = Path()
        ..moveTo(x, 2)
        ..lineTo(x + 6, size.height / 2)
        ..lineTo(x, size.height - 2);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// ±10s / 滑动进度提示
class PlayerSeekHintChip extends StatelessWidget {
  const PlayerSeekHintChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'AppSans',
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(color: Color(0x88000000), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}
