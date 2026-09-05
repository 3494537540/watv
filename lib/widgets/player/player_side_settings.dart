import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../player/player_danmaku_prefs.dart';
import '../../player/player_settings_store.dart';
import '../../player/player_skip_store.dart';
import '../../player/source_latency.dart';
import '../../player/vod_playback.dart';
import '../../theme/app_colors.dart';
import '../dialogx/dialogx.dart';
import 'player_setting_controls.dart';

Color get _playerAccent => AppColors.brand;
const _moreGray = Color(0xFF8E8E93);
const _moreInk = Color(0xFF333333);

/// 全屏右侧 / 底部「更多」设置回调
class PlayerSideSettingsHost {
  const PlayerSideSettingsHost({
    required this.playbackRate,
    required this.onPlaybackRate,
    required this.danmakuPrefs,
    required this.onDanmakuPrefs,
    required this.skipPrefs,
    required this.onSkipPrefs,
    required this.settings,
    required this.onSettings,
    required this.sleepMinutes,
    required this.onSleepMinutes,
    required this.onToggleLock,
    required this.locked,
    required this.onSendDanmaku,
    required this.onScreenshot,
    required this.onOpenEpisodes,
    required this.onOpenSources,
    required this.onCast,
    required this.hasEpisodes,
    required this.hasSources,
    required this.hasCast,
    required this.hasNext,
    required this.onNextEpisode,
    required this.onReportError,
    this.onPip,
    this.enableDanmaku = true,
    this.qualityPrefer = VodQualityTier.auto,
    this.qualityVariants = const [],
    this.currentQuality,
    this.onQualityPrefer,
    this.onQualityVariant,
    this.positionSec = 0,
    this.durationSec = 0,
    this.sourceNames = const [],
    this.sourceIndex = 0,
    this.sourceProbeUrls = const [],
    this.onSourceSelect,
  });

  final double playbackRate;
  final ValueChanged<double> onPlaybackRate;
  final DanmakuDisplayPrefs danmakuPrefs;
  final ValueChanged<DanmakuDisplayPrefs> onDanmakuPrefs;
  final PlayerSkipPrefs skipPrefs;
  final ValueChanged<PlayerSkipPrefs> onSkipPrefs;
  final PlayerSettingsPrefs settings;
  final ValueChanged<PlayerSettingsPrefs> onSettings;
  final int sleepMinutes;
  final ValueChanged<int> onSleepMinutes;
  final VoidCallback onToggleLock;
  final bool locked;
  final VoidCallback onSendDanmaku;
  final VoidCallback onScreenshot;
  final VoidCallback onOpenEpisodes;
  final VoidCallback onOpenSources;
  final VoidCallback onCast;
  final VoidCallback? onPip;
  final bool hasEpisodes;
  final bool hasSources;
  final bool hasCast;
  final bool hasNext;
  final VoidCallback? onNextEpisode;
  final VoidCallback onReportError;
  final bool enableDanmaku;
  final VodQualityTier qualityPrefer;
  final List<VodHlsVariant> qualityVariants;
  final VodHlsVariant? currentQuality;
  final ValueChanged<VodQualityTier>? onQualityPrefer;
  final ValueChanged<VodHlsVariant>? onQualityVariant;
  final int positionSec;
  final int durationSec;
  final List<String> sourceNames;
  final int sourceIndex;
  final List<String> sourceProbeUrls;
  final ValueChanged<int>? onSourceSelect;
}

/// 白底「更多」设置卡片（图三）
class PlayerSideSettingsPanel extends StatefulWidget {
  const PlayerSideSettingsPanel({
    super.key,
    required this.host,
    required this.onClose,
    this.asBottomSheet = false,
    this.initialPage = 'home',
    this.flatMode = false,
  });

  final PlayerSideSettingsHost host;
  final VoidCallback onClose;
  final bool asBottomSheet;
  final String initialPage;
  /// 扁平设置：控件直接露出，少做二级入口
  final bool flatMode;

  @override
  State<PlayerSideSettingsPanel> createState() =>
      _PlayerSideSettingsPanelState();
}

class _PlayerSideSettingsPanelState extends State<PlayerSideSettingsPanel> {
  late String _page;

