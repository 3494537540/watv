import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:gal/gal.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';

import '../../models/movie_models.dart';
import '../../player/danmaku_store.dart';
import '../../player/playback_speed_tracker.dart';
import '../../player/playback_wakelock.dart';
import '../../player/player_danmaku_prefs.dart';
import '../../player/player_pip.dart';
import '../../player/player_settings_store.dart';
import '../../player/player_skip_store.dart';
import '../../player/vod_playback.dart';
import '../../services/app_permission.dart';
import '../../services/danmaku_remote_api.dart';
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

/// 芒果风格内嵌播放器（video_player / ExoPlayer，Android 稳定）
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
  /// 与 sourceNames 对应的探测地址（测速）
  final List<String> sourceProbeUrls;
  /// 当前线路失败时请求父级切源；返回 true 表示已切换，播放器等待新 url
  final Future<bool> Function()? onRequestSourceFailover;
  /// 用户点「重试」前，父级可清空失败线路记录并回到最优源
  final Future<void> Function()? onPrepareRetry;
  /// 全屏等无下方选集区时，在「更多」里显示选集
  final bool showEpisodesInMenu;
  /// 有 vodId 时启用弹幕
  final String? vodId;
  /// 片名，用于第三方弹幕库按标题匹配（如 B 站）
  final String danmakuTitle;
  final int danmakuEpisode;
  /// CMS 集标题，例如「第12集」，用于对齐 B 站分集
  final String danmakuEpisodeLabel;
  final VoidCallback? onCast;
  /// 短剧/直播等场景关闭弹幕
  final bool enableDanmaku;
  final VoidCallback? onPip;
  /// 未就绪时垫在画面下的封面
  final String? posterUrl;

  @override
  State<MangoInlinePlayer> createState() => MangoInlinePlayerState();
}

