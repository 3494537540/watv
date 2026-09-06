import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

/// 播放顶栏：当前时间 + 横向电量图标（百分比画在电池壳内）
class PlayerSysStatus extends StatefulWidget {
  const PlayerSysStatus({super.key, this.compact = false});

  final bool compact;

  @override
  State<PlayerSysStatus> createState() => _PlayerSysStatusState();
}

class _PlayerSysStatusState extends State<PlayerSysStatus> {
  final _battery = Battery();
  Timer? _timer;
  String _time = '';
  int? _level;
  BatteryState _state = BatteryState.unknown;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    var level = _level;
    var state = _state;
    try {
      level = await _battery.batteryLevel;
      state = await _battery.batteryState;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _time = '$hh:$mm';
      _level = level;
      _state = state;
    });
  }

  bool get _charging =>
      _state == BatteryState.charging || _state == BatteryState.full;

  bool get _low => (_level ?? 100) <= 20 && !_charging;

  Color get _fg {
    if (_charging) return const Color(0xFF64D2FF);
    if (_low) return const Color(0xFFFF9F0A);
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final lv = (_level ?? 100).clamp(0, 100);
    final style = TextStyle(
      fontFamily: 'AppSans',
      fontSize: widget.compact ? 11 : 12,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: const [
        Shadow(color: Color(0xCC000000), blurRadius: 4),
      ],
    );
    // 壳体加宽，容纳壳内百分比文字
    final batW = widget.compact ? 34.0 : 40.0;
    final batH = widget.compact ? 14.0 : 16.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(_time.isEmpty ? '--:--' : _time, style: style),
        SizedBox(width: widget.compact ? 6 : 8),
        SizedBox(
          width: batW + 3,
          height: batH,
          child: CustomPaint(
            painter: _HorizontalBatteryPainter(
              level: lv / 100.0,
              color: _fg,
              charging: _charging,
              percentLabel: '$lv',
            ),
          ),
        ),
      ],
    );
  }
}

/// 横向电池：左侧壳体 + 右侧小凸起；百分比文字在壳内
class _HorizontalBatteryPainter extends CustomPainter {
  _HorizontalBatteryPainter({
    required this.level,
    required this.color,
    required this.charging,
    required this.percentLabel,
  });

  final double level;
  final Color color;
  final bool charging;
  final String percentLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final bodyW = size.width - 2.8;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.7, 0.7, bodyW - 1.4, size.height - 1.4),
      const Radius.circular(2.6),
    );
    canvas.drawRRect(body, stroke);

    final tip = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyW, size.height * 0.28, 2.4, size.height * 0.44),
      const Radius.circular(0.8),
    );
    canvas.drawRRect(tip, Paint()..color = color);

    final fillW = (bodyW - 3.6) * level.clamp(0.08, 1.0);
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(2.0, 2.0, fillW, size.height - 4.0),
      const Radius.circular(1.4),
    );
    canvas.drawRRect(
      fill,
      Paint()..color = color.withValues(alpha: charging ? 0.42 : 0.32),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: percentLabel,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: size.height * 0.72,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: bodyW - 4);
    tp.paint(
      canvas,
      Offset(
        (bodyW - tp.width) / 2,
        (size.height - tp.height) / 2,
      ),
    );

    if (charging) {
      final cx = bodyW * 0.18;
      final cy = size.height * 0.5;
      final bolt = Path()
        ..moveTo(cx + 1.0, cy - 2.6)
        ..lineTo(cx - 1.2, cy + 0.3)
        ..lineTo(cx + 0.15, cy + 0.3)
        ..lineTo(cx - 1.0, cy + 2.6)
        ..lineTo(cx + 1.2, cy - 0.3)
        ..lineTo(cx - 0.15, cy - 0.3)
        ..close();
      canvas.drawPath(
        bolt,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HorizontalBatteryPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.color != color ||
      oldDelegate.charging != charging ||
      oldDelegate.percentLabel != percentLabel;
}
