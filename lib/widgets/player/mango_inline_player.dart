import 'dart:async';
import 'dart:io';
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
  });

  final String url;
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

  /// ???????
  bool _scrubbing = false;
  int _scrubBaseMs = 0;
  int _scrubTargetMs = 0;
  double _scrubAccumDx = 0;

  int get positionMs =>
      _engine?.value.position.inMilliseconds ?? widget.startPositionMs;

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

  Future<void> _markSkipAtCurrent({required bool intro}) async {
    final c = _engine;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position.inSeconds.clamp(0, 600);
    final dur = c.value.duration.inSeconds;
    PlayerSkipPrefs next;
    if (intro) {
      next = _skipPrefs.copyWith(enabled: true, introSeconds: pos);
      DialogX.showSuccess('??????? ${pos}s???????');
    } else {
      final remain = dur > 0 ? (dur - pos).clamp(0, 600) : 90;
      next = _skipPrefs.copyWith(enabled: true, outroSeconds: remain);
      DialogX.showSuccess('?????????? ${remain}s???????');
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
    await PlayerPip.enter(
      sourceRect: rect,
      iosPlayerId: _engine?.nativePlayerId,
      videoAspect: _engine?.value.aspectRatio ?? 16 / 9,
    );
    // ?????????????????
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
  }

  Future<void> _onScrubEnd() async {
    if (!_scrubbing) return;
    _scrubbing = false;
    final target = _scrubTargetMs;
    _seekHintTimer?.cancel();
    if (mounted) setState(() => _seekHint = null);
    final c = _engine;
    if (c == null || !c.value.isInitialized) return;
    StreamAheadCache.instance.updatePosition(target);
    unawaited(StreamAheadCache.instance.warmSeekTarget(target, count: 2));
    await c.seekTo(Duration(milliseconds: target));
    await c.play();
    StreamAheadCache.instance.setPaused(false);
    _onInteract();
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
    );
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
    // 仅系统内核
    prefs = prefs.copyWith(kernel: PlayerKernel.exo);
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
    final modeChanged = prev.playMode != prefs.playMode;
    final cacheChanged = prev.streamCacheEnabled != prefs.streamCacheEnabled;
    if (kernelChanged) {
      _suppressSourceFailover = true;
      StreamAheadCache.instance.stop();
      final resume = positionMs;
      final wasPlaying = !_failed && (_engine?.value.isPlaying ?? true);
      if (mounted) {
        setState(() {
          _ready = false;
          _failed = false;
          _lastErrorMsg = '';
          // ???????????????????????????????
          _currentVariant = null;
          _qualityVariants = const [];
          _activePlayUrl = null;
        });
      }
      // ???????????? media_kit ??????? Exo
      await _disposeController(keepWakelock: false);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      try {
        await _init(resumeMs: resume, autoPlay: wasPlaying);
      } finally {
        _suppressSourceFailover = false;
      }
      return;
    }
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
    // ?????? 2.5s ???
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (!mounted || token != _initToken) return;
    unawaited(_loadDanmaku());
    // ????????????????????????
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || token != _initToken) return;
      final c = _engine;
      if (c == null || !c.value.isInitialized || c.value.hasError) return;
      if (c.value.isBuffering) continue;
      final ahead = _bufferedAheadMsOf(c.value);
      if (ahead < 0 || ahead >= 8000 || i >= 8) {
        _syncStreamAheadCache();
        return;
      }
    }
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


  Future<bool> _trySourceFailover(String reason) async {
    // ????????????????
    if (!_playerSettings.autoSourceFailover) return false;
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
      return ok;
    } catch (_) {
      return false;
    } finally {
      _failoverBusy = false;
    }
  }

  Future<void> _onPlayFailed(String reason) async {
    if (!mounted) return;
    if (!_suppressSourceFailover) {
      final switched = await _trySourceFailover(reason);
      if (switched) return;
    }
    if (!mounted) return;
    setState(() {
      _failed = true;
      _ready = false;
      _lastErrorMsg = reason;
    });
  }

  void _onPlaybackStatus() {
    final c = _engine;
    if (c == null || !_ready || _failoverBusy || _failed) return;
    if (!c.value.hasError) return;
    final msg = c.value.errorDescription?.trim();
    unawaited(_onPlayFailed(
      (msg == null || msg.isEmpty) ? '????' : msg,
    ));
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
    _onInteract();
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
  }) async {
    final token = ++_initToken;
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
          ).timeout(
            const Duration(milliseconds: 1200),
            onTimeout: () => VodResolvedStream(playUrl: url),
          );
          if (!mounted || token != _initToken) return;
          playUrl = resolved.playUrl.isNotEmpty ? resolved.playUrl : url;
          if (resolved.variants.isNotEmpty) {
            _qualityVariants = resolved.variants;
            _currentVariant = resolved.selected ??
                VodPlayback.pickVariant(
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
        path = await VodCacheStore.instance.prepareLocalMediaPath(path);
        if (!mounted || token != _initToken) return;
        playUrl = path;
        _activePlayUrl = path;
        final file = File(path);
        if (!await file.exists()) {
          throw StateError('???????');
        }
      }

      _initSurfaceBuilt = false;
      final engine = createVodEngine(PlayerKernel.exo);
      _engine = engine;
      engine.addListener(_onInitControllerTick);
      _initSpeedTimer?.cancel();
      _initSpeedTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        _onInitControllerTick();
      });
      await engine.open(
        url: playUrl,
        httpHeaders: VodPlayback.httpHeaders,
        backBufferMs: isFile ? 15000 : profile.backBufferMs,
        preferPlatformView: false,
      );
      if (!mounted || token != _initToken) {
        await _disposeController();
        return;
      }

      final start = resumeMs ?? widget.startPositionMs;
      final total = engine.value.duration.inMilliseconds;
      if (start > 1500 && total > 0 && start < total - 2000) {
        await engine.seekTo(Duration(milliseconds: start));
      }
      if (resumeMs == null) {
        await _applySkipIntro(engine);
      }
      await engine.setPlaybackSpeed(_playbackRate);
      await engine.setLooping(_playerSettings.loopSingle);
      if (autoPlay) {
        await engine.play();
      }
      if (_playerSettings.keepScreenOn) {
        await PlaybackWakelock.acquire();
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
        // ????????????????????
        StreamAheadCache.instance.setPaused(
          ctrl.value.isBuffering || (aheadMs >= 0 && aheadMs < 10000),
        );
        if (_progressTick % 5 == 0) {
          widget.onProgress?.call(ctrl.value.position, ctrl.value.duration);
        }
      });

      if (!mounted || token != _initToken) return;
      _stopInitSpeedTracking();
      engine.removeListener(_onInitControllerTick);
      engine.addListener(_onPlaybackStatus);
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
        } else if (_qualityVariants.isEmpty && engine.value.size.height > 0) {
          final sz = engine.value.size;
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
      // ???????????? / ????????????
      unawaited(_deferredAfterPlay(token));
    } catch (e) {
      if (!mounted || token != _initToken) return;
      _qualityBusy = false;
      await _onPlayFailed(e.toString());
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
      await c.releaseSafe();
      c.dispose();
    }
    if (!keepWakelock) {
      await PlaybackWakelock.release();
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
                // ?????????media_kit ? Surface ???????
                if (!_failed && c != null && c.value.isInitialized)
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: _videoShotKey,
                      child: _StableVideoSurface(
                        controller: c,
                        aspect: _playerSettings.aspect,
                        immersiveTop: widget.immersiveTop,
                        mirrorX: _playerSettings.mirrorX,
                        mirrorY: _playerSettings.mirrorY,
                        enhanceLevel: _playerSettings.enhanceLevel,
                      ),
                    ),
                  )
                else if (_failed)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '????????????',
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
                                  '??',
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
                                  '??',
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
                // ?????????
                if (c != null && !_failed)
                  IgnorePointer(
                    child: _DanmakuOverlay(
                      controller: c,
                      items: _danmakuItems,
                      enabled: widget.enableDanmaku &&
                          _danmakuPrefs.enabled &&
                          widget.vodId?.trim().isNotEmpty == true,
                      prefs: _danmakuPrefs,
                      fitCover: widget.immersiveTop ||
                          _playerSettings.aspect == PlayerAspectMode.cover ||
                          _playerSettings.aspect == PlayerAspectMode.fill,
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
                if (c != null && !_failed && !_locked) ...[
                  Positioned(
                    right: lockRight,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !showChrome,
                      child: AnimatedOpacity(
                        opacity: showChrome ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Center(
                          child: PlayerCircleButton(
                            icon: Icons.lock_open_rounded,
                            onTap: _toggleLock,
                            iconSize: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !showChrome,
                      child: AnimatedOpacity(
                        opacity: showChrome ? 1 : 0,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: AnimatedSlide(
                          offset: showChrome
                              ? Offset.zero
                              : const Offset(0, 0.06),
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: _ThrottledChrome(
                            controller: c,
                            chromeVisible: showChrome,
                            ready: _ready,
                            holdEnterAheadMs:
                                PlaybackProfile.of(_playerSettings).holdEnterAheadMs,
                            holdResumeAheadMs:
                                PlaybackProfile.of(_playerSettings).holdResumeAheadMs,
                            speedTracker: _bufferSpeedTracker,
                            showNetSpeed: _playerSettings.showNetSpeed,
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
                            onDanmakuToggle: () =>
                                unawaited(_toggleDanmaku()),
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
                            // ???????????/??/??/??
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
                                ? (anchor) =>
                                    unawaited(_pickPlaybackSpeed(anchor))
                                : null,
                            onQuality: (widget.immersiveTop &&
                                    MediaQuery.sizeOf(context).width >
                                        MediaQuery.sizeOf(context).height)
                                ? (anchor) => unawaited(_pickQuality(anchor))
                                : null,
                            aspectLabel: _playerSettings.aspect.label,
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
                            onMarkIntro: () => unawaited(_markSkipAtCurrent(intro: true)),
                            onMarkOutro: () =>
                                unawaited(_markSkipAtCurrent(intro: false)),
                            onSkip: (_) => _openSideSettings(page: 'skip'),
                            skipEnabled: _skipPrefs.enabled,
                            // ???/?????????
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
                      ),
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
                if (widget.topOverlay != null && !_locked)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !showChrome || _failed || showSide,
                      child: AnimatedOpacity(
                        opacity: showChrome && !_failed && !showSide
                            ? 1
                            : 0,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: AnimatedSlide(
                          offset: showChrome && !showSide
                              ? Offset.zero
                              : const Offset(0, -0.15),
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: widget.topOverlay,
                        ),
                      ),
                    ),
                  ),
                // ???????????/??????????????
                if (!_failed && !_ready)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: PlayerLoadingHud(
                            tracker: _playerSettings.showNetSpeed
                                ? _bufferSpeedTracker
                                : null,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (!_failed && _ready)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _stallLoading,
                        builder: (_, stalled, _) {
                          if (!stalled) return const SizedBox.shrink();
                          return Center(
                            child: PlayerLoadingHud(
                              compact: true,
                              showSpeed: _playerSettings.showNetSpeed,
                              tracker: _playerSettings.showNetSpeed
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
                                final prefer = w * (_showCastSide ? 0.38 : 0.42);
                                final lo = prefer < 260 ? 0.0 : 260.0;
                                final hi = w < 400 ? w : 380.0;
                                return prefer.clamp(lo, hi < lo ? lo : hi);
                              }(),
                              height: double.infinity,
                              child: Material(
                                elevation: 8,
                                color: const Color(0xFFF5F6F8),
                                child: SafeArea(
                                  left: false,
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

    return Positioned.fill(child: layer);
  }
}

/// ??????????/???????
class _StableVideoSurface extends StatelessWidget {
  const _StableVideoSurface({
    required this.controller,
    required this.aspect,
    required this.immersiveTop,
    required this.mirrorX,
    required this.mirrorY,
    this.enhanceLevel = PlayerEnhanceLevel.off,
  });

  final VodEngine controller;
  final PlayerAspectMode aspect;
  final bool immersiveTop;
  final bool mirrorX;
  final bool mirrorY;
  final PlayerEnhanceLevel enhanceLevel;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) return const SizedBox.shrink();
    // 对齐 git 上传版画面路径：直接 VideoPlayer + FittedBox（功能层 enhance 另包）
    final effectiveAspect = aspect;
    final rawRatio =
        controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    final forcedRatio = switch (effectiveAspect) {
      PlayerAspectMode.ratio16x9 => 16 / 9,
      PlayerAspectMode.ratio4x3 => 4 / 3,
      _ => rawRatio,
    };
    final boxFit = switch (effectiveAspect) {
      PlayerAspectMode.cover => BoxFit.cover,
      PlayerAspectMode.fill => BoxFit.fill,
      PlayerAspectMode.fit ||
      PlayerAspectMode.ratio16x9 ||
      PlayerAspectMode.ratio4x3 =>
        BoxFit.contain,
    };

    // 与 git 一致：优先裸 VideoPlayer，避免多余包装
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

    final sz = controller.value.size;
    final logicalW =
        sz.width > 1 ? sz.width : (forcedRatio >= 1 ? 1920.0 : 1080.0);
    final logicalH = sz.height > 1 ? sz.height : (logicalW / forcedRatio);

    Widget fittedFor(BoxFit fit, Alignment align) {
      return ClipRect(
        child: FittedBox(
          fit: fit,
          alignment: align,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: logicalW,
            height: logicalH,
            child: player,
          ),
        ),
      );
    }

    Widget fitted;
    if (effectiveAspect == PlayerAspectMode.cover) {
      // git 原版 cover：底边留白 + bottomCenter（不是自定义 alignY）
      fitted = LayoutBuilder(
        builder: (context, constraints) {
          final guard = (constraints.maxHeight * 0.05).clamp(10.0, 36.0);
          return Padding(
            padding: EdgeInsets.only(bottom: guard),
            child: fittedFor(BoxFit.cover, Alignment.bottomCenter),
          );
        },
      );
    } else {
      fitted = fittedFor(boxFit, Alignment.center);
      if (!(immersiveTop ||
          effectiveAspect == PlayerAspectMode.fill ||
          effectiveAspect == PlayerAspectMode.ratio16x9 ||
          effectiveAspect == PlayerAspectMode.ratio4x3)) {
        fitted = Center(
          child: AspectRatio(
            aspectRatio: forcedRatio,
            child: fitted,
          ),
        );
      }
    }

    // 功能保留：鲜明等画质增强仍可用，但不改底层 Texture 挂载方式
    return PlaybackEnhanceFilter(level: enhanceLevel, child: fitted);
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

  static const _stallNeedMs = 2200;

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
    if (!widget.ready) return true;
    if (_inLayoutQuiet) return false;
    if (_draggingProgress) return false;
    if (_holdingForBuffer) return true;
    final v = widget.controller.value;
    // ???????????????Exo ??? isBuffering?
    if (v.isPlaying) {
      final pos = v.position.inMilliseconds;
      if (!v.isBuffering) return false;
      if (_lastPosMs >= 0 && pos > _lastPosMs) return false;
      // ????????
      return _showBufferSpinner;
    }
    if (_seekLoading) return true;
    if (_showBufferSpinner) return true;
    return false;
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
    // ?????????????????? 120ms ?? 1ms?
    final moved = _lastPosMs >= 0 && posMs > _lastPosMs;

    if (v.isPlaying && moved && !v.isBuffering) {
      _lastPosMs = posMs;
      _clearStallFlags();
      return;
    }
    if (v.isPlaying && moved) {
      _lastPosMs = posMs;
      // ???????? isBuffering ?????
      _clearStallFlags();
      return;
    }

    // ????????????????
    if (v.isPlaying || (!_userPaused && (v.isBuffering || _showBufferSpinner))) {
      _stallSince ??= DateTime.now();
      final waited = DateTime.now().difference(_stallSince!).inMilliseconds;
      // ?? buffering ?????
      final need = v.isBuffering ? (_stallNeedMs ~/ 2) : _stallNeedMs;
      if (waited < need) {
        if (_lastPosMs < 0) _lastPosMs = posMs;
        return;
      }
      if (!_showBufferSpinner) _showBufferSpinner = true;
      return;
    }

    _lastPosMs = posMs;
    final maybeStuck = v.isBuffering || _seekLoading;
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
    final lock = _uiSeekPos;
    if (lock == null || _draggingProgress) return;
    final diff = (v.position.inMilliseconds - lock.inMilliseconds).abs();
    // ??????????????
    if (diff <= 900 ||
        (v.isPlaying && diff <= 2500) ||
        (v.isPlaying && !v.isBuffering)) {
      _uiSeekPos = null;
      if (_seekLoading) {
        _seekLoading = false;
        _showBufferSpinner = false;
        widget.speedTracker.setLoading(false);
      }
    }
  }

  void _onSeekStart() {
    // ??????????????????? seek
    StreamAheadCache.instance.setPaused(true);
    StreamAheadCache.instance.abortInFlight();
    setState(() {
      _draggingProgress = true;
      _seekLoading = false;
      _showBufferSpinner = false;
      _uiSeekPos = widget.controller.value.position;
    });
    widget.speedTracker.setLoading(false);
    _notifyLoading(false);
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
    // ? seek ?????????CDN???????
    StreamAheadCache.instance.updatePosition(d.inMilliseconds);
    unawaited(
      StreamAheadCache.instance.warmSeekTarget(d.inMilliseconds, count: 2),
    );
    try {
      await c.seekTo(d);
      await c.play();
    } catch (_) {}
    unawaited(_resumeAfterSeek());
  }

  void _onSeekEnd() {
    // seek ?? onSeek(commit) ??????????
    if (_draggingProgress) {
      setState(() => _draggingProgress = false);
    }
  }

  Future<void> _resumeAfterSeek() async {
    final c = widget.controller;
    final target = _uiSeekPos;
    try {
      await c.play();
      // ????????????? play???? 6s
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted || _draggingProgress) return;
        final v = c.value;
        if (!v.isPlaying) {
          await c.play();
        }
        final ahead = _bufferedAheadMsOfEngine(v);
        final near = target == null ||
            (v.position.inMilliseconds - target.inMilliseconds).abs() <= 2500;
        final ready = near &&
            !v.isBuffering &&
            v.isPlaying &&
            (ahead < 0 || ahead >= 900);
        if (ready || (near && ahead >= 2000)) {
          if (!mounted) return;
          setState(() {
            _seekLoading = false;
            _showBufferSpinner = false;
            if (near) _uiSeekPos = null;
          });
          widget.speedTracker.setLoading(false);
          _notifyLoading(false);
          StreamAheadCache.instance.setPaused(false);
          return;
        }
        if (i >= 4) {
          setState(() => _showBufferSpinner = true);
          _notifyLoading(true);
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
    StreamAheadCache.instance.setPaused(false);
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
      buffering: !widget.ready || _showBufferSpinner,
      showLoadingHud: false,
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

