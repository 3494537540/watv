import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_settings_store.dart';
import 'vod_engine.dart';

/// media_kit / libmpv 全功能引擎：缓冲策略、硬软解、音轨/字幕/音量设备。
class MediaKitVodEngine extends VodEngine {
  MediaKitVodEngine(this.kernel);

  final PlayerKernel kernel;

  Player? _player;
  VideoController? _video;
  final List<StreamSubscription<dynamic>> _subs = [];
  VodEngineValue _value = const VodEngineValue();
  bool _looping = false;

  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  List<VideoTrack> _videoTracks = const [];
  List<AudioDevice> _audioDevices = const [];
  AudioTrack? _audio;
  SubtitleTrack? _subtitle;
  VideoTrack? _videoTrack;
  AudioDevice? _audioDevice;
  List<String> _subtitleText = const [];

  Player? get rawPlayer => _player;
  VideoController? get videoController => _video;

  List<AudioTrack> get audioTracks => List.unmodifiable(_audioTracks);
  List<SubtitleTrack> get subtitleTracks => List.unmodifiable(_subtitleTracks);
  List<VideoTrack> get videoTracks => List.unmodifiable(_videoTracks);
  List<AudioDevice> get audioDevices => List.unmodifiable(_audioDevices);
  AudioTrack? get currentAudio => _audio;
  SubtitleTrack? get currentSubtitle => _subtitle;
  VideoTrack? get currentVideoTrack => _videoTrack;
  AudioDevice? get currentAudioDevice => _audioDevice;
  List<String> get subtitleLines => List.unmodifiable(_subtitleText);

  @override
  VodEngineValue get value => _value;

  @override
  bool get prefersIntrinsicFit => true;

  int get _bufferBytes {
    // ali / smooth 更大缓冲；ijk 中等；mpv 默认
    return switch (kernel) {
      PlayerKernel.ali => 64 * 1024 * 1024,
      PlayerKernel.ijk => 32 * 1024 * 1024,
      PlayerKernel.mpv => 24 * 1024 * 1024,
      PlayerKernel.exo => 24 * 1024 * 1024,
    };
  }

