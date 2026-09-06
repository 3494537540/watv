import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'vod_playback.dart';

/// 边播预热：只做 CDN/连接预热，**不**充当播放器磁盘缓存。
///
/// 播放器（Exo）读不到这里的数据；因此默认应关闭。开启时：
/// - 播放中轻量预热前方分片（可随时 abort，避免抢带宽）
/// - 拖动进度时优先预热**目标点**附近分片，缩短冷启动
class StreamAheadCache {
  StreamAheadCache._();
  static final instance = StreamAheadCache._();

  http.Client? _client;
  Timer? _timer;
  String? _activeUrl;
  int _warmCount = 0;
  int _approxPosMs = 0;
  final Set<String> _warmed = {};
  bool _busy = false;
  bool _paused = false;
  int _gen = 0;

  void setPaused(bool paused) {
    _paused = paused;
    if (paused) {
      abortInFlight();
    }
  }

  /// 打断进行中的预热（拖进度/卡顿时立刻让出带宽）
  void abortInFlight() {
    _gen++;
    _busy = false;
    final c = _client;
    _client = null;
    try {
      c?.close();
    } catch (_) {}
  }

  void start({
    required String playUrl,
    required int warmSegmentCount,
    int positionMs = 0,
  }) {
    final url = playUrl.trim();
    if (url.isEmpty || warmSegmentCount <= 0) {
      stop();
      return;
    }
    if (VodPlayback.isLocalMediaPath(url)) {
      stop();
      return;
    }
    _activeUrl = url;
    _warmCount = warmSegmentCount.clamp(0, 6);
    _approxPosMs = positionMs.clamp(0, 1 << 30);
    // 播放中不周期抢带宽（易造成解码掉帧）；仅登记 URL，供拖动预热
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  void updatePosition(int positionMs) {
    _approxPosMs = positionMs.clamp(0, 1 << 30);
  }

  /// 拖动落点：预热目标时间附近分片（与 seek 并行，不阻塞）
  Future<void> warmSeekTarget(int positionMs, {int count = 2}) async {
    final url = _activeUrl;
    if (url == null || url.isEmpty) return;
    final gen = ++_gen;
    _paused = false;
    _approxPosMs = positionMs.clamp(0, 1 << 30);
    try {
      await _warmAt(url, _approxPosMs, count.clamp(1, 3), gen, fullSegment: true);
    } catch (_) {}
  }

  void stop() {
    abortInFlight();
    _timer?.cancel();
    _timer = null;
    _activeUrl = null;
    _warmCount = 0;
    _warmed.clear();
    _paused = false;
  }

  Future<void> _tick() async {
    if (_busy || _paused) return;
    final url = _activeUrl;
    final n = _warmCount;
    if (url == null || n <= 0) return;
    final gen = _gen;
    _busy = true;
    try {
      await _warmAt(url, _approxPosMs, n, gen, fullSegment: false);
    } catch (_) {
    } finally {
      if (gen == _gen) _busy = false;
    }
  }

  Future<void> _warmAt(
    String url,
    int posMs,
    int count,
    int gen, {
    required bool fullSegment,
  }) async {
    final lower = url.toLowerCase();
    if (!lower.contains('.m3u8') && !lower.contains('m3u8?')) {
      await _warmBytes(
        url,
        maxBytes: fullSegment ? 1024 * 1024 : 256 * 1024,
        gen: gen,
      );
      return;
    }
    var body = await _getText(url, gen);
    if (body == null || gen != _gen || _paused) return;
    var playlistUrl = url;
    if (body.contains('#EXT-X-STREAM-INF')) {
      final variants = VodPlayback.parseMasterPlaylist(body, url);
      if (variants.isEmpty) return;
      // 取中档，避免总去暖最高码率抢带宽
      final mid = variants[variants.length ~/ 2];
      playlistUrl = mid.url;
      body = await _getText(playlistUrl, gen);
      if (body == null || gen != _gen || _paused) return;
    }
    await _warmPlaylistSegments(
      playlistUrl,
      body,
      count,
      posMs,
      gen,
      fullSegment: fullSegment,
    );
  }

  Future<void> _warmPlaylistSegments(
    String playlistUrl,
    String body,
    int count,
    int posMs,
    int gen, {
    required bool fullSegment,
  }) async {
    final segs = <String>[];
    var durAcc = 0.0;
    final targetSec = posMs / 1000.0;
    var started = false;
    final lines = const LineSplitter().convert(body);
    var pendingDur = 6.0;
    for (final raw in lines) {
      if (gen != _gen || _paused) return;
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF:')) {
        final numStr = line.substring(8).split(',').first.trim();
        pendingDur = double.tryParse(numStr) ?? 6;
        continue;
      }
      if (line.startsWith('#')) continue;
      final abs = _resolve(playlistUrl, line);
      if (!started) {
        if (durAcc + pendingDur >= targetSec) {
          started = true;
        } else {
          durAcc += pendingDur;
          continue;
        }
      }
      segs.add(abs);
      durAcc += pendingDur;
      if (segs.length >= count) break;
    }
    final maxBytes = fullSegment ? 1536 * 1024 : 320 * 1024;
    for (final s in segs) {
      if (gen != _gen || _paused) return;
      if (_warmed.contains(s)) continue;
      _warmed.add(s);
      await _warmBytes(s, maxBytes: maxBytes, gen: gen);
      if (_warmed.length > 48) {
        _warmed.remove(_warmed.first);
      }
    }
  }

  Future<void> _warmBytes(
    String url, {
    required int maxBytes,
    required int gen,
  }) async {
    if (gen != _gen || _paused) return;
    final client = _client ??= http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers.addAll({
        ...VodPlayback.httpHeaders,
        'Range': 'bytes=0-${maxBytes - 1}',
      });
      final res = await client.send(req).timeout(const Duration(seconds: 6));
      if (gen != _gen || _paused) {
        await res.stream.drain<void>();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 400) {
        await res.stream.drain<void>();
        return;
      }
      // 不落盘：只把流读掉做 CDN 预热，播放器仍走自己的通道
      var got = 0;
      await for (final chunk in res.stream) {
        if (gen != _gen || _paused) break;
        got += chunk.length;
        if (got >= maxBytes) break;
      }
    } catch (_) {
      // ignore
    }
  }

  Future<String?> _getText(String url, int gen) async {
    if (gen != _gen || _paused) return null;
    final client = _client ??= http.Client();
    try {
      final res = await client
          .get(Uri.parse(url), headers: VodPlayback.httpHeaders)
          .timeout(const Duration(seconds: 6));
      if (gen != _gen || _paused) return null;
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return res.body;
    } catch (_) {
      return null;
    }
  }

  static String _resolve(String base, String ref) {
    final t = ref.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return Uri.parse(base).resolve(t).toString();
  }
}