class MangoInlinePlayerState extends State<MangoInlinePlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  /// 最近一次播放失败原因（提交 CMS 报错用）
  String _lastErrorMsg = '';
  bool _failoverBusy = false;
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
  bool _lastStallFlag = false;

  /// HLS 多清晰度
  List<VodHlsVariant> _qualityVariants = const [];
  VodHlsVariant? _currentVariant;
  VodQualityTier _qualityPrefer = VodQualityStore.cached;
  String? _activePlayUrl;
  int _stallDropHits = 0;
  DateTime? _stallDropWindow;
  bool _qualityBusy = false;

  /// 横向滑动调进度
  bool _scrubbing = false;
  int _scrubBaseMs = 0;
  int _scrubTargetMs = 0;
  double _scrubAccumDx = 0;

  int get positionMs =>
      _controller?.value.position.inMilliseconds ?? widget.startPositionMs;

  Duration get position =>
      _controller?.value.position ??
      Duration(milliseconds: widget.startPositionMs);

  String get _sourceChromeLabel {
    if (widget.sourceNames.isEmpty) return '线路';
    final i = widget.sourceIndex.clamp(0, widget.sourceNames.length - 1);
    final raw = widget.sourceNames[i].trim();
    if (raw.isEmpty) return '线路${i + 1}';
    // 底栏空间有限，过长截断
    if (raw.length <= 6) return raw;
    return '${raw.substring(0, 5)}…';
  }

  Future<void> _pickSource([BuildContext? anchor]) async {
    if (widget.sourceNames.length <= 1 || widget.onSourceSelect == null) {
      DialogX.showWarning('当前影片只有一条播放线路');
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
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position.inSeconds.clamp(0, 600);
    final dur = c.value.duration.inSeconds;
    PlayerSkipPrefs next;
    if (intro) {
      next = _skipPrefs.copyWith(enabled: true, introSeconds: pos);
      DialogX.showSuccess('已设片头结束于 ${pos}s（进度条绿标）');
    } else {
      final remain = dur > 0 ? (dur - pos).clamp(0, 600) : 90;
      next = _skipPrefs.copyWith(enabled: true, outroSeconds: remain);
      DialogX.showSuccess('已设片尾开始（距片尾 ${remain}s，进度条橙标）');
    }
    await _saveSkipPrefs(next);
  }

  Future<void> pause() async {
    await _controller?.pause();
  }

  Future<void> play() async {
    await _controller?.play();
  }

  Future<void> seekTo(Duration position) async {
    await _controller?.seekTo(position);
  }

  /// 进入画中画前收起控件，小窗只留画面
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

  /// 播放器在屏幕上的区域（画中画 sourceRectHint，物理像素）
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
      controller: _controller,
    );
    // 进窗后再播，避免和系统动画抢同一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(play());
    });
  }

  void _onPipFlag() {
    if (!mounted) return;
    // 仅刷新本控件透明度，绝不挪动 VideoPlayer 节点
    setState(() {});
    if (PlayerPip.isInPip) {
      hideChrome();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(play());
      });
    }
  }

  /// 顶栏快进等外部入口
  Future<void> seekBySeconds(int seconds) => _seekRelative(seconds);

  Future<void> _seekRelative(int seconds) async {
    final c = _controller;
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
    if (_locked || !_ready || _holdBoost) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _scrubbing = true;
    _scrubBaseMs = c.value.position.inMilliseconds;
    _scrubTargetMs = _scrubBaseMs;
    _scrubAccumDx = 0;
    _seekHintTimer?.cancel();
  }

  void _onScrubUpdate(DragUpdateDetails d, double width) {
    if (!_scrubbing || width <= 0) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _scrubAccumDx += d.delta.dx;
    final total = c.value.duration.inMilliseconds;
    if (total <= 0) return;
    // 整屏横向约扫过片长的 40%，手感接近主流播放器
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
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(Duration(milliseconds: target));
    await c.play();
    _onInteract();
  }

  Future<void> _applySkipIntro(VideoPlayerController c) async {
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
    final c = _controller;
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

  /// 沉浸播放：一律右侧滑出（点遮罩关闭）；内嵌矮窗才用底部 sheet
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
        await _controller?.setPlaybackSpeed(r);
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
      // 勿在此 Navigator.pop：面板按钮已 onClose，再 pop 会退出详情页
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
      durationSec: _controller?.value.duration.inSeconds ?? 0,
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
    // 横屏全屏用侧栏；竖屏小窗用底部投屏面板，避免未全屏看不到入口
    final wide =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    if (widget.immersiveTop && wide) {
      _openCastSide();
      return;
    }
    widget.onCast?.call();
  }

  Future<void> _reportPlayError() async {
    final c = _controller;
    var err = _lastErrorMsg.trim();
    if (err.isEmpty && c != null && c.value.hasError) {
      err = c.value.errorDescription?.trim() ?? '';
    }
    if (err.isEmpty && _failed) {
      err = '播放失败';
    }
    if (err.isEmpty) {
      err = '用户手动报错（播放异常/卡顿/错源等）';
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
    await PlayerSettingsStore.save(prefs);
    if (!mounted) return;
    setState(() => _playerSettings = prefs);
    await _controller?.setLooping(prefs.loopSingle);
    if (prefs.keepScreenOn) {
      await PlaybackWakelock.acquire();
    } else {
      await PlaybackWakelock.release();
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
        await _controller?.pause();
        setState(() => _sleepMinutes = 0);
        DialogX.showSuccess('定时关闭：已暂停播放');
      });
      DialogX.showSuccess('将在 $minutes 分钟后暂停');
    }
    if (mounted) setState(() {});
  }

  Future<void> _takeScreenshot() async {
    try {
      final allowed = await AppPermission.requestWithRationale(
        AppPermissionKind.saveMedia,
        context: context,
        title: '需要保存到相册',
        message: '截图会保存到系统相册，方便你查看与分享。',
      );
      if (!allowed) return;
      final boundary = _videoShotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        DialogX.showWarning('截图失败');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) {
        DialogX.showWarning('截图失败');
        return;
      }
      await Gal.putImageBytes(bytes.buffer.asUint8List());
      DialogX.showSuccess('已保存到相册');
    } catch (e) {
      debugPrint('[player] screenshot fail: $e');
      DialogX.showWarning('截图失败（部分机型硬解画面无法截取）');
    }
  }
  Future<void> _openEpisodes([BuildContext? anchor]) async {
    final eps = widget.episodes;
    if (eps.length <= 1 || widget.onEpisodeSelect == null) return;
    final ctx = anchor ?? context;
    if (!ctx.mounted) return;
    // 横屏右侧侧栏；竖屏底部面板
    await showPlayerEpisodeSheet(
      context: ctx,
      episodes: eps,
      selected: widget.selectedEpisode,
      onSelect: widget.onEpisodeSelect!,
    );
    _onInteract();
  }

  bool get _preferSidePopups {
    if (!widget.immersiveTop || !mounted) return false;
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

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
    await _controller?.setPlaybackSpeed(picked);
    // 所选倍速 ≥1.5 时同步为长按快进倍率，避免「设了倍速按住仍是 2x」
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
        DialogX.showWarning('请从详情页切换播放线路');
      }
      _onInteract();
      return;
    }
    if (picked == '_sole') {
      if (widget.sourceNames.length > 1) {
        DialogX.showWarning('当前线路仅单一清晰度，请换播放线路');
      } else {
        DialogX.showWarning('当前片源无多清晰度可选');
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
            ? '当前线路无多清晰度，请换播放线路试试'
            : '当前片源无多清晰度可选',
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
      DialogX.showSuccess('已是 ${variant.shortLabel}');
      return;
    }
    final resume = positionMs;
    final wasPlaying = _controller?.value.isPlaying ?? true;
    if (prefer != null) {
      await VodQualityStore.save(prefer);
    }
    if (!mounted) return;
    setState(() {
      _qualityPrefer = prefer ?? variant.tier;
      _currentVariant = variant;
      _stallDropHits = 0;
    });
    await _init(
      forceUrl: variant.url,
      resumeMs: resume,
      autoPlay: wasPlaying,
    );
    if (mounted && !_failed) {
      DialogX.showSuccess('已切换到 ${variant.shortLabel}');
    }
  }

  /// 卡顿过多时自动降一档；单档线路则尝试换线
  Future<void> _maybeAutoDropQuality() async {
    final now = DateTime.now();
    if (_stallDropWindow == null ||
        now.difference(_stallDropWindow!).inSeconds > 60) {
      _stallDropWindow = now;
      _stallDropHits = 0;
    }
    _stallDropHits++;
    if (_stallDropHits < 2) return;

    if (_qualityBusy) return;

    if (_qualityVariants.length >= 2) {
      final cur = _currentVariant;
      if (cur == null) return;
      final lower = VodPlayback.lowerThan(_qualityVariants, cur);
      if (lower == null) return;
      _stallDropHits = 0;
      DialogX.showWarning('网络不稳，已切换到 ${lower.shortLabel}');
      await _switchToVariant(lower, prefer: VodQualityTier.auto);
      return;
    }

    // 单档：仅在开启「自动切换线路」时换线
    if (_playerSettings.autoSourceFailover &&
        widget.sourceNames.length > 1 &&
        widget.onRequestSourceFailover != null) {
      _stallDropHits = 0;
      await _trySourceFailover('播放卡顿，切换线路');
    }
  }

  Future<bool> _trySourceFailover(String reason) async {
    // 默认关闭自动切线，需在设置中开启
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
    final switched = await _trySourceFailover(reason);
    if (switched) return;
    if (!mounted) return;
    setState(() {
      _failed = true;
      _ready = false;
      _lastErrorMsg = reason;
    });
  }

  void _onPlaybackStatus() {
    final c = _controller;
    if (c == null || !_ready || _failoverBusy || _failed) return;
    if (!c.value.hasError) return;
    final msg = c.value.errorDescription?.trim();
    unawaited(_onPlayFailed(
      (msg == null || msg.isEmpty) ? '播放中断' : msg,
    ));
  }

  Future<void> _manualRetry() async {
    final before = widget.url;
    await widget.onPrepareRetry?.call();
    if (!mounted) return;
    // 父级切回最优源改了 url 时，交给 didUpdateWidget 拉流
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
      DialogX.showWarning('当前影片暂不支持弹幕');
      return;
    }
    if (!_danmakuPrefs.enabled) {
      await PlayerDanmakuPrefs.setEnabled(true);
      if (!mounted) return;
      setState(() => _danmakuPrefs = PlayerDanmakuPrefs.cached);
    }
    if (!mounted) return;
    final c = _controller;
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
      author: (author == null || author.isEmpty) ? '游客' : author,
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
      DialogX.showSuccess('弹幕已发送');
    } else {
      DialogX.showWarning('已显示，同步第三方失败（仍保存在本地）');
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
    await _controller?.setPlaybackSpeed(rate);
    if (mounted) setState(() {});
  }

  Future<void> _endHoldBoost() async {
    if (!_holdBoost) return;
    _holdBoost = false;
    _playbackRate = _holdRateBackup;
    await _controller?.setPlaybackSpeed(_holdRateBackup);
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
      // 静默：有弹幕也不弹 Toast
    } else if (cached.isEmpty) {
      setState(() => _danmakuItems = const []);
      // 静默：无弹幕也不提示
    }
  }

  /// 立即停止并释放（切页、热重载、新实例抢占时调用）
  Future<void> forceStop() async {
    _initToken++;
    _holdBoost = false;
    _showSideSettings = false;
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _outroTimer?.cancel();
    _seekHintTimer?.cancel();
    _sleepTimer?.cancel();
    _stallLoading.value = false;
    _stopInitSpeedTracking();
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        if (c.value.isInitialized) await c.pause();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
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
    _stallLoading.addListener(_onStallLoadingFlag);
    unawaited(_loadDanmaku());
    _init();
  }

  void _onStallLoadingFlag() {
    final stalled = _stallLoading.value;
    if (stalled && !_lastStallFlag) {
      unawaited(_maybeAutoDropQuality());
    }
    _lastStallFlag = stalled;
  }

  @override
  void reassemble() {
    super.reassemble();
    // 热重载不会走 dispose，必须主动停掉原生 ExoPlayer
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

  VideoFormat? _formatHintFor(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('m3u8?')) {
      return VideoFormat.hls;
    }
    return null;
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
      await _onPlayFailed('播放地址为空');
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
      if (forceUrl != null && forceUrl.trim().isNotEmpty) {
        playUrl = forceUrl.trim();
      } else {
        final prefer = await VodQualityStore.load();
        if (!mounted || token != _initToken) return;
        _qualityPrefer = prefer;
        final resolved = await VodPlayback.resolveStream(url, prefer: prefer);
        if (!mounted || token != _initToken) return;
        playUrl = resolved.playUrl;
        _qualityVariants = resolved.variants;
        _currentVariant = resolved.selected;
        if (_currentVariant == null && resolved.variants.isNotEmpty) {
          _currentVariant = VodPlayback.pickVariant(resolved.variants, prefer);
        }
      }
      _activePlayUrl = playUrl;
      if (!mounted || token != _initToken) return;
      final uri = Uri.parse(playUrl);
      final isFile = uri.scheme == 'file' ||
          (!playUrl.contains('://') &&
              (playUrl.startsWith('/') ||
                  RegExp(r'^[A-Za-z]:[\\/]').hasMatch(playUrl)));
      final VideoPlayerController c;
      final opts = VideoPlayerOptions(
        mixWithOthers: false,
        // 更大回退缓冲：拖进度 / 小幅回看更少重新加载
        backBufferDurationMs: 90000,
        // iOS 画中画需要 AVPlayerLayer（PlatformView）
        allowBackgroundPlayback: true,
      );
      // iOS：PlatformView 才能挂 AVPictureInPictureController
      final viewType = (!kIsWeb &&
              defaultTargetPlatform == TargetPlatform.iOS)
          ? VideoViewType.platformView
          : VideoViewType.textureView;
      if (isFile) {
        final path = uri.scheme == 'file' ? uri.toFilePath() : playUrl;
        c = VideoPlayerController.file(
          File(path),
          videoPlayerOptions: opts,
          viewType: viewType,
        );
      } else {
        c = VideoPlayerController.networkUrl(
          uri,
          httpHeaders: VodPlayback.httpHeaders,
          formatHint: _formatHintFor(playUrl),
          videoPlayerOptions: opts,
          viewType: viewType,
        );
      }
      _controller = c;
      c.addListener(_onInitControllerTick);
      _initSpeedTimer?.cancel();
      _initSpeedTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        _onInitControllerTick();
      });
      await c.initialize();
      if (!mounted || token != _initToken) {
        await c.dispose();
        return;
      }

      final start = resumeMs ?? widget.startPositionMs;
      final total = c.value.duration.inMilliseconds;
      if (start > 1500 && total > 0 && start < total - 2000) {
        await c.seekTo(Duration(milliseconds: start));
      }
      if (resumeMs == null) {
        await _applySkipIntro(c);
      }
      await c.setPlaybackSpeed(_playbackRate);
      await c.setLooping(_playerSettings.loopSingle);
      if (autoPlay) {
        await c.play();
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
        final ctrl = _controller;
        if (ctrl == null || !ctrl.value.isInitialized) return;
        if (_progressTick % 5 == 0) {
          widget.onProgress?.call(ctrl.value.position, ctrl.value.duration);
        }
      });

      if (!mounted || token != _initToken) return;
      _stopInitSpeedTracking();
      c.removeListener(_onInitControllerTick);
      c.addListener(_onPlaybackStatus);
      setState(() {
        _ready = true;
        _qualityBusy = false;
        // 单路媒体流：用真实分辨率补一条清晰度标签
        if (_qualityVariants.isEmpty && c.value.size.height > 0) {
          final sz = c.value.size;
          final synthetic = VodHlsVariant(
            url: playUrl,
            bandwidth: 0,
            width: sz.width.round(),
            height: sz.height.round(),
          );
          _qualityVariants = [synthetic];
          _currentVariant = synthetic;
        } else if (_currentVariant == null &&
            _qualityVariants.length == 1) {
          _currentVariant = _qualityVariants.first;
        }
      });
      _scheduleHideChrome();
    } catch (e) {
      if (!mounted || token != _initToken) return;
      _qualityBusy = false;
      await _onPlayFailed(e.toString());
    }
  }

  void _onInitControllerTick() {
    final c = _controller;
    _bufferSpeedTracker.setLoading(true);
    if (c != null && c.value.isInitialized) {
      _bufferSpeedTracker.tick(
        c.value.buffered,
        isBuffering: c.value.isBuffering || !_ready,
      );
    } else {
      _bufferSpeedTracker.tick(const [], isBuffering: true);
    }
    // 不 setState：加载 HUD 自己读 tracker，避免整页狂刷导致掉帧/黑屏
  }

  void _stopInitSpeedTracking() {
    _initSpeedTimer?.cancel();
    _initSpeedTimer = null;
    final c = _controller;
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
    final c = _controller;
    _controller = null;
    if (c != null) {
      try {
        c.removeListener(_onPlaybackStatus);
      } catch (_) {}
      await c.dispose();
    }
    if (!keepWakelock) {
      await PlaybackWakelock.release();
    }
  }

  @override
  void dispose() {
    PlayerPip.inPip.removeListener(_onPipFlag);
    _stallLoading.removeListener(_onStallLoadingFlag);
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
      final c = _controller;
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
    final c = _controller;
    final topInset =
        widget.immersiveTop ? 0.0 : MediaQuery.paddingOf(context).top;
    // 小窗模式只留画面，不叠控件，避免卡死
    final inPip = PlayerPip.isInPip;
    final showChrome = _showChrome && !inPip;
    final showSide = (_showSideSettings || _showCastSide) && !inPip;
    // 锁屏：右侧垂直居中（横屏全屏同样右侧）
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
                if (_ready && c != null && c.value.isInitialized)
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: _videoShotKey,
                      child: _StableVideoSurface(
                        controller: c,
                        aspect: _playerSettings.aspect,
                        immersiveTop: widget.immersiveTop,
                        mirrorX: _playerSettings.mirrorX,
                        mirrorY: _playerSettings.mirrorY,
                      ),
                    ),
                  )
                else if (_failed)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '播放失败，已尝试可用线路',
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
                      // 横屏时偏上，避免挡画面中心
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
                // 缓冲中也照常画弹幕
                if (c != null && !_failed)
                  _DanmakuOverlay(
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
                            ready: _ready,
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
                            onSources: widget.sourceNames.length > 1 &&
                                    widget.onSourceSelect != null
                                ? (anchor) => unawaited(_pickSource(anchor))
                                : null,
                            onAspect: (anchor) => unawaited(_pickAspect(anchor)),
                            onSpeed: (anchor) =>
                                unawaited(_pickPlaybackSpeed(anchor)),
                            onQuality: (anchor) =>
                                unawaited(_pickQuality(anchor)),
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
                            onSkip: () => _openSideSettings(page: 'skip'),
                            skipEnabled: _skipPrefs.enabled,
                            // 仅全屏/横屏显示设置与投屏
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
                // 加载置顶正中：盖在顶栏/底栏之上，视觉落在画面正中央
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
                                                ? '正在播放'
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
                                          key: ValueKey(
                                            'side-$_sideSettingsPage',
                                          ),
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

/// 随播放进度刷新弹幕；非 cover 模式时对齐视频画面区域
class _DanmakuOverlay extends StatefulWidget {
  const _DanmakuOverlay({
    required this.controller,
    required this.items,
    required this.enabled,
    required this.prefs,
    this.fitCover = false,
  });

  final VideoPlayerController controller;
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

/// 稳定视频表面：仅比例/镜像变化时重建
class _StableVideoSurface extends StatelessWidget {
  const _StableVideoSurface({
    required this.controller,
    required this.aspect,
    required this.immersiveTop,
    required this.mirrorX,
    required this.mirrorY,
  });

  final VideoPlayerController controller;
  final PlayerAspectMode aspect;
  final bool immersiveTop;
  final bool mirrorX;
  final bool mirrorY;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) return const SizedBox.shrink();
    // 尊重用户比例设置；不再横屏强制 cover，避免 1080 被放大裁切发糊
    final effectiveAspect = aspect;
    final rawRatio =
        controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    final forcedRatio = switch (effectiveAspect) {
      PlayerAspectMode.ratio16x9 => 16 / 9,
      PlayerAspectMode.ratio4x3 => 4 / 3,
      _ => rawRatio,
    };
    final boxFit = switch (effectiveAspect) {
      // 裁剪填充：铺满 + 贴底，优先保住硬字幕；底部再留一点安全边
      PlayerAspectMode.cover => BoxFit.cover,
      PlayerAspectMode.fill => BoxFit.fill,
      PlayerAspectMode.fit ||
      PlayerAspectMode.ratio16x9 ||
      PlayerAspectMode.ratio4x3 =>
        BoxFit.contain,
    };

    Widget player = VideoPlayer(controller);
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

    // 用真实分辨率铺面，避免固定 1600 逻辑画布被放大后发糊
    final sz = controller.value.size;
    final logicalW = sz.width > 1 ? sz.width : (forcedRatio >= 1 ? 1920.0 : 1080.0);
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

    if (effectiveAspect == PlayerAspectMode.cover) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // 硬字幕常贴片源底边；留出安全边避免贴齐屏幕被裁切
          final guard = (constraints.maxHeight * 0.05).clamp(10.0, 36.0);
          return Padding(
            padding: EdgeInsets.only(bottom: guard),
            child: fittedFor(BoxFit.cover, Alignment.bottomCenter),
          );
        },
      );
    }

    final fitted = fittedFor(
      boxFit,
      Alignment.center,
    );

    if (immersiveTop ||
        effectiveAspect == PlayerAspectMode.fill ||
        effectiveAspect == PlayerAspectMode.ratio16x9 ||
        effectiveAspect == PlayerAspectMode.ratio4x3) {
      return fitted;
    }
    return Center(
      child: AspectRatio(
        aspectRatio: forcedRatio,
        child: fitted,
      ),
    );
  }
}