  Future<void> _applyBufferProps(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      // 严禁在此设置 vid/vo/hwdec：必须交给 VideoController，否则 Android 有声无画。
      await platform.setProperty('keep-open', 'yes');
      await platform.setProperty('force-seekable', 'yes');
      await platform.setProperty('hr-seek', 'absolute');
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('demuxer-max-bytes', '$_bufferBytes');
      await platform.setProperty(
        'demuxer-max-back-bytes',
        '${(_bufferBytes / 4).round()}',
      );
      if (kernel == PlayerKernel.ali) {
        await platform.setProperty('demuxer-readahead-secs', '20');
        await platform.setProperty('cache-secs', '25');
      } else if (kernel == PlayerKernel.ijk) {
        await platform.setProperty('demuxer-readahead-secs', '8');
        await platform.setProperty('cache-secs', '12');
        await platform.setProperty('vd-lavc-threads', '0');
        await platform.setProperty('ad-lavc-threads', '0');
      } else {
        await platform.setProperty('demuxer-readahead-secs', '8');
        await platform.setProperty('cache-secs', '12');
      }
    } catch (e) {
      debugPrint('[media_kit] setProperty skip: $e');
    }
  }

  /// 模拟器 EGL 常挂：走 mediacodec_embed；真机用默认 gpu + 合适 hwdec。
  Future<VideoControllerConfiguration> _videoControllerConfig() async {
    var hwdec = kernel == PlayerKernel.ijk ? 'no' : 'auto-safe';
    String? vo;
    var androidAttachAfterParams = true;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        const ch = MethodChannel('com.alexmercerind/media_kit_video');
        final isEmu = await ch.invokeMethod<bool>('Utils.IsEmulator') ?? false;
        if (isEmu) {
          // issue #1343：模拟器 gpu/EGL 黑屏，改 Surface 直出
          vo = 'mediacodec_embed';
          hwdec = 'mediacodec';
          androidAttachAfterParams = false;
          debugPrint('[media_kit] emulator → vo=mediacodec_embed');
        }
      } catch (e) {
        debugPrint('[media_kit] IsEmulator check: $e');
      }
    }
    return VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      vo: vo,
      hwdec: hwdec,
      androidAttachSurfaceAfterVideoParameters: androidAttachAfterParams,
    );
  }

  void _bindStreams(Player player) {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    // 进度/缓冲/字幕高频更新：只写 _value，不 notify（播控用定时器读）。
    // 否则主线程被刷爆 → 播一会卡死无响应。
    _subs
      ..clear()
      ..addAll([
        player.stream.playing.listen((playing) {
          var next = _value.copyWith(isPlaying: playing);
          if (playing) next = next.copyWith(clearError: true);
          _value = next;
          notifyListeners();
        }),
        player.stream.buffering.listen((buf) {
          _value = _value.copyWith(isBuffering: buf);
          notifyListeners();
        }),
        player.stream.position.listen((pos) {
          var next = _value.copyWith(position: pos);
          // 已有有效进度：清掉瞬时 error，避免 hasError 粘住反复触发切线
          if (_value.hasError &&
              (pos > const Duration(milliseconds: 800) ||
                  _value.isPlaying)) {
            next = next.copyWith(clearError: true);
            _value = next;
            notifyListeners();
            return;
          }
          _value = next;
        }),
        player.stream.duration.listen((dur) {
          _value = _value.copyWith(duration: dur);
          notifyListeners();
        }),
        player.stream.width.listen((w) {
          final h = player.state.height;
          if (w != null && w > 0 && h != null && h > 0) {
            _value = _value.copyWith(size: Size(w.toDouble(), h.toDouble()));
            notifyListeners();
          }
        }),
        player.stream.height.listen((h) {
          final w = player.state.width;
          if (w != null && w > 0 && h != null && h > 0) {
            _value = _value.copyWith(size: Size(w.toDouble(), h.toDouble()));
            notifyListeners();
          }
        }),
        player.stream.buffer.listen((buf) {
          final pos = player.state.position;
          _value = _value.copyWith(
            buffered: [
              VodBufferedRange(Duration.zero, buf),
              if (buf > pos) VodBufferedRange(pos, buf),
            ],
          );
        }),
        player.stream.error.listen((err) {
          final msg = err.trim();
          if (msg.isEmpty) return;
          // 已在正常播放时的软错误忽略，避免连环切线卡死
          if (_value.isPlaying &&
              _value.position > const Duration(seconds: 2)) {
            debugPrint('[media_kit] soft error ignored: $msg');
            return;
          }
          _value = _value.copyWith(hasError: true, errorDescription: msg);
          notifyListeners();
        }),
        player.stream.tracks.listen((tracks) {
          _videoTracks = tracks.video;
          _audioTracks = tracks.audio;
          _subtitleTracks = tracks.subtitle;
          notifyListeners();
        }),
        player.stream.track.listen((track) {
          _videoTrack = track.video;
          _audio = track.audio;
          _subtitle = track.subtitle;
          // 轨切换不刷整树
        }),
        player.stream.audioDevices.listen((devices) {
          _audioDevices = devices;
          notifyListeners();
        }),
        player.stream.audioDevice.listen((device) {
          _audioDevice = device;
        }),
        player.stream.subtitle.listen((lines) {
          _subtitleText = lines;
          // 字幕行极高频，不 notify
        }),
        player.stream.completed.listen((done) {
          if (!done) return;
          if (_looping) {
            unawaited(player.seek(Duration.zero).then((_) => player.play()));
          }
        }),
      ]);
  }

  @override
  Future<void> open({
    required String url,
    Map<String, String> httpHeaders = const {},
    int backBufferMs = 90000,
    bool preferPlatformView = false,
  }) async {
    await _disposeInner();
    final player = Player(
      configuration: PlayerConfiguration(
        bufferSize: _bufferBytes,
        title: '哇TV',
        ready: () {},
      ),
    );
    _player = player;

    // 官方顺序（issue #909）：Player + VideoController 创建后，必须先让
    // Video widget 进树，再 open。先 open 再挂 Video → Android 永久 vo=null（有声无画）。
    final mkCfg = await _videoControllerConfig();
    final video = VideoController(player, configuration: mkCfg);
    _video = video;
    _bindStreams(player);
    await _applyBufferProps(player);

    // 立刻标记可挂载，占位宽高让 Video 进树。
    _value = const VodEngineValue(
      isInitialized: true,
      isBuffering: true,
      size: Size(16, 9),
    );
    notifyListeners();

    // 等 1 帧挂上 Video，再等 platform 附着（默认仅等一帧后创建 AndroidVideoController）。
    // 禁止再轮询宽高/首帧，避免切线路 ANR；超时也继续 open。
    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {}
    try {
      await video.platform.future.timeout(const Duration(milliseconds: 450));
    } on TimeoutException {
      debugPrint('[media_kit] platform attach timeout');
    } catch (e) {
      debugPrint('[media_kit] platform attach: $e');
    }
    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {}

    final uri = url.trim();
    final isFile = !uri.contains('://') || uri.startsWith('file:');
    String playable;
    if (isFile) {
      var path = uri;
      if (path.startsWith('file:')) {
        path = Uri.parse(path).toFilePath();
      }
      playable = path;
    } else {
      playable = uri;
    }

    final headers = <String, String>{...httpHeaders};
    if (headers.isEmpty && !isFile) {
      headers.addAll({
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      });
    }

    try {
      await player
          .open(
            Media(
              playable,
              httpHeaders: headers.isEmpty ? const {} : headers,
            ),
            play: false,
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      debugPrint('[media_kit] player.open timeout');
      rethrow;
    }

    // 宽高由 _bindStreams(width/height) 异步更新；此处只同步轨信息
    final st = player.state;
    _audioTracks = st.tracks.audio;
    _subtitleTracks = st.tracks.subtitle;
    _videoTracks = st.tracks.video;
    _audioDevices = st.audioDevices;
    _audio = st.track.audio;
    _subtitle = st.track.subtitle;
    _videoTrack = st.track.video;
    _audioDevice = st.audioDevice;
    notifyListeners();
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  /// 返回是否已拿到 Texture id（Surface 已挂，vo 可切 gpu）。
  Future<bool> waitUntilTextureReady({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final v = _video;
    if (v == null) return false;

    bool ok() => v.id.value != null;

    if (ok()) return true;
    final done = Completer<void>();
    void check() {
      if (ok() && !done.isCompleted) done.complete();
    }

    v.id.addListener(check);
    check();
    try {
      await done.future.timeout(timeout);
    } catch (_) {
    } finally {
      v.id.removeListener(check);
    }
    final ready = ok();
    if (!ready) {
      debugPrint(
        '[media_kit] texture not ready id=${v.id.value} rect=${v.rect.value}',
      );
    }
    return ready;
  }

  @override
  Future<void> seekTo(Duration position) async {
    final p = _player;
    if (p == null) return;
    try {
      final platform = p.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(
          'force-seekable',
          'yes',
          waitForInitialization: false,
        );
        await platform.setProperty(
          'hr-seek',
          'absolute',
          waitForInitialization: false,
        );
      }
    } catch (_) {}
    // 不要在 seek 里 play：初始化阶段会绕过「先挂纹理」
    await p.seek(position);
  }

  @override
  Future<void> setPlaybackSpeed(double rate) async {
    await _player?.setRate(rate);
  }

  @override
  Future<void> setLooping(bool looping) async {
    _looping = looping;
    await _player?.setPlaylistMode(
      looping ? PlaylistMode.single : PlaylistMode.none,
    );
  }

  Future<void> setVolume(double volume) async {
    await _player?.setVolume((volume * 100).clamp(0, 100));
  }

  Future<void> selectAudioTrack(AudioTrack track) async {
    await _player?.setAudioTrack(track);
  }

  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    await _player?.setSubtitleTrack(track);
  }

  Future<void> selectVideoTrack(VideoTrack track) async {
    await _player?.setVideoTrack(track);
  }

  Future<void> selectAudioDevice(AudioDevice device) async {
    await _player?.setAudioDevice(device);
  }

  Future<void> selectAudioDeviceByName(String name) async {
    for (final d in _audioDevices) {
      if (d.name == name) {
        await selectAudioDevice(d);
        return;
      }
    }
  }

  List<({String id, String label, bool selected})> audioDeviceChoices() {
    return [
      for (final d in _audioDevices)
        (
          id: d.name,
          label: d.description.trim().isNotEmpty ? d.description : d.name,
          selected: _audioDevice?.name == d.name,
        ),
    ];
  }

  Future<Uint8List?> takeScreenshot() async {
    return _player?.screenshot(format: 'image/png');
  }

  Future<void> selectAudioTrackById(String id) async {
    for (final t in _audioTracks) {
      if (t.id == id) {
        await selectAudioTrack(t);
        return;
      }
    }
  }

  Future<void> selectSubtitleTrackById(String id) async {
    if (id == 'no') {
      await disableSubtitle();
      return;
    }
    if (id == 'auto') {
      await autoSubtitle();
      return;
    }
    for (final t in _subtitleTracks) {
      if (t.id == id) {
        await selectSubtitleTrack(t);
        return;
      }
    }
  }

  String _labelOf(String id, String? title, String? language) {
    final parts = <String>[
      if ((title ?? '').trim().isNotEmpty) title!.trim(),
      if ((language ?? '').trim().isNotEmpty) language!.trim(),
    ];
    if (parts.isEmpty) {
      if (id == 'auto') return '自动';
      if (id == 'no') return '关闭';
      return '轨道 $id';
    }
    return parts.join(' · ');
  }

  List<({String id, String label, bool selected})> audioTrackChoices() {
    return [
      for (final t in _audioTracks)
        (
          id: t.id,
          label: _labelOf(t.id, t.title, t.language),
          selected: _audio?.id == t.id,
        ),
    ];
  }

  List<({String id, String label, bool selected})> subtitleTrackChoices() {
    final seen = <String>{};
    final out = <({String id, String label, bool selected})>[];
    void add(String id, String label, bool selected) {
      if (!seen.add(id)) return;
      out.add((id: id, label: label, selected: selected));
    }

    add('auto', '自动', _subtitle?.id == 'auto');
    add('no', '关闭', _subtitle?.id == 'no');
    for (final t in _subtitleTracks) {
      if (t.id == 'auto' || t.id == 'no') continue;
      add(
        t.id,
        _labelOf(t.id, t.title, t.language),
        _subtitle?.id == t.id,
      );
    }
    return out;
  }

  Future<void> disableSubtitle() async {
    await _player?.setSubtitleTrack(SubtitleTrack.no());
  }

  Future<void> autoSubtitle() async {
    await _player?.setSubtitleTrack(SubtitleTrack.auto());
  }

  @override
  Widget buildSurface({
    Key? key,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) {
    final c = _video;
    if (c == null || !_value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return Video(
      key: key ?? ValueKey('mk-video-${kernel.name}'),
      controller: c,
      fit: fit,
      alignment: alignment,
      controls: NoVideoControls,
      fill: Colors.black,
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: true,
    );
  }

  Future<void> _disposeInner() async {
    for (final s in _subs) {
      try {
        await s.cancel();
      } catch (_) {}
    }
    _subs.clear();
    final p = _player;
    _player = null;
    _video = null;
    _value = const VodEngineValue();
    _audioTracks = const [];
    _subtitleTracks = const [];
    _videoTracks = const [];
    _audioDevices = const [];
    if (p != null) {
      try {
        // 切线路时旧 player dispose 偶发卡住，必须限时，否则 ANR。
        await p.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  @override
  Future<void> release() => _disposeInner();
}
