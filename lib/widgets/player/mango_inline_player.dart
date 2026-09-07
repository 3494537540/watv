import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../models/movie_models.dart';
import '../../player/danmaku_store.dart';
import '../../player/playback_enhance.dart';
import '../../player/playback_profile.dart';
import '../../player/playback_speed_tracker.dart';
import '../../player/playback_wakelock.dart';
import '../../player/player_danmaku_prefs.dart';
import '../../player/player_pip.dart';
import '../../player/player_settings_store.dart';
import '../../player/player_skip_store.dart';
import '../../player/stream_ahead_cache.dart';
import '../../player/media_kit_vod_engine.dart';
import '../../player/vod_engine.dart';
import '../../player/vod_playback.dart';
import '../../services/app_permission.dart';
import '../../services/danmaku_remote_api.dart';
import '../../services/vod_cache_store.dart';
import '../../state/cms_auth_controller.dart';
import '../dialogx/dialogx.dart';
import '../cast_sheet.dart';
import 'mango_player_chrome.dart';
import 'player_chrome_menus.dart';
import 'player_danmaku_layer.dart';
import 'player_gesture_hud.dart';
import 'player_hold_boost_hud.dart';
import 'player_loading_hud.dart';
import 'play_error_report.dart';
import 'player_sheets.dart';
import 'player_side_settings.dart';

/// ??????????video_player / ExoPlayer?Android ???
class MangoInlinePlayer extends StatefulWidget {
  const MangoInlinePlayer({
    super.key,
    required this.url,
    this.startPositionMs = 0,
    this.showBack = false,
    this.onBack,
    this.onFullscreen,
    this.onProgress,
    this.showNextEpisode = false,
    this.onNextEpisode,
    this.immersiveTop = false,
    this.topOverlay,
    this.episodes = const [],
    this.selectedEpisode = 0,
    this.onEpisodeSelect,
    this.sourceNames = const [],
    this.sourceIndex = 0,
    this.onSourceSelect,
    this.sourceProbeUrls = const [],
    this.onRequestSourceFailover,
    this.onPrepareRetry,
    this.showEpisodesInMenu = false,
    this.vodId,
    this.danmakuTitle = '',
    this.danmakuEpisode = 0,
    this.danmakuEpisodeLabel = '',
    this.onCast,
    this.enableDanmaku = true,
    this.onPip,
    this.posterUrl,
    this.networkFallbackUrl,
  });

  final String url;
  /// 本地缓存播失败时回退的在线地址
  final String? networkFallbackUrl;
  final int startPositionMs;
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback? onFullscreen;
  final void Function(Duration position, Duration duration)? onProgress;
  final bool showNextEpisode;
  final VoidCallback? onNextEpisode;
  final bool immersiveTop;
  final Widget? topOverlay;
  final List<MoviePlayEpisode> episodes;
  final int selectedEpisode;
  final ValueChanged<int>? onEpisodeSelect;
  final List<String> sourceNames;
  final int sourceIndex;
  final ValueChanged<int>? onSourceSelect;
  /// ? sourceNames ???????????
  final List<String> sourceProbeUrls;
  /// ???????????????? true ???????????? url
  final Future<bool> Function()? onRequestSourceFailover;
  /// ??????????????????????????
  final Future<void> Function()? onPrepareRetry;
  /// ?????????????????????
  final bool showEpisodesInMenu;
  /// ? vodId ?????
  final String? vodId;
  /// ?????????????????? B ??
  final String danmakuTitle;
  final int danmakuEpisode;
  /// CMS ????????12??????? B ???
  final String danmakuEpisodeLabel;
  final VoidCallback? onCast;
  /// ??/?????????
  final bool enableDanmaku;
  final VoidCallback? onPip;
  /// ????????????
  final String? posterUrl;

  @override
  State<MangoInlinePlayer> createState() => MangoInlinePlayerState();
}

class MangoInlinePlayerState extends State<MangoInlinePlayer> {
  VodEngine? _engine;
  bool _ready = false;
  bool _failed = false;
  /// ????????????? CMS ????
  String _lastErrorMsg = '';
  bool _failoverBusy = false;
  bool _suppressSourceFailover = false;
  bool _showChrome = true;
  double _playbackRate = 1.0;
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _outroTimer;
  int _initToken = 0;
  PlayerSkipPrefs _skipPrefs = PlayerSkipStore.cached;
  PlayerSettingsPrefs _playerSettings = PlayerSettingsStore.cached;
  bool _outroHandled = false;
  String? _seekHint;
  Timer? _seekHintTimer;
  int _progressTick = 0;
  bool _locked = false;
  bool _isLocalMedia = false;
  /// 当前会话是否以 PlatformView 打开（iOS 弹幕需与此一致，否则发灰）
  bool _openedWithPlatformView = false;
  DanmakuDisplayPrefs _danmakuPrefs = PlayerDanmakuPrefs.cached;
  List<DanmakuItem> _danmakuItems = const [];
  int _danmakuLoadToken = 0;
  final _danmakuApi = DanmakuRemoteApi();
  final _bufferSpeedTracker = PlaybackSpeedTracker();
  Timer? _initSpeedTimer;
  double _holdRateBackup = 1.0;
  bool _holdBoost = false;
  bool _showSideSettings = false;
  bool _showCastSide = false;
  String _sideSettingsPage = 'home';
  int _sleepMinutes = 0;
  Timer? _sleepTimer;
  final _videoShotKey = GlobalKey();
  final _stallLoading = ValueNotifier<bool>(false);

  /// HLS ????
  List<VodHlsVariant> _qualityVariants = const [];
  VodHlsVariant? _currentVariant;
  VodQualityTier _qualityPrefer = VodQualityStore.cached;
  String? _activePlayUrl;
  bool _qualityBusy = false;
  /// 出第一帧后再 seek，避免冷启动跳中部拖慢秒开
  int? _pendingResumeMs;
  bool _pendingSkipIntro = false;
  bool _postStartSeekDone = false;

  /// ???????
  bool _scrubbing = false;
  int _scrubBaseMs = 0;
  int _scrubTargetMs = 0;
  double _scrubAccumDx = 0;

  int get positionMs =>
      _engine?.value.position.inMilliseconds ?? widget.startPositionMs;

  /// 已初始化且（正在播 / 有进度 / 无致命错误）——供外层禁止误切线
  bool get isPlaybackHealthy {
    final c = _engine;
    if (c == null || _failed || !_ready) return false;
    final v = c.value;
    if (!v.isInitialized || v.hasError) return false;
    if (v.isPlaying) return true;
    if (v.position.inMilliseconds > 800) return true;
    if (v.duration.inMilliseconds > 0 && v.size.width > 0) return true;
    return false;
  }

  Duration get position =>
      _engine?.value.position ??
      Duration(milliseconds: widget.startPositionMs);

  String get _sourceChromeLabel {
    if (widget.sourceNames.isEmpty) return '??';
    final i = widget.sourceIndex.clamp(0, widget.sourceNames.length - 1);
    final raw = widget.sourceNames[i].trim();
    if (raw.isEmpty) return '??${i + 1}';
    // ???????????
    if (raw.length <= 6) return raw;
    return '${raw.substring(0, 5)}?';
  }

  Future<void> _pickSource([BuildContext? anchor]) async {
    if (widget.sourceNames.length <= 1 || widget.onSourceSelect == null) {
      DialogX.showWarning('????????????');
      return;
    }
    if (_preferSidePopups) {
      _openSideSettings(page: 'sources');
      return;
    }
    final ctx = anchor ?? context;
    if (!ctx.mounted) return;
    final picked = await showChromeSourceMenu(
      ctx,
      names: widget.sourceNames,
      selected: widget.sourceIndex,
      probeUrls: widget.sourceProbeUrls,
    );
    if (picked == null || !mounted) return;
    if (picked == widget.sourceIndex) return;
    widget.onSourceSelect!(picked);
    _onInteract();
  }

  Future<void> _pickSkip(BuildContext anchor) async {
    final action = await showChromeSkipMenu(
      anchor,
      enabled: _skipPrefs.enabled,
      introSec: _skipPrefs.introSeconds,
      outroSec: _skipPrefs.outroSeconds,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'toggle':
        await _saveSkipPrefs(
          _skipPrefs.copyWith(enabled: !_skipPrefs.enabled),
        );
      case 'intro':
        await _markSkipAtCurrent(intro: true);
      case 'outro':
        await _markSkipAtCurrent(intro: false);
    }
    _onInteract();
  }

  Future<void> _markSkipAtCurrent({required bool intro}) async {
    final c = _engine;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position.inSeconds.clamp(0, 600);
    final dur = c.value.duration.inSeconds;
    PlayerSkipPrefs next;
    if (intro) {
      next = _skipPrefs.copyWith(enabled: true, introSeconds: pos);
      DialogX.showSuccess('已记录片头 ${pos}s，开播将自动跳过');
    } else {
      final remain = dur > 0 ? (dur - pos).clamp(0, 600) : 90;
      next = _skipPrefs.copyWith(enabled: true, outroSeconds: remain);
      DialogX.showSuccess('已记录片尾前 ${remain}s，临近将切下一集');
    }
    await _saveSkipPrefs(next);
  }

  Future<void> pause() async {
    await _engine?.pause();
  }

  Future<void> play() async {
    await _engine?.play();
  }

  Future<void> seekTo(Duration position) async {
    await _engine?.seekTo(position);
  }