/// 全局只允许一个内嵌播放器，防止热重载/切页后残留播放
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

/// 供页面退出时停止所有播放
Future<void> stopAllInlinePlayback() => _PlaybackSession.stopAll();

/// 播控层：真正卡顿才提示缓冲
class _ThrottledChrome extends StatefulWidget {
  const _ThrottledChrome({
    required this.controller,
    required this.ready,
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

  final VideoPlayerController controller;
  final bool ready;
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
  final VoidCallback? onSkip;
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
  bool _draggingProgress = false;
  bool _seekLoading = false;
  bool _lastLoadingNotified = false;
  int _lastPosMs = -1;
  DateTime? _stallSince;
  Size? _lastMqSize;
  DateTime? _layoutQuietUntil;
  /// 拖动/seek 目标：进度条与时间先锁在这里，等解码追上再放开
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
    if (_showBufferSpinner || _seekLoading) {
      _showBufferSpinner = false;
      _seekLoading = false;
    }
  }

  bool get _showLoadingHud {
    if (!widget.ready) return true;
    if (_inLayoutQuiet) return false;
    if (_draggingProgress) return false;
    final v = widget.controller.value;
    // 已在播且画面在走：绝不挡画面（Exo 常误报 isBuffering）
    if (v.isPlaying) {
      final pos = v.position.inMilliseconds;
      if (!v.isBuffering) return false;
      if (_lastPosMs >= 0 && pos > _lastPosMs) return false;
      // 仅真正卡住才转圈
      return _showBufferSpinner;
    }
    if (_seekLoading) return true;
    if (_showBufferSpinner) return true;
    return false;
  }

  void _notifyLoading(bool visible) {
    if (_lastLoadingNotified == visible) return;
    _lastLoadingNotified = visible;
    // ValueListenableBuilder 不能在 build/layout 阶段被通知
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
    widget.controller.addListener(_onController);
    _uiTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final v = widget.controller.value;
      _evaluateStall(v);
      _maybeReleaseSeekLock(v);
      widget.speedTracker.setLoading(_showLoadingHud);
      widget.speedTracker.tick(v.buffered, isBuffering: _showBufferSpinner);
      _notifyLoading(_showLoadingHud);
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
      // 横竖屏切换时 surface 短暂缓冲，不展示“重新加载”观感
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
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _lastPosMs = -1;
      _stallSince = null;
      _showBufferSpinner = false;
    }
  }

