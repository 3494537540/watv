import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

/// 左右边缘竖滑：左亮度 / 右音量，带 HUD 提示
class PlayerEdgeGestures extends StatefulWidget {
  const PlayerEdgeGestures({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<PlayerEdgeGestures> createState() => _PlayerEdgeGesturesState();
}

class _PlayerEdgeGesturesState extends State<PlayerEdgeGestures> {
  _HudKind? _hud;
  double _hudValue = 0;
  bool _volumeInited = false;

  @override
  void initState() {
    super.initState();
    _initVolume();
  }

  Future<void> _initVolume() async {
    try {
      VolumeController.instance.showSystemUI = false;
      _volumeInited = true;
    } catch (_) {}
  }

  Future<void> _onBrightnessDrag(double delta, double height) async {
    if (height <= 0) return;
    try {
      final b = await ScreenBrightness().application;
      final next = (b + delta / height * 1.2).clamp(0.05, 1.0);
      await ScreenBrightness().setApplicationScreenBrightness(next);
      if (!mounted) return;
      setState(() {
        _hud = _HudKind.brightness;
        _hudValue = next;
      });
    } catch (_) {}
  }

  Future<void> _onVolumeDrag(double delta, double height) async {
    if (height <= 0 || !_volumeInited) return;
    try {
      final v = await VolumeController.instance.getVolume();
      final next = (v - delta / height * 1.2).clamp(0.0, 1.0);
      await VolumeController.instance.setVolume(next);
      if (!mounted) return;
      setState(() {
        _hud = _HudKind.volume;
        _hudValue = next;
      });
    } catch (_) {}
  }

  void _clearHud() {
    if (_hud != null) {
      setState(() => _hud = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final edge = w * 0.32;

        Widget edgeZone({
          required Alignment alignment,
          required Future<void> Function(double delta) onDrag,
        }) {
          return Align(
            alignment: alignment,
            child: SizedBox(
              width: edge,
              height: h,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
                onVerticalDragEnd: (_) => _clearHud(),
                onVerticalDragCancel: _clearHud,
              ),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (widget.enabled) ...[
              edgeZone(
                alignment: Alignment.centerLeft,
                onDrag: (dy) => _onBrightnessDrag(-dy, h),
              ),
              edgeZone(
                alignment: Alignment.centerRight,
                onDrag: (dy) => _onVolumeDrag(dy, h),
              ),
            ],
            if (_hud != null)
              Center(
                child: _GestureHud(kind: _hud!, value: _hudValue),
              ),
          ],
        );
      },
    );
  }
}

enum _HudKind { brightness, volume }

class _GestureHud extends StatelessWidget {
  const _GestureHud({required this.kind, required this.value});

  final _HudKind kind;
  final double value;

  @override
  Widget build(BuildContext context) {
    final icon = kind == _HudKind.brightness
        ? CupertinoIcons.sun_max_fill
        : CupertinoIcons.speaker_2_fill;
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              fontFamily: 'AppSans',
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
