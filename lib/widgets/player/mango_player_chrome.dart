import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'player_loading_hud.dart';
import 'player_network_indicator.dart';
import 'player_sys_status.dart';

/// 播放器强调色：品牌青
Color get _playerAccent => AppColors.brand;

/// 圆形半透明按钮（返回 / 投屏 / 锁屏等）
class PlayerCircleButton extends StatelessWidget {
  const PlayerCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 36,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}

/// 画面中央快进/快退（仅图标，无文字胶囊）
class PlayerCenterSeekButton extends StatelessWidget {
  const PlayerCenterSeekButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x55000000),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

/// 播放页顶栏：返回 + 片名/集数 · 右侧快进/投屏/画中画/设置
/// [showSysStatus] 仅全屏横屏时显示时间电量
class MangoWatchTopBar extends StatelessWidget {
  const MangoWatchTopBar({
    super.key,
    required this.topInset,
    required this.episodeLabel,
    required this.onBack,
    this.title,
    this.tag,
    this.onCast,
    this.onSettings,
    this.onSeekForward,
    this.onPip,
    this.showSysStatus = false,
    this.safeInset,
  });

  final double topInset;
  final String episodeLabel;
  final VoidCallback onBack;
  final String? title;
  final String? tag;
  final VoidCallback? onCast;
  final VoidCallback? onSettings;
  final VoidCallback? onSeekForward;
  final VoidCallback? onPip;
  final bool showSysStatus;
  /// 全屏去掉 MediaQuery padding 后，仍用原始挖孔边距避让控件
  final EdgeInsets? safeInset;

  static const _titleStyle = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.25,
    shadows: [
      Shadow(color: Color(0x80000000), blurRadius: 6),
    ],
  );

  static const _episodeStyle = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xE6FFFFFF),
    height: 1.2,
    shadows: [
      Shadow(color: Color(0x80000000), blurRadius: 6),
    ],
  );

  static const _iconGap = SizedBox(width: 10);

  @override
  Widget build(BuildContext context) {
    final t = title?.trim() ?? '';
    final ep = episodeLabel.trim();
    final tagText = tag?.trim() ?? '';
    final vp = safeInset ?? MediaQuery.viewPaddingOf(context);
    // 沉浸式后 padding 常为 0，仍要用 viewPadding 避开刘海/挖孔
    final padTop = topInset > 0 ? topInset : vp.top;
    final padLeft = vp.left;
    final padRight = vp.right;
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final showClock = showSysStatus && landscape;

    final actions = <Widget>[
      if (onSeekForward != null)
        PlayerCircleButton(
          icon: CupertinoIcons.goforward_10,
          onTap: onSeekForward!,
          iconSize: 18,
        ),
      if (onCast != null)
        PlayerCircleButton(
          icon: CupertinoIcons.tv,
          onTap: onCast!,
          iconSize: 18,
        ),
      if (onPip != null)
        PlayerCircleButton(
          icon: Icons.picture_in_picture_alt_rounded,
          onTap: onPip!,
          iconSize: 18,
        ),
      if (onSettings != null)
        PlayerCircleButton(
          icon: CupertinoIcons.gear,
          onTap: onSettings!,
          iconSize: 18,
        ),
    ];

    final bar = Padding(
      padding: EdgeInsets.fromLTRB(
        10 + padLeft,
        // 横屏顶部通常无大刘海，少加一点；竖屏保留状态栏避让
        landscape ? (padTop > 0 ? padTop + 2 : 8.0) : padTop + 6,
        10 + padRight,
        8,
      ),
      child: Row(
        children: [
          PlayerCircleButton(
            icon: CupertinoIcons.chevron_left,
            onTap: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.isNotEmpty)
                  Text(
                    t,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle,
                  ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (ep.isNotEmpty)
                      Flexible(
                        child: Text(
                          ep,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _episodeStyle,
                        ),
                      ),
                    if (tagText.isNotEmpty) ...[
                      if (ep.isNotEmpty) const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tagText,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    const PlayerNetworkIndicator(),
                  ],
                ),
              ],
            ),
          ),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) _iconGap,
            actions[i],
          ],
        ],
      ),
    );

    if (!showClock) return bar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        bar,
        Positioned(
          top: landscape ? (padTop > 0 ? padTop + 4 : 10.0) : padTop + 10,
          left: 0,
          right: 0,
          child: const IgnorePointer(
            child: Center(child: PlayerSysStatus()),
          ),
        ),
      ],
    );
  }
}

