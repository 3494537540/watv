import 'dart:async';
import 'dart:io';

/// iOS 离线 HLS：AVPlayer 不认 file:// m3u8。
/// 把缓存目录挂到 127.0.0.1，用 http 相对路径播本地分片。
///
/// 必须带 Content-Length / Accept-Ranges / Range / HEAD，
/// 否则 iOS 会一直缓冲、时长一直为 0。
class LocalMediaServer {
  LocalMediaServer._();
  static final instance = LocalMediaServer._();

  HttpServer? _server;
  Directory? _root;
  int? _port;
  StreamSubscription<HttpRequest>? _sub;

  int? get port => _port;

  bool get isRunning => _server != null && _port != null;

  /// 返回可播 URL。非 m3u8 / 非 iOS 直接返回本地路径。
  Future<String> playableUrlFor(String rawPath) async {
    var path = rawPath.trim();
    if (path.startsWith('file:')) {
      path = Uri.parse(path).toFilePath();
    }
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('本地缓存文件不存在');
    }
    final lower = path.toLowerCase();
    final needServer = !Platform.isAndroid && lower.endsWith('.m3u8');
    // 双端都校验相对分片 + VOD 收尾；仅 iOS/桌面用本机 HTTP
    await hardenOfflinePlaylist(file);
    if (!needServer) {
      return path;
    }
    await startForDirectory(file.parent);
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'index.m3u8';
    return 'http://127.0.0.1:$_port/$name';
  }

  Future<void> startForDirectory(Directory dir) async {
    final root = Directory(dir.path);
    if (_server != null &&
        _root != null &&
        _root!.path == root.path &&
        _port != null) {
      return;
    }
    await stop();
    _root = root;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
    _sub = server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _root = null;
    _port = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final root = _root;
    if (root == null) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      await req.response.close();
      return;
    }
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
      }

      var rel = Uri.decodeComponent(req.uri.path);
      if (rel.startsWith('/')) rel = rel.substring(1);
      if (rel.isEmpty || rel.contains('..')) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }

      final rootPath = root.path.endsWith(Platform.pathSeparator)
          ? root.path.substring(0, root.path.length - 1)
          : root.path;
      final target = File('$rootPath${Platform.pathSeparator}$rel');
      final targetPath = target.absolute.path;
      final rootAbs = Directory(rootPath).absolute.path;
      final sep = Platform.pathSeparator;
      final within =
          targetPath == rootAbs || targetPath.startsWith('$rootAbs$sep');
      if (!within) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      if (!await target.exists()) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final name = targetPath.toLowerCase();
      if (name.endsWith('.m3u8')) {
        req.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
      } else if (name.endsWith('.ts') || name.endsWith('.m4s')) {
        req.response.headers.contentType = ContentType('video', 'MP2T');
      } else if (name.endsWith('.mp4') || name.endsWith('.m4a')) {
        req.response.headers.contentType = ContentType('video', 'mp4');
      } else if (name.endsWith('.key')) {
        req.response.headers.contentType =
            ContentType('application', 'octet-stream');
      } else {
        req.response.headers.contentType =
            ContentType('application', 'octet-stream');
      }
      req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set('Access-Control-Allow-Origin', '*');

      final length = await target.length();
      var start = 0;
      var end = length > 0 ? length - 1 : 0;
      var partial = false;

      final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && length > 0) {
        final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader.trim());
        if (m != null) {
          final s = m.group(1) ?? '';
          final e = m.group(2) ?? '';
          if (s.isNotEmpty) {
            start = int.tryParse(s) ?? 0;
          } else if (e.isNotEmpty) {
            final suffix = int.tryParse(e) ?? 0;
            start = (length - suffix).clamp(0, length - 1);
            end = length - 1;
          }
          if (e.isNotEmpty && s.isNotEmpty) {
            end = int.tryParse(e) ?? (length - 1);
          } else if (s.isNotEmpty) {
            end = length - 1;
          }
          if (start >= length || start > end) {
            req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            req.response.headers
                .set(HttpHeaders.contentRangeHeader, 'bytes */$length');
            await req.response.close();
            return;
          }
          end = end.clamp(0, length - 1);
          partial = true;
        }
      }

      final contentLen = length == 0 ? 0 : (end - start + 1);
      if (partial) {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$length',
        );
      } else {
        req.response.statusCode = HttpStatus.ok;
      }
      req.response.contentLength = contentLen;

      if (req.method == 'HEAD' || contentLen == 0) {
        await req.response.close();
        return;
      }

      await req.response.addStream(target.openRead(start, end + 1));
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// 相对分片 + 强制 VOD 收尾（无 ENDLIST 时 iOS 时长恒为 0、一直缓冲）
  Future<void> hardenOfflinePlaylist(File playlist) async {
    String body;
    try {
      body = await playlist.readAsString();
    } catch (_) {
      return;
    }
    final dir = playlist.parent;
    final out = StringBuffer();
    var changed = false;
    var hasEndList = false;
    var hasPlaylistType = false;
    var segCount = 0;

    for (final raw in body.split('\n')) {
      final trimmed = raw.trim();
      final upper = trimmed.toUpperCase();
      if (upper.startsWith('#EXT-X-ENDLIST')) {
        hasEndList = true;
        out.writeln(raw);
        continue;
      }
      if (upper.startsWith('#EXT-X-PLAYLIST-TYPE:')) {
        hasPlaylistType = true;
        if (upper.contains('VOD')) {
          out.writeln(raw);
        } else {
          changed = true;
          out.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
        }
        continue;
      }
      if (upper.startsWith('#EXT-X-KEY:') || upper.startsWith('#EXT-X-MAP:')) {
        final m =
            RegExp(r'URI="([^"]+)"', caseSensitive: false).firstMatch(trimmed);
        final uri = m?.group(1)?.trim() ?? '';
        if (uri.isEmpty) {
          out.writeln(raw);
          continue;
        }
        String localName;
        if (uri.startsWith('http://') || uri.startsWith('https://')) {
          throw StateError('缓存密钥未下载完成，请重新下载');
        } else if (uri.startsWith('file:')) {
          localName =
              Uri.parse(uri).toFilePath().split(Platform.pathSeparator).last;
        } else {
          localName = uri.split('/').last.split('\\').last;
        }
        final f = File('${dir.path}${Platform.pathSeparator}$localName');
        if (!await f.exists() || await f.length() == 0) {
          throw StateError('缓存密钥/初始化段缺失，请重新下载');
        }
        final next = trimmed.replaceFirstMapped(
          RegExp(r'URI="[^"]+"', caseSensitive: false),
          (_) => 'URI="$localName"',
        );
        if (next != trimmed) changed = true;
        out.writeln(next);
      } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
          throw StateError('缓存不完整（分片仍指向网络），请重新下载');
        }
        final localName = trimmed.startsWith('file:')
            ? Uri.parse(trimmed).toFilePath().split(Platform.pathSeparator).last
            : trimmed.split('/').last.split('\\').last;
        final seg = File('${dir.path}${Platform.pathSeparator}$localName');
        if (!await seg.exists() || await seg.length() == 0) {
          throw StateError('缓存不完整（缺少分片），请重新下载');
        }
        segCount++;
        if (localName != trimmed) changed = true;
        out.writeln(localName);
      } else {
        out.writeln(raw);
      }
    }

    if (segCount == 0) {
      throw StateError('缓存播放列表无效，请重新下载');
    }

    var text = out.toString();
    if (!hasPlaylistType) {
      text = _insertAfterM3uHeader(text, '#EXT-X-PLAYLIST-TYPE:VOD');
      changed = true;
    }
    if (!hasEndList) {
      if (!text.endsWith('\n')) text = '$text\n';
      text = '$text#EXT-X-ENDLIST\n';
      changed = true;
    }
    if (changed) {
      await playlist.writeAsString(text);
    }
  }

  static String _insertAfterM3uHeader(String body, String tag) {
    final lines = body.split('\n');
    final out = <String>[];
    var inserted = false;
    for (var i = 0; i < lines.length; i++) {
      out.add(lines[i]);
      if (!inserted && lines[i].trim().toUpperCase().startsWith('#EXTM3U')) {
        out.add(tag);
        inserted = true;
      }
    }
    if (!inserted) {
      out.insert(0, tag);
      out.insert(0, '#EXTM3U');
    }
    return out.join('\n');
  }
}