  void _evaluateStall(VideoPlayerValue v) {
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
    // 任意进度前进都算在播，清加载（阈值从 120ms 降到 1ms）
    final moved = _lastPosMs >= 0 && posMs > _lastPosMs;

    if (v.isPlaying && (moved || !v.isBuffering)) {
      _lastPosMs = posMs;
      _clearStallFlags();
      return;
    }

    // 播放中但进度本 tick 未动：先记时间，别立刻转圈
    if (v.isPlaying) {
      _stallSince ??= DateTime.now();
      final waited = DateTime.now().difference(_stallSince!).inMilliseconds;
      if (waited < _stallNeedMs) {
        if (_lastPosMs < 0) _lastPosMs = posMs;
        return;
      }
      // 长时间无进度才显示缓冲
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

  void _onController() {
    if (!widget.ready) return;
    _evaluateStall(widget.controller.value);
    _notifyLoading(_showLoadingHud);
  }

  void _maybeReleaseSeekLock(VideoPlayerValue v) {
    final lock = _uiSeekPos;
    if (lock == null || _draggingProgress) return;
    final diff = (v.position.inMilliseconds - lock.inMilliseconds).abs();
    // 解码位置已贴近目标，或已在播
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
      _stallSince = DateTime.now();
    });
    widget.onInteract();
    widget.speedTracker.setLoading(true);
    widget.speedTracker.resetMetrics();
    widget.speedTracker.tick(c.value.buffered, isBuffering: true);
    _notifyLoading(true);
    try {
      await c.seekTo(d);
      await c.play();
    } catch (_) {}
    unawaited(_resumeAfterSeek());
    _stallTimer?.cancel();
    _stallTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final v = c.value;
      _maybeReleaseSeekLock(v);
      if (v.isPlaying &&
          (v.position.inMilliseconds > 0 || !v.isBuffering)) {
        setState(() {
          _seekLoading = false;
          _showBufferSpinner = false;
          final lock = _uiSeekPos;
          if (lock != null) {
            final diff =
                (v.position.inMilliseconds - lock.inMilliseconds).abs();
            if (diff <= 900) _uiSeekPos = null;
          }
        });
        widget.speedTracker.setLoading(false);
        _notifyLoading(false);
        return;
      }
      if (!v.isPlaying) {
        setState(() => _showBufferSpinner = true);
        _notifyLoading(true);
        unawaited(_resumeAfterSeek());
      } else {
        setState(() {
          _seekLoading = false;
          _showBufferSpinner = false;
          final lock = _uiSeekPos;
          if (lock != null) {
            final diff =
                (v.position.inMilliseconds - lock.inMilliseconds).abs();
            if (diff <= 900) _uiSeekPos = null;
          }
        });
        widget.speedTracker.setLoading(false);
        _notifyLoading(false);
      }
    });
  }

  void _onSeekEnd() {
    // seek 已在 onSeek(commit) 里完成；此处仅作兜底
    if (_draggingProgress) {
      setState(() => _draggingProgress = false);
    }
  }

  Future<void> _resumeAfterSeek() async {
    final c = widget.controller;
    try {
      await c.play();
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted || _draggingProgress) return;
        final v = c.value;
        if (v.isPlaying) return;
        await c.play();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _stallTimer?.cancel();
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final displayPos = _uiSeekPos ?? c.value.position;
    return MangoPlayerChrome(
      playing: c.value.isPlaying,
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
        if (c.value.isPlaying) {
          c.pause();
        } else {
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

