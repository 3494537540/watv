import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../player/danmaku_store.dart';
import '../../player/player_danmaku_prefs.dart';

/// 按播放进度绘制滚动弹幕（CustomPainter，降低卡顿）
class PlayerDanmakuLayer extends StatefulWidget {
  const PlayerDanmakuLayer({
    super.key,
    required this.items,
    required this.positionSec,
    required this.enabled,
    required this.prefs,
    this.playing = true,
  });

  final List<DanmakuItem> items;
  final double positionSec;
  final bool enabled;
  final DanmakuDisplayPrefs prefs;
  final bool playing;

  @override
  State<PlayerDanmakuLayer> createState() => _PlayerDanmakuLayerState();
}

class _PlayerDanmakuLayerState extends State<PlayerDanmakuLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _smoothPos = 0;
  int _lastTickMs = 0;
  int _lastPaintMs = 0;
  final _widthCache = <int, double>{};

  static const _minPaintIntervalMs = 48; // ~20fps

  @override
  void initState() {
    super.initState();
    _smoothPos = widget.positionSec;
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;
    _ticker = createTicker((_) {
      if (!mounted || !widget.enabled || widget.items.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = ((now - _lastTickMs) / 1000.0).clamp(0.0, 0.05);
      _lastTickMs = now;
      final target = widget.positionSec;
      final gap = target - _smoothPos;
      if (gap.abs() > 0.8) {
        _smoothPos = target;
      } else if (widget.playing) {
        _smoothPos += gap * 0.35 + dt;
        if (_smoothPos > target + 0.08) _smoothPos = target + 0.08;
      } else {
        _smoothPos = target;
      }
      if (now - _lastPaintMs < _minPaintIntervalMs) return;
      _lastPaintMs = now;
      setState(() {});
    })
      ..start();
  }

  @override
  void didUpdateWidget(covariant PlayerDanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.positionSec - oldWidget.positionSec).abs() > 1.0) {
      _smoothPos = widget.positionSec;
    }
    if (oldWidget.prefs.fontSize != widget.prefs.fontSize) {
      _widthCache.clear();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _measure(String text, double fontSize) {
    final key = Object.hash(text, fontSize.round());
    final cached = _widthCache[key];
    if (cached != null) return cached;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    if (_widthCache.length > 800) _widthCache.clear();
    _widthCache[key] = w;
    return w;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.items.isEmpty) {
      return const SizedBox.shrink();
    }
    return CustomPaint(
      painter: _DanmakuPainter(
        items: widget.items,
        pos: _smoothPos - widget.prefs.timeOffsetSec,
        prefs: widget.prefs,
        measure: _measure,
      ),
      child: const SizedBox.expand(),
    );
  }
}

typedef _MeasureFn = double Function(String text, double fontSize);

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.items,
    required this.pos,
    required this.prefs,
    required this.measure,
  });

  final List<DanmakuItem> items;
  final double pos;
  final DanmakuDisplayPrefs prefs;
  final _MeasureFn measure;

  static const _baseFlightSec = 8.0;

  int _lowerBound(double t) {
    var lo = 0;
    var hi = items.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (items[mid].timeSec < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  (double, double) _areaBand(double h) {
    return switch (prefs.area) {
      DanmakuArea.top => (h * 0.04, h * 0.42),
      DanmakuArea.full => (h * 0.04, h * 0.72),
      DanmakuArea.bottom => (h * 0.52, h * 0.40),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final flightSec = (_baseFlightSec / prefs.speed).clamp(3.5, 16.0);
    final fontSize = prefs.fontSize;
    final opacity = prefs.opacity;
    final band = _areaBand(h);
    final areaTop = band.$1;
    final areaH = band.$2;
    final trackH = max(fontSize + 6, min(32.0, areaH * 0.16));
    final maxTracks = max(2, (areaH / trackH).floor());
    final tracks = min(maxTracks, max(2, (6 * prefs.density).round()));
    final laneGap = (0.55 / prefs.density).clamp(0.25, 1.2);
    final maxDraw = (18 * prefs.density).round().clamp(8, 28);

    final from = pos - flightSec - 0.2;
    final to = pos + 0.05;
    final start = _lowerBound(from);
    final laneBusyUntil = List<double>.filled(tracks, -999);
    var drawn = 0;

    for (var i = start; i < items.length && drawn < maxDraw; i++) {
      final item = items[i];
      if (item.timeSec > to) break;
      if (item.timeSec < from) continue;
      final age = pos - item.timeSec;
      if (age < 0) continue;

      final fs = fontSize + (item.self ? 1.0 : 0.0);
      final textW = measure(item.text, fs);
      final travel = w + textW + 16;
      final x = w - (age / flightSec) * travel;
      if (x + textW < -8 || x > w + 8) continue;

      final track =
          (item.text.hashCode.abs() + (item.timeSec * 10).round()) % tracks;
      if (item.timeSec < laneBusyUntil[track] && !item.self) continue;
      laneBusyUntil[track] = item.timeSec + laneGap;

      final color = Color(item.color | 0xFF000000).withValues(alpha: opacity);
      final tp = TextPainter(
        text: TextSpan(
          text: item.text,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: fs,
            fontWeight: FontWeight.w700,
            color: color,
            shadows: [
              Shadow(
                color: Color.fromRGBO(0, 0, 0, 0.85 * opacity),
                blurRadius: 2.5,
                offset: const Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      tp.paint(canvas, Offset(x, areaTop + track * trackH));
      drawn++;
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter old) {
    return old.pos != pos ||
        old.items != items ||
        old.prefs != prefs;
  }
}
