import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'vod_playback.dart';

/// 线路测速：真实拉一段媒体估吞吐量（不是 ping）。
///
/// 设计要点：
/// - 全局限流，避免同时狂测把 CDN 打挂（好线被测成「死」）
/// - URL 级短缓存，UI / 自动选线 / 侧栏共用，结果一致
/// - 速率按「首字节后传输」为主、轻微计入 TTFB，减少虚高/虚低
/// - JSON 套壳二次探测会降权，减轻「假绿」
abstract final class SourceLatency {
  SourceLatency._();

  static const _sampleBytes = 96 * 1024;
  static const _minMediaBytes = 8 * 1024;
  static const _budget = Duration(milliseconds: 7000);
  static const _cacheTtl = Duration(seconds: 120);
  static const _maxConcurrent = 2;

  static final Map<String, _CacheEntry> _cache = {};
  static int _inflight = 0;
  static final List<Completer<void>> _waiters = [];

  /// 清空缓存（换集 / 强制重测时）
  static void clearCache() => _cache.clear();

  /// 返回字节/秒；不可播或超时返回 null（UI 显示 —）
  static Future<int?> probe(
    String url, {
    Duration timeout = _budget,
    bool bypassCache = false,
  }) async {
    final u = url.trim();
    if (u.isEmpty) return null;
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }

    final key = u;
    if (!bypassCache) {
      final hit = _cache[key];
      if (hit != null && !hit.expired) return hit.bps;
    }