/// 底部播控条（竖屏精简 / 横屏图三图四样式）
class MangoPlayerChrome extends StatelessWidget {
  const MangoPlayerChrome({
    super.key,
    required this.playing,
    required this.position,
    required this.duration,
    required this.buffering,
    required this.onPlayPause,
    required this.onSeek,
    required this.onFullscreen,
    this.onSeekStart,
    this.onSeekEnd,
    this.showLoadingHud = false,
    this.loadingSpeedLabel = '— KB/s',
    this.onBack,
    this.showBack = true,
    this.topInset = 0,
    this.showDanmakuToggle = false,
    this.danmakuEnabled = true,
    this.onDanmakuToggle,
    this.onDanmakuSend,
    this.onNextEpisode,
    this.onEpisodes,
    this.onAspect,
    this.onSpeed,
    this.aspectLabel = '适应',
    this.speedLabel = '倍速',
    this.denseLandscape = false,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final bool buffering;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onFullscreen;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;
  final bool showLoadingHud;
  final String loadingSpeedLabel;
  final VoidCallback? onBack;
  final bool showBack;
  final double topInset;
  final bool showDanmakuToggle;
  final bool danmakuEnabled;
  final VoidCallback? onDanmakuToggle;
  final VoidCallback? onDanmakuSend;
  final VoidCallback? onNextEpisode;
  /// 传入按钮 context，便于弹出锚点小菜单
  final void Function(BuildContext anchor)? onEpisodes;
  final void Function(BuildContext anchor)? onAspect;
  final void Function(BuildContext anchor)? onSpeed;
  final String aspectLabel;
  final String speedLabel;
  final bool denseLandscape;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  static const _timeStyle = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
    shadows: [
      Shadow(color: Color(0x99000000), blurRadius: 4),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final landscape = denseLandscape ||
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final totalMs = duration.inMilliseconds;
    final progress = totalMs > 0
        ? (position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBack && onBack != null)
          Positioned(
            left: 12,
            top: topInset + 4,
            child: PlayerCircleButton(
              icon: CupertinoIcons.chevron_left,
              onTap: onBack!,
            ),
          ),
        if (showLoadingHud)
          Center(
            child: PlayerLoadingHud(speedLabel: loadingSpeedLabel),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xE6000000),
                  Color(0x66000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                landscape ? 14 + MediaQuery.viewPaddingOf(context).left : 12,
                landscape ? 6 : 20,
                landscape ? 14 + MediaQuery.viewPaddingOf(context).right : 12,
                landscape
                    ? 6 + MediaQuery.viewPaddingOf(context).bottom
                    : 14,
              ),
              child: landscape
                  ? _buildLandscapeBar(context, progress, totalMs)
                  : _buildPortraitBar(progress, totalMs),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitBar(double progress, int totalMs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _PlayPauseButton(playing: playing, onTap: onPlayPause),
        const SizedBox(width: 4),
        Text(_fmt(position), style: _timeStyle),
        const SizedBox(width: 10),
        Expanded(child: _ProgressSlider(progress: progress, totalMs: totalMs, onSeek: onSeek, onSeekStart: onSeekStart, onSeekEnd: onSeekEnd)),
        const SizedBox(width: 10),
        Text(
          _fmt(duration),
          style: _timeStyle.copyWith(color: Colors.white.withValues(alpha: 0.78)),
        ),
        if (showDanmakuToggle && onDanmakuToggle != null)
          _DanmakuToggleButton(enabled: danmakuEnabled, onTap: onDanmakuToggle!),
        _ChromeIconButton(
          icon: Icons.stay_current_landscape,
          onTap: onFullscreen,
          size: 22,
        ),
      ],
    );
  }

  Widget _buildLandscapeBar(
    BuildContext context,
    double progress,
    int totalMs,
  ) {
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_fmt(position)} / ${_fmt(duration)}',
          style: _timeStyle,
        ),
        SizedBox(
          height: 26,
          child: _ProgressSlider(
            progress: progress,
            totalMs: totalMs,
            onSeek: onSeek,
            onSeekStart: onSeekStart,
            onSeekEnd: onSeekEnd,
            accent: true,
          ),
        ),
        SizedBox(
          height: 36,
          child: Row(
            children: [
              _PlayPauseButton(playing: playing, onTap: onPlayPause),
              if (onNextEpisode != null) ...[
                const SizedBox(width: 2),
                _ChromeIconButton(
                  icon: CupertinoIcons.forward_end_alt_fill,
                  onTap: onNextEpisode!,
                  size: 22,
                ),
              ],
              if (showDanmakuToggle && onDanmakuToggle != null) ...[
                const SizedBox(width: 4),
                _DanmakuToggleButton(
                  enabled: danmakuEnabled,
                  onTap: onDanmakuToggle!,
                ),
              ],
              if (wide && showDanmakuToggle && onDanmakuSend != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _DanmakuInputChip(onTap: onDanmakuSend!),
                ),
              ] else ...[
                if (showDanmakuToggle && onDanmakuSend != null)
                  _ChromeIconButton(
                    icon: CupertinoIcons.pencil,
                    onTap: onDanmakuSend!,
                    size: 18,
                  ),
                const Spacer(),
              ],
              if (onEpisodes != null)
                Builder(
                  builder: (ctx) => _ChromeTextButton(
                    label: '选集',
                    onTap: () => onEpisodes!(ctx),
                  ),
                ),
              if (onAspect != null)
                Builder(
                  builder: (ctx) => _ChromeTextButton(
                    label: aspectLabel,
                    onTap: () => onAspect!(ctx),
                  ),
                ),
              if (onSpeed != null)
                Builder(
                  builder: (ctx) => _ChromeTextButton(
                    label: speedLabel,
                    onTap: () => onSpeed!(ctx),
                  ),
                ),
              _FullscreenExitButton(onTap: onFullscreen),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({
    required this.progress,
    required this.totalMs,
    required this.onSeek,
    this.onSeekStart,
    this.onSeekEnd,
    this.accent = false,
  });

  final double progress;
  final int totalMs;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final active = accent ? _playerAccent : Colors.white;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: accent ? 3.5 : 3,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: accent ? 7 : 6,
          elevation: 2,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: active,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
        thumbColor: active,
        overlayColor: active.withValues(alpha: 0.14),
      ),
      child: Slider(
        value: progress,
        onChangeStart: totalMs > 0 ? (_) => onSeekStart?.call() : null,
        onChanged: totalMs > 0
            ? (v) => onSeek(Duration(milliseconds: (v * totalMs).round()))
            : null,
        onChangeEnd: totalMs > 0
            ? (v) {
                onSeek(Duration(milliseconds: (v * totalMs).round()));
                onSeekEnd?.call();
              }
            : null,
      ),
    );
  }
}

