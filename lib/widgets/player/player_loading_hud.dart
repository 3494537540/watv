import 'dart:async';

import 'package:flutter/material.dart';

import '../../player/playback_speed_tracker.dart';
import 'player_buffer_spinner.dart';

/// 居中加载：单色波浪 + 网速（compact 也会显示速率）
class PlayerLoadingHud extends StatefulWidget {
  const PlayerLoadingHud({
    super.key,
    this.speedLabel,
    this.tracker,
    this.compact = false,
    this.showSpeed = true,
  });

  final String? speedLabel;
  final PlaybackSpeedTracker? tracker;
  final bool compact;
  final bool showSpeed;

  static const _speedStyle = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: Color(0xF2FFFFFF),
    fontFeatures: [FontFeature.tabularFigures()],
    shadows: [
      Shadow(color: Color(0xAA000000), blurRadius: 10),
    ],
  );

  static const _speedStyleCompact = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: Color(0xE6FFFFFF),
    fontFeatures: [FontFeature.tabularFigures()],
    shadows: [
      Shadow(color: Color(0x99000000), blurRadius: 8),
    ],
  );

  @override
  State<PlayerLoadingHud> createState() => _PlayerLoadingHudState();
}

class _PlayerLoadingHudState extends State<PlayerLoadingHud> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (!mounted) return;
      widget.tracker?.tick(const [], isBuffering: true);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String? get _label {
    if (!widget.showSpeed) return null;
    if (widget.tracker != null) return widget.tracker!.displayLabel;
    final s = widget.speedLabel;
    if (s == null || s.trim().isEmpty) return null;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 42.0 : 58.0;
    final label = _label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerBufferSpinner(size: size),
        if (label != null) ...[
          SizedBox(height: widget.compact ? 8 : 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Text(
              label,
              key: ValueKey(label),
              style: widget.compact
                  ? PlayerLoadingHud._speedStyleCompact
                  : PlayerLoadingHud._speedStyle,
            ),
          ),
        ],
      ],
    );
  }
}
