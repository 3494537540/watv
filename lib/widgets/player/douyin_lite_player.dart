import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_colors.dart';
import '../figma_loading.dart';
import 'player_hold_boost_hud.dart';

/// 抖音式轻量播放：双击左右快退/快进，可拖进度条，长按倍速
class DouyinLitePlayer extends StatefulWidget {
  const DouyinLitePlayer({
    super.key,
    required this.url,
    this.active = true,
    this.coverUrl,
    this.bottomInset = 0,
  });

  final String url;
  final bool active;
  final String? coverUrl;
  final double bottomInset;

  @override
  State<DouyinLitePlayer> createState() => _DouyinLitePlayerState();
}

class _DouyinLitePlayerState extends State<DouyinLitePlayer> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _failed = false;
  bool _showPause = false;
  bool _dragging = false;
  double? _dragValue;
  String? _seekHint;
  bool _holdingBoost = false;
  double _savedRate = 1;
  Timer? _pauseHint;
  Timer? _seekHintTimer;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_open(widget.url));
  }

  @override
  void didUpdateWidget(covariant DouyinLitePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_open(widget.url));
      return;
    }
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        unawaited(_c?.play());
      } else {
        unawaited(_c?.pause());
      }
    }
  }

  @override
  void dispose() {
    _pauseHint?.cancel();
    _seekHintTimer?.cancel();
    final c = _c;
    _c = null;
    unawaited(c?.dispose());
    super.dispose();
  }

  Future<void> _open(String url) async {
    final u = url.trim();
    final old = _c;
    _c = null;
    unawaited(old?.dispose());
    if (!mounted) return;
    setState(() {
      _ready = false;
      _failed = false;
      _dragging = false;
      _dragValue = null;
      _seekHint = null;
      _holdingBoost = false;
    });
    if (u.isEmpty || !widget.active) return;
    try {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(u),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize().timeout(const Duration(seconds: 20));
      await c.setLooping(true);
      if (!mounted || widget.url.trim() != u) {
        await c.dispose();
        return;
      }
      _c = c;
      setState(() => _ready = true);
      if (widget.active) await c.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _ready = false;
      });
    }
  }

  void _toggle() {
    if (_failed) {
      unawaited(_open(widget.url));
      return;
    }
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    if (c.value.isPlaying) {
      unawaited(c.pause());
      _pauseHint?.cancel();
      setState(() => _showPause = true);
      _pauseHint = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _showPause = false);
      });
    } else {
      unawaited(c.play());
      setState(() => _showPause = false);
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final total = c.value.duration.inMilliseconds;
    if (total <= 0) return;
    final next = (c.value.position.inMilliseconds + seconds * 1000)
        .clamp(0, total);
    await c.seekTo(Duration(milliseconds: next));
    HapticFeedback.selectionClick();
    _flashSeek(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  void _flashSeek(String text) {
    _seekHintTimer?.cancel();
    setState(() => _seekHint = text);
    _seekHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _onDoubleTapDown(TapDownDetails details, double width) {
    if (details.localPosition.dx < width * 0.4) {
      unawaited(_seekRelative(-10));
    } else if (details.localPosition.dx > width * 0.6) {
      unawaited(_seekRelative(10));
    } else {
      _toggle();
    }
  }

  Future<void> _onHoldStart() async {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    _savedRate = c.value.playbackSpeed;
    _holdingBoost = true;
    setState(() {});
    await c.setPlaybackSpeed(2);
    HapticFeedback.lightImpact();
  }

  Future<void> _onHoldEnd() async {
    if (!_holdingBoost) return;
    final c = _c;
    _holdingBoost = false;
    if (mounted) setState(() {});
    if (c != null && c.value.isInitialized) {
      await c.setPlaybackSpeed(_savedRate <= 0 ? 1 : _savedRate);
    }
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cover = widget.coverUrl?.trim() ?? '';
    final c = _c;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: _toggle,
          onDoubleTap: () {},
          onDoubleTapDown: (d) => _onDoubleTapDown(d, constraints.maxWidth),
          onLongPressStart: (_) => unawaited(_onHoldStart()),
          onLongPressEnd: (_) => unawaited(_onHoldEnd()),
          onLongPressCancel: () => unawaited(_onHoldEnd()),
          behavior: HitTestBehavior.opaque,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cover.isNotEmpty && !_ready)
                  Positioned.fill(
                    child: Image.network(
                      cover,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                if (_ready && c != null)
                  Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio == 0
                          ? 16 / 9
                          : c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
                if (!_ready && !_failed)
                  const Center(child: FigmaMetaballLoader(size: 40)),
                if (_failed)
                  const Center(
                    child: Text(
                      '加载失败，点击重试',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        color: Colors.white70,
                      ),
                    ),
                  ),
                if (_showPause)
                  const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 64,
                      color: Colors.white70,
                    ),
                  ),
                if (_seekHint != null)
                  Center(child: PlayerSeekHintChip(text: _seekHint!)),
                if (_holdingBoost)
                  const Positioned(
                    top: 72,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: PlayerSeekHintChip(text: '2x 快进中'),
                    ),
                  ),
                if (_ready && c != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: widget.bottomInset + 4,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, v, _) {
                        final total = v.duration.inMilliseconds;
                        final pos = v.position.inMilliseconds;
                        final p = _dragging
                            ? (_dragValue ?? 0)
                            : (total <= 0
                                ? 0.0
                                : (pos / total).clamp(0.0, 1.0));
                        final cur = Duration(
                          milliseconds: total <= 0
                              ? 0
                              : (p * total).round(),
                        );
                        final end = v.duration;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _fmt(cur),
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _fmt(end),
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: _dragging ? 4 : 2.5,
                                thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: _dragging ? 7 : 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                activeTrackColor: AppColors.brand,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: AppColors.brand
                                    .withValues(alpha: 0.25),
                              ),
                              child: Slider(
                                value: p.clamp(0.0, 1.0),
                                onChangeStart: (_) {
                                  setState(() {
                                    _dragging = true;
                                    _dragValue = p;
                                  });
                                },
                                onChanged: (v) {
                                  setState(() => _dragValue = v);
                                },
                                onChangeEnd: (v) async {
                                  final ctrl = _c;
                                  setState(() {
                                    _dragging = false;
                                    _dragValue = null;
                                  });
                                  if (ctrl == null ||
                                      !ctrl.value.isInitialized) {
                                    return;
                                  }
                                  final ms = ctrl
                                      .value.duration.inMilliseconds;
                                  if (ms <= 0) return;
                                  await ctrl.seekTo(
                                    Duration(
                                      milliseconds: (v * ms).round(),
                                    ),
                                  );
                                  if (widget.active) {
                                    unawaited(ctrl.play());
                                  }
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