class _DanmakuInputChip extends StatelessWidget {
  const _DanmakuInputChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '发个弹幕…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.paperplane,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeTextButton extends StatelessWidget {
  const _ChromeTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [Shadow(color: Color(0x99000000), blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.onTap,
  });

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
          color: Colors.white,
          size: 26,
          shadows: const [
            Shadow(color: Color(0x99000000), blurRadius: 4),
          ],
        ),
      ),
    );
  }
}

/// 弹幕开关：与全屏图标同尺寸的纯文字按钮
class _DanmakuToggleButton extends StatelessWidget {
  const _DanmakuToggleButton({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  static const _onStyle = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: 1,
    color: Colors.white,
    shadows: [
      Shadow(color: Color(0x99000000), blurRadius: 4),
    ],
  );

  static final _offStyle = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1,
    color: Colors.white.withValues(alpha: 0.38),
    shadows: const [
      Shadow(color: Color(0x99000000), blurRadius: 4),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 28,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text('弹', style: enabled ? _onStyle : _offStyle),
            if (enabled)
              Positioned(
                bottom: 7,
                child: Container(
                  width: 10,
                  height: 2,
                  decoration: BoxDecoration(
                    color: _playerAccent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            if (!enabled)
              CustomPaint(
                size: const Size(18, 18),
                painter: _SlashPainter(),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.15),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FullscreenExitButton extends StatelessWidget {
  const _FullscreenExitButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: const SizedBox(
        width: 36,
        height: 36,
        child: CustomPaint(
          painter: _BoldFullscreenExitPainter(),
        ),
      ),
    );
  }
}

/// 加粗「退出全屏」图标，与 play_fill / next_fill 视觉重量一致
class _BoldFullscreenExitPainter extends CustomPainter {
  const _BoldFullscreenExitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final cx = size.width / 2;
    final cy = size.height / 2;
    const arm = 5.5;
    const gap = 3.2;

    // 左上折角
    canvas.drawLine(Offset(cx - gap - arm, cy - gap), Offset(cx - gap, cy - gap), paint);
    canvas.drawLine(Offset(cx - gap, cy - gap - arm), Offset(cx - gap, cy - gap), paint);
    // 右上
    canvas.drawLine(Offset(cx + gap, cy - gap), Offset(cx + gap + arm, cy - gap), paint);
    canvas.drawLine(Offset(cx + gap, cy - gap - arm), Offset(cx + gap, cy - gap), paint);
    // 左下
    canvas.drawLine(Offset(cx - gap - arm, cy + gap), Offset(cx - gap, cy + gap), paint);
    canvas.drawLine(Offset(cx - gap, cy + gap), Offset(cx - gap, cy + gap + arm), paint);
    // 右下
    canvas.drawLine(Offset(cx + gap, cy + gap), Offset(cx + gap + arm, cy + gap), paint);
    canvas.drawLine(Offset(cx + gap, cy + gap), Offset(cx + gap, cy + gap + arm), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.onTap,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          color: Colors.white,
          size: size,
          shadows: const [
            Shadow(color: Color(0x99000000), blurRadius: 4),
          ],
        ),
      ),
    );
  }
}