  late double _playbackRate;
  late DanmakuDisplayPrefs _danmakuPrefs;
  late PlayerSkipPrefs _skipPrefs;
  late PlayerSettingsPrefs _settings;
  late int _sleepMinutes;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    final h = widget.host;
    _playbackRate = h.playbackRate;
    _danmakuPrefs = h.danmakuPrefs;
    _skipPrefs = h.skipPrefs;
    _settings = h.settings;
    _sleepMinutes = h.sleepMinutes;
  }

  @override
  void didUpdateWidget(covariant PlayerSideSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPage != widget.initialPage) {
      _page = widget.initialPage;
    }
    final h = widget.host;
    if (oldWidget.host.playbackRate != h.playbackRate) {
      _playbackRate = h.playbackRate;
    }
    if (oldWidget.host.danmakuPrefs != h.danmakuPrefs) {
      _danmakuPrefs = h.danmakuPrefs;
    }
    if (oldWidget.host.skipPrefs != h.skipPrefs) {
      _skipPrefs = h.skipPrefs;
    }
    if (oldWidget.host.settings != h.settings) {
      _settings = h.settings;
    }
    if (oldWidget.host.sleepMinutes != h.sleepMinutes) {
      _sleepMinutes = h.sleepMinutes;
    }
  }

  PlayerSideSettingsHost get h {
    final base = widget.host;
    return PlayerSideSettingsHost(
      playbackRate: _playbackRate,
      onPlaybackRate: (r) {
        setState(() => _playbackRate = r);
        base.onPlaybackRate(r);
      },
      danmakuPrefs: _danmakuPrefs,
      onDanmakuPrefs: (p) {
        setState(() => _danmakuPrefs = p);
        base.onDanmakuPrefs(p);
      },
      skipPrefs: _skipPrefs,
      onSkipPrefs: (p) {
        setState(() => _skipPrefs = p);
        base.onSkipPrefs(p);
      },
      settings: _settings,
      onSettings: (p) {
        setState(() => _settings = p);
        base.onSettings(p);
      },
      sleepMinutes: _sleepMinutes,
      onSleepMinutes: (m) {
        setState(() => _sleepMinutes = m);
        base.onSleepMinutes(m);
      },
      onToggleLock: base.onToggleLock,
      locked: base.locked,
      onSendDanmaku: base.onSendDanmaku,
      onScreenshot: base.onScreenshot,
      onOpenEpisodes: base.onOpenEpisodes,
      onOpenSources: base.onOpenSources,
      onCast: base.onCast,
      onPip: base.onPip,
      hasEpisodes: base.hasEpisodes,
      hasSources: base.hasSources,
      hasCast: base.hasCast,
      hasNext: base.hasNext,
      onNextEpisode: base.onNextEpisode,
      onReportError: base.onReportError,
      enableDanmaku: base.enableDanmaku,
      qualityPrefer: base.qualityPrefer,
      qualityVariants: base.qualityVariants,
      currentQuality: base.currentQuality,
      onQualityPrefer: base.onQualityPrefer,
      onQualityVariant: base.onQualityVariant,
      positionSec: base.positionSec,
      durationSec: base.durationSec,
      sourceNames: base.sourceNames,
      sourceIndex: base.sourceIndex,
      sourceProbeUrls: base.sourceProbeUrls,
      onSourceSelect: base.onSourceSelect,
    );
  }

  void _go(String page) {
    HapticFeedback.selectionClick();
    setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    // 全屏侧栏扁平模式：背景与内容同色，不要白边套灰卡
    if (widget.flatMode) {
      return Material(
        color: const Color(0xFFF5F6F8),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _pageBody(),
        ),
      );
    }
    return Material(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 10 + pad.bottom),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _pageBody(),
        ),
      ),
    );
  }

  Widget _pageBody() {
    final host = h;
    return switch (_page) {
      'speed' => _SpeedPage(
          key: const ValueKey('speed'),
          value: host.playbackRate,
          onBack: () => _go('home'),
          onChanged: host.onPlaybackRate,
        ),
      'sleep' => _SleepPage(
          key: const ValueKey('sleep'),
          minutes: host.sleepMinutes,
          onBack: () => _go('home'),
          onChanged: host.onSleepMinutes,
        ),
      'aspect' => _AspectPage(
          key: const ValueKey('aspect'),
          value: host.settings.aspect,
          onBack: () => _go('home'),
          onChanged: (m) => host.onSettings(host.settings.copyWith(aspect: m)),
        ),
      'quality' => _QualityPage(
          key: const ValueKey('quality'),
          prefer: host.qualityPrefer,
          variants: host.qualityVariants,
          current: host.currentQuality,
          onBack: () => _go('home'),
          onPrefer: host.onQualityPrefer,
          onVariant: host.onQualityVariant,
        ),
      'danmaku' => _DanmakuPage(
          key: const ValueKey('danmaku'),
          prefs: host.danmakuPrefs,
          onBack: () => _go('home'),
          onChanged: host.onDanmakuPrefs,
        ),
      'skip' => _SkipPage(
          key: const ValueKey('skip'),
          prefs: host.skipPrefs,
          positionSec: host.positionSec,
          durationSec: host.durationSec,
          onBack: () => _go('home'),
          onChanged: host.onSkipPrefs,
        ),
      'sources' => _SourcesPage(
          key: const ValueKey('sources'),
          names: host.sourceNames,
          selected: host.sourceIndex,
          probeUrls: host.sourceProbeUrls,
          onBack: () => _go('home'),
          onSelect: (i) {
            host.onSourceSelect?.call(i);
            widget.onClose();
          },
        ),
      'more' => _ExtraSettingsPage(
          key: const ValueKey('more'),
          host: host,
          onBack: () => _go('home'),
          onOpen: _go,
        ),
      _ => widget.flatMode
          ? _FlatSettingsPage(
              key: const ValueKey('flat'),
              host: host,
              onClose: widget.onClose,
              onOpen: _go,
            )
          : _MoreHomePage(
              key: const ValueKey('home'),
              host: host,
              onClose: widget.onClose,
              onOpen: _go,
            ),
    };
  }
}

