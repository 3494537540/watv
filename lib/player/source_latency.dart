import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'vod_playback.dart';

/// 线路测速：对齐播放器请求；拉到分片就报真实速率。
/// 清单能通但分片被拦时，仍用已下载字节估速，避免「能播却红点」。
abstract final class SourceLatency {
  SourceLatency._();

  static const _sampleBytes = 64 * 1024;
  static const _minBytes = 4 * 1024;
  static const _budget = Duration(milliseconds: 6500);

  /// 返回字节/秒；彻底不可达才返回 null（UI 显示 —）
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
        referer: '${uri.scheme}://${uri.host}/',
      ).timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<int?> _probeUri(
    http.Client client,
    Uri uri, {
    required Duration budget,
    required int depth,
    required String referer,
  }) async {
    if (depth > 2) return null;
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

    final text = utf8.decode(first.bytes, allowMalformed: true);
    final looksM3u8 = text.contains('#EXTM3U') ||
        uri.path.toLowerCase().contains('.m3u8');

    // 直链 mp4/ts：有数据就报速
    if (!looksM3u8) {
      if (first.bytes.length < 512) return null;
      return first.bps;
    }

    final playlistReferer = uri.toString();

    // master → 选一条清晰度再测
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

    final segs = _segmentUris(text, uri, limit: 3);
    if (segs.isEmpty) {
      // 只有清单、没有分片行：按清单下载速度给下限（能打开清单≈能播）
      return math.max(48 * 1024, first.bps);
    }

    var totalBytes = 0;
    var totalMs = 0;
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
        preferRange: true,
      );
      if (part == null || part.bytes.isEmpty) continue;

      // 分片地址其实是嵌套 m3u8
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

      totalBytes += part.bytes.length;
      totalMs += part.ms;
      if (totalBytes >= _minBytes) break;
    }

    if (totalBytes >= 512 && totalMs > 0) {
      return (totalBytes * 1000 / totalMs).round();
    }

    // 清单通了、分片被拦/超时：仍给保守速率，不要红「—」
    // （播放器能播 m3u8 的场景很常见）
    return math.max(64 * 1024, first.bps.clamp(32 * 1024, 400 * 1024));
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

    // 分片：先 Range 再整段；清单：不要 Range
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
      final sw = Stopwatch()..start();
      final out = <int>[];
      await for (final chunk in streamed.stream.timeout(timeout)) {
        out.addAll(chunk);
        if (out.length >= maxBytes) break;
        if (sw.elapsed >= timeout) break;
      }
      sw.stop();
      if (out.length < 16) return null;
      final ms = math.max(1, sw.elapsedMilliseconds);
      return _Chunk(bytes: out, bps: (out.length * 1000 / ms).round(), ms: ms);
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
    // 优先中等清晰度，测速更快更稳
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

  /// 只显示速率；彻底失败才 —
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
  const _Chunk({required this.bytes, required this.bps, required this.ms});
  final List<int> bytes;
  final int bps;
  final int ms;
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