  /// ?????????????????
  void hideChrome() {
    if (!_showChrome && !_showSideSettings && !_showCastSide) return;
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showChrome = false;
      _showSideSettings = false;
      _showCastSide = false;
    });
  }

  /// ?????????????? sourceRectHint??????
  Rect? playerScreenRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final topLeft = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      topLeft.dx * dpr,
      topLeft.dy * dpr,
      box.size.width * dpr,
      box.size.height * dpr,
    );
  }

  Future<void> enterPictureInPicture() async {
    hideChrome();
    DialogX.dismiss();
    final rect = playerScreenRect();
    // iOS PiP 更稳：先切 PlatformView 再进小窗（Texture 常进不去）
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        !_openedWithPlatformView &&
        _engine != null &&
        (_activePlayUrl?.isNotEmpty ?? false)) {
      final resume = positionMs;
      final wasPlaying = _engine?.value.isPlaying ?? true;
      try {
        await _init(
          forceUrl: _activePlayUrl,
          resumeMs: resume,
          autoPlay: wasPlaying,
          preferPlatformViewOverride: true,
        );
      } catch (e) {
        debugPrint('[pip] reopen platformView fail: $e');
      }
    }
    await PlayerPip.enter(
      sourceRect: rect,
      iosPlayerId: _engine?.nativePlayerId,
      videoAspect: _engine?.value.aspectRatio ?? 16 / 9,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(play());
    });
  }

  void _onPipFlag() {
    if (!mounted) return;
    // ?????????????? VideoPlayer ??
    setState(() {});
    if (PlayerPip.isInPip) {
      hideChrome();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(play());
      });
    }
  }

  /// ?????????
  Future<void> seekBySeconds(int seconds) => _seekRelative(seconds);

  Future<void> _seekRelative(int seconds) async {
    final c = _engine;
    if (c == null || !c.value.isInitialized) return;
    final cur = c.value.position.inMilliseconds;
    final total = c.value.duration.inMilliseconds;
    var next = cur + seconds * 1000;
    if (total > 0) next = next.clamp(0, total);
    await c.seekTo(Duration(milliseconds: next));
    await c.play();
    _flashSeekHint(seconds > 0 ? '+${seconds}s' : '${seconds}s');
    _onInteract();
  }

  void _flashSeekHint(String text) {
    _seekHintTimer?.cancel();
    setState(() => _seekHint = text);
    _seekHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _onDoubleTapDown(TapDownDetails details, double width) {
    if (_locked) return;
    if (!_playerSettings.doubleTapSeek) return;
    if (width <= 0) return;
    final x = details.localPosition.dx;
    if (x < width * 0.35) {
      unawaited(_seekRelative(-10));
    } else if (x > width * 0.65) {
      unawaited(_seekRelative(10));
    }
  }

  String _fmtClock(int ms) {
    final totalSec = (ms ~/ 1000).clamp(0, 999999);
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onScrubStart() {
    StreamAheadCache.instance.setPaused(true);
    StreamAheadCache.instance.abortInFlight();
    if (_locked || !_ready || _holdBoost) return;
    final c = _engine;
    if (c == null || !c.value.isInitialized) return;
    _scrubbing = true;
    _scrubBaseMs = c.value.position.inMilliseconds;
    _scrubTargetMs = _scrubBaseMs;
    _scrubAccumDx = 0;
    _seekHintTimer?.cancel();
    // 拖进度：立刻出加载圈 + 速率（与进度条一致）
    _stallLoading.value = true;
    _bufferSpeedTracker.setLoading(true);
    _bufferSpeedTracker.resetMetrics();
    _bufferSpeedTracker.tick(c.value.buffered, isBuffering: true);
  }

  void _onScrubUpdate(DragUpdateDetails d, double width) {
    if (!_scrubbing || width <= 0) return;
    final c = _engine;
    if (c == null || !c.value.isInitialized) return;
    _scrubAccumDx += d.delta.dx;
    final total = c.value.duration.inMilliseconds;
    if (total <= 0) return;
    // ?????????? 40%??????????
    final deltaMs = (_scrubAccumDx / width * total * 0.4).round();
    _scrubTargetMs = (_scrubBaseMs + deltaMs).clamp(0, total);
    final deltaSec = ((_scrubTargetMs - _scrubBaseMs) / 1000).round();
    final sign = deltaSec >= 0 ? '+' : '';
    setState(() {
      _seekHint =
          '${_fmtClock(_scrubTargetMs)}  $sign${deltaSec}s';
    });
    _bufferSpeedTracker.tick(c.value.buffered, isBuffering: true);
  }

  Future<void> _onScrubEnd() async {
    if (!_scrubbing) return;
    _scrubbing = false;
    final target = _scrubTargetMs;
    _seekHintTimer?.cancel();
    if (mounted) setState(() => _seekHint = null);
    final c = _engine;
    if (c == null || !c.value.isInitialized) {
      _stallLoading.value = false;
      _bufferSpeedTracker.setLoading(false);
      return;
    }
    // 拖进度：打断旁路预热，把带宽让给播放器真正 seek
    StreamAheadCache.instance.abortInFlight();
    StreamAheadCache.instance.setPaused(true);
    StreamAheadCache.instance.updatePosition(target);
    _stallLoading.value = true;
    _bufferSpeedTracker.setLoading(true);
    _bufferSpeedTracker.resetMetrics();
    _bufferSpeedTracker.tick(c.value.buffered, isBuffering: true);
    try {
      await c.seekTo(Duration(milliseconds: target));
      await c.play();
    } catch (_) {}
    _onInteract();
    // 松手后继续显示加载，直到接近目标或超时
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted || _scrubbing) return;
      final eng = _engine;
      if (eng == null || !identical(eng, c)) return;
      final v = eng.value;
      _bufferSpeedTracker.tick(v.buffered, isBuffering: true);
      final near =
          (v.position.inMilliseconds - target).abs() <= 4000;
      // 已在播就尽快收起转圈（HLS 可能长时间 isBuffering=true）
      if (v.isPlaying && near) break;
      if (v.isPlaying && i >= 6) break;
      if (near && v.isPlaying && !v.isBuffering) break;
    }
    if (!mounted || _scrubbing) return;
    _stallLoading.value = false;
    _bufferSpeedTracker.setLoading(false);
  }

  Future<void> _applySkipIntro(VodEngine c) async {
    _skipPrefs = await PlayerSkipStore.load();
    if (!_skipPrefs.enabled || _skipPrefs.introSeconds <= 0) return;
    if (widget.startPositionMs > 3000) return;
    final pos = c.value.position.inSeconds;
    if (pos < _skipPrefs.introSeconds) {
      await c.seekTo(Duration(seconds: _skipPrefs.introSeconds));
    }
  }

  void _checkSkipOutro() {
    if (_outroHandled) return;
    if (_playerSettings.loopSingle) return;
    if (!_playerSettings.autoPlayNext) return;
    if (!widget.showNextEpisode || widget.onNextEpisode == null) return;
    final c = _engine;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration.inSeconds;
    if (dur <= 0) return;
    final remain = dur - c.value.position.inSeconds;
    final threshold = _skipPrefs.enabled && _skipPrefs.outroSeconds > 0
        ? _skipPrefs.outroSeconds
        : 1;
    if (remain <= threshold && remain >= 0) {
      _outroHandled = true;
      widget.onNextEpisode!();
    }
  }

  void _openSideSettings({String page = 'home'}) {
    if (!mounted) return;
    setState(() {
      _sideSettingsPage = page;
      _showSideSettings = true;
      _showChrome = false;
    });
  }

  /// ??????????????????????????? sheet
  Future<void> openSettings({String page = 'home'}) async {
    if (!mounted) return;
    if (widget.immersiveTop) {
      _openSideSettings(page: page);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x99000000),
      isDismissible: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final sh = MediaQuery.sizeOf(ctx).height;
        final sheetH = (sh * 0.72).clamp(160.0, sh < 560 ? sh : 560.0);
        return SizedBox(
          height: sheetH,
          child: PlayerSideSettingsPanel(
            asBottomSheet: true,
            flatMode: true,
            initialPage: page,
            onClose: () {
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            },
            host: _settingsHost(),
          ),
        );
      },
    );
  }

  PlayerSideSettingsHost _settingsHost() {
    return PlayerSideSettingsHost(
      playbackRate: _playbackRate,
      onPlaybackRate: (r) async {
        _playbackRate = r;
        await _engine?.setPlaybackSpeed(r);
        if (r >= 1.5) {
          await _savePlayerSettings(
            _playerSettings.copyWith(
              holdBoostRate: r.clamp(1.5, 3.0),
            ),
          );
        } else if (mounted) {
          setState(() {});
        }
      },
      danmakuPrefs: _danmakuPrefs,
      onDanmakuPrefs: (p) => unawaited(_saveDanmakuPrefs(p)),
      skipPrefs: _skipPrefs,
      onSkipPrefs: (p) => unawaited(_saveSkipPrefs(p)),
      settings: _playerSettings,
      onSettings: (p) => unawaited(_savePlayerSettings(p)),
      sleepMinutes: _sleepMinutes,
      onSleepMinutes: _setSleepMinutes,
      // ??? Navigator.pop?????? onClose?? pop ??????
      onToggleLock: _toggleLock,
      locked: _locked,
      onSendDanmaku: () => unawaited(_sendDanmaku()),
      onScreenshot: () => unawaited(_takeScreenshot()),
      onOpenEpisodes: () => unawaited(_openEpisodes()),
      onOpenSources: () => unawaited(_pickSource()),
      onCast: openCast,
      onPip: () {
        unawaited(enterPictureInPicture());
      },
      hasEpisodes:
          widget.episodes.length > 1 && widget.onEpisodeSelect != null,
      hasSources:
          widget.sourceNames.length > 1 && widget.onSourceSelect != null,
      hasCast: widget.onCast != null,
      hasNext: widget.showNextEpisode,
      onNextEpisode: widget.onNextEpisode,
      onReportError: () => unawaited(_reportPlayError()),
      enableDanmaku: widget.enableDanmaku,
      qualityPrefer: _qualityPrefer,
      qualityVariants: _qualityVariants,
      currentQuality: _currentVariant,
      onQualityPrefer: (t) => unawaited(_applyQualityPrefer(t)),
      onQualityVariant: (v) => unawaited(_switchToVariant(v, prefer: v.tier)),
      positionSec: position.inSeconds,
      durationSec: _engine?.value.duration.inSeconds ?? 0,
      sourceNames: widget.sourceNames,
      sourceIndex: widget.sourceIndex,
      sourceProbeUrls: widget.sourceProbeUrls,
      onSourceSelect: widget.onSourceSelect,
      isLocalMedia: _isLocalMedia,
      audioTrackOptions: _mediaKitAudioOptions(),
      subtitleTrackOptions: _mediaKitSubtitleOptions(),
      audioDeviceOptions: _mediaKitAudioDeviceOptions(),
      onAudioTrackId: (id) {
        final e = _engine;
        if (e is MediaKitVodEngine) {
          unawaited(e.selectAudioTrackById(id).then((_) {
            if (mounted) setState(() {});
          }));
        }
      },
      onSubtitleTrackId: (id) {
        final e = _engine;
        if (e is MediaKitVodEngine) {
          unawaited(e.selectSubtitleTrackById(id).then((_) {
            if (mounted) setState(() {});
          }));
        }
      },
      onAudioDeviceId: (id) {
        final e = _engine;
        if (e is MediaKitVodEngine) {
          unawaited(e.selectAudioDeviceByName(id).then((_) {
            if (mounted) setState(() {});
          }));
        }
      },
    );
  }

  List<VodTrackOption> _mediaKitAudioOptions() {
    final e = _engine;
    if (e is! MediaKitVodEngine) return const [];
    return [
      for (final t in e.audioTrackChoices())
        VodTrackOption(id: t.id, label: t.label, selected: t.selected),
    ];
  }

  List<VodTrackOption> _mediaKitSubtitleOptions() {
    final e = _engine;
    if (e is! MediaKitVodEngine) return const [];
    return [
      for (final t in e.subtitleTrackChoices())
        VodTrackOption(id: t.id, label: t.label, selected: t.selected),
    ];
  }

  List<VodTrackOption> _mediaKitAudioDeviceOptions() {
    final e = _engine;
    if (e is! MediaKitVodEngine) return const [];
    return [
      for (final t in e.audioDeviceChoices())
        VodTrackOption(id: t.id, label: t.label, selected: t.selected),
    ];
  }

  void _closeSideSettings() {
    if (!_showSideSettings) return;
    setState(() {
      _showSideSettings = false;
      _sideSettingsPage = 'home';
    });
    _onInteract();
  }

  void _closeCastSide() {
    if (!_showCastSide) return;
    setState(() => _showCastSide = false);
    _onInteract();
  }

  void _openCastSide() {
    if (!mounted) return;
    setState(() {
      _showCastSide = true;
      _showSideSettings = false;
      _showChrome = false;
    });
  }

  void openCast() {
    // ??????????????????????????????
    final wide =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    if (widget.immersiveTop && wide) {
      _openCastSide();
      return;
    }
    widget.onCast?.call();
  }

  Future<void> _reportPlayError() async {
    final c = _engine;
    var err = _lastErrorMsg.trim();
    if (err.isEmpty && c != null && c.value.hasError) {
      err = c.value.errorDescription?.trim() ?? '';
    }
    if (err.isEmpty && _failed) {
      err = '????';
    }
    if (err.isEmpty) {
      err = '???????/??/????';
    }
    final sourceName = (widget.sourceIndex >= 0 &&
            widget.sourceIndex < widget.sourceNames.length)
        ? widget.sourceNames[widget.sourceIndex]
        : '';
    final epLabel = widget.danmakuEpisodeLabel.trim().isNotEmpty
        ? widget.danmakuEpisodeLabel.trim()
        : (widget.selectedEpisode >= 0 &&
                widget.selectedEpisode < widget.episodes.length
            ? widget.episodes[widget.selectedEpisode].name
            : '');
    await showPlayErrorReportDialog(
      context,
      vodId: widget.vodId ?? '',
      title: widget.danmakuTitle,
      sourceName: sourceName,
      sourceIndex: widget.sourceIndex,
      episodeIndex: widget.selectedEpisode,
      episodeLabel: epLabel,
      playUrl: widget.url,
      errorMsg: err,
    );
  }

  Future<void> _savePlayerSettings(PlayerSettingsPrefs prefs) async {
    final prev = _playerSettings;
    await PlayerSettingsStore.save(prefs);
    if (!mounted) return;
    setState(() => _playerSettings = prefs);
    await _engine?.setLooping(prefs.loopSingle);
    if (prefs.keepScreenOn) {
      await PlaybackWakelock.acquire();
    } else {
      await PlaybackWakelock.release();
    }
    final kernelChanged = prev.kernel != prefs.kernel;
    if (kernelChanged) {
      final resume = positionMs;
      final wasPlaying = _engine?.value.isPlaying ?? true;
      await _init(
        forceUrl: _activePlayUrl ?? widget.url,
        resumeMs: resume,
        autoPlay: wasPlaying,
      );
      return;
    }
    final modeChanged = prev.playMode != prefs.playMode;
    final cacheChanged = prev.streamCacheEnabled != prefs.streamCacheEnabled;
    if (modeChanged &&
        _qualityPrefer == VodQualityTier.auto &&
        _qualityVariants.length > 1) {
      final v = VodPlayback.pickVariant(
        _qualityVariants,
        VodQualityTier.auto,
        playMode: prefs.playMode,
      );
      if (v != null && v.url != _currentVariant?.url) {
        unawaited(_switchToVariant(v, prefer: VodQualityTier.auto));
        return;
      }
    }
    if (modeChanged || cacheChanged) {
      _syncStreamAheadCache();
    }
  }


  Future<void> _enrichVariantsLater(String masterUrl, int token) async {
    try {
      final resolved = await VodPlayback.resolveStream(
        masterUrl,
        prefer: _qualityPrefer,
        playMode: _playerSettings.playMode,
      );
      if (!mounted || token != _initToken) return;
      if (resolved.variants.length < 2) return;
      setState(() {
        _qualityVariants = resolved.variants;
        _currentVariant ??= resolved.selected ??
            VodPlayback.pickVariant(
              resolved.variants,
              _qualityPrefer,
              playMode: _playerSettings.playMode,
            );
      });
    } catch (_) {}
  }

  Future<void> _deferredAfterPlay(int token) async {
    // 弹幕延后，少抢首包带宽
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (!mounted || token != _initToken) return;
    unawaited(_loadDanmaku());
    // 前方缓冲够了再开旁路预热，并尝试升到目标清晰度
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || token != _initToken) return;
      final c = _engine;
      if (c == null || !c.value.isInitialized || c.value.hasError) return;
      if (c.value.isBuffering) continue;
      final ahead = _bufferedAheadMsOf(c.value);
      if (ahead < 0 || ahead >= 8000 || i >= 8) {
        _syncStreamAheadCache();
        unawaited(_maybeUpgradeQualityAfterStable(token));
        return;
      }
    }
  }

  /// 出画后再续播/跳片头，避免冷启动 seek 拖死第一帧
  Future<void> _runPostStartSeek(int token) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || token != _initToken || _postStartSeekDone) return;
      final c = _engine;
      if (c == null || !c.value.isInitialized || c.value.hasError) return;
      final v = c.value;
      final painted = v.isPlaying ||
          v.size.width > 0 ||
          v.position.inMilliseconds > 200 ||
          (!v.isBuffering && v.buffered.isNotEmpty);
      if (!painted && i < 8) continue;

      final resume = _pendingResumeMs;
      _pendingResumeMs = null;
      final doSkip = _pendingSkipIntro;
      _pendingSkipIntro = false;
      _postStartSeekDone = true;

      if (resume != null && resume > 1500) {
        try {
          await c.seekTo(Duration(milliseconds: resume));
          if (!c.value.isPlaying) await c.play();
        } catch (_) {}
      }
      if (doSkip) {
        try {
          await _applySkipIntro(c);
          if (!c.value.isPlaying) await c.play();
        } catch (_) {}
      }
      return;
    }
    _pendingResumeMs = null;
    _pendingSkipIntro = false;
    _postStartSeekDone = true;
  }

  /// 自动档：秒开用中低码率，稳住后升到 playMode 目标档
  Future<void> _maybeUpgradeQualityAfterStable(int token) async {
    if (!mounted || token != _initToken) return;
    if (_isLocalMedia || _qualityBusy) return;
    if (_qualityPrefer != VodQualityTier.auto) return;
    if (_qualityVariants.length < 2) return;
    final upgrade = VodPlayback.pickUpgradeVariant(
      variants: _qualityVariants,
      prefer: _qualityPrefer,
      playMode: _playerSettings.playMode,
      current: _currentVariant,
    );
    if (upgrade == null) return;
    final c = _engine;
    if (c == null || !c.value.isInitialized || c.value.hasError) return;
    if (c.value.isBuffering) return;
    final ahead = _bufferedAheadMsOf(c.value);
    if (ahead >= 0 && ahead < 6000) return;
    // 无感升清：保留进度（不弹 Toast）
    final resume = positionMs;
    final wasPlaying = _engine?.value.isPlaying ?? true;
    if (!mounted) return;
    setState(() {
      _currentVariant = upgrade;
    });
    await _init(
      forceUrl: upgrade.url,
      resumeMs: resume,
      autoPlay: wasPlaying,
    );
  }

  int _bufferedAheadMsOf(VodEngineValue v) {
    final pos = v.position;
    Duration end = Duration.zero;
    for (final r in v.buffered) {
      if (r.end > end) end = r.end;
    }
    if (v.buffered.isEmpty) return -1;
    if (end <= pos) return 0;
    return (end - pos).inMilliseconds;
  }

  void _syncStreamAheadCache() {
    final profile = PlaybackProfile.of(_playerSettings);
    final url = _activePlayUrl?.trim() ?? '';
    if (_ready &&
        !_failed &&
        url.isNotEmpty &&
        _playerSettings.streamCacheEnabled &&
        profile.warmSegmentCount > 0 &&
        !_isLocalMedia) {
      StreamAheadCache.instance.start(
        playUrl: url,
        warmSegmentCount: profile.warmSegmentCount,
        positionMs: positionMs,
      );
    } else {
      StreamAheadCache.instance.stop();
    }
  }

  Future<void> _saveSkipPrefs(PlayerSkipPrefs prefs) async {
    await PlayerSkipStore.save(prefs);
    if (!mounted) return;
    setState(() => _skipPrefs = prefs);
  }

  Future<void> _saveDanmakuPrefs(DanmakuDisplayPrefs prefs) async {
    await PlayerDanmakuPrefs.save(prefs);
    if (!mounted) return;
    setState(() => _danmakuPrefs = prefs);
    await _syncIosSurfaceForDanmaku();
  }

  void _setSleepMinutes(int minutes) {
    _sleepTimer?.cancel();
    _sleepMinutes = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () async {
        if (!mounted) return;
        await _engine?.pause();
        setState(() => _sleepMinutes = 0);
        DialogX.showSuccess('??????????');
      });
      DialogX.showSuccess('?? $minutes ?????');
    }
    if (mounted) setState(() {});
  }

  Future<void> _takeScreenshot() async {
    try {
      final allowed = await AppPermission.requestWithRationale(
        AppPermissionKind.saveMedia,
        context: context,
        title: '????',
        message: '??????????????????????',
      );
      if (!allowed) return;

      // media_kit：优先原生截帧（含硬解画面）
      final mk = _engine;
      if (mk is MediaKitVodEngine) {
        final bytes = await mk.takeScreenshot();
        if (bytes != null && bytes.isNotEmpty) {
          await Gal.putImageBytes(bytes);
          DialogX.showSuccess('??????');
          return;
        }
      }

      final ro = _videoShotKey.currentContext?.findRenderObject();
      final boundary = ro is RenderRepaintBoundary ? ro : null;
      if (boundary == null) {
        DialogX.showWarning('?????????????/?????');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) {
        DialogX.showWarning('????');
        return;
      }
      await Gal.putImageBytes(bytes.buffer.asUint8List());
      DialogX.showSuccess('??????');
    } catch (e) {
      debugPrint('[player] screenshot fail: $e');
      DialogX.showWarning('??????????????????');
    }
  }
  Future<void> _openEpisodes([BuildContext? anchor]) async {
    final eps = widget.episodes;
    if (eps.length <= 1 || widget.onEpisodeSelect == null) return;
    final ctx = anchor ?? context;
    if (!ctx.mounted) return;
    // ?????????????
    await showPlayerEpisodeSheet(
      context: ctx,
      episodes: eps,
      selected: widget.selectedEpisode,
      onSelect: widget.onEpisodeSelect!,
    );
    _onInteract();
  }

  // ????/??/???/????????????????????
  bool get _preferSidePopups => false;

  Future<void> _pickPlaybackSpeed([BuildContext? anchor]) async {
    if (_preferSidePopups) {
      _openSideSettings(page: 'speed');
      return;
    }
    final ctx = anchor ?? context;
    if (!ctx.mounted) return;
    final picked = await showChromeSpeedMenu(ctx, current: _playbackRate);
    if (picked == null || !mounted) return;
    _playbackRate = picked;
    await _engine?.setPlaybackSpeed(picked);
    // ???? ?1.5 ?????????????????????? 2x?
    if (picked >= 1.5) {
      await _savePlayerSettings(
        _playerSettings.copyWith(holdBoostRate: picked.clamp(1.5, 3.0)),
      );
    } else if (mounted) {
      setState(() {});
    }
    _onInteract();
  }

  Future<void> _pickAspect([BuildContext? anchor]) async {
    if (_preferSidePopups) {
      _openSideSettings(page: 'aspect');
      return;
    }
    final ctx = anchor ?? context;
    if (!ctx.mounted) return;
    final picked = await showChromeAspectMenu(
      ctx,
      current: _playerSettings.aspect,
    );
    if (picked == null || !mounted) return;
    await _savePlayerSettings(_playerSettings.copyWith(aspect: picked));
    _onInteract();
  }

  Future<void> _pickQuality([BuildContext? anchor]) async {
    if (_preferSidePopups) {
      _openSideSettings(page: 'quality');
      return;
    }
    final ctx = anchor ?? context;
    if (!ctx.mounted) return;
    final picked = await showChromeQualityMenu(
      ctx,
      prefer: _qualityPrefer,
      variants: _qualityVariants,
      current: _currentVariant,
      sourceNames: widget.sourceNames,
      sourceIndex: widget.sourceIndex,
    );
    if (picked == null || !mounted) return;
    if (picked is String && picked.startsWith('_src:')) {
      final i = int.tryParse(picked.substring(5));
      if (i != null && widget.onSourceSelect != null) {
        widget.onSourceSelect!(i);
      } else if (i != null) {
        DialogX.showWarning('???????????');
      }
      _onInteract();
      return;
    }
    if (picked == '_sole') {
      if (widget.sourceNames.length > 1) {
        DialogX.showWarning('?????????????????');
      } else {
        DialogX.showWarning('???????????');
      }
      _onInteract();
      return;
    }
    if (picked is VodQualityTier) {
      await _applyQualityPrefer(picked);
    } else if (picked is VodHlsVariant) {
      await _switchToVariant(picked, prefer: picked.tier);
    }
    _onInteract();
  }

  Future<void> _applyQualityPrefer(VodQualityTier tier) async {
    await VodQualityStore.save(tier);
    if (!mounted) return;
    setState(() => _qualityPrefer = tier);
    if (_qualityVariants.length < 2) {
      DialogX.showWarning(
        widget.sourceNames.length > 1
            ? '?????????????????'
            : '???????????',
      );
      return;
    }
    final v = VodPlayback.pickVariant(_qualityVariants, tier);
    if (v != null) await _switchToVariant(v, prefer: tier);
  }

  Future<void> _switchToVariant(
    VodHlsVariant variant, {
    VodQualityTier? prefer,
  }) async {
    if (_qualityBusy) return;
    if (_currentVariant?.url == variant.url &&
        _activePlayUrl == variant.url) {
      if (prefer != null) {
        await VodQualityStore.save(prefer);
        if (mounted) setState(() => _qualityPrefer = prefer);
      }
      DialogX.showSuccess('?? ${variant.shortLabel}');
      return;
    }
    final resume = positionMs;
    final wasPlaying = _engine?.value.isPlaying ?? true;
    if (prefer != null) {
      await VodQualityStore.save(prefer);
    }
    if (!mounted) return;
    setState(() {
      _qualityPrefer = prefer ?? variant.tier;
      _currentVariant = variant;
    });
    await _init(
      forceUrl: variant.url,
      resumeMs: resume,
      autoPlay: wasPlaying,
    );
    if (mounted && !_failed) {
      DialogX.showSuccess('???? ${variant.shortLabel}');
    }
  }


  Future<bool> _trySourceFailover(String reason, {bool force = false}) async {
    // 卡顿自动切线可关；硬性 Source error（源地址打不开）仍切，避免死守坏线
    if (!force && !_playerSettings.autoSourceFailover) return false;
    if (_failoverBusy) return false;
    final cb = widget.onRequestSourceFailover;
    if (cb == null) return false;
    _failoverBusy = true;
    _lastErrorMsg = reason;
    try {
      if (mounted) {
        setState(() {
          _failed = false;
          _ready = false;
        });
      }
      final ok = await cb();
      if (ok) {
        // 等新 url 的 _init 接手；否则旧引擎 error 会连环把所有线路标死
        await Future<void>.delayed(const Duration(milliseconds: 1800));
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _failoverBusy = false;
    }
  }

  /// Exo / AVPlayer 明确打不开源（404、DNS、协议错）时强制换线
  static bool _isHardSourceError(String reason) {
    final r = reason.toLowerCase();
    return r.contains('source error') ||
        r.contains('exoplayer') ||
        r.contains('videoerror') ||
        r.contains('404') ||
        r.contains('file not found') ||
        r.contains('unable to connect') ||
        r.contains('failed to connect') ||
        r.contains('httperror') ||
        r.contains('response code');
  }

  Future<void> _onPlayFailed(String reason) async {
    if (!mounted) return;
    // 已出画时的偶发错误：先别连环切线
    if (isPlaybackHealthy && positionMs > 2000) {
      return;
    }
    if (!_suppressSourceFailover) {
      final force = _isHardSourceError(reason);
      final switched = await _trySourceFailover(reason, force: force);
      if (switched) return;
    }
    if (!mounted) return;
    setState(() {
      _failed = true;
      _ready = false;
      _lastErrorMsg = reason;
    });
  }

  String? _handledErrorKey;

  void _onPlaybackStatus() {
    final c = _engine;
    if (c == null || !_ready || _failoverBusy || _failed) return;
    if (!c.value.hasError) {
      _handledErrorKey = null;
      return;
    }
    // 已在播：忽略粘住的 error，避免刷屏切线导致卡死
    if (c.value.isPlaying && c.value.position.inMilliseconds > 1500) {
      return;
    }
    final msg = c.value.errorDescription?.trim() ?? '';
    final key = msg.isEmpty ? 'error' : msg;
    if (_handledErrorKey == key) return;
    _handledErrorKey = key;
    unawaited(_onPlayFailed(msg.isEmpty ? '播放出错' : msg));
  }

  Future<void> _manualRetry() async {
    final before = widget.url;
    await widget.onPrepareRetry?.call();
    if (!mounted) return;
    // ????????? url ???? didUpdateWidget ??
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (widget.url != before) return;
    await _init();
  }

  Future<void> _toggleDanmaku() async {
    final next = !_danmakuPrefs.enabled;
    await PlayerDanmakuPrefs.setEnabled(next);
    if (mounted) {
      setState(() => _danmakuPrefs = PlayerDanmakuPrefs.cached);
    }
    await _syncIosSurfaceForDanmaku();
    _onInteract();
  }

  /// iOS：保持 Texture；若仍被 PlatformView 打开则重开
  Future<void> _syncIosSurfaceForDanmaku() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    if (!_ready || _failed || _engine == null) return;
    if (!_openedWithPlatformView) return;
    final pos = _engine!.value.position.inMilliseconds;
    final playing = _engine!.value.isPlaying;
    final url = _activePlayUrl?.trim();
    if (url == null || url.isEmpty) return;
    await _init(forceUrl: url, resumeMs: pos, autoPlay: playing);
  }

  Future<void> _sendDanmaku() async {
    final id = widget.vodId?.trim();
    if (id == null || id.isEmpty) {
      DialogX.showWarning('??????????');
      return;
    }
    if (!_danmakuPrefs.enabled) {
      await PlayerDanmakuPrefs.setEnabled(true);
      if (!mounted) return;
      setState(() => _danmakuPrefs = PlayerDanmakuPrefs.cached);
      await _syncIosSurfaceForDanmaku();
    }
    if (!mounted) return;
    final c = _engine;
    final timeSec = (c?.value.position.inMilliseconds ?? 0) / 1000.0;
    final draft = await showSendDanmakuSheet(context, timeSec: timeSec);
    if (draft == null || !mounted) return;
    final item = DanmakuItem(
      timeSec: timeSec,
      text: draft.text,
      color: draft.color,
      self: true,
    );
    final author = CmsAuthController.instance.user?.userName.trim();
    final remoteOk = await _danmakuApi.send(
      vodId: id,
      episode: widget.danmakuEpisode,
      playUrl: widget.url,
      item: item,
      title: widget.danmakuTitle,
      episodeLabel: widget.danmakuEpisodeLabel,
      author: (author == null || author.isEmpty) ? '?' : author,
    );
    await DanmakuStore.append(
      vodId: id,
      ep: widget.danmakuEpisode,
      item: item,
    );
    if (!mounted) return;
    setState(() {
      _danmakuItems = [..._danmakuItems, item]
        ..sort((a, b) => a.timeSec.compareTo(b.timeSec));
    });
    if (remoteOk) {
      DialogX.showSuccess('?????');
    } else {
      DialogX.showWarning('???????????????????');
    }
    _onInteract();
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      if (_locked) _showChrome = false;
    });
  }

  Future<void> _startHoldBoost() async {
    if (_locked || _holdBoost) return;
    if (!_playerSettings.holdBoostEnabled) return;
    _holdBoost = true;
    _holdRateBackup = _playbackRate;
    final rate = _playerSettings.holdBoostRate;
    _playbackRate = rate;
    await _engine?.setPlaybackSpeed(rate);
    if (mounted) setState(() {});
  }

  Future<void> _endHoldBoost() async {
    if (!_holdBoost) return;
    _holdBoost = false;
    _playbackRate = _holdRateBackup;
    await _engine?.setPlaybackSpeed(_holdRateBackup);
    if (mounted) setState(() {});
  }

  Future<void> _loadDanmaku() async {
    if (!widget.enableDanmaku) {
      if (mounted) setState(() => _danmakuItems = const []);
      return;
    }
    final id = widget.vodId?.trim();
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _danmakuItems = const []);
      return;
    }
    final ep = widget.danmakuEpisode;
    final title = widget.danmakuTitle.trim();
    final token = ++_danmakuLoadToken;
    debugPrint('[danmaku] load start vod=$id ep=$ep title=$title');

    final loaded = await PlayerDanmakuPrefs.load();
    final cached = await DanmakuStore.load(id, ep);
    if (!mounted || token != _danmakuLoadToken) return;
    setState(() {
      _danmakuPrefs = loaded;
      if (cached.isNotEmpty) _danmakuItems = cached;
    });
    unawaited(_syncIosSurfaceForDanmaku());

    List<DanmakuItem> remote = const [];
    try {
      remote = await _danmakuApi
          .fetch(
            vodId: id,
            episode: ep,
            playUrl: widget.url,
            title: title,
            episodeLabel: widget.danmakuEpisodeLabel,
          )
          .timeout(const Duration(seconds: 10), onTimeout: () => const []);
    } catch (e, st) {
      debugPrint('[danmaku] fetch error: $e\n$st');
    }
    if (!mounted || token != _danmakuLoadToken) {
      debugPrint('[danmaku] load cancelled token=$token');
      return;
    }

    debugPrint('[danmaku] load done remote=${remote.length} cached=${cached.length}');

    if (remote.isNotEmpty) {
      final selfOnly = [
        for (final d in cached)
          if (d.self) d,
      ];
      final merged = [...remote, ...selfOnly]
        ..sort((a, b) => a.timeSec.compareTo(b.timeSec));
      await DanmakuStore.save(vodId: id, ep: ep, items: merged);
      if (!mounted || token != _danmakuLoadToken) return;
      setState(() => _danmakuItems = merged);
      // ????????? Toast
    } else if (cached.isEmpty) {
      setState(() => _danmakuItems = const []);
      // ??????????
    }
  }

  /// ????????????????????????
  Future<void> forceStop() async {
    _initToken++;
    _holdBoost = false;
    _showSideSettings = false;
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _outroTimer?.cancel();
    _seekHintTimer?.cancel();
    _sleepTimer?.cancel();
    StreamAheadCache.instance.stop();
    _stallLoading.value = false;
    _stopInitSpeedTracking();
    final c = _engine;
    _engine = null;
    if (c != null) {
      try {
        if (c.value.isInitialized) await c.pause();
      } catch (_) {}
      try {
        await c.release();
      } catch (_) {}
      c.dispose();
    }
    await PlaybackWakelock.release();
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _ready = false;
        _failed = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _PlaybackSession.attach(this);
    PlayerPip.inPip.addListener(_onPipFlag);
    PlayerPip.setOnEntered(() {
      if (!mounted) return;
      hideChrome();
      unawaited(play());
    });
    unawaited(PlayerSkipStore.load().then((p) {
      if (mounted) setState(() => _skipPrefs = p);
    }));
    unawaited(PlayerSettingsStore.load().then((p) {
      if (mounted) setState(() => _playerSettings = p);
    }));
    unawaited(PlayerDanmakuPrefs.load().then((p) {
      if (mounted) setState(() => _danmakuPrefs = p);
    }));
    unawaited(VodQualityStore.load().then((q) {
      if (mounted) setState(() => _qualityPrefer = q);
    }));
    // ??????????????????
    _init();
  }


  @override
  void reassemble() {
    super.reassemble();
    // ?????? dispose????????? ExoPlayer
    unawaited(forceStop());
  }

  @override
  void didUpdateWidget(covariant MangoInlinePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _init();
    }
    if (oldWidget.vodId != widget.vodId ||
        oldWidget.danmakuEpisode != widget.danmakuEpisode ||
        oldWidget.danmakuEpisodeLabel != widget.danmakuEpisodeLabel ||
        (oldWidget.danmakuTitle != widget.danmakuTitle &&
            widget.danmakuTitle.trim().isNotEmpty &&
            _danmakuItems.isEmpty)) {
      if (oldWidget.danmakuEpisode != widget.danmakuEpisode ||
          oldWidget.vodId != widget.vodId) {
        setState(() => _danmakuItems = const []);
      }
      unawaited(_loadDanmaku());
    }
  }

  Future<void> _init({
    String? forceUrl,
    int? resumeMs,
    bool autoPlay = true,
    bool? preferPlatformViewOverride,
  }) async {
    final token = ++_initToken;
    _handledErrorKey = null;
    _stallLoading.value = false;
    await _disposeController(keepWakelock: false);
    final url = widget.url.trim();
    if (url.isEmpty && (forceUrl == null || forceUrl.trim().isEmpty)) {
      if (!mounted || token != _initToken) return;
      await _onPlayFailed('??????');
      return;
    }

    if (mounted && token == _initToken) {
      setState(() {
        _ready = false;
        _failed = false;
        _showChrome = true;
        _outroHandled = false;
        _qualityBusy = forceUrl != null;
      });
      _bufferSpeedTracker.reset();
      _bufferSpeedTracker.setLoading(true);
    }

    try {
      String playUrl;
      final preservedVariants =
          forceUrl != null ? List<VodHlsVariant>.from(_qualityVariants) : null;
      final preservedCurrent = forceUrl != null ? _currentVariant : null;
      if (forceUrl != null && forceUrl.trim().isNotEmpty) {
        playUrl = forceUrl.trim();
      } else {
        // ????????????? 1.2s????????
        playUrl = url;
        try {
          final loaded = await VodQualityStore.load()
              .timeout(const Duration(milliseconds: 400));
          if (!mounted || token != _initToken) return;
          _qualityPrefer = loaded;
        } catch (_) {}
        try {
          final resolved = await VodPlayback.resolveStream(
            url,
            prefer: _qualityPrefer,
            playMode: _playerSettings.playMode,
            forInstantStart: true,
          ).timeout(
            const Duration(milliseconds: 1600),
            onTimeout: () => VodResolvedStream(playUrl: url),
          );
          if (!mounted || token != _initToken) return;
          playUrl = resolved.playUrl.isNotEmpty ? resolved.playUrl : url;
          if (resolved.variants.isNotEmpty) {
            _qualityVariants = resolved.variants;
            _currentVariant = resolved.selected ??
                VodPlayback.pickStartVariant(
                  resolved.variants,
                  _qualityPrefer,
                  playMode: _playerSettings.playMode,
                );
          } else {
            unawaited(_enrichVariantsLater(url, token));
          }
        } catch (_) {
          playUrl = url;
          unawaited(_enrichVariantsLater(url, token));
        }
      }
      _activePlayUrl = playUrl;
      if (!mounted || token != _initToken) return;
      final isFile = VodPlayback.isLocalMediaPath(playUrl);
      _isLocalMedia = isFile;
      final profile = PlaybackProfile.of(_playerSettings);

      if (isFile) {
        var path = playUrl;
        if (path.startsWith('file:')) {
          path = Uri.parse(path).toFilePath();
        }
        try {
          path = await VodCacheStore.instance
              .prepareLocalMediaPath(path)
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          final msg = '$e';
          throw StateError(
            msg.contains('缓存') || msg.contains('本地')
                ? msg
                    .replaceFirst('Bad state: ', '')
                    .replaceFirst('StateError: ', '')
                : '本地缓存无法打开，请重新下载后离线播放',
          );
        }
        if (!mounted || token != _initToken) return;
        playUrl = path;
        _activePlayUrl = path;
        // 即使变成 http://127.0.0.1 仍视为离线缓存
        _isLocalMedia = true;
        if (!VodPlayback.isLoopbackCacheUrl(path)) {
          final file = File(path);
          if (!await file.exists()) {
            throw StateError('本地缓存文件不存在，请重新下载');
          }
        }
      }

      _initSurfaceBuilt = false;
      final engine = createVodEngine(_playerSettings.kernel);
      _engine = engine;
      engine.addListener(_onInitControllerTick);
      _initSpeedTimer?.cancel();
      _initSpeedTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        _onInitControllerTick();
      });
      // iOS 正常播放一律 Texture。PlatformView + Flutter 叠层会发灰白罩。
      // 画中画入口可传 preferPlatformViewOverride=true。
      final preferPv = preferPlatformViewOverride ?? false;
      _openedWithPlatformView = preferPv;
      try {
        await engine
            .open(
              url: playUrl,
              httpHeaders: _isLocalMedia ? const {} : VodPlayback.httpHeaders,
              backBufferMs: _isLocalMedia ? 15000 : profile.backBufferMs,
              preferPlatformView: preferPv,
            )
            .timeout(Duration(seconds: _isLocalMedia ? 20 : 25));
      } catch (e) {
        if (_isLocalMedia) {
          throw StateError('缓存离线播放失败，请重新下载该集');
        }
        rethrow;
      }
      if (!mounted || token != _initToken) {
        await _disposeController();
        return;
      }

      final engineLive = _engine;
      if (engineLive == null) {
        throw StateError('播放器未就绪');
      }
      final start = resumeMs ?? widget.startPositionMs;
      final total = engineLive.value.duration.inMilliseconds;
      // 进度贴近片尾/越界时强制从头播，避免一直转圈（清历史又能播的常见原因）
      var seekMs = start;
      if (total > 0) {
        if (seekMs < 0 || seekMs > total - 5000 || seekMs > total * 0.97) {
          seekMs = 0;
        }
      } else if (seekMs > 30 * 60 * 1000) {
        // 时长未知却带超长进度，不可信
        seekMs = 0;
      }
      // 秒开：先 play 出画，再异步续播/跳片头
      // media_kit 禁止在 Texture 挂上前 seek/play（seekTo 曾内部 play 导致有声无画）
      _pendingResumeMs = null;
      _pendingSkipIntro = false;
      _postStartSeekDone = false;
      final isMk = engineLive is MediaKitVodEngine;
      final canImmediateSeek =
          _isLocalMedia && seekMs > 1500 && !isMk;
      if (canImmediateSeek) {
        await engineLive.seekTo(Duration(milliseconds: seekMs));
        if (resumeMs == null) {
          await _applySkipIntro(engineLive);
        }
        _postStartSeekDone = true;
      } else {
        if (seekMs > 1500) {
          _pendingResumeMs = seekMs;
        }
        if (resumeMs == null) {
          _pendingSkipIntro = true;
        }
      }
      await engineLive.setPlaybackSpeed(_playbackRate);
      await engineLive.setLooping(_playerSettings.loopSingle);
      // media_kit：open 内已抢先挂 Video；这里等 Surface 真就绪再 play
      final deferMkPlay = autoPlay && isMk;
      if (autoPlay && !deferMkPlay) {
        await engineLive.play();
      }
      if (_playerSettings.keepScreenOn) {
        await PlaybackWakelock.acquire();
      }

      if (!_postStartSeekDone &&
          (_pendingResumeMs != null || _pendingSkipIntro) &&
          !deferMkPlay) {
        unawaited(_runPostStartSeek(token));
      }

      _skipPrefs = await PlayerSkipStore.load();
      _progressTimer?.cancel();
      _outroTimer?.cancel();
      _progressTick = 0;
      _outroTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _checkSkipOutro();
      });
      _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _progressTick++;
        final ctrl = _engine;
        if (ctrl == null || !ctrl.value.isInitialized) return;
        final aheadMs = _bufferedAheadMsOf(ctrl.value);
        StreamAheadCache.instance.updatePosition(
          ctrl.value.position.inMilliseconds,
        );
        // 预热默认让路：缓冲不足时不抢带宽（拖进度尤其重要）
        StreamAheadCache.instance.setPaused(
          ctrl.value.isBuffering || (aheadMs >= 0 && aheadMs < 10000),
        );
        if (_progressTick % 5 == 0) {
          widget.onProgress?.call(ctrl.value.position, ctrl.value.duration);
        }
      });

      if (!mounted || token != _initToken) return;
      _stopInitSpeedTracking();
      engineLive.removeListener(_onInitControllerTick);
      engineLive.addListener(_onPlaybackStatus);
      setState(() {
        _ready = true;
        _qualityBusy = false;
        if (preservedVariants != null && preservedVariants.length > 1) {
          _qualityVariants = preservedVariants;
          VodHlsVariant? matched;
          for (final v in preservedVariants) {
            if (v.url == playUrl) {
              matched = v;
              break;
            }
          }
          _currentVariant = matched ?? preservedCurrent;
        } else if (_qualityVariants.isEmpty && engineLive.value.size.height > 0) {
          final sz = engineLive.value.size;
          final synthetic = VodHlsVariant(
            url: playUrl,
            bandwidth: 0,
            width: sz.width.round(),
            height: sz.height.round(),
          );
          _qualityVariants = [synthetic];
          _currentVariant = synthetic;
        } else if (_currentVariant == null && _qualityVariants.length == 1) {
          _currentVariant = _qualityVariants.first;
        }
      });
      _scheduleHideChrome();
      // media_kit：禁止在 _init 里长时间等纹理/首帧（切线路会卡死主线程 → ANR）。
      // 挂载 Video 后短延迟再 play，失败也立刻放，不阻塞 UI。
      if (deferMkPlay) {
        final mk = _engine;
        if (mk is MediaKitVodEngine) {
          unawaited(_startMediaKitPlayDeferred(mk, token));
        }
      }
      unawaited(_watchStuckAtZero(token));
      unawaited(_deferredAfterPlay(token));
    } catch (e) {
      if (!mounted || token != _initToken) return;
      _qualityBusy = false;
      await _onPlayFailed(e.toString());
    }
  }

  /// media_kit 延后起播：尽快 play，纹理最多等 ~1s，缩短黑屏。
  Future<void> _startMediaKitPlayDeferred(
    MediaKitVodEngine mk,
    int token,
  ) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || token != _initToken || !identical(_engine, mk)) return;
      final ok = await mk.waitUntilTextureReady(
        timeout: const Duration(milliseconds: 900),
      );
      if (!mounted || token != _initToken || !identical(_engine, mk)) return;
      if (!ok) {
        debugPrint('[media_kit] surface lag, play anyway');
      }
      await mk.play();
      if (!mounted || token != _initToken || !identical(_engine, mk)) return;
      // 首帧轻踢，超时要短
      try {
        await mk.videoController?.waitUntilFirstFrameRendered.timeout(
          const Duration(milliseconds: 1200),
        );
      } catch (_) {
        if (!mounted || token != _initToken || !identical(_engine, mk)) return;
        try {
          await mk.pause();
          await Future<void>.delayed(const Duration(milliseconds: 40));
          if (!mounted || token != _initToken || !identical(_engine, mk)) {
            return;
          }
          await mk.play();
        } catch (_) {}
      }
      if (!_postStartSeekDone &&
          (_pendingResumeMs != null || _pendingSkipIntro)) {
        unawaited(_runPostStartSeek(token));
      }
    } catch (e) {
      debugPrint('[media_kit] deferred play: $e');
    }
  }

  /// 卡住 00:00/00:00 过久：先踢播，再仍无进度则报错（切线路后常见）。
  Future<void> _watchStuckAtZero(int token) async {
    await Future<void>.delayed(const Duration(seconds: 15));
    if (!mounted || token != _initToken) return;
    final c = _engine;
    if (c == null || !_ready || _failed) return;
    final v = c.value;
    if (v.hasError) return;
    // 已在播 / 已有进度 / 已出时长：不算卡死（部分 HLS 时长晚到）
    if (v.isPlaying ||
        v.duration > Duration.zero ||
        v.position > const Duration(milliseconds: 800)) {
      return;
    }
    debugPrint('[player] stuck at 00:00, kick play');
    try {
      await c.pause();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted || token != _initToken) return;
      await c.play();
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 10));
    if (!mounted || token != _initToken) return;
    final v2 = _engine?.value;
    if (v2 == null || _failed) return;
    if (v2.isPlaying ||
        v2.position > const Duration(milliseconds: 800) ||
        v2.duration > Duration.zero) {
      return;
    }
    if (v2.isBuffering || !v2.isPlaying) {
      if (!mounted || token != _initToken) return;
      await _onPlayFailed('加载超时，请切换线路或内核重试');
    }
  }

  bool _initSurfaceBuilt = false;

  void _onInitControllerTick() {
    final c = _engine;
    _bufferSpeedTracker.setLoading(true);
    if (c != null && c.value.isInitialized) {
      _bufferSpeedTracker.tick(
        c.value.buffered,
        isBuffering: c.value.isBuffering || !_ready,
      );
      // ?????? Surface ? rebuild ????? position ?? setState
      if (mounted && !_ready && !_failed && !_initSurfaceBuilt) {
        _initSurfaceBuilt = true;
        setState(() {});
      }
    } else {
      _bufferSpeedTracker.tick(const [], isBuffering: true);
    }
  }

  void _stopInitSpeedTracking() {
    _initSpeedTimer?.cancel();
    _initSpeedTimer = null;
    final c = _engine;
    if (c != null) {
      try {
        c.removeListener(_onInitControllerTick);
      } catch (_) {}
    }
    _bufferSpeedTracker.reset();
  }

  Future<void> _disposeController({bool keepWakelock = false}) async {
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _outroTimer?.cancel();
    _seekHintTimer?.cancel();
    _stopInitSpeedTracking();
    final c = _engine;
    _engine = null;
    if (c != null) {
      try {
        c.removeListener(_onPlaybackStatus);
      } catch (_) {}
      try {
        c.removeListener(_onInitControllerTick);
      } catch (_) {}
      final wasMk = c is MediaKitVodEngine;
      final releaseFut = () async {
        try {
          await c.releaseSafe().timeout(const Duration(seconds: 2));
        } catch (_) {}
        try {
          c.dispose();
        } catch (_) {}
      }();
      if (wasMk) {
        // 切内核：旧 Surface 尽快放，最多等 350ms，减少黑屏
        try {
          await releaseFut.timeout(const Duration(milliseconds: 350));
        } catch (_) {}
      } else {
        unawaited(releaseFut);
      }
    }
    if (!keepWakelock) {
      unawaited(PlaybackWakelock.release());
    }
  }

  @override
  void dispose() {
    PlayerPip.inPip.removeListener(_onPipFlag);
    _PlaybackSession.detach(this);
    PlayerPip.setOnEntered(null);
    unawaited(forceStop());
    _stallLoading.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    if (_locked) return;
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) _scheduleHideChrome();
  }

  void _scheduleHideChrome() {
    _hideTimer?.cancel();
    if (!_showChrome) return;
    final sec = _playerSettings.chromeAutoHideSec.clamp(2, 12);
    _hideTimer = Timer(Duration(seconds: sec), () {
      if (!mounted) return;
      final c = _engine;
      if (c != null && c.value.isPlaying) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _onInteract() {
    if (!_showChrome) setState(() => _showChrome = true);
    _scheduleHideChrome();
  }

  @override
  Widget build(BuildContext context) {
    final c = _engine;
    final topInset =
        widget.immersiveTop ? 0.0 : MediaQuery.paddingOf(context).top;
    // ??????????????????
    final inPip = PlayerPip.isInPip;
    final showChrome = _showChrome && !inPip;
    final showSide = (_showSideSettings || _showCastSide) && !inPip;
    // ???????????????????
    final vp = MediaQuery.viewPaddingOf(context);
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final lockRight = (landscape ? vp.right : 0.0) + 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return PlayerEdgeGestures(
          enabled: _ready &&
              !_locked &&
              !_failed &&
              _playerSettings.gestureEnabled &&
              !showSide &&
              !inPip,
          child: GestureDetector(
          onTap: (showSide || inPip) ? null : _toggleChrome,
          onDoubleTapDown: (showSide || inPip)
              ? null
              : (d) => _onDoubleTapDown(d, constraints.maxWidth),
          onLongPressStart: (showSide || inPip)
              ? null
              : (_) => unawaited(_startHoldBoost()),
          onLongPressEnd: (_) => unawaited(_endHoldBoost()),
          onLongPressCancel: () => unawaited(_endHoldBoost()),
          onHorizontalDragStart:
              (showSide || inPip) ? null : (_) => _onScrubStart(),
          onHorizontalDragUpdate: (showSide || inPip)
              ? null
              : (d) => _onScrubUpdate(d, constraints.maxWidth),
          onHorizontalDragEnd:
              (showSide || inPip) ? null : (_) => unawaited(_onScrubEnd()),
          onHorizontalDragCancel:
              (showSide || inPip) ? null : () => unawaited(_onScrubEnd()),
          behavior: HitTestBehavior.opaque,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_ready &&
                    !_failed &&
                    (widget.posterUrl?.trim().isNotEmpty ?? false))
                  Positioned.fill(
                    child: Image.network(
                      widget.posterUrl!.trim(),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Colors.black),
                    ),
                  ),
                if (!_failed && c != null && c.value.isInitialized)
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: _videoShotKey,
                      child: _StableVideoSurface(
                        controller: c,
                        // 缓存离线：固定「适应」留边（与上图一致），不被裁剪铺满吃掉
                        aspect: _isLocalMedia
                            ? PlayerAspectMode.fit
                            : _playerSettings.aspect,
                        immersiveTop: widget.immersiveTop,
                        mirrorX: _playerSettings.mirrorX,
                        mirrorY: _playerSettings.mirrorY,
                        enhanceLevel: _playerSettings.enhanceLevel,
                        // media_kit Texture + ColorFiltered 在 Android 上常见有声无画
                        allowColorMatrix: !_openedWithPlatformView &&
                            c is! MediaKitVodEngine,
                        letterboxLikeCache: _isLocalMedia ||
                            _playerSettings.aspect == PlayerAspectMode.fit,
                      ),
                    ),
                  )
                else if (_failed)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '播放失败',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (_lastErrorMsg.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _lastErrorMsg,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 42,
                              child: FilledButton(
                                onPressed: () => unawaited(_manualRetry()),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1ECAD3),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(21),
                                  ),
                                ),
                                child: const Text(
                                  '重试',
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 42,
                              child: OutlinedButton(
                                onPressed: () =>
                                    unawaited(_reportPlayError()),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF3B30),
                                  side: const BorderSide(
                                    color: Color(0xFFFF3B30),
                                    width: 1.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(21),
                                  ),
                                ),
                                child: const Text(
                                  '报错',
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF3B30),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_holdBoost)
                  IgnorePointer(
                    child: Align(
                      // ?????????????
                      alignment: const Alignment(0, -0.52),
                      child: PlayerHoldBoostHud(
                        rate: _playerSettings.holdBoostRate,
                      ),
                    ),
                  )
                else if (_seekHint != null)
                  IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, -0.52),
                      child: PlayerSeekHintChip(text: _seekHint!),
                    ),
                  ),
                // 弹幕层：Positioned 必须是 Stack 直系子节点，否则 iOS 合成发灰白
                if (c != null && !_failed && _ready)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _DanmakuOverlay(
                        controller: c,
                        items: _danmakuItems,
                        enabled: widget.enableDanmaku &&
                            _danmakuPrefs.enabled &&
                            widget.vodId?.trim().isNotEmpty == true,
                        prefs: _danmakuPrefs,
                        fitCover: !_isLocalMedia &&
                            (widget.immersiveTop ||
                                _playerSettings.aspect ==
                                    PlayerAspectMode.cover ||
                                _playerSettings.aspect ==
                                    PlayerAspectMode.fill),
                      ),
                    ),
                  ),
                if (c != null && !_failed && _locked)
                  Positioned(
                    right: lockRight,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: PlayerCircleButton(
                        icon: Icons.lock_rounded,
                        onTap: _toggleLock,
                        iconSize: 22,
                      ),
                    ),
                  ),
                // 注意：不要在 Video Texture 上方盖全屏 AnimatedOpacity。
                // iOS 上 Opacity 合成层会让画面发灰，像「套了一层」。
                if (c != null && !_failed && !_locked && showChrome) ...[
                  Positioned(
                    right: lockRight,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: PlayerCircleButton(
                        icon: Icons.lock_open_rounded,
                        onTap: _toggleLock,
                        iconSize: 22,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: _ThrottledChrome(
                      controller: c,
                      chromeVisible: showChrome,
                      ready: _ready,
                      holdEnterAheadMs:
                          PlaybackProfile.of(_playerSettings).holdEnterAheadMs,
                      holdResumeAheadMs:
                          PlaybackProfile.of(_playerSettings).holdResumeAheadMs,
                      speedTracker: _bufferSpeedTracker,
                      showNetSpeed:
                          !_isLocalMedia && _playerSettings.showNetSpeed,
                      onLoadingChanged: (v) {
                        void apply() {
                          if (!mounted) return;
                          if (_stallLoading.value != v) {
                            _stallLoading.value = v;
                          }
                        }

                        final phase =
                            SchedulerBinding.instance.schedulerPhase;
                        if (phase == SchedulerPhase.idle ||
                            phase == SchedulerPhase.postFrameCallbacks) {
                          apply();
                        } else {
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => apply());
                        }
                      },
                      showBack:
                          widget.showBack && widget.topOverlay == null,
                      topInset:
                          widget.showBack && widget.topOverlay == null
                              ? topInset
                              : 0.0,
                      onBack: widget.onBack,
                      showDanmakuToggle: widget.enableDanmaku &&
                          widget.vodId?.trim().isNotEmpty == true,
                      danmakuEnabled: _danmakuPrefs.enabled,
                      onDanmakuToggle: () => unawaited(_toggleDanmaku()),
                      onDanmakuSend: () => unawaited(_sendDanmaku()),
                      onFullscreen: () {
                        widget.onFullscreen?.call();
                        _onInteract();
                      },
                      onInteract: _onInteract,
                      onNextEpisode: widget.showNextEpisode &&
                              widget.onNextEpisode != null
                          ? () {
                              widget.onNextEpisode!();
                              _onInteract();
                            }
                          : null,
                      onEpisodes: widget.episodes.length > 1 &&
                              widget.onEpisodeSelect != null
                          ? (anchor) => unawaited(_openEpisodes(anchor))
                          : null,
                      onSources: (widget.immersiveTop &&
                              MediaQuery.sizeOf(context).width >
                                  MediaQuery.sizeOf(context).height &&
                              widget.sourceNames.length > 1 &&
                              widget.onSourceSelect != null)
                          ? (anchor) => unawaited(_pickSource(anchor))
                          : null,
                      onAspect: (widget.immersiveTop &&
                              MediaQuery.sizeOf(context).width >
                                  MediaQuery.sizeOf(context).height)
                          ? (anchor) => unawaited(_pickAspect(anchor))
                          : null,
                      onSpeed: (widget.immersiveTop &&
                              MediaQuery.sizeOf(context).width >
                                  MediaQuery.sizeOf(context).height)
                          ? (anchor) => unawaited(_pickPlaybackSpeed(anchor))
                          : null,
                      onQuality: (widget.immersiveTop &&
                              MediaQuery.sizeOf(context).width >
                                  MediaQuery.sizeOf(context).height)
                          ? (anchor) => unawaited(_pickQuality(anchor))
                          : null,
                      aspectLabel: _isLocalMedia
                          ? PlayerAspectMode.fit.label
                          : _playerSettings.aspect.label,
                      speedLabel: VodPlayback.rateLabel(_playbackRate),
                      qualityLabel: _currentVariant?.shortLabel ??
                          _qualityPrefer.label,
                      sourceLabel: _sourceChromeLabel,
                      denseLandscape: widget.immersiveTop &&
                          MediaQuery.sizeOf(context).width >
                              MediaQuery.sizeOf(context).height,
                      introMs: _skipPrefs.enabled
                          ? _skipPrefs.introSeconds * 1000
                          : 0,
                      outroMs: _skipPrefs.enabled
                          ? _skipPrefs.outroSeconds * 1000
                          : 0,
                      onMarkIntro: () =>
                          unawaited(_markSkipAtCurrent(intro: true)),
                      onMarkOutro: () =>
                          unawaited(_markSkipAtCurrent(intro: false)),
                      onSkip: (anchor) => unawaited(_pickSkip(anchor)),
                      skipEnabled: _skipPrefs.enabled,
                      onSettings: widget.immersiveTop &&
                              MediaQuery.sizeOf(context).width >
                                  MediaQuery.sizeOf(context).height
                          ? () => _openSideSettings()
                          : null,
                      onCast: widget.onCast != null &&
                              widget.immersiveTop &&
                              MediaQuery.sizeOf(context).width >
                                  MediaQuery.sizeOf(context).height
                          ? () {
                              openCast();
                              _onInteract();
                            }
                          : null,
                    ),
                  ),
                ],
                if (c != null &&
                    _ready &&
                    !_failed &&
                    !_locked &&
                    _playbackRate != 1.0)
                  Positioned(
                    top: (widget.immersiveTop ? 0.0 : topInset) +
                        (widget.topOverlay != null ? 52 : 8),
                    right: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x99000000),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          VodPlayback.rateLabel(_playbackRate),
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.topOverlay != null &&
                    !_locked &&
                    showChrome &&
                    !_failed &&
                    !showSide)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: widget.topOverlay!,
                  ),
                // 未就绪：只有引擎也没在播时才盖全屏加载（避免「已经出画还转圈」）
                if (!_failed && !_ready && !(_engine?.value.isPlaying ?? false))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: PlayerLoadingHud(
                            tracker: (!_isLocalMedia &&
                                    _playerSettings.showNetSpeed)
                                ? _bufferSpeedTracker
                                : null,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!_failed &&
                    (_ready || (_engine?.value.isPlaying ?? false)))
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _stallLoading,
                        builder: (_, stalled, _) {
                          if (!stalled) return const SizedBox.shrink();
                          // seek/卡顿加载：即使引擎仍报 isPlaying 也要显示
                          return Center(
                            child: PlayerLoadingHud(
                              compact: true,
                              showSpeed: !_isLocalMedia &&
                                  _playerSettings.showNetSpeed,
                              tracker: (!_isLocalMedia &&
                                      _playerSettings.showNetSpeed)
                                  ? _bufferSpeedTracker
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (showSide)
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ModalBarrier(
                          dismissible: true,
                          color: const Color(0x66000000),
                          onDismiss: () {
                            _closeSideSettings();
                            _closeCastSide();
                          },
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () {
                              _closeSideSettings();
                              _closeCastSide();
                            },
                            behavior: HitTestBehavior.translucent,
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {},
                            child: SizedBox(
                              width: () {
                                final w = MediaQuery.sizeOf(context).width;
                                // 横屏侧栏加宽并贴右，避免内容区右侧空一大块
                                if (_showCastSide) {
                                  return (w * 0.34).clamp(240.0, 320.0);
                                }
                                return (w * 0.38).clamp(260.0, 340.0);
                              }(),
                              height: double.infinity,
                              child: Material(
                                elevation: 8,
                                color: const Color(0xFFF5F6F8),
                                // 勿保留 right SafeArea，横屏会在面板右侧挤出空白
                                child: SafeArea(
                                  left: false,
                                  right: false,
                                  child: _showCastSide
                                      ? ColoredBox(
                                          color: Colors.white,
                                          child: CastPanel(
                                            mediaUrl: widget.url,
                                            title: widget.danmakuTitle.isEmpty
                                                ? '????'
                                                : widget.danmakuTitle,
                                            asSide: true,
                                            onClose: _closeCastSide,
                                            onCastStarted: () {
                                              unawaited(pause());
                                            },
                                            onCastStopped: () {
                                              unawaited(play());
                                            },
                                          ),
                                        )
                                      : PlayerSideSettingsPanel(
                                          key: const ValueKey('player-side-settings'),
                                          flatMode: true,
                                          initialPage: _sideSettingsPage,
                                          onClose: _closeSideSettings,
                                          host: _settingsHost(),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

/// ??????????? cover ???????????
class _DanmakuOverlay extends StatefulWidget {
  const _DanmakuOverlay({
    required this.controller,
    required this.items,
    required this.enabled,
    required this.prefs,
    this.fitCover = false,
  });

  final VodEngine controller;
  final List<DanmakuItem> items;
  final bool enabled;
  final DanmakuDisplayPrefs prefs;
  final bool fitCover;

  @override
  State<_DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<_DanmakuOverlay> {
  Timer? _timer;
  double _pos = 0;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _sync();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !widget.enabled) return;
      final nextPos = _readPos();
      final nextPlaying = _readPlaying();
      if ((nextPos - _pos).abs() < 0.04 && nextPlaying == _playing) return;
      setState(() {
        _pos = nextPos;
        _playing = nextPlaying;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    _pos = _readPos();
    _playing = _readPlaying();
  }

  double _readPos() {
    final v = widget.controller.value;
    return v.isInitialized ? v.position.inMilliseconds / 1000.0 : 0.0;
  }

  bool _readPlaying() {
    final v = widget.controller.value;
    return v.isInitialized && v.isPlaying;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final v = widget.controller.value;

    Widget layer = PlayerDanmakuLayer(
      items: widget.items,
      positionSec: _pos,
      enabled: widget.enabled,
      prefs: widget.prefs,
      playing: _playing,
    );

    if (!widget.fitCover && v.isInitialized) {
      final ratio = v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio;
      layer = Center(
        child: AspectRatio(
          aspectRatio: ratio,
          child: layer,
        ),
      );
    }

    return IgnorePointer(
      // 勿包 RepaintBoundary：iOS 上盖在视频上会整层发灰
      child: layer,
    );
  }
}

/// 画面表面：按比例裁剪/适应；裁剪铺满用显式宽高，避免 FittedBox+Texture 底边黑条
class _StableVideoSurface extends StatelessWidget {
  const _StableVideoSurface({
    required this.controller,
    required this.aspect,
    required this.immersiveTop,
    required this.mirrorX,
    required this.mirrorY,
    this.enhanceLevel = PlayerEnhanceLevel.off,
    this.allowColorMatrix = true,
    this.letterboxLikeCache = false,
  });

  final VodEngine controller;
  final PlayerAspectMode aspect;
  final bool immersiveTop;
  final bool mirrorX;
  final bool mirrorY;
  final PlayerEnhanceLevel enhanceLevel;
  final bool allowColorMatrix;
  /// 缓存播放器同款：contain 留边，横屏左右黑边 / 竖屏上下黑边
  final bool letterboxLikeCache;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) return const SizedBox.shrink();
    // 缓存同款留边：强制 fit/contain，不被 cover 放大吃黑边
    final effectiveAspect =
        letterboxLikeCache ? PlayerAspectMode.fit : aspect;
    final rawRatio =
        controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    final forcedRatio = switch (effectiveAspect) {
      PlayerAspectMode.ratio16x9 => 16 / 9,
      PlayerAspectMode.ratio4x3 => 4 / 3,
      _ => rawRatio <= 0 ? 16 / 9 : rawRatio,
    };
    final boxFit = switch (effectiveAspect) {
      PlayerAspectMode.cover => BoxFit.cover,
      PlayerAspectMode.fill => BoxFit.fill,
      PlayerAspectMode.fit ||
      PlayerAspectMode.ratio16x9 ||
      PlayerAspectMode.ratio4x3 =>
        BoxFit.contain,
    };

    final raw = controller.rawVideoPlayer;
    Widget player = raw != null
        ? VideoPlayer(raw)
        : controller.buildSurface();
    if (mirrorX || mirrorY) {
      player = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          mirrorX ? -1.0 : 1.0,
          mirrorY ? -1.0 : 1.0,
          1.0,
        ),
        child: player,
      );
    }

    if (controller.prefersIntrinsicFit) {
      final align = effectiveAspect == PlayerAspectMode.cover
          ? const Alignment(0, 0.18)
          : Alignment.center;
      return PlaybackEnhanceFilter(
        level: enhanceLevel,
        allowColorMatrix: allowColorMatrix,
        child: SizedBox.expand(
          child: controller.buildSurface(fit: boxFit, alignment: align),
        ),
      );
    }

    return PlaybackEnhanceFilter(
      level: enhanceLevel,
      allowColorMatrix: allowColorMatrix,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
          if (!(maxW.isFinite && maxH.isFinite) || maxW <= 0 || maxH <= 0) {
            return const SizedBox.shrink();
          }
          final videoRatio = forcedRatio <= 0 ? (16 / 9) : forcedRatio;
          final screenRatio = maxW / maxH;

          // contain：横屏左右黑边 / 竖屏上下黑边（上图缓存播放器同款）
          late final double baseW;
          late final double baseH;
          if (screenRatio > videoRatio) {
            baseH = maxH;
            baseW = maxH * videoRatio;
          } else {
            baseW = maxW;
            baseH = maxW / videoRatio;
          }

          switch (effectiveAspect) {
            case PlayerAspectMode.fill:
              return ClipRect(
                child: SizedBox(
                  width: maxW,
                  height: maxH,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox(
                      width: videoRatio * 100,
                      height: 100,
                      child: player,
                    ),
                  ),
                ),
              );
            case PlayerAspectMode.cover:
              final scale = math.max(maxW / baseW, maxH / baseH) * 1.03;
              final alignY =
                  screenRatio < videoRatio * 0.98 ? 0.18 : 0.10;
              return ClipRect(
                child: SizedBox(
                  width: maxW,
                  height: maxH,
                  child: Center(
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment(0, alignY),
                      child: SizedBox(
                        width: baseW,
                        height: baseH,
                        child: player,
                      ),
                    ),
                  ),
                ),
              );
            case PlayerAspectMode.fit:
            case PlayerAspectMode.ratio16x9:
            case PlayerAspectMode.ratio4x3:
              return ColoredBox(
                color: Colors.black,
                child: Center(
                  child: SizedBox(
                    width: baseW,
                    height: baseH,
                    child: player,
                  ),
                ),
              );
          }
        },
      ),
    );
  }
}

class _PlaybackSession {
  _PlaybackSession._();

  static MangoInlinePlayerState? _active;

  static void attach(MangoInlinePlayerState player) {
    final prev = _active;
    if (prev != null && prev != player) {
      unawaited(prev.forceStop());
    }
    _active = player;
  }

  static void detach(MangoInlinePlayerState player) {
    if (_active == player) _active = null;
  }

  static Future<void> stopAll() async {
    final p = _active;
    _active = null;
    if (p != null) await p.forceStop();
  }
}

/// ????????????
Future<void> stopAllInlinePlayback() => _PlaybackSession.stopAll();

/// ?????????????
class _ThrottledChrome extends StatefulWidget {
  const _ThrottledChrome({
    required this.controller,
    required this.chromeVisible,
    required this.ready,
    this.holdEnterAheadMs = 2500,
    this.holdResumeAheadMs = 6000,
    required this.speedTracker,
    required this.onLoadingChanged,
    required this.showBack,
    required this.topInset,
    required this.onBack,
    required this.onFullscreen,
    required this.onInteract,
    this.showNetSpeed = true,
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
    this.aspectLabel = '??',
    this.speedLabel = '??',
    this.qualityLabel = '???',
    this.sourceLabel = '??',
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

  final VodEngine controller;
  /// 控制栏隐藏时不 setState，避免播放中每 250ms 重建拖慢点击
  final bool chromeVisible;
  final bool ready;
  final int holdEnterAheadMs;
  final int holdResumeAheadMs;
  final PlaybackSpeedTracker speedTracker;
  final ValueChanged<bool> onLoadingChanged;
  final bool showBack;
  final double topInset;
  final VoidCallback? onBack;
  final VoidCallback onFullscreen;
  final VoidCallback onInteract;
  final bool showNetSpeed;
  final bool showDanmakuToggle;
  final bool danmakuEnabled;
  final VoidCallback? onDanmakuToggle;
  final VoidCallback? onDanmakuSend;
  final VoidCallback? onNextEpisode;
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
  final void Function(BuildContext anchor)? onSkip;
  final bool skipEnabled;
  final VoidCallback? onSettings;
  final VoidCallback? onCast;

  @override
  State<_ThrottledChrome> createState() => _ThrottledChromeState();
}

class _ThrottledChromeState extends State<_ThrottledChrome> {
  Timer? _uiTimer;
  Timer? _stallTimer;
  bool _showBufferSpinner = false;
  bool _holdingForBuffer = false;
  bool _userPaused = false;
  bool _draggingProgress = false;
  bool _seekLoading = false;
  bool _lastLoadingNotified = false;
  int _lastPosMs = -1;
  DateTime? _stallSince;
  Size? _lastMqSize;
  DateTime? _layoutQuietUntil;
  /// ??/seek ???????????????????????
  Duration? _uiSeekPos;

  static const _stallNeedMs = 3500;

  bool get _inLayoutQuiet {
    final until = _layoutQuietUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _clearStallFlags() {
    _stallSince = null;
    _stallTimer?.cancel();
    _stallTimer = null;
    if (_showBufferSpinner || _seekLoading || _holdingForBuffer) {
      _showBufferSpinner = false;
      _seekLoading = false;
      _holdingForBuffer = false;
    }
  }

  bool get _showLoadingHud {
    if (_inLayoutQuiet) return false;
    final v = widget.controller.value;
    // 手指拖动中：显示
    if (_draggingProgress) return true;
    // seek 中：只有还没续上（未播 / 离目标很远）才转圈；已在播则立刻消掉
    if (_seekLoading) {
      final lock = _uiSeekPos;
      final near = lock == null ||
          (v.position.inMilliseconds - lock.inMilliseconds).abs() <= 4000;
      if (v.isPlaying && near) return false;
      if (v.isPlaying && !v.isBuffering) return false;
      return true;
    }
    // 正常播放绝不盖圈（HLS 切片缓冲抖动不算）
    if (v.isPlaying) return false;
    if (v.isInitialized &&
        v.size.width > 1 &&
        v.size.height > 1 &&
        v.position.inMilliseconds > 400) {
      return false;
    }
    if (!widget.ready) return true;
    if (_holdingForBuffer) return true;
    return _showBufferSpinner;
  }

  void _notifyLoading(bool visible) {
    if (_lastLoadingNotified == visible) return;
    _lastLoadingNotified = visible;
    // ValueListenableBuilder ??? build/layout ?????
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      widget.onLoadingChanged(visible);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onLoadingChanged(visible);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // 不监听 engine：避免播放进度广播打满主线程；定时器自行读 value
    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final v = widget.controller.value;
      final beforeSpinner = _showBufferSpinner;
      final beforeSeek = _seekLoading;
      _evaluateStall(v);
      _maybeHoldForBuffer(v);
      _maybeReleaseSeekLock(v);
      widget.speedTracker.setLoading(_showLoadingHud);
      widget.speedTracker.tick(v.buffered, isBuffering: _showBufferSpinner);
      _notifyLoading(_showLoadingHud);
      final hudChanged =
          beforeSpinner != _showBufferSpinner || beforeSeek != _seekLoading;
      // 隐藏控制栏时只处理卡顿 HUD，不重建整棵控件树（否则点击会慢几拍）
      if (!widget.chromeVisible && !hudChanged && !_draggingProgress) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = MediaQuery.sizeOf(context);
    final prev = _lastMqSize;
    if (prev != null &&
        ((prev.width - s.width).abs() > 48 ||
            (prev.height - s.height).abs() > 48)) {
      // ?????? surface ????????????????
      _layoutQuietUntil =
          DateTime.now().add(const Duration(milliseconds: 3200));
      _showBufferSpinner = false;
      _seekLoading = false;
      _stallSince = null;
      _stallTimer?.cancel();
      _stallTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifyLoading(false);
      });
    }
    _lastMqSize = s;
  }

  @override
  void didUpdateWidget(covariant _ThrottledChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _lastPosMs = -1;
      _stallSince = null;
      _showBufferSpinner = false;
    }
  }

  void _maybeHoldForBuffer(VodEngineValue v) {
    // ???? pause??????????????????????
    if (_holdingForBuffer) {
      _holdingForBuffer = false;
      if (!_userPaused && !v.isPlaying && widget.ready) {
        unawaited(widget.controller.play());
      }
    }
  }

  void _evaluateStall(VodEngineValue v) {
    if (_inLayoutQuiet) {
      _stallSince = null;
      _showBufferSpinner = false;
      return;
    }
    if (!widget.ready || !v.isInitialized) {
      _stallSince = null;
      _showBufferSpinner = false;
      _stallTimer?.cancel();
      _stallTimer = null;
      return;
    }

    final posMs = v.position.inMilliseconds;

    // seek 已续播成功：强制清标记（避免「在播还转圈」）
    if (_seekLoading && !_draggingProgress && v.isPlaying) {
      final lock = _uiSeekPos;
      final near = lock == null ||
          (posMs - lock.inMilliseconds).abs() <= 4000;
      if (near || !v.isBuffering) {
        _seekLoading = false;
        _showBufferSpinner = false;
        _uiSeekPos = null;
        _stallSince = null;
        _lastPosMs = posMs;
        return;
      }
    }

    // 拖进度中：保持加载圈
    if (_draggingProgress) {
      _lastPosMs = posMs;
      _showBufferSpinner = true;
      return;
    }

    // 正在播：清掉一切卡顿标记（不要靠 position 是否前进，上报经常落后画面）
    if (v.isPlaying) {
      _lastPosMs = posMs;
      _clearStallFlags();
      return;
    }

    final moved = _lastPosMs >= 0 && posMs > _lastPosMs;
    if (moved) {
      _lastPosMs = posMs;
      _clearStallFlags();
      return;
    }

    _lastPosMs = posMs < 0 ? _lastPosMs : posMs;
    final maybeStuck =
        v.isBuffering || _seekLoading || (!_userPaused && !v.isPlaying);
    if (!maybeStuck) {
      _clearStallFlags();
      return;
    }

    _stallSince ??= DateTime.now();
    final waited = DateTime.now().difference(_stallSince!).inMilliseconds;
    if (waited >= _stallNeedMs && !_showBufferSpinner) {
      _showBufferSpinner = true;
    }
  }


  void _maybeReleaseSeekLock(VodEngineValue v) {
    if (_draggingProgress) return;
    if (!_seekLoading && _uiSeekPos == null) return;
    final lock = _uiSeekPos;
    final diff = lock == null
        ? 0
        : (v.position.inMilliseconds - lock.inMilliseconds).abs();
    if (diff <= 900 ||
        (v.isPlaying && diff <= 4000) ||
        (v.isPlaying && !v.isBuffering) ||
        (v.isPlaying && lock == null)) {
      _uiSeekPos = null;
      if (_seekLoading || _showBufferSpinner) {
        _seekLoading = false;
        _showBufferSpinner = false;
        widget.speedTracker.setLoading(false);
      }
    }
  }

  void _onSeekStart() {
    // 拖进度条：立刻显示加载动画 + 速率
    StreamAheadCache.instance.setPaused(true);
    StreamAheadCache.instance.abortInFlight();
    setState(() {
      _draggingProgress = true;
      _seekLoading = true;
      _showBufferSpinner = true;
      _uiSeekPos = widget.controller.value.position;
    });
    widget.speedTracker.setLoading(true);
    widget.speedTracker.resetMetrics();
    widget.speedTracker.tick(
      widget.controller.value.buffered,
      isBuffering: true,
    );
    _notifyLoading(true);
    widget.onInteract();
  }

  void _onSeekPreview(Duration d) {
    if (!_draggingProgress) return;
    setState(() => _uiSeekPos = d);
  }

  Future<void> _commitSeek(Duration d) async {
    final c = widget.controller;
    setState(() {
      _uiSeekPos = d;
      _draggingProgress = false;
      _seekLoading = true;
      _showBufferSpinner = true;
      _stallSince = DateTime.now();
    });
    widget.onInteract();
    widget.speedTracker.setLoading(true);
    widget.speedTracker.resetMetrics();
    widget.speedTracker.tick(c.value.buffered, isBuffering: true);
    _notifyLoading(true);
    // 拖进度不走旁路预热：warmSeek 与播放器抢同一 CDN，常见「滑了不加载」
    StreamAheadCache.instance.abortInFlight();
    StreamAheadCache.instance.setPaused(true);
    StreamAheadCache.instance.updatePosition(d.inMilliseconds);
    try {
      await c.seekTo(d);
      await c.play();
    } catch (_) {}
    unawaited(_resumeAfterSeek());
  }

  void _onSeekEnd() {
    // 若未走到 onSeek(commit)，也要结束拖动态，避免 seekLoading 粘住
    if (_draggingProgress) {
      setState(() => _draggingProgress = false);
    }
    final v = widget.controller.value;
    if (_seekLoading && v.isPlaying && !v.isBuffering) {
      setState(() {
        _seekLoading = false;
        _showBufferSpinner = false;
        _uiSeekPos = null;
      });
      widget.speedTracker.setLoading(false);
      _notifyLoading(false);
    }
  }

  Future<void> _resumeAfterSeek() async {
    final c = widget.controller;
    final target = _uiSeekPos;
    try {
      await c.play();
      // 最多约 8s：续播 + 缓冲；media_kit 常无 buffered 上报
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted || _draggingProgress) return;
        final v = c.value;
        if (!v.isPlaying) {
          await c.play();
        }
        final ahead = _bufferedAheadMsOfEngine(v);
        final near = target == null ||
            (v.position.inMilliseconds - target.inMilliseconds).abs() <= 4000;
        // 已在播且接近目标：尽快收起（不要死等 !isBuffering）
        if (v.isPlaying && near && i >= 3) {
          if (!mounted) return;
          setState(() {
            _seekLoading = false;
            _showBufferSpinner = false;
            if (near) _uiSeekPos = null;
          });
          widget.speedTracker.setLoading(false);
          _notifyLoading(false);
          return;
        }
        final bufferOk = ahead < 0 || ahead >= 400 || !v.isBuffering;
        final ready = near && !v.isBuffering && v.isPlaying && bufferOk;
        if (ready || (near && v.isPlaying && ahead >= 1500)) {
          if (!mounted) return;
          setState(() {
            _seekLoading = false;
            _showBufferSpinner = false;
            if (near) _uiSeekPos = null;
          });
          widget.speedTracker.setLoading(false);
          _notifyLoading(false);
          return;
        }
        if (i >= 3) {
          setState(() => _showBufferSpinner = true);
          _notifyLoading(true);
        }
        // 卡缓冲时再踢一脚 seek（部分 HLS 首次 seek 空转）
        if (i == 15 && target != null && !near) {
          try {
            await c.seekTo(target);
            await c.play();
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (!mounted || _draggingProgress) return;
    setState(() {
      _seekLoading = false;
      _showBufferSpinner = false;
    });
    widget.speedTracker.setLoading(false);
    _notifyLoading(false);
  }

  int _bufferedAheadMsOfEngine(VodEngineValue v) {
    final pos = v.position;
    var end = Duration.zero;
    for (final r in v.buffered) {
      if (r.end > end) end = r.end;
    }
    if (v.buffered.isEmpty) return -1;
    if (end <= pos) return 0;
    return (end - pos).inMilliseconds;
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _stallTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final displayPos = _uiSeekPos ?? c.value.position;
    final wantPlay = !_userPaused;
    final uiPlaying = c.value.isPlaying || (wantPlay && _showBufferSpinner);
    return MangoPlayerChrome(
      playing: uiPlaying,
      position: displayPos,
      duration: c.value.duration,
      buffering: !widget.ready ||
          _draggingProgress ||
          _seekLoading ||
          _showBufferSpinner ||
          (!c.value.isPlaying && c.value.isBuffering),
      showLoadingHud: _draggingProgress || _seekLoading || _showBufferSpinner,
      loadingSpeedLabel:
          widget.showNetSpeed ? widget.speedTracker.displayLabel : '',
      showBack: widget.showBack,
      topInset: widget.topInset,
      onBack: widget.onBack,
      showDanmakuToggle: widget.showDanmakuToggle,
      danmakuEnabled: widget.danmakuEnabled,
      onDanmakuToggle: widget.onDanmakuToggle == null
          ? null
          : () {
              widget.onDanmakuToggle!();
              widget.onInteract();
            },
      onDanmakuSend: widget.onDanmakuSend == null
          ? null
          : () {
              widget.onDanmakuSend!();
              widget.onInteract();
            },
      onSeek: (d) {
        unawaited(_commitSeek(d));
      },
      onSeekPreview: _onSeekPreview,
      onSeekStart: _onSeekStart,
      onSeekEnd: _onSeekEnd,
      onPlayPause: () {
        if (c.value.isPlaying || _holdingForBuffer) {
          _userPaused = true;
          _holdingForBuffer = false;
          _clearStallFlags();
          c.pause();
        } else {
          _userPaused = false;
          _holdingForBuffer = false;
          c.play();
        }
        widget.onInteract();
      },
      onFullscreen: widget.onFullscreen,
      onNextEpisode: widget.onNextEpisode,
      onEpisodes: widget.onEpisodes,
      onSources: widget.onSources,
      onAspect: widget.onAspect,
      onSpeed: widget.onSpeed,
      onQuality: widget.onQuality,
      aspectLabel: widget.aspectLabel,
      speedLabel: widget.speedLabel,
      qualityLabel: widget.qualityLabel,
      sourceLabel: widget.sourceLabel,
      denseLandscape: widget.denseLandscape,
      introMs: widget.introMs,
      outroMs: widget.outroMs,
      onMarkIntro: widget.onMarkIntro,
      onMarkOutro: widget.onMarkOutro,
      onSkip: widget.onSkip,
      skipEnabled: widget.skipEnabled,
      onSettings: widget.onSettings,
      onCast: widget.onCast,
    );
  }
}

