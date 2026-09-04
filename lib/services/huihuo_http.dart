import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'app_security.dart';

/// 哇TV 面板 HTTP；证书/代理策略见 [AppSecurity]
Future<({int status, String body})> huihuoHttpGet(
  String url, {
  Duration timeout = const Duration(seconds: 12),
  Map<String, String>? headers,
}) async {
  if (kIsWeb) {
    throw UnsupportedError('huihuoHttpGet 不支持 Web');
  }
  final client = HttpClient()..connectionTimeout = timeout;
  AppSecurity.instance.hardenClient(client);
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
    );
    headers?.forEach(req.headers.set);
    final res = await req.close().timeout(timeout);
    final bytes = await res.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
    return (status: res.statusCode, body: utf8.decode(bytes));
  } finally {
    client.close(force: true);
  }
}

Future<({int status, String body})> huihuoHttpPostJson(
  String url,
  Map<String, dynamic> payload, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (kIsWeb) {
    throw UnsupportedError('huihuoHttpPostJson 不支持 Web');
  }
  final client = HttpClient()..connectionTimeout = timeout;
  AppSecurity.instance.hardenClient(client);
  try {
    final req = await client.postUrl(Uri.parse(url)).timeout(timeout);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.contentType = ContentType.json;
    req.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
    );
    final raw = utf8.encode(jsonEncode(payload));
    req.contentLength = raw.length;
    req.add(raw);
    final res = await req.close().timeout(timeout);
    final bytes = await res.fold<List<int>>(<int>[], (p, e) => p..addAll(e));
    return (status: res.statusCode, body: utf8.decode(bytes));
  } finally {
    client.close(force: true);
  }
}
