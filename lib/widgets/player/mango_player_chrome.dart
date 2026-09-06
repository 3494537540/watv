import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../press_scale.dart';
import 'player_loading_hud.dart';
import 'player_network_indicator.dart';
import 'player_sys_status.dart';

/// 播放器强调色：品牌青
Color get _playerAccent => AppColors.brand;

/// 播放器图标按钮
/// [outlined] 圆形描边；[card] 圆角卡片描边（返回键）
class PlayerCircleButton extends StatelessWidget {
  const PlayerCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 36,
    this.iconSize = 22,
    this.outlined = false,
    this.card = false,
    this.weight = 700,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool outlined;
  final bool card;
  /// 字重感：越大越「粗」
  final int weight;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      color: Colors.white,
      size: iconSize,
      weight: weight.toDouble(),
      grade: 200,
      opticalSize: iconSize,
      shadows: const [
        Shadow(color: Color(0xCC000000), blurRadius: 6),
      ],
    );
    Widget body = iconWidget;
    if (card) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.88),
            width: 1.3,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 6,
            ),
          ],
        ),
        child: Center(child: iconWidget),
      );
    } else if (outlined) {
      body = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.88),
            width: 1.6,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Center(child: iconWidget),
      );
    }

    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: PressScale(
        onTap: onTap,
        scale: 0.88,
        child: SizedBox(
          width: size,
          height: size,
          child: body,
        ),
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
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: PressScale(
        onTap: onTap,
        scale: 0.9,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            icon,
            color: Colors.white,
            size: 30,
            weight: 700,
            shadows: const [
              Shadow(color: Color(0xCC000000), blurRadius: 8),
            ],
          ),
        ),
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
    this.onSeekRewind,
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
  final VoidCallback? onSeekRewind;
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
      if (onSeekRewind != null)
        PlayerCircleButton(
          icon: Icons.replay_10_rounded,
          onTap: onSeekRewind!,
          iconSize: 24,
          weight: 800,
        ),
      if (onSeekForward != null)
        PlayerCircleButton(
          icon: Icons.forward_10_rounded,
          onTap: onSeekForward!,
          iconSize: 24,
          weight: 800,
        ),
      if (onCast != null)
        PlayerCircleButton(
          icon: Icons.cast_rounded,
          onTap: onCast!,
          iconSize: 22,
          weight: 800,
        ),
      if (onPip != null)
        PlayerCircleButton(
          icon: Icons.picture_in_picture_alt_rounded,
          onTap: onPip!,
          iconSize: 22,
          weight: 800,
        ),
      if (onSettings != null)
        PlayerCircleButton(
          icon: Icons.settings_rounded,
          onTap: onSettings!,
          iconSize: 22,
          weight: 800,
        ),
    ];

    final bar = Padding(
      padding: EdgeInsets.fromLTRB(
        16 + padLeft,
        // 全屏顶栏略下移，避开刘海/状态栏更舒服
        landscape
            ? (padTop > 0 ? padTop + 10 : 14.0)
            : padTop + 12,
        10 + padRight,
        8,
      ),
      child: Row(
        children: [
          PlayerCircleButton(
            icon: Icons.chevron_left_rounded,
            onTap: onBack,
            size: 32,
            iconSize: 28,
            weight: 700,
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

    // 与两侧圆形按钮同高对齐（按钮默认 36）
    final barTop = landscape ? (padTop > 0 ? padTop + 2 : 8.0) : padTop + 6;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bar,
        Positioned(
          top: barTop,
          left: 0,
          right: 0,
          height: 36,
          child: const IgnorePointer(
            child: Align(
              alignment: Alignment.center,
              child: PlayerSysStatus(compact: true),
            ),
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
    this.onSeekPreview,
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
    this.onSources,
    this.onAspect,
    this.onSpeed,
    this.onQuality,
    this.aspectLabel = '适应',
    this.speedLabel = '倍速',
    this.qualityLabel = '清晰度',
    this.sourceLabel = '线路',
    this.denseLandscape = false,
    this.introMs = 0,
    this.outroMs = 0,
    this.onMarkIntro,
    this.onMarkOutro,
    this.onSkip,
    this.skipEnabled = false,
    this.onSettings,
    this.onCast,
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
  /// 拖动预览（仅更新 UI，不 seek）
  final ValueChanged<Duration>? onSeekPreview;
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
  final void Function(BuildContext anchor)? onSources;
  final void Function(BuildContext anchor)? onAspect;
  final void Function(BuildContext anchor)? onSpeed;
  final void Function(BuildContext anchor)? onQuality;
  final String aspectLabel;
  final String speedLabel;
  final String qualityLabel;
  final String sourceLabel;
  final bool denseLandscape;
  final int introMs;
  final int outroMs;
  final VoidCallback? onMarkIntro;
  final VoidCallback? onMarkOutro;
  /// 传入按钮 context，便于弹出锚点小菜单
  final void Function(BuildContext anchor)? onSkip;
  final bool skipEnabled;
  final VoidCallback? onSettings;
  final VoidCallback? onCast;

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
            left: 16,
            top: topInset + 12,
            child: PlayerCircleButton(
              icon: Icons.chevron_left_rounded,
              onTap: onBack!,
              size: 32,
              iconSize: 28,
              weight: 700,
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
        Expanded(
          child: _ProgressSlider(
            progress: progress,
            totalMs: totalMs,
            onSeek: onSeek,
            onSeekPreview: onSeekPreview,
            onSeekStart: onSeekStart,
            onSeekEnd: onSeekEnd,
            introMs: introMs,
            outroMs: outroMs,
            onMarkIntro: onMarkIntro,
            onMarkOutro: onMarkOutro,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _fmt(duration),
          style: _timeStyle.copyWith(color: Colors.white.withValues(alpha: 0.78)),
        ),
        if (showDanmakuToggle && onDanmakuToggle != null)
          _DanmakuToggleButton(enabled: danmakuEnabled, onTap: onDanmakuToggle!),
        // 竖屏/非全屏底栏不放线路·画质·倍速，避免挤掉进度条（仅横屏全屏栏显示）
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
            onSeekPreview: onSeekPreview,
            onSeekStart: onSeekStart,
            onSeekEnd: onSeekEnd,
            accent: true,
            introMs: introMs,
            outroMs: outroMs,
            onMarkIntro: onMarkIntro,
            onMarkOutro: onMarkOutro,
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
                  icon: Icons.skip_next_rounded,
                  onTap: onNextEpisode!,
                  size: 24,
                ),
              ],
              if (onSkip != null) ...[
                const SizedBox(width: 2),
                Builder(
                  builder: (ctx) => _ChromeTextButton(
                    label: skipEnabled ? '跳过·开' : '跳过',
                    onTap: () => onSkip!(ctx),
                  ),
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
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onEpisodes != null)
                          Builder(
                            builder: (ctx) => _ChromeTextButton(
                              label: '选集',
                              onTap: () => onEpisodes!(ctx),
                            ),
                          ),
                        if (onSources != null)
                          Builder(
                            builder: (ctx) => _ChromeTextButton(
                              label: sourceLabel,
                              onTap: () => onSources!(ctx),
                            ),
                          ),
                        if (onAspect != null)
                          Builder(
                            builder: (ctx) => _ChromeTextButton(
                              label: aspectLabel,
                              onTap: () => onAspect!(ctx),
                            ),
                          ),
                        if (onQuality != null)
                          Builder(
                            builder: (ctx) => _ChromeTextButton(
                              label: qualityLabel,
                              onTap: () => onQuality!(ctx),
                            ),
                          ),
                        if (onSpeed != null)
                          Builder(
                            builder: (ctx) => _ChromeTextButton(
                              label: speedLabel,
                              onTap: () => onSpeed!(ctx),
                            ),
                          ),
                        // 投屏/设置移到顶栏，仅全屏显示
                        _FullscreenExitButton(onTap: onFullscreen),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 进度条：拖动跟手；长按可定位片头/片尾。
class _ProgressSlider extends StatefulWidget {
  const _ProgressSlider({
    required this.progress,
    required this.totalMs,
    required this.onSeek,
    this.onSeekPreview,
    this.onSeekStart,
    this.onSeekEnd,
    this.accent = false,
    this.introMs = 0,
    this.outroMs = 0,
    this.onMarkIntro,
    this.onMarkOutro,
  });

  final double progress;
  final int totalMs;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration>? onSeekPreview;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;
  final bool accent;
  final int introMs;
  final int outroMs;
  final VoidCallback? onMarkIntro;
  final VoidCallback? onMarkOutro;

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  double? _drag;

  Future<void> _onLongPress() async {
    if (widget.onMarkIntro == null && widget.onMarkOutro == null) return;
    HapticFeedback.mediumImpact();
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    RelativeRect pos = const RelativeRect.fromLTRB(40, 200, 40, 200);
    if (box != null && overlay != null) {
      final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
      final bottomRight = box.localToGlobal(
        box.size.bottomRight(Offset.zero),
        ancestor: overlay,
      );
      pos = RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      );
    }
    final pick = await showMenu<String>(
      context: context,
      position: pos,
      color: const Color(0xF21C1C1E),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        if (widget.onMarkIntro != null)
          const PopupMenuItem(
            value: 'intro',
            child: Text(
              '将当前位置设为片头结束',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        if (widget.onMarkOutro != null)
          const PopupMenuItem(
            value: 'outro',
            child: Text(
              '将当前位置设为片尾开始',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
    if (pick == 'intro') widget.onMarkIntro?.call();
    if (pick == 'outro') widget.onMarkOutro?.call();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.accent ? _playerAccent : Colors.white;
    final value = (_drag ?? widget.progress).clamp(0.0, 1.0);

    return GestureDetector(
      onLongPress: _onLongPress,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            alignment: Alignment.center,
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: widget.accent ? 3.5 : 3,
                  trackShape: const RoundedRectSliderTrackShape(),
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: widget.accent ? 7 : 6,
                    elevation: 2,
                  ),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: active,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
                  thumbColor: Colors.white,
                  overlayColor: active.withValues(alpha: 0.14),
                ),
                child: Slider(
                  value: value,
                  onChangeStart: widget.totalMs > 0
                      ? (v) {
                          setState(() => _drag = v);
                          widget.onSeekStart?.call();
                          widget.onSeekPreview?.call(
                            Duration(
                              milliseconds: (v * widget.totalMs).round(),
                            ),
                          );
                        }
                      : null,
                  onChanged: widget.totalMs > 0
                      ? (v) {
                          setState(() => _drag = v);
                          widget.onSeekPreview?.call(
                            Duration(
                              milliseconds: (v * widget.totalMs).round(),
                            ),
                          );
                        }
                      : null,
                  onChangeEnd: widget.totalMs > 0
                      ? (v) {
                          final ms = (v * widget.totalMs).round();
                          setState(() => _drag = null);
                          widget.onSeek(Duration(milliseconds: ms));
                          widget.onSeekEnd?.call();
                        }
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DanmakuInputChip extends StatelessWidget {
  const _DanmakuInputChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scale: 0.94,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: SizedBox(
          height: 32,
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
    return PressScale(
      onTap: onTap,
      scale: 0.9,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: FontWeight.w800,
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
    return PressScale(
      onTap: onTap,
      scale: 0.86,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 28,
          weight: 800,
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
    return PressScale(
      onTap: onTap,
      scale: 0.88,
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
    return PressScale(
      onTap: onTap,
      scale: 0.88,
      child: const SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          Icons.fullscreen_exit_rounded,
          color: Colors.white,
          size: 28,
          weight: 800,
          shadows: [
            Shadow(color: Color(0xCC000000), blurRadius: 6),
          ],
        ),
      ),
    );
  }
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
    return PressScale(
      onTap: onTap,
      scale: 0.88,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          color: Colors.white,
          size: size + 4,
          weight: 800,
          shadows: const [
            Shadow(color: Color(0xCC000000), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}
