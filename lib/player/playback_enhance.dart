import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'player_settings_store.dart';

class PlaybackEnhance {
  PlaybackEnhance._();

  static List<double> matrixFor(PlayerEnhanceLevel level) {
    return switch (level) {
      PlayerEnhanceLevel.off => _identity,
      PlayerEnhanceLevel.mild => _compose(
          contrast: 1.06, saturation: 1.05, brightness: 0.012, clarity: 0.04),
      PlayerEnhanceLevel.standard => _compose(
          contrast: 1.12, saturation: 1.10, brightness: 0.018, clarity: 0.08),
      PlayerEnhanceLevel.vivid => _compose(
          contrast: 1.18, saturation: 1.22, brightness: 0.022, clarity: 0.10),
    };
  }

  static const List<double> _identity = <double>[
    1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0,
  ];

  static List<double> _compose({
    required double contrast,
    required double saturation,
    required double brightness,
    required double clarity,
  }) {
    final c = contrast + clarity * 0.35;
    final t = (1.0 - c) * 0.5 + brightness;
    const double rw = 0.2126, gw = 0.7152, bw = 0.0722;
    final s = saturation;
    final sr = (1 - s) * rw, sg = (1 - s) * gw, sb = (1 - s) * bw;
    return <double>[
      (sr + s) * c, sg * c, sb * c, 0, t * 255,
      sr * c, (sg + s) * c, sb * c, 0, t * 255,
      sr * c, sg * c, (sb + s) * c, 0, t * 255,
      0, 0, 0, 1, 0,
    ];
  }
}

/// 画质增强：iOS 可用 ColorMatrix；Android 用叠层，避免每帧滤 Texture 掉帧
class PlaybackEnhanceFilter extends StatelessWidget {
  const PlaybackEnhanceFilter({
    super.key,
    required this.level,
    required this.child,
  });

  final PlayerEnhanceLevel level;
  final Widget child;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    if (level == PlayerEnhanceLevel.off) return child;

    Widget out = child;
    if (!_android) {
      out = ColorFiltered(
        colorFilter: ColorFilter.matrix(PlaybackEnhance.matrixFor(level)),
        child: child,
      );
    }

    final vivid = level == PlayerEnhanceLevel.vivid;
    final standard = level == PlayerEnhanceLevel.standard;
    final topA = vivid ? 0.04 : (standard ? 0.024 : 0.014);
    final botA = vivid ? 0.06 : (standard ? 0.038 : 0.022);
    final lift = _android ? (vivid ? 0.05 : (standard ? 0.032 : 0.02)) : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        out,
        if (lift > 0)
          IgnorePointer(
            child: ColoredBox(color: Colors.white.withValues(alpha: lift * 0.4)),
          ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: topA),
                  Colors.transparent,
                  Colors.black.withValues(alpha: botA),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

Future<ui.ImageFilter?> tryEnhanceImageFilter(PlayerEnhanceLevel level) async {
  if (level == PlayerEnhanceLevel.off) return null;
  return null;
}
