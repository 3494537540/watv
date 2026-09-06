import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'vod_playback.dart';

/// 线路测速：m3u8 / mp4 / flv / mkv 等直链都能测；
/// 仅拒绝 HTML 假页；JSON 套壳会解出真实地址再测。
abstract final class SourceLatency {
  SourceLatency._();

  static const _sampleBytes = 64 * 1024;
  static const _minMediaBytes = 2 * 1024;
  static const _budget = Duration(milliseconds: 6500);

  /// 返回字节/秒；不可播返回 null（UI 显示 —）
  static Future<int?> probe(
    String url, {
    Duration timeout = _budget,
  }) async {
    final u = url.trim();
    if (u.isEmpty) return null;
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }

    final client = http.Client();
    try {
      return await _probeUri(
        client,
        uri,
        budget: timeout,
        depth: 0,
        referer: VodPlayback.httpHeaders['Referer'] ??
            '${uri.scheme}://${uri.host}/',
      ).timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// 在 [budget] 内测速，返回速率最高的下标；全失败则回退 [fallback]。
  static Future<int> pickBestIndex(
    List<String> urls, {
    Duration budget = const Duration(milliseconds: 2200),
    int fallback = 0,
    int concurrency = 3,
  }) async {
    if (urls.isEmpty) return fallback;
    if (urls.length == 1) return 0;
    final scores = List<int?>.filled(urls.length, null);
    var next = 0;
    final deadline = DateTime.now().add(budget);

    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= urls.length) return;
        final left = deadline.difference(DateTime.now());
        if (left.inMilliseconds < 200) return;
        final url = urls[i];
        final per = left < const Duration(milliseconds: 1600)
            ? left
            : const Duration(milliseconds: 1600);
        scores[i] = await probe(url, timeout: per);
      }
    }

    await Future.wait([
      for (var w = 0; w < concurrency.clamp(1, urls.length); w++) worker(),
    ]).timeout(budget, onTimeout: () => const []);

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

  static Future<int?> _probeUri(
    http.Client client,
    Uri uri, {
    required Duration budget,
    required int depth,
    required String referer,
  }) async {
    if (depth > 3) return null;
    final deadline = DateTime.now().add(budget);
    Duration left() {
      final ms = deadline.difference(DateTime.now()).inMilliseconds;
      return Duration(milliseconds: math.max(400, ms));
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

    // HTML 播放页 / 报错页：假高速
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
            left().inMilliseconds > 500) {
          return _probeUri(
            client,
            nestedUri,
            budget: left(),
            depth: depth + 1,
            referer: uri.toString(),
          );
        }
      }
    }

    // 声称是 m3u8，正文却不是 → 不可播
    if (pathSaysM3u8 && !hasExtM3u) return null;

    // 非 HLS：mp4 / flv / mkv / webm / ts 直链
    if (!hasExtM3u) {
      return _scoreDirectMedia(first, uri);
    }

    // —— 以下 HLS ——
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
    if (variant != null && left().inMilliseconds > 800) {
      final nested = await _probeUri(
        client,
        variant,
        budget: left(),
        depth: depth + 1,
        referer: playlistReferer,
      );
      if (nested != null) return nested;
    }

    final segs = _segmentUris(text, uri, limit: 4);
    if (segs.isEmpty) return null;

    var totalBytes = 0;
    var totalMs = 0;
    var mediaOk = 0;
    for (final seg in segs) {
      if (left().inMilliseconds < 500) break;
      final need = _sampleBytes - totalBytes;
      if (need <= 0) break;
      final part = await _getBytes(
        client,
        seg,
        maxBytes: need.clamp(24 * 1024, _sampleBytes),
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
          referer: playlistReferer,
        );
        if (nested != null) return nested;
        continue;
      }

      if (!encrypted &&
          !_looksLikeAvMedia(part.bytes) &&
          !_binaryMediaOk(part)) {
        continue;
      }
      if (encrypted && part.bytes.length < 256) continue;

      totalBytes += part.bytes.length;
      totalMs += part.ms;
      mediaOk++;
      if (totalBytes >= _minMediaBytes && mediaOk >= 1) break;
    }

    if (mediaOk == 0 || totalBytes < _minMediaBytes || totalMs <= 0) {
      return null;
    }
    return (totalBytes * 1000 / totalMs).round();
  }

  /// mp4/flv/mkv/webm/ts 等直链打分
  static int? _scoreDirectMedia(_Chunk first, Uri uri) {
    if (first.bytes.length < 512) return null;
    if (_looksLikeAvMedia(first.bytes)) return first.bps;
    if (_binaryMediaOk(first)) return first.bps;
    // 路径像媒体、内容不是 HTML/JSON：宽松通过（部分 CDN 前缀非标准）
    if (_pathLooksMedia(uri) && !_looksLikeText(first.bytes)) {
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

  /// Content-Type 为 video/audio，或二进制占比高（非文本伪装）
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
    if (c == 0x7B || c == 0x5B || c == 0x3C) return true; // { [ <
    var printable = 0;
    final n = math.min(bytes.length, 256);
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      if (b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127)) printable++;
    }
    return printable / n > 0.92;
  }

  /// 从 JSON / 简单文本里抠出可播 URL
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

  /// MPEG-TS / MP4 / WebM / FLV / Matroska 特征
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
      final streamed = await client.send(req).timeout(timeout);
      if (streamed.statusCode < 200 || streamed.statusCode >= 400) {
        return null;
      }
      final ctype = (streamed.headers['content-type'] ?? '').toLowerCase();
      final sw = Stopwatch()..start();
      final out = <int>[];
      await for (final chunk in streamed.stream.timeout(timeout)) {
        out.addAll(chunk);
        if (out.length >= maxBytes) break;
        if (sw.elapsed >= timeout) break;
      }
      sw.stop();
      if (out.length < 16) return null;
      if (ctype.contains('text/html') && _isHtmlGarbage(out)) return null;
      final ms = math.max(1, sw.elapsedMilliseconds);
      return _Chunk(
        bytes: out,
        bps: (out.length * 1000 / ms).round(),
        ms: ms,
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
    cands.sort((a, b) {
      final da = (a.h > 0 ? (a.h - 480).abs() : 9999);
      final db = (b.h > 0 ? (b.h - 480).abs() : 9999);
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
    return ColorTone.warn;
  }
}

class _Chunk {
  const _Chunk({
    required this.bytes,
    required this.bps,
    required this.ms,
    this.contentType = '',
  });
  final List<int> bytes;
  final int bps;
  final int ms;
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
