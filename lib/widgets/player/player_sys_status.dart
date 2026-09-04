import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 播放顶栏：当前时间 + 电量
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
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
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

  IconData get _batteryIcon {
    final charging = _state == BatteryState.charging ||
        _state == BatteryState.full;
    final lv = _level ?? 100;
    if (charging) return CupertinoIcons.battery_100;
    if (lv <= 15) return CupertinoIcons.battery_25;
    if (lv <= 40) return CupertinoIcons.battery_25;
    if (lv <= 70) return CupertinoIcons.battery_75_percent;
    return CupertinoIcons.battery_100;
  }

  @override
  Widget build(BuildContext context) {
    final lv = _level;
    final style = TextStyle(
      fontFamily: 'AppSans',
      fontSize: widget.compact ? 11 : 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: const [
        Shadow(color: Color(0x99000000), blurRadius: 4),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_time.isEmpty ? '--:--' : _time, style: style),
        const SizedBox(width: 8),
        Icon(
          _batteryIcon,
          size: widget.compact ? 14 : 15,
          color: Colors.white,
          shadows: const [
            Shadow(color: Color(0x99000000), blurRadius: 4),
          ],
        ),
        if (lv != null) ...[
          const SizedBox(width: 2),
          Text('$lv%', style: style),
        ],
      ],
    );
  }
}