    return _withPermit(() async {
      if (!bypassCache) {
        final hit = _cache[key];
        if (hit != null && !hit.expired) return hit.bps;
      }
      final client = http.Client();
      try {
        final bps = await _probeUri(
          client,
          uri,
          budget: timeout,
          depth: 0,
          shellHops: 0,
          referer: VodPlayback.httpHeaders['Referer'] ??
              '${uri.scheme}://${uri.host}/',
        ).timeout(timeout);
        _cache[key] = _CacheEntry(bps, DateTime.now().add(_cacheTtl));
        return bps;
      } catch (_) {
        // 超时不缓存太久，避免好线被一次抖动永久判死
        _cache[key] = _CacheEntry(null, DateTime.now().add(
          const Duration(seconds: 12),
        ));
        return null;
      } finally {
        client.close();
      }
    });
  }

  /// 在 [budget] 内测速，返回速率最高的下标；全失败则回退 [fallback]。
  static Future<int> pickBestIndex(
    List<String> urls, {
    Duration budget = const Duration(milliseconds: 8000),
    int fallback = 0,
    int concurrency = 2,
  }) async {
    if (urls.isEmpty) return fallback;
    if (urls.length == 1) return 0;
    final scores = List<int?>.filled(urls.length, null);
    final deadline = DateTime.now().add(budget);

    Future<void> runPass({required bool onlyNulls}) async {
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= urls.length) return;
          if (onlyNulls && scores[i] != null) continue;
          final left = deadline.difference(DateTime.now());
          if (left.inMilliseconds < 400) return;
          final url = urls[i];
          if (url.trim().isEmpty) continue;
          final per = left < const Duration(milliseconds: 5500)
              ? left
              : const Duration(milliseconds: 5500);
          scores[i] = await probe(url, timeout: per);
        }
      }

      final n = concurrency.clamp(1, urls.length);
      await Future.wait([for (var w = 0; w < n; w++) worker()]);
    }

    await runPass(onlyNulls: false);
    // 第二轮只补测第一轮没出分的（超时/拥堵），避免「没测到」当「死线」
    if (deadline.difference(DateTime.now()).inMilliseconds > 800) {
      final missing = scores.where((e) => e == null).length;
      if (missing > 0) {
        await runPass(onlyNulls: true);
      }
    }

    var best = fallback.clamp(0, urls.length - 1);
    var bestBps = -1;
    for (var i = 0; i < scores.length; i++) {
      final bps = scores[i];
      if (bps != null && bps > bestBps) {
        bestBps = bps;
        best = i;
      }
    }
    return best;
  }

  static Future<T> _withPermit<T>(Future<T> Function() action) async {
    while (_inflight >= _maxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _inflight++;
    try {
      return await action();
    } finally {
      _inflight--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }

  static Future<int?> _probeUri(
    http.Client client,
    Uri uri, {
    required Duration budget,
    required int depth,
    required int shellHops,
    required String referer,
  }) async {
    if (depth > 3) return null;
    final deadline = DateTime.now().add(budget);
    Duration left() {
      final ms = deadline.difference(DateTime.now()).inMilliseconds;
      return Duration(milliseconds: math.max(500, ms));
    }

    final first = await _getBytes(
      client,
      uri,
      maxBytes: _sampleBytes,
      timeout: left(),
      referer: referer,
      preferRange: false,
    );
    if (first == null || first.bytes.length < 16) return null;

    if (_isHtmlGarbage(first.bytes)) return null;

    final text = utf8.decode(first.bytes, allowMalformed: true);
    final hasExtM3u = text.contains('#EXTM3U');
    final pathSaysM3u8 = uri.path.toLowerCase().contains('.m3u8');

    // JSON / 文本接口：解出真实播放地址再测（云播常见）
    if (!hasExtM3u) {
      final nested = _extractPlayUrl(text);
      if (nested != null && nested != uri.toString()) {
        final nestedUri = Uri.tryParse(nested);
        if (nestedUri != null &&
            (nestedUri.isScheme('http') || nestedUri.isScheme('https')) &&
            left().inMilliseconds > 600) {
          final nestedBps = await _probeUri(
            client,
            nestedUri,
            budget: left(),
            depth: depth + 1,
            shellHops: shellHops + 1,
            referer: uri.toString(),
          );
          return _demoteShell(nestedBps, shellHops + 1);
        }
      }
    }

    // 声称 m3u8 但正文不是：若也不像媒体，判死；直链媒体仍可打分
    if (pathSaysM3u8 && !hasExtM3u) {
      final direct = _scoreDirectMedia(first, uri);
      return _demoteShell(direct, shellHops);
    }

    if (!hasExtM3u) {
      return _demoteShell(_scoreDirectMedia(first, uri), shellHops);
    }

    // —— HLS ——
    final keyMethod = _hlsKeyMethod(text);
    if (keyMethod != null &&
        keyMethod != 'NONE' &&
        keyMethod != 'AES-128') {
      return null;
    }
    if (keyMethod == 'AES-128') {
      final keyUri = _hlsKeyUri(text, uri);
      if (keyUri == null) return null;
      final keyOk = await _keyReachable(client, keyUri, left(), referer);
      if (!keyOk) return null;
    }
    final encrypted = keyMethod == 'AES-128';
    final playlistReferer = uri.toString();

    final variant = _bestVariantUri(text, uri);
    if (variant != null && left().inMilliseconds > 900) {
      final nested = await _probeUri(
        client,
        variant,
        budget: left(),
        depth: depth + 1,
        shellHops: shellHops,
        referer: playlistReferer,
      );
      if (nested != null) return _demoteShell(nested, shellHops);
    }

    final segs = _segmentUris(text, uri, limit: 3);
    if (segs.isEmpty) return null;

    var totalBytes = 0;
    var totalScoreMs = 0;
    var mediaOk = 0;
    for (final seg in segs) {
      if (left().inMilliseconds < 500) break;
      final need = _sampleBytes - totalBytes;
      if (need <= 0) break;
      final part = await _getBytes(
        client,
        seg,
        maxBytes: need.clamp(32 * 1024, _sampleBytes),
        timeout: left(),
        referer: playlistReferer,
        preferRange: !encrypted,
      );
      if (part == null || part.bytes.isEmpty) continue;
      if (_isHtmlGarbage(part.bytes)) continue;

      final nest = utf8.decode(
        part.bytes.take(math.min(part.bytes.length, 512)).toList(),
        allowMalformed: true,
      );
      if (nest.contains('#EXTM3U')) {
        final nested = await _probeUri(
          client,
          seg,
          budget: left(),
          depth: depth + 1,
          shellHops: shellHops,
          referer: playlistReferer,
        );
        if (nested != null) return _demoteShell(nested, shellHops);
        continue;
      }

      // 宽松：非 HTML、够字节即可（避免严格魔数把可播 TS 判死）
      if (!encrypted) {
        final ok = _looksLikeAvMedia(part.bytes) ||
            _binaryMediaOk(part) ||
            (part.bytes.length >= 2048 && !_looksLikeText(part.bytes));
        if (!ok) continue;
      } else if (part.bytes.length < 256) {
        continue;
      }

      totalBytes += part.bytes.length;
      totalScoreMs += part.scoreMs;
      mediaOk++;
      // 尽量采满两片，速率更稳；时间不够有一片且够字节也行
      if (mediaOk >= 2 && totalBytes >= _minMediaBytes) break;
      if (mediaOk >= 1 &&
          totalBytes >= _minMediaBytes &&
          left().inMilliseconds < 900) {
        break;
      }
    }

    if (mediaOk == 0 || totalBytes < _minMediaBytes || totalScoreMs <= 0) {
      return null;
    }
    return _demoteShell(
      (totalBytes * 1000 / totalScoreMs).round(),
      shellHops,
    );
  }

  static int? _demoteShell(int? bps, int shellHops) {
    if (bps == null || bps <= 0) return bps;
    if (shellHops <= 0) return bps;
    // 每层套壳打七折，最高打到约 0.5
    var factor = 1.0;
    for (var i = 0; i < shellHops; i++) {
      factor *= 0.7;
    }
    factor = math.max(0.45, factor);
    return math.max(1, (bps * factor).round());
  }

  static int? _scoreDirectMedia(_Chunk first, Uri uri) {
    if (first.bytes.length < 512) return null;
    if (_looksLikeAvMedia(first.bytes)) return first.bps;
    if (_binaryMediaOk(first)) return first.bps;
    if (_pathLooksMedia(uri) && !_looksLikeText(first.bytes)) {
      return first.bps;
    }
    // 足够大的非文本响应：多数直链可播
    if (first.bytes.length >= 8192 && !_looksLikeText(first.bytes)) {
      return first.bps;
    }
    return null;
  }

  static bool _pathLooksMedia(Uri uri) {
    final p = uri.path.toLowerCase();
    const exts = [
      '.mp4',
      '.m4v',
      '.flv',
      '.mkv',
      '.webm',
      '.mov',
      '.ts',
      '.m2ts',
      '.avi',
      '.mp3',
      '.m4a',
      '.aac',
    ];
    for (final e in exts) {
      if (p.contains(e)) return true;
    }
    return false;
  }

  static bool _binaryMediaOk(_Chunk chunk) {
    final ct = chunk.contentType.toLowerCase();
    if (ct.startsWith('video/') ||
        ct.startsWith('audio/') ||
        ct.contains('mpegurl') ||
        ct.contains('mp2t') ||
        ct.contains('octet-stream') ||
        ct.contains('flv') ||
        ct.contains('mp4')) {
      if (_looksLikeText(chunk.bytes)) return false;
      return chunk.bytes.length >= 1024;
    }
    if (chunk.bytes.length >= 4096 && _binaryRatio(chunk.bytes) >= 0.85) {
      return !_looksLikeText(chunk.bytes);
    }
    return false;
  }

  static double _binaryRatio(List<int> bytes) {
    if (bytes.isEmpty) return 0;
    var bin = 0;
    final n = math.min(bytes.length, 4096);
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      if (b == 9 || b == 10 || b == 13) continue;
      if (b < 32 || b == 127) {
        bin++;
      } else if (b > 127) {
        bin++;
      }
    }
    return bin / n;
  }

  static bool _looksLikeText(List<int> bytes) {
    final head = utf8
        .decode(
          bytes.take(math.min(bytes.length, 400)).toList(),
          allowMalformed: true,
        )
        .trimLeft();
    if (head.isEmpty) return false;
    final c = head.codeUnitAt(0);
    if (c == 0x7B || c == 0x5B || c == 0x3C) return true;
    var printable = 0;
    final n = math.min(bytes.length, 256);
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      if (b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127)) printable++;
    }
    return printable / n > 0.92;
  }

  static String? _extractPlayUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    if ((t.startsWith('http://') || t.startsWith('https://')) &&
        !t.contains('\n') &&
        t.length < 2000) {
      return t.split(RegExp(r'\s')).first.trim();
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(t);
    } catch (_) {
      final m = RegExp(
        r'https?://[^\s"<>]+?\.(?:m3u8|mp4|flv|mkv|webm|ts)[^\s"<>]*',
        caseSensitive: false,
      ).firstMatch(t);
      return m?.group(0);
    }

    String? fromMap(dynamic v) {
      if (v is! Map) return null;
      final map = Map<String, dynamic>.from(v);
      const keys = [
        'url',
        'play',
        'play_url',
        'playurl',
        'video',
        'video_url',
        'videourl',
        'src',
        'link',
        'm3u8',
        'mp4',
        'file',
        'path',
      ];
      for (final k in keys) {
        final val = map[k] ?? map[k.toUpperCase()];
        if (val is String && val.trim().startsWith('http')) {
          return val.trim();
        }
      }
      for (final nest in ['data', 'result', 'info', 'video']) {
        final inner = map[nest];
        final hit = fromMap(inner);
        if (hit != null) return hit;
        if (inner is List) {
          for (final e in inner) {
            final h = fromMap(e);
            if (h != null) return h;
          }
        }
      }
      return null;
    }

    if (decoded is Map) return fromMap(decoded);
    if (decoded is List) {
      for (final e in decoded) {
        final h = fromMap(e);
        if (h != null) return h;
      }
    }
    return null;
  }

  static bool _isHtmlGarbage(List<int> bytes) {
    if (bytes.isEmpty) return true;
    final head = utf8
        .decode(
          bytes.take(math.min(bytes.length, 800)).toList(),
          allowMalformed: true,
        )
        .trimLeft()
        .toLowerCase();
    if (head.startsWith('<!doctype') ||
        head.startsWith('<html') ||
        head.startsWith('<head') ||
        head.contains('<html')) {
      return true;
    }
    if (head.startsWith('error') ||
        head.startsWith('denied') ||
        head.startsWith('forbidden') ||
        head.startsWith('404') ||
        head.startsWith('403')) {
      return true;
    }
    return false;
  }

  static bool _looksLikeAvMedia(List<int> bytes) {
    if (bytes.length < 8) return false;
    final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    if (b.length >= 188 && b[0] == 0x47) return true;
    for (var i = 0; i + 188 <= math.min(b.length, 188 * 4); i += 188) {
      if (b[i] == 0x47) return true;
    }
    final scan = math.min(b.length - 1, 512);
    for (var i = 0; i < scan; i++) {
      if (b[i] == 0x47 && i + 188 < b.length && b[i + 188] == 0x47) {
        return true;
      }
    }

    for (var i = 0; i + 8 <= math.min(b.length, 64); i++) {
      if (b[i + 4] == 0x66 &&
          b[i + 5] == 0x74 &&
          b[i + 6] == 0x79 &&
          b[i + 7] == 0x70) {
        return true;
      }
    }

    if (b[0] == 0x1A && b[1] == 0x45 && b[2] == 0xDF && b[3] == 0xA3) {
      return true;
    }
    if (b[0] == 0x46 && b[1] == 0x4C && b[2] == 0x56) return true;
    return false;
  }

  static String? _hlsKeyMethod(String playlist) {
    final m = RegExp(
      r'#EXT-X-KEY:[^\n]*METHOD=([A-Za-z0-9\-]+)',
      caseSensitive: false,
    ).firstMatch(playlist);
    return m?.group(1)?.toUpperCase();
  }

  static Uri? _hlsKeyUri(String playlist, Uri base) {
    final m = RegExp(
      r'#EXT-X-KEY:[^\n]*URI="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(playlist);
    final raw = m?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return _resolve(base, raw);
  }

  static Future<bool> _keyReachable(
    http.Client client,
    Uri keyUri,
    Duration timeout,
    String referer,
  ) async {
    final hit = await _getBytes(
      client,
      keyUri,
      maxBytes: 64,
      timeout: timeout,
      referer: referer,
      preferRange: false,
    );
    return hit != null &&
        hit.bytes.length >= 8 &&
        !_isHtmlGarbage(hit.bytes);
  }

  static Future<_Chunk?> _getBytes(
    http.Client client,
    Uri uri, {
    required int maxBytes,
    required Duration timeout,
    required String referer,
    required bool preferRange,
  }) async {
    final headerSets = <Map<String, String>>[
      {
        ...VodPlayback.httpHeaders,
        'Accept': '*/*',
        'Referer': referer,
      },
      {
        'User-Agent': VodPlayback.userAgent,
        'Accept': '*/*',
        'Referer': referer,
      },
      {
        'User-Agent': VodPlayback.userAgent,
        'Accept': '*/*',
      },
    ];

    final rangeModes = preferRange ? [true, false] : [false];

    for (final headers in headerSets) {
      for (final useRange in rangeModes) {
        final hit = await _getOnce(
          client,
          uri,
          maxBytes: maxBytes,
          timeout: timeout,
          headers: headers,
          useRange: useRange,
        );
        if (hit != null) return hit;
      }
    }
    return null;
  }

  static Future<_Chunk?> _getOnce(
    http.Client client,
    Uri uri, {
    required int maxBytes,
    required Duration timeout,
    required Map<String, String> headers,
    required bool useRange,
  }) async {
    try {
      final req = http.Request('GET', uri);
      req.headers.addAll(headers);
      if (useRange) {
        req.headers['Range'] = 'bytes=0-${maxBytes - 1}';
      }
      final wall = Stopwatch()..start();
      final streamed = await client.send(req).timeout(timeout);
      if (streamed.statusCode < 200 || streamed.statusCode >= 400) {
        return null;
      }
      final ctype = (streamed.headers['content-type'] ?? '').toLowerCase();
      final out = <int>[];
      var ttfbMs = 0;
      final transfer = Stopwatch();
      await for (final chunk in streamed.stream.timeout(timeout)) {
        if (!transfer.isRunning) {
          ttfbMs = math.max(1, wall.elapsedMilliseconds);
          transfer.start();
        }
        out.addAll(chunk);
        if (out.length >= maxBytes) break;
        if (wall.elapsed >= timeout) break;
      }
      wall.stop();
      if (transfer.isRunning) transfer.stop();
      if (out.length < 16) return null;
      if (ctype.contains('text/html') && _isHtmlGarbage(out)) return null;

      // 传输时间为主，TTFB 计 40%：既反映秒开，又不全被冷启动拖垮
      final transferMs = math.max(1, transfer.elapsedMilliseconds);
      final scoreMs = math.max(
        1,
        (ttfbMs * 0.4 + transferMs).round(),
      );
      return _Chunk(
        bytes: out,
        bps: (out.length * 1000 / scoreMs).round(),
        ms: wall.elapsedMilliseconds,
        scoreMs: scoreMs,
        contentType: ctype,
      );
    } catch (_) {
      return null;
    }
  }

  static Uri? _bestVariantUri(String playlist, Uri base) {
    if (!playlist.contains('#EXT-X-STREAM-INF')) return null;
    final lines = const LineSplitter().convert(playlist);
    final cands = <({Uri uri, int bw, int h})>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      if (i + 1 >= lines.length) break;
      final next = lines[i + 1].trim();
      if (next.isEmpty || next.startsWith('#')) continue;
      final resolved = _resolve(base, next);
      if (resolved == null) continue;
      final bw = _attrInt(line, 'BANDWIDTH') ?? 0;
      final res = _attr(line, 'RESOLUTION');
      var h = 0;
      if (res != null && res.contains('x')) {
        h = int.tryParse(res.split('x').last) ?? 0;
      }
      cands.add((uri: resolved, bw: bw, h: h));
    }
    if (cands.isEmpty) return null;
    // 贴近 480～720：测速接近真实起播档，避免专测最渣/最顶档
    cands.sort((a, b) {
      int dist(int h) {
        if (h <= 0) return 9000;
        if (h >= 480 && h <= 720) return (h - 540).abs();
        return (h - 540).abs() + 400;
      }

      final da = dist(a.h);
      final db = dist(b.h);
      if (da != db) return da.compareTo(db);
      return a.bw.compareTo(b.bw);
    });
    return cands.first.uri;
  }

  static List<Uri> _segmentUris(String playlist, Uri base, {int limit = 3}) {
    final out = <Uri>[];
    for (final raw in const LineSplitter().convert(playlist)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final resolved = _resolve(base, line);
      if (resolved == null) continue;
      out.add(resolved);
      if (out.length >= limit) break;
    }
    return out;
  }

  static Uri? _resolve(Uri base, String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final parsed = Uri.tryParse(t);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    try {
      return base.resolveUri(parsed);
    } catch (_) {
      return null;
    }
  }

  static String? _attr(String line, String key) {
    final m = RegExp('$key=([^,]+)').firstMatch(line);
    return m?.group(1)?.replaceAll('"', '');
  }

  static int? _attrInt(String line, String key) {
    return int.tryParse(_attr(line, key) ?? '');
  }

  static String label(int? bytesPerSec) {
    if (bytesPerSec == null || bytesPerSec <= 0) return '—';
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)}MB/s';
    }
    if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).round()}KB/s';
    }
    return '${bytesPerSec}B/s';
  }

  static ColorTone tone(int? bytesPerSec) {
    if (bytesPerSec == null || bytesPerSec <= 0) return ColorTone.bad;
    if (bytesPerSec >= 280 * 1024) return ColorTone.good;
    if (bytesPerSec >= 120 * 1024) return ColorTone.ok;
    if (bytesPerSec >= 40 * 1024) return ColorTone.warn;
    return ColorTone.bad;
  }
}

class _CacheEntry {
  _CacheEntry(this.bps, this.until);
  final int? bps;
  final DateTime until;
  bool get expired => DateTime.now().isAfter(until);
}

class _Chunk {
  const _Chunk({
    required this.bytes,
    required this.bps,
    required this.ms,
    required this.scoreMs,
    this.contentType = '',
  });
  final List<int> bytes;
  final int bps;
  final int ms;
  final int scoreMs;
  final String contentType;
}

enum ColorTone { good, ok, warn, bad }

extension ColorToneX on ColorTone {
  int get argb => switch (this) {
        ColorTone.good => 0xFF34C759,
        ColorTone.ok => 0xFF30D158,
        ColorTone.warn => 0xFFFF9F0A,
        ColorTone.bad => 0xFFFF3B30,
      };
}