/// 全屏侧栏：设置直接可改，分类卡片
class _FlatSettingsPage extends StatelessWidget {
  const _FlatSettingsPage({
    super.key,
    required this.host,
    required this.onClose,
    required this.onOpen,
  });

  final PlayerSideSettingsHost host;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final h = host;
    return SizedBox.expand(
      child: ColoredBox(
        color: const Color(0xFFF5F6F8),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '播放设置',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _moreInk,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(CupertinoIcons.xmark, size: 18, color: _moreGray),
                ),
              ],
            ),
            _SettingsCard(
          title: '播放',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('倍速'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
                    _Chip(
                      label: VodPlayback.rateLabel(r),
                      selected: (h.playbackRate - r).abs() < 0.01,
                      onTap: () => h.onPlaybackRate(r),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _SectionLabel('清晰度'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    label: '自动',
                    selected: h.qualityPrefer == VodQualityTier.auto,
                    onTap: () => h.onQualityPrefer?.call(VodQualityTier.auto),
                  ),
                  if (h.qualityVariants.isEmpty)
                    for (final t in [
                      VodQualityTier.q1080,
                      VodQualityTier.q720,
                      VodQualityTier.q480,
                    ])
                      _Chip(
                        label: t.label,
                        selected: h.qualityPrefer == t,
                        onTap: () => h.onQualityPrefer?.call(t),
                      )
                  else
                    for (final v in [...h.qualityVariants].reversed)
                      _Chip(
                        label: v.shortLabel,
                        selected: h.currentQuality?.url == v.url &&
                            h.qualityPrefer != VodQualityTier.auto,
                        onTap: () => h.onQualityVariant?.call(v),
                      ),
                ],
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: '画面',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in PlayerAspectMode.values)
                _Chip(
                  label: m.label,
                  selected: h.settings.aspect == m,
                  onTap: () =>
                      h.onSettings(h.settings.copyWith(aspect: m)),
                ),
            ],
          ),
        ),
        _SettingsCard(
          title: '播放控制',
          child: Column(
            children: [
              _SwitchRow(
                title: '跳过片头片尾',
                value: h.skipPrefs.enabled,
                onChanged: (v) =>
                    h.onSkipPrefs(h.skipPrefs.copyWith(enabled: v)),
              ),
              if (h.skipPrefs.enabled)
                _LightTile(
                  title: '片头/片尾细调',
                  selected: false,
                  onTap: () => onOpen('skip'),
                ),
              _SwitchRow(
                title: '自动连播',
                value: h.settings.autoPlayNext,
                onChanged: (v) =>
                    h.onSettings(h.settings.copyWith(autoPlayNext: v)),
              ),
              _SwitchRow(
                title: '卡顿自动切换线路',
                value: h.settings.autoSourceFailover,
                onChanged: (v) => h.onSettings(
                  h.settings.copyWith(autoSourceFailover: v),
                ),
              ),
              _SwitchRow(
                title: '循环播放',
                value: h.settings.loopSingle,
                onChanged: (v) => h.onSettings(
                  h.settings.copyWith(
                    loopSingle: v,
                    autoPlayNext: v ? false : h.settings.autoPlayNext,
                  ),
                ),
              ),
              _SwitchRow(
                title: '左右镜像',
                value: h.settings.mirrorX,
                onChanged: (v) => h.onSettings(
                  h.settings.copyWith(mirrorX: v, mirrorY: false),
                ),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: '定时与手势',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('定时关闭'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in const [0, 15, 30, 45, 60])
                    _Chip(
                      label: m == 0 ? '关闭' : '$m 分',
                      selected: h.sleepMinutes == m,
                      onTap: () => h.onSleepMinutes(m),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const _SectionLabel('长按倍率'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in const [1.5, 2.0, 2.5, 3.0])
                    _Chip(
                      label: VodPlayback.rateLabel(r),
                      selected: (h.settings.holdBoostRate - r).abs() < 0.01,
                      onTap: () => h.onSettings(
                        h.settings.copyWith(holdBoostRate: r),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              _SwitchRow(
                title: '显示网速',
                value: h.settings.showNetSpeed,
                onChanged: (v) =>
                    h.onSettings(h.settings.copyWith(showNetSpeed: v)),
              ),
              _SwitchRow(
                title: '手势调节音量/亮度',
                value: h.settings.gestureEnabled,
                onChanged: (v) =>
                    h.onSettings(h.settings.copyWith(gestureEnabled: v)),
              ),
              _SwitchRow(
                title: '双击快进/快退',
                value: h.settings.doubleTapSeek,
                onChanged: (v) =>
                    h.onSettings(h.settings.copyWith(doubleTapSeek: v)),
              ),
              _SwitchRow(
                title: '长按倍速',
                value: h.settings.holdBoostEnabled,
                onChanged: (v) =>
                    h.onSettings(h.settings.copyWith(holdBoostEnabled: v)),
              ),
              _SwitchRow(
                title: '屏幕常亮',
                value: h.settings.keepScreenOn,
                onChanged: (v) =>
                    h.onSettings(h.settings.copyWith(keepScreenOn: v)),
              ),
              if (h.enableDanmaku)
                _SwitchRow(
                  title: '显示弹幕',
                  value: h.danmakuPrefs.enabled,
                  onChanged: (v) =>
                      h.onDanmakuPrefs(h.danmakuPrefs.copyWith(enabled: v)),
                ),
            ],
          ),
        ),
        _SettingsCard(
          title: '快捷',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (h.hasSources)
                _Chip(
                  label: '播放线路',
                  selected: false,
                  onTap: () => onOpen('sources'),
                ),
              if (h.hasEpisodes)
                _Chip(
                  label: '选集',
                  selected: false,
                  onTap: () {
                    onClose();
                    h.onOpenEpisodes();
                  },
                ),
              _Chip(
                label: h.locked ? '解锁' : '锁屏',
                selected: h.locked,
                onTap: () {
                  onClose();
                  h.onToggleLock();
                },
              ),
              _Chip(
                label: '截图',
                selected: false,
                onTap: () {
                  onClose();
                  h.onScreenshot();
                },
              ),
              if (h.hasCast)
                _Chip(
                  label: '投屏',
                  selected: false,
                  onTap: () {
                    onClose();
                    h.onCast();
                  },
                ),
              if (h.onPip != null)
                _Chip(
                  label: '画中画',
                  selected: false,
                  onTap: () {
                    onClose();
                    h.onPip?.call();
                  },
                ),
              if (h.enableDanmaku)
                _Chip(
                  label: '弹幕细调',
                  selected: false,
                  onTap: () => onOpen('danmaku'),
                ),
              _Chip(
                label: '报错反馈',
                selected: false,
                onTap: () {
                  onClose();
                  h.onReportError();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F1F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _moreInk,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _moreGray,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _playerAccent.withValues(alpha: 0.12)
              : const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _playerAccent : const Color(0xFFE8E9ED),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? _playerAccent : _moreInk,
          ),
        ),
      ),
    );
  }
}

/// 图三：更多首页 2×5
class _MoreHomePage extends StatelessWidget {
  const _MoreHomePage({
    super.key,
    required this.host,
    required this.onClose,
    required this.onOpen,
  });

  final PlayerSideSettingsHost host;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final h = host;
    final tiles = <_MoreTile>[
      if (h.hasCast)
        _MoreTile(
          icon: CupertinoIcons.tv,
          label: '投屏',
          onTap: () {
            onClose();
            h.onCast();
          },
        ),
      if (h.hasSources)
        _MoreTile(
          icon: CupertinoIcons.layers_alt_fill,
          label: '播放线路',
          onTap: () {
            onClose();
            h.onOpenSources();
          },
        ),
      _MoreTile(
        icon: CupertinoIcons.rectangle_on_rectangle,
        label: '画中画',
        onTap: () {
          onClose();
          h.onPip?.call();
          if (h.onPip == null) {
            DialogX.showWarning('当前环境暂不支持画中画');
          }
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.moon_zzz,
        label: '定时关闭',
        onTap: () => onOpen('sleep'),
      ),
      _MoreTile(
        icon: CupertinoIcons.arrow_down_to_line,
        label: '下载',
        onTap: () {
          DialogX.showWarning('请从详情页使用缓存下载');
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.gauge,
        label: '倍速',
        onTap: () => onOpen('speed'),
      ),
      _MoreTile(
        icon: CupertinoIcons.video_camera,
        label: h.currentQuality?.shortLabel ?? h.qualityPrefer.label,
        onTap: () => onOpen('quality'),
      ),
      _MoreTile(
        icon: CupertinoIcons.music_note_2,
        label: '音频播放',
        active: !h.settings.keepScreenOn,
        onTap: () {
          final next = h.settings.copyWith(keepScreenOn: false);
          h.onSettings(next);
          DialogX.showSuccess('已切换为后台音频优先');
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.nosign,
        label: '设为禁看',
        onTap: () => DialogX.showWarning('禁看列表功能即将上线'),
      ),
      _MoreTile(
        icon: CupertinoIcons.headphones,
        label: '后台播放',
        active: !h.settings.keepScreenOn,
        onTap: () {
          final next = !h.settings.keepScreenOn;
          h.onSettings(h.settings.copyWith(keepScreenOn: next));
          DialogX.showSuccess(next ? '已开启屏幕常亮' : '已允许息屏后台播放倾向');
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.arrow_2_squarepath,
        label: h.settings.loopSingle ? '循环·开' : '循环播放',
        active: h.settings.loopSingle,
        onTap: () {
          final next = !h.settings.loopSingle;
          // 开循环时关掉连播，避免片尾抢跳下一集
          h.onSettings(
            h.settings.copyWith(
              loopSingle: next,
              autoPlayNext: next ? false : h.settings.autoPlayNext,
            ),
          );
          DialogX.showSuccess(next ? '已开启单集循环' : '已关闭循环');
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.exclamationmark_triangle,
        label: '侵权/举报',
        onTap: () {
          onClose();
          h.onReportError();
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.pencil_outline,
        label: '问题反馈',
        onTap: () {
          onClose();
          h.onReportError();
        },
      ),
    ];

    // 第二行下方再放锁屏等核心播控，仍在同一白卡片内
    final extra = <_MoreTile>[
      _MoreTile(
        icon: h.locked ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
        label: h.locked ? '解锁屏幕' : '锁定屏幕',
        onTap: () {
          onClose();
          h.onToggleLock();
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.camera,
        label: '截图',
        onTap: () {
          onClose();
          h.onScreenshot();
        },
      ),
      _MoreTile(
        icon: CupertinoIcons.rectangle_expand_vertical,
        label: '画面比例',
        onTap: () => onOpen('aspect'),
      ),
      _MoreTile(
        icon: CupertinoIcons.arrow_left_right_square,
        label: h.settings.mirrorX ? '镜像·开' : '镜像翻转',
        active: h.settings.mirrorX,
        onTap: () {
          final next = !h.settings.mirrorX;
          h.onSettings(
            h.settings.copyWith(mirrorX: next, mirrorY: false),
          );
          DialogX.showSuccess(next ? '已开启左右镜像' : '已关闭镜像');
        },
      ),
      if (h.enableDanmaku)
        _MoreTile(
          icon: CupertinoIcons.text_bubble,
          label: '弹幕设置',
          onTap: () => onOpen('danmaku'),
        ),
      _MoreTile(
        icon: CupertinoIcons.slider_horizontal_3,
        label: '更多设置',
        onTap: () => onOpen('more'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '更多',
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _moreInk,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(
                CupertinoIcons.xmark,
                size: 18,
                color: _moreGray,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 窄侧栏 / 矮底栏时放宽格子高度，避免图标+文案把格子撑爆
              final cellW = (constraints.maxWidth - 4 * 4) / 5;
              final minH = 72.0;
              final ratio = (cellW / minH).clamp(0.55, 0.85);
              return GridView.count(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 4,
                childAspectRatio: ratio,
                physics: const BouncingScrollPhysics(),
                children: [
                  ...tiles,
                  ...extra,
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ink = active ? _playerAccent : _moreInk;
    final gray = active ? _playerAccent : _moreGray;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active
                    ? _playerAccent.withValues(alpha: 0.12)
                    : const Color(0xFFF2F3F5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: ink),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: gray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubPageScaffold extends StatelessWidget {
  const _SubPageScaffold({
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _moreInk,
                ),
              ),
            ),
            IconButton(
              onPressed: onBack,
              icon: const Icon(
                CupertinoIcons.xmark,
                size: 18,
                color: _moreGray,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(child: child),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _moreInk,
              ),
            ),
          ),
          PlayerSettingSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LightTile extends StatelessWidget {
  const _LightTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: 14,
          color: selected ? _playerAccent : _moreInk,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      trailing: selected
          ? Icon(CupertinoIcons.check_mark, color: _playerAccent, size: 18)
          : null,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}

class _AspectPage extends StatelessWidget {
  const _AspectPage({
    super.key,
    required this.value,
    required this.onBack,
    required this.onChanged,
  });

  final PlayerAspectMode value;
  final VoidCallback onBack;
  final ValueChanged<PlayerAspectMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: '画面比例',
      onBack: onBack,
      child: ListView(
        children: [
          for (final m in PlayerAspectMode.values)
            _LightTile(
              title: m.label,
              selected: value == m,
              onTap: () => onChanged(m),
            ),
        ],
      ),
    );
  }
}

class _SourcesPage extends StatefulWidget {
  const _SourcesPage({
    super.key,
    required this.names,
    required this.selected,
    required this.probeUrls,
    required this.onBack,
    required this.onSelect,
  });

  final List<String> names;
  final int selected;
  final List<String> probeUrls;
  final VoidCallback onBack;
  final ValueChanged<int> onSelect;

  @override
  State<_SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<_SourcesPage> {
  final Map<int, int?> _latency = {};
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_runProbe());
  }

  Future<void> _runProbe() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _latency.clear();
    });
    final futures = <Future<void>>[];
    for (var i = 0; i < widget.names.length; i++) {
      final url = i < widget.probeUrls.length ? widget.probeUrls[i] : '';
      futures.add(() async {
        final ms = url.trim().isEmpty ? null : await SourceLatency.probe(url);
        if (!mounted) return;
        setState(() => _latency[i] = ms);
      }());
    }
    await Future.wait(futures);
    if (mounted) setState(() => _probing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: '播放线路',
      onBack: widget.onBack,
      child: ListView(
        children: [
          if (_probing)
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                '正在测速…',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  color: _moreGray,
                ),
              ),
            ),
          for (var i = 0; i < widget.names.length; i++)
            _LightTile(
              title: () {
                final raw = widget.names[i].trim();
                final name = raw.isEmpty ? '线路${i + 1}' : raw;
                if (!_latency.containsKey(i)) {
                  return _probing ? '$name · …' : name;
                }
                return '$name · ${SourceLatency.label(_latency[i])}';
              }(),
              selected: i == widget.selected,
              onTap: () => widget.onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _SpeedPage extends StatelessWidget {
  const _SpeedPage({
    super.key,
    required this.value,
    required this.onBack,
    required this.onChanged,
  });

  final double value;
  final VoidCallback onBack;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: '播放倍速',
      onBack: onBack,
      child: ListView(
        children: [
          for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0])
            _LightTile(
              title: VodPlayback.rateLabel(r),
              selected: (value - r).abs() < 0.01,
              onTap: () => onChanged(r),
            ),
        ],
      ),
    );
  }
}

class _QualityPage extends StatelessWidget {
  const _QualityPage({
    super.key,
    required this.prefer,
    required this.variants,
    required this.current,
    required this.onBack,
    this.onPrefer,
    this.onVariant,
  });

  final VodQualityTier prefer;
  final List<VodHlsVariant> variants;
  final VodHlsVariant? current;
  final VoidCallback onBack;
  final ValueChanged<VodQualityTier>? onPrefer;
  final ValueChanged<VodHlsVariant>? onVariant;

  @override
  Widget build(BuildContext context) {
    final multi = variants.length > 1;
    return _SubPageScaffold(
      title: '清晰度',
      onBack: onBack,
      child: ListView(
        children: [
          if (multi) ...[
            _LightTile(
              title: '自动（推荐）',
              selected: prefer == VodQualityTier.auto,
              onTap: () => onPrefer?.call(VodQualityTier.auto),
            ),
            for (final v in [...variants].reversed)
              _LightTile(
                title: v.label,
                selected:
                    current?.url == v.url && prefer != VodQualityTier.auto,
                onTap: () => onVariant?.call(v),
              ),
          ] else ...[
            _LightTile(
              title:
                  '${(current ?? (variants.isNotEmpty ? variants.first : null))?.shortLabel ?? '原画'}（当前线路）',
              selected: true,
              onTap: () {},
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '此线路只有单一清晰度。可在「播放线路」里换源，部分线路自带更高画质。',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFF888888),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SleepPage extends StatelessWidget {
  const _SleepPage({
    super.key,
    required this.minutes,
    required this.onBack,
    required this.onChanged,
  });

  final int minutes;
  final VoidCallback onBack;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: '定时关闭',
      onBack: onBack,
      child: ListView(
        children: [
          for (final m in const [0, 15, 30, 45, 60])
            _LightTile(
              title: m == 0 ? '关闭' : '$m 分钟',
              selected: minutes == m,
              onTap: () => onChanged(m),
            ),
        ],
      ),
    );
  }
}

class _SkipPage extends StatelessWidget {
  const _SkipPage({
    super.key,
    required this.prefs,
    required this.onBack,
    required this.onChanged,
    this.positionSec = 0,
    this.durationSec = 0,
  });

  final PlayerSkipPrefs prefs;
  final VoidCallback onBack;
  final ValueChanged<PlayerSkipPrefs> onChanged;
  final int positionSec;
  final int durationSec;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: '跳过片头片尾',
      onBack: onBack,
      child: ListView(
        children: [
          _SwitchRow(
            title: '启用跳过',
            value: prefs.enabled,
            onChanged: (v) => onChanged(prefs.copyWith(enabled: v)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              '也可在进度条上长按，把当前位置设为片头结束或片尾开始',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                color: _moreGray,
                height: 1.35,
              ),
            ),
          ),
          _LightTile(
            title: '用当前进度设为片头结束（${positionSec}s）',
            selected: false,
            onTap: () {
              onChanged(
                prefs.copyWith(
                  enabled: true,
                  introSeconds: positionSec.clamp(0, 600),
                ),
              );
              DialogX.showSuccess('已设片头结束于 ${positionSec}s');
            },
          ),
          _LightTile(
            title: '用当前进度设为片尾开始',
            selected: false,
            onTap: () {
              final remain = durationSec > 0
                  ? (durationSec - positionSec).clamp(0, 600)
                  : 90;
              onChanged(
                prefs.copyWith(enabled: true, outroSeconds: remain),
              );
              DialogX.showSuccess('已设片尾（距结束 ${remain}s）');
            },
          ),
          Text('片头 ${prefs.introSeconds}s',
              style: const TextStyle(fontFamily: 'AppSans', color: _moreGray)),
          PlayerSettingSlider(
            value: prefs.introSeconds.toDouble(),
            min: 0,
            max: 180,
            divisions: 36,
            label: '${prefs.introSeconds}',
            darkSurface: false,
            onChanged: (v) =>
                onChanged(prefs.copyWith(introSeconds: v.round())),
          ),
          Text('片尾 ${prefs.outroSeconds}s',
              style: const TextStyle(fontFamily: 'AppSans', color: _moreGray)),
          PlayerSettingSlider(
            value: prefs.outroSeconds.toDouble(),
            min: 0,
            max: 180,
            divisions: 36,
            label: '${prefs.outroSeconds}',
            darkSurface: false,
            onChanged: (v) =>
                onChanged(prefs.copyWith(outroSeconds: v.round())),
          ),
        ],
      ),
    );
  }
}

class _DanmakuPage extends StatelessWidget {
  const _DanmakuPage({
    super.key,
    required this.prefs,
    required this.onBack,
    required this.onChanged,
  });

  final DanmakuDisplayPrefs prefs;
  final VoidCallback onBack;
  final ValueChanged<DanmakuDisplayPrefs> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: '弹幕设置',
      onBack: onBack,
      child: ListView(
        children: [
          _SwitchRow(
            title: '显示弹幕',
            value: prefs.enabled,
            onChanged: (v) => onChanged(prefs.copyWith(enabled: v)),
          ),
          Text('字号 ${prefs.fontSize.round()}',
              style: const TextStyle(fontFamily: 'AppSans', color: _moreGray)),
          PlayerSettingSlider(
            value: prefs.fontSize,
            min: 12,
            max: 26,
            divisions: 14,
            label: '${prefs.fontSize.round()}',
            darkSurface: false,
            onChanged: (v) => onChanged(prefs.copyWith(fontSize: v)),
          ),
          Text('透明度 ${(prefs.opacity * 100).round()}%',
              style: const TextStyle(fontFamily: 'AppSans', color: _moreGray)),
          PlayerSettingSlider(
            value: prefs.opacity,
            min: 0.2,
            max: 1,
            divisions: 8,
            label: '${(prefs.opacity * 100).round()}',
            darkSurface: false,
            onChanged: (v) => onChanged(prefs.copyWith(opacity: v)),
          ),
        ],
      ),
    );
  }
}

class _ExtraSettingsPage extends StatelessWidget {
  const _ExtraSettingsPage({
    super.key,
    required this.host,
    required this.onBack,
    required this.onOpen,
  });

  final PlayerSideSettingsHost host;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final h = host;
    return _SubPageScaffold(
      title: '更多设置',
      onBack: onBack,
      child: ListView(
        children: [
          _LightTile(
            title: '跳过片头片尾',
            selected: false,
            onTap: () => onOpen('skip'),
          ),
          _SwitchRow(
            title: '自动连播',
            value: h.settings.autoPlayNext,
            onChanged: (v) =>
                h.onSettings(h.settings.copyWith(autoPlayNext: v)),
          ),
          _SwitchRow(
            title: '卡顿自动切换线路',
            value: h.settings.autoSourceFailover,
            onChanged: (v) =>
                h.onSettings(h.settings.copyWith(autoSourceFailover: v)),
          ),
          _SwitchRow(
            title: '镜像翻转',
            value: h.settings.mirrorX,
            onChanged: (v) => h.onSettings(h.settings.copyWith(mirrorX: v)),
          ),
          _SwitchRow(
            title: '长按倍速',
            value: h.settings.holdBoostEnabled,
            onChanged: (v) =>
                h.onSettings(h.settings.copyWith(holdBoostEnabled: v)),
          ),
          _SwitchRow(
            title: '循环播放',
            value: h.settings.loopSingle,
            onChanged: (v) => h.onSettings(
              h.settings.copyWith(
                loopSingle: v,
                autoPlayNext: v ? false : h.settings.autoPlayNext,
              ),
            ),
          ),
          _SwitchRow(
            title: '双击快进退',
            value: h.settings.doubleTapSeek,
            onChanged: (v) =>
                h.onSettings(h.settings.copyWith(doubleTapSeek: v)),
          ),
          _SwitchRow(
            title: '显示网速',
            value: h.settings.showNetSpeed,
            onChanged: (v) =>
                h.onSettings(h.settings.copyWith(showNetSpeed: v)),
          ),
          _SwitchRow(
            title: '屏幕常亮',
            value: h.settings.keepScreenOn,
            onChanged: (v) =>
                h.onSettings(h.settings.copyWith(keepScreenOn: v)),
          ),
          if (h.hasEpisodes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('选集', style: TextStyle(fontFamily: 'AppSans')),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
              onTap: h.onOpenEpisodes,
            ),
          if (h.hasNext && h.onNextEpisode != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('下一集', style: TextStyle(fontFamily: 'AppSans')),
              onTap: h.onNextEpisode,
            ),
        ],
      ),
    );
  }
}
