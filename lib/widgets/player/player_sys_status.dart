import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 播放顶栏：当前时间 + 电量（百分比在电池图标内）
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

  /// 描边/填充：常态白，充电青柠，低电橙红
  Color get _batColor {
    if (_charging) return const Color(0xFF64D2FF);
    if (_low) return const Color(0xFFFF9F0A);
    return Colors.white;
  }

  Color get _textInBat {
    if (_charging) return const Color(0xFF003547);
    if (_low) return const Color(0xFF3A1A00);
    return const Color(0xFF111111);
  }

  @override
  Widget build(BuildContext context) {
    final lv = (_level ?? 100).clamp(0, 100);
    final timeStyle = TextStyle(
      fontFamily: 'AppSans',
      fontSize: widget.compact ? 12 : 13,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: const [
        Shadow(color: Color(0xCC000000), blurRadius: 5),
      ],
    );

    final batW = widget.compact ? 34.0 : 38.0;
    final batH = widget.compact ? 16.0 : 18.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_time.isEmpty ? '--:--' : _time, style: timeStyle),
        SizedBox(width: widget.compact ? 6 : 8),
        SizedBox(
          width: batW + 3,
          height: batH,
          child: CustomPaint(
            painter: _BatteryPainter(
              level: lv / 100.0,
              color: _batColor,
              charging: _charging,
              low: _low,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 2.5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_charging)
                      Icon(
                        CupertinoIcons.bolt_fill,
                        size: widget.compact ? 8 : 9,
                        color: _textInBat,
                      ),
                    Text(
                      '$lv',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: widget.compact ? 9 : 10,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        color: _textInBat,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter({
    required this.level,
    required this.color,
    required this.charging,
    required this.low,
  });

  final double level;
  final Color color;
  final bool charging;
  final bool low;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final bodyW = size.width - 3;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.8, 0.8, bodyW - 1.6, size.height - 1.6),
      const Radius.circular(2.8),
    );
    canvas.drawRRect(body, stroke);
    final tip = RRect.fromRectAndRadius(
      Rect.fromLTWH(bodyW, size.height * 0.28, 2.8, size.height * 0.44),
      const Radius.circular(1),
    );
    canvas.drawRRect(tip, Paint()..color = color);

    final fillW = (bodyW - 4.2) * level.clamp(0.08, 1.0);
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTWH(2.4, 2.6, fillW, size.height - 5.2),
      const Radius.circular(1.6),
    );
    final fillColor = charging || low
        ? color.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.92);
    canvas.drawRRect(fill, Paint()..color = fillColor);
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.color != color ||
      oldDelegate.charging != charging ||
      oldDelegate.low != low;
}
