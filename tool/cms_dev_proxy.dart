/// 本地 H5 跨域代理：把请求转到 MacCMS，并补 CORS。
///
/// 用法：
///   dart run tool/cms_dev_proxy.dart
/// 然后 Edge 调试 App（macCmsBase 在 Web 上默认指向本代理）。
library;

import 'dart:async';
import 'dart:io';

const _listenHost = '127.0.0.1';
const _listenPort = 8791;
const _upstream = 'https://154.12.29.28';

Future<void> main(List<String> args) async {
  final upstream = (args.isNotEmpty ? args.first : _upstream)
      .replaceAll(RegExp(r'/+$'), '');

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30);
  client.badCertificateCallback = (cert, host, port) => true;
  client.userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final server = await HttpServer.bind(_listenHost, _listenPort);
  stdout.writeln(
    'H5 CORS proxy  http://$_listenHost:$_listenPort  →  $upstream',
  );

  await for (final req in server) {
    unawaited(_handle(req, client, upstream));
  }
}

Future<void> _handle(
  HttpRequest req,
  HttpClient client,
  String upstream,
) async {
  void cors([int status = 204]) {
    req.response.statusCode = status;
    req.response.headers.set('Access-Control-Allow-Origin', '*');
    req.response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, PUT, DELETE, OPTIONS',
    );
    req.response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, X-Requested-With, Cookie, Accept',
    );
    req.response.headers.set('Access-Control-Max-Age', '86400');
  }

  try {
    if (req.method == 'OPTIONS') {
      cors(204);
      await req.response.close();
      return;
    }

    final path = req.uri.hasQuery
        ? '${req.uri.path}?${req.uri.query}'
        : req.uri.path;
    final target = Uri.parse('$upstream$path');

    final up = await client.openUrl(req.method, target);
    up.followRedirects = true;
    up.maxRedirects = 5;
    req.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'host' ||
          lower == 'origin' ||
          lower == 'referer' ||
          lower.startsWith('sec-')) {
        return;
      }
      for (final v in values) {
        up.headers.add(name, v);
      }
    });
    up.headers.set(HttpHeaders.acceptHeader, '*/*');

    if (req.method != 'GET' && req.method != 'HEAD') {
      await up.addStream(req);
    }

    final res = await up.close().timeout(const Duration(seconds: 25));
    final bytes = await res.fold<List<int>>(<int>[], (p, e) => p..addAll(e));

    cors(res.statusCode);
    final ct = res.headers.contentType;
    if (ct != null) {
      req.response.headers.contentType = ct;
    } else {
      req.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
    }
    req.response.headers.set('Cache-Control', 'no-store');
    req.response.contentLength = bytes.length;
    req.response.add(bytes);
    await req.response.close();

    stdout.writeln('${req.method} ${req.uri} → ${res.statusCode} ${bytes.length}B');
  } catch (e, st) {
    stderr.writeln('proxy error ${req.uri}: $e\n$st');
    try {
      cors(502);
      req.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.response.write('{"code":0,"msg":"proxy error"}');
      await req.response.close();
    } catch (_) {}
  }
}
