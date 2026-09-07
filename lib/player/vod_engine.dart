import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'player_settings_store.dart';
import 'media_kit_vod_engine.dart';
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

  bool get prefersIntrinsicFit => false;

  Widget buildSurface({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  });

  /// iOS video_player 画中画用
  int? get nativePlayerId => null;

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

VodEngine createVodEngine([PlayerKernel kernel = PlayerKernel.exo]) {
  if (kernel.isMediaKit && !kIsWeb) {
    return MediaKitVodEngine(kernel);
  }
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
        for (final r in v.buffered)
          VodBufferedRange(r.start, r.end),
      ],
    );
    final changed = next.isInitialized != _value.isInitialized ||
        next.isPlaying != _value.isPlaying ||
        next.isBuffering != _value.isBuffering ||
        next.hasError != _value.hasError ||
        next.position != _value.position ||
        next.duration != _value.duration ||
        next.size != _value.size;
    _value = next;
    if (changed || (notifyOnError && next.hasError)) {
      notifyListeners();
    }
  }

  void _ensurePoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _refreshValue();
    });
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
      mixWithOthers: true,
      allowBackgroundPlayback: false,
    );
    // 必须尊重 preferPlatformView：iOS 上 PlatformView 盖 Flutter 弹幕层会整屏发灰白。
    // 弹幕开启时应传 false → TextureView。
    final viewType = preferPlatformView
        ? VideoViewType.platformView
        : VideoViewType.textureView;
    final lower = url.toLowerCase();
    final isHls = lower.contains('.m3u8') || lower.contains('m3u8?');
    final loopback = VodPlayback.isLoopbackCacheUrl(url);
    final localFile = VodPlayback.isLocalMediaPath(url) && !loopback;

    late final VideoPlayerController c;
    if (loopback) {
      // iOS 缓存：本机 HTTP，空 headers，纯离线
      c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        formatHint: isHls ? VideoFormat.hls : null,
        videoPlayerOptions: opts,
        viewType: viewType,
      );
    } else if (localFile) {
      var path = url;
      if (path.startsWith('file:')) {
        path = Uri.parse(path).toFilePath();
      }
      if (isHls) {
        // Android 本地 m3u8
        c = VideoPlayerController.networkUrl(
          Uri.file(path),
          formatHint: VideoFormat.hls,
          videoPlayerOptions: opts,
          viewType: viewType,
        );
      } else {
        c = VideoPlayerController.file(
          File(path),
          videoPlayerOptions: opts,
          viewType: viewType,
        );
      }
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
    final timeoutSec = (loopback || localFile) ? 18 : 18;
    await c.initialize().timeout(Duration(seconds: timeoutSec));
    // 远程：initialize 完成后立即可 play，不再额外空等
    _refreshValue();
    _ensurePoll();
    notifyListeners();
    // 本地 HLS：再等时长（缓存校验）
    if (loopback || localFile) {
      for (var i = 0; i < 20; i++) {
        _refreshValue();
        final ms = _c?.value.duration.inMilliseconds ?? 0;
        if (ms > 0) break;
        if (_c?.value.hasError ?? false) break;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      final durMs = _c?.value.duration.inMilliseconds ?? 0;
      if (durMs <= 0 && !(_c?.value.hasError ?? false)) {
        throw StateError('缓存媒体时长无效，请重新下载该集');
      }
      _refreshValue();
      notifyListeners();
    }
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

  @override
  int? get nativePlayerId {
    final c = _c;
    if (c == null || !c.value.isInitialized) return null;
    // video_player 2.11+：textureId 改名为 playerId（标注 testing，运行时可用）
    // ignore: invalid_use_of_visible_for_testing_member
    final id = c.playerId;
    if (id < 0) return null;
    return id;
  }

  @override
  VideoPlayerController? get rawVideoPlayer => _c;

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
