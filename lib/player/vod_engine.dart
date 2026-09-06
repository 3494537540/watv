import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'player_settings_store.dart';
import 'vod_playback.dart';

class VodBufferedRange {
  const VodBufferedRange(this.start, this.end);
  final Duration start;
  final Duration end;
}

class VodEngineValue {
  const VodEngineValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.hasError = false,
    this.errorDescription,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.size = Size.zero,
    this.buffered = const [],
  });

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool hasError;
  final String? errorDescription;
  final Duration position;
  final Duration duration;
  final Size size;
  final List<VodBufferedRange> buffered;

  double get aspectRatio {
    if (size.width > 0 && size.height > 0) {
      return size.width / size.height;
    }
    return 0;
  }

  VodEngineValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? hasError,
    String? errorDescription,
    bool clearError = false,
    Duration? position,
    Duration? duration,
    Size? size,
    List<VodBufferedRange>? buffered,
  }) {
    return VodEngineValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      hasError: clearError ? false : (hasError ?? this.hasError),
      errorDescription:
          clearError ? null : (errorDescription ?? this.errorDescription),
      position: position ?? this.position,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      buffered: buffered ?? this.buffered,
    );
  }
}

abstract class VodEngine extends ChangeNotifier {
  VodEngineValue get value;

  Future<void> open({
    required String url,
    Map<String, String> httpHeaders = const {},
    int backBufferMs = 90000,
    bool preferPlatformView = false,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setPlaybackSpeed(double rate);
  Future<void> setLooping(bool looping);

  /// media_kit 等用自身 BoxFit，勿外套 FittedBox（否则易黑屏）
  bool get prefersIntrinsicFit => false;

  Widget buildSurface({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  });

  /// iOS video_player 画中画用；其它内核为 null
  int? get nativePlayerId => null;

  /// 仅系统内核有
  VideoPlayerController? get rawVideoPlayer => null;

  Future<void> release();

  bool _released = false;

  Future<void> releaseSafe() async {
    if (_released) return;
    _released = true;
    await release();
  }

  @override
  void dispose() {
    if (!_released) {
      _released = true;
      unawaited(release());
    }
    super.dispose();
  }
}

VodEngine createVodEngine(PlayerKernel kernel) {
  // 仅保留系统 Exo / AVPlayer
  return VideoPlayerVodEngine();
}

class VideoPlayerVodEngine extends VodEngine {
  VideoPlayerController? _c;
  VodEngineValue _value = const VodEngineValue();
  Timer? _poll;

  @override
  VodEngineValue get value => _value;

  void _refreshValue({bool notifyOnError = false}) {
    final c = _c;
    if (c == null) {
      _value = const VodEngineValue();
      return;
    }
    final v = c.value;
    final next = VodEngineValue(
      isInitialized: v.isInitialized,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      hasError: v.hasError,
      errorDescription: v.errorDescription,
      position: v.position,
      duration: v.duration,
      size: v.size,
      buffered: [
        for (final r in v.buffered) VodBufferedRange(r.start, r.end),
      ],
    );
    final errEdge = notifyOnError && next.hasError && !_value.hasError;
    _value = next;
    if (errEdge) notifyListeners();
  }

  void _ensurePoll() {
    _poll?.cancel();
    // 最多 5Hz 刷新进度缓存，禁止每次 get value 都 new 对象（会 OOM/卡顿）
    _poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_c == null) return;
      _refreshValue();
    });
  }

  @override
  VideoPlayerController? get rawVideoPlayer => _c;

  @override
  int? get nativePlayerId {
    final c = _c;
    if (c == null || !c.value.isInitialized) return null;
    // ignore: invalid_use_of_visible_for_testing_member
    return c.playerId;
  }

  @override
  Future<void> open({
    required String url,
    Map<String, String> httpHeaders = const {},
    int backBufferMs = 90000,
    bool preferPlatformView = false,
  }) async {
    await _disposeInner();
    final opts = VideoPlayerOptions(
      mixWithOthers: false,
      // 对齐 git：90s
      backBufferDurationMs: 90000,
      allowBackgroundPlayback: true,
    );
    final viewType = preferPlatformView
        ? VideoViewType.platformView
        : VideoViewType.textureView;
    final lower = url.toLowerCase();
    final isHls = lower.contains('.m3u8') || lower.contains('m3u8?');
    final VideoPlayerController c;
    if (VodPlayback.isLocalMediaPath(url)) {
      var path = url;
      if (path.startsWith('file:')) {
        path = Uri.parse(path).toFilePath();
      }
      c = VideoPlayerController.file(
        File(path),
        videoPlayerOptions: opts,
        viewType: viewType,
      );
    } else {
      c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: httpHeaders.isEmpty ? VodPlayback.httpHeaders : httpHeaders,
        formatHint: isHls ? VideoFormat.hls : null,
        videoPlayerOptions: opts,
        viewType: viewType,
      );
    }
    _c = c;
    c.addListener(() {
      if (!c.value.hasError) return;
      _refreshValue(notifyOnError: true);
    });
    await c.initialize();
    _refreshValue();
    _ensurePoll();
    notifyListeners();
  }

  @override
  Future<void> play() async => _c?.play();

  @override
  Future<void> pause() async => _c?.pause();

  @override
  Future<void> seekTo(Duration position) async => _c?.seekTo(position);

  @override
  Future<void> setPlaybackSpeed(double rate) async =>
      _c?.setPlaybackSpeed(rate);

  @override
  Future<void> setLooping(bool looping) async => _c?.setLooping(looping);

  @override
  Widget buildSurface({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) {
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return VideoPlayer(c, key: key);
  }

  Future<void> _disposeInner() async {
    _poll?.cancel();
    _poll = null;
    final c = _c;
    _c = null;
    _value = const VodEngineValue();
    if (c != null) {
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<void> release() => _disposeInner();
}
