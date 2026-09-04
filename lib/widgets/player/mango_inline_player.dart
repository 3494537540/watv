import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
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
  int _sleepMinutes = 0;
  Timer? _sleepTimer;
  final _videoShotKey = GlobalKey();
  final _stallLoading = ValueNotifier<bool>(false);

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
    if (!_showChrome && !_showSideSettings) return;
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showChrome = false;
      _showSideSettings = false;
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
    await PlayerPip.enter(sourceRect: rect);
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

  /// 横屏全屏：右侧滑出；竖屏/内嵌：底部白卡片（避免播放器高度不够整页溢出）
  Future<void> openSettings() async {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    if (widget.immersiveTop && landscape) {
      setState(() {
        _showSideSettings = true;
        _showChrome = false;
      });
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x99000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final sh = MediaQuery.sizeOf(ctx).height;
        // 小窗高度不够时不能 clamp(380, 560)
        final sheetH = (sh * 0.62).clamp(120.0, sh < 560 ? sh : 560.0);
        return SizedBox(
          height: sheetH,
          child: PlayerSideSettingsPanel(
            asBottomSheet: true,
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
      onOpenSources: () {},
      onCast: () => widget.onCast?.call(),
      onPip: () {
        unawaited(enterPictureInPicture());
      },
      hasEpisodes:
          widget.episodes.length > 1 && widget.onEpisodeSelect != null,
      hasSources: false,
      hasCast: widget.onCast != null,
      hasNext: widget.showNextEpisode,
      onNextEpisode: widget.onNextEpisode,
      onReportError: () => unawaited(_reportPlayError()),
      enableDanmaku: widget.enableDanmaku,
    );
  }

  void _closeSideSettings() {
    if (!_showSideSettings) return;
    setState(() => _showSideSettings = false);
    _onInteract();
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

  Future<void> _pickPlaybackSpeed([BuildContext? anchor]) async {
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

  Future<bool> _trySourceFailover(String reason) async {
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
      remote = await _danmakuApi.fetch(
        vodId: id,
        episode: ep,
        playUrl: widget.url,
        title: title,
        episodeLabel: widget.danmakuEpisodeLabel,
      );
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
    unawaited(_loadDanmaku());
    _init();
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

  Future<void> _init() async {
    final token = ++_initToken;
    await _disposeController(keepWakelock: false);
    final url = widget.url.trim();
    if (url.isEmpty) {
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
      });
      _bufferSpeedTracker.reset();
      _bufferSpeedTracker.setLoading(true);
    }

    try {
      final uri = Uri.parse(url);
      final isFile = uri.scheme == 'file' ||
          (!url.contains('://') &&
              (url.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url)));
      final VideoPlayerController c;
      if (isFile) {
        final path = uri.scheme == 'file' ? uri.toFilePath() : url;
        c = VideoPlayerController.file(
          File(path),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );
      } else {
        c = VideoPlayerController.networkUrl(
          uri,
          httpHeaders: VodPlayback.httpHeaders,
          formatHint: _formatHintFor(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
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

      final start = widget.startPositionMs;
      final total = c.value.duration.inMilliseconds;
      if (start > 3000 && total > 0 && start < total - 8000) {
        await c.seekTo(Duration(milliseconds: start));
      }
      await _applySkipIntro(c);
      await c.setPlaybackSpeed(_playbackRate);
      await c.setLooping(_playerSettings.loopSingle);
      await c.play();
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
      setState(() => _ready = true);
      _scheduleHideChrome();
    } catch (e) {
      if (!mounted || token != _initToken) return;
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
    final showSide = _showSideSettings && !inPip;

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
                // 仅未就绪时全屏加载；播放中卡顿用轻量转圈，避免黑屏盖住画面
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
                  ),
                if (!_failed && _ready)
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
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: PlayerCircleButton(
                        icon: CupertinoIcons.lock_fill,
                        onTap: _toggleLock,
                      ),
                    ),
                  ),
                if (c != null && !_failed && !_locked) ...[
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IgnorePointer(
                        ignoring: !showChrome,
                        child: AnimatedOpacity(
                          opacity: showChrome ? 1 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: PlayerCircleButton(
                            icon: CupertinoIcons.lock_open,
                            onTap: _toggleLock,
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
                            onAspect: (anchor) => unawaited(_pickAspect(anchor)),
                            onSpeed: (anchor) =>
                                unawaited(_pickPlaybackSpeed(anchor)),
                            aspectLabel: _playerSettings.aspect.label,
                            speedLabel: VodPlayback.rateLabel(_playbackRate),
                            denseLandscape: widget.immersiveTop &&
                                MediaQuery.sizeOf(context).width >
                                    MediaQuery.sizeOf(context).height,
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
                if (showSide)
                  Positioned.fill(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _closeSideSettings,
                          behavior: HitTestBehavior.opaque,
                          child: const ColoredBox(color: Color(0x66000000)),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: () {
                              final w = MediaQuery.sizeOf(context).width;
                              final prefer = w * 0.42;
                              final lo = prefer < 280 ? 0.0 : 280.0;
                              final hi = w < 400 ? w : 400.0;
                              return prefer.clamp(lo, hi < lo ? lo : hi);
                            }(),
                            height: double.infinity,
                            child: Material(
                              elevation: 8,
                              color: Colors.white,
                              child: SafeArea(
                                left: false,
                                child: PlayerSideSettingsPanel(
                                  onClose: _closeSideSettings,
                                  host: _settingsHost(),
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
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    // 全屏横屏强制铺满，避免挖孔旁/上下黑边
    final effectiveAspect = immersiveTop && landscape
        ? (aspect == PlayerAspectMode.fill
            ? PlayerAspectMode.fill
            : PlayerAspectMode.cover)
        : aspect;
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

    // 固定逻辑分辨率再 FittedBox，旋转时减少中间花屏
    final logicalW = forcedRatio >= 1 ? 1600.0 : 900.0;
    final logicalH = logicalW / forcedRatio;
    final fitted = ClipRect(
      child: FittedBox(
        fit: boxFit,
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: logicalW,
          height: logicalH,
          child: player,
        ),
      ),
    );

    if (immersiveTop ||
        effectiveAspect == PlayerAspectMode.cover ||
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
    this.onAspect,
    this.onSpeed,
    this.aspectLabel = '适应',
    this.speedLabel = '倍速',
    this.denseLandscape = false,
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
  final void Function(BuildContext anchor)? onAspect;
  final void Function(BuildContext anchor)? onSpeed;
  final String aspectLabel;
  final String speedLabel;
  final bool denseLandscape;

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

  static const _stallNeedMs = 1100;

  bool get _inLayoutQuiet {
    final until = _layoutQuietUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get _showLoadingHud {
    if (!widget.ready) return true;
    if (_inLayoutQuiet) return false;
    if (_draggingProgress) return false;
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
    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final v = widget.controller.value;
      _evaluateStall(v);
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
    final advanced = _lastPosMs >= 0 && (posMs - _lastPosMs) >= 120;
    if (advanced || (v.isPlaying && !v.isBuffering)) {
      _lastPosMs = posMs;
      _stallSince = null;
      _stallTimer?.cancel();
      _stallTimer = null;
      if (_showBufferSpinner || _seekLoading) {
        _showBufferSpinner = false;
        _seekLoading = false;
      }
      return;
    }

    _lastPosMs = posMs;
    final maybeStuck = v.isBuffering || (!v.isPlaying && _seekLoading);
    if (!maybeStuck) {
      _stallSince = null;
      _stallTimer?.cancel();
      _stallTimer = null;
      if (_showBufferSpinner) _showBufferSpinner = false;
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

  void _onSeekStart() {
    setState(() {
      _draggingProgress = true;
      _seekLoading = false;
      _showBufferSpinner = false;
    });
    widget.speedTracker.setLoading(false);
    _notifyLoading(false);
    widget.onInteract();
  }

  void _onSeekEnd() {
    setState(() {
      _draggingProgress = false;
      _seekLoading = true;
      _stallSince = DateTime.now();
    });
    widget.onInteract();
    widget.speedTracker.setLoading(true);
    widget.speedTracker.resetMetrics();
    widget.speedTracker.tick(
      widget.controller.value.buffered,
      isBuffering: true,
    );
    // 拖到哪松手就播；部分机型 seek 后会停住，多次补 play
    unawaited(_resumeAfterSeek());
    _notifyLoading(true);
    _stallTimer?.cancel();
    _stallTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final v = widget.controller.value;
      if (!v.isPlaying || v.isBuffering) {
        setState(() => _showBufferSpinner = true);
        _notifyLoading(true);
        unawaited(_resumeAfterSeek());
      } else {
        setState(() {
          _seekLoading = false;
          _showBufferSpinner = false;
        });
        widget.speedTracker.setLoading(false);
        _notifyLoading(false);
      }
    });
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
    return MangoPlayerChrome(
      playing: c.value.isPlaying,
      position: c.value.position,
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
        c.seekTo(d);
        widget.onInteract();
      },
      onSeekStart: _onSeekStart,
      onSeekEnd: () {
        _onSeekEnd();
      },
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
      onAspect: widget.onAspect,
      onSpeed: widget.onSpeed,
      aspectLabel: widget.aspectLabel,
      speedLabel: widget.speedLabel,
      denseLandscape: widget.denseLandscape,
    );
  }
}

