import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 局域网 DLNA/UPnP 媒体渲染器
class DlnaDevice {
  const DlnaDevice({
    required this.usn,
    required this.name,
    required this.location,
    required this.controlUrl,
    this.manufacturer = '',
    this.isDemo = false,
  });

  final String usn;
  final String name;
  final String location;
  final String controlUrl;
  final String manufacturer;
  /// 本地模拟设备：不走真实网络，用于体验投屏流程
  final bool isDemo;

  String get host {
    if (isDemo) return '模拟 · 本机';
    try {
      return Uri.parse(location).host;
    } catch (_) {
      return '';
    }
  }

  /// 演示用假电视（始终出现在列表里）
  static const demo = DlnaDevice(
    usn: 'uuid:watv-cast-demo-local',
    name: '哇TV 演示电视',
    location: 'http://127.0.0.1/watv-demo',
    controlUrl: 'http://127.0.0.1/watv-demo/AVTransport/control',
    manufacturer: '模拟设备',
    isDemo: true,
  );
}

/// 纯 Dart DLNA：SSDP 发现 + AVTransport 推流
class DlnaCastService {
  DlnaCastService._();
  static final instance = DlnaCastService._();

  final Map<String, DlnaDevice> _devices = {};
  RawDatagramSocket? _socket;
  Timer? _searchTimer;
  bool _searching = false;

  List<DlnaDevice> get devices => _devices.values.toList(growable: false);
  bool get searching => _searching;

  /// 扫描局域网设备（默认约 4 秒）
  Future<List<DlnaDevice>> search({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _devices.clear();
    _searching = true;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastHops = 4;
      _socket = socket;

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        final text = utf8.decode(dg.data, allowMalformed: true);
        unawaited(_handleSsdp(text));
      });

      _sendMSearch(socket);
      _searchTimer?.cancel();
      _searchTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        if (_socket != null) _sendMSearch(_socket!);
      });

      await Future<void>.delayed(timeout);
    } catch (_) {
      // 部分机型禁止组播，返回已发现列表
    } finally {
      _searchTimer?.cancel();
      _searchTimer = null;
      _searching = false;
      try {
        _socket?.close();
      } catch (_) {}
      _socket = null;
    }
    // 仅返回真实设备，不再注入演示电视
    return _devices.values
        .where((d) => !d.isDemo)
        .toList(growable: false);
  }

  void _sendMSearch(RawDatagramSocket socket) {
    const payload = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'
        '\r\n';
    final bytes = utf8.encode(payload);
    try {
      socket.send(bytes, InternetAddress('239.255.255.250'), 1900);
    } catch (_) {}
    // 部分路由对 ST:ssdp:all 更友好
    const allPayload = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: ssdp:all\r\n'
        '\r\n';
    try {
      socket.send(utf8.encode(allPayload), InternetAddress('239.255.255.250'), 1900);
    } catch (_) {}
  }

  Future<void> _handleSsdp(String text) async {
    final location = _header(text, 'LOCATION') ?? _header(text, 'Location');
    final usn = _header(text, 'USN') ?? location;
    if (location == null || location.isEmpty || usn == null) return;
    if (_devices.containsKey(usn)) return;

    try {
      final desc = await http
          .get(Uri.parse(location))
          .timeout(const Duration(seconds: 3));
      if (desc.statusCode < 200 || desc.statusCode >= 300) return;
      final xml = desc.body;
      final name = _xmlTag(xml, 'friendlyName') ?? '智能电视';
      final mfr = _xmlTag(xml, 'manufacturer') ?? '';
      final control = _resolveControlUrl(location, xml);
      if (control == null || control.isEmpty) return;
      _devices[usn] = DlnaDevice(
        usn: usn,
        name: name,
        location: location,
        controlUrl: control,
        manufacturer: mfr,
      );
    } catch (_) {}
  }

  String? _resolveControlUrl(String location, String xml) {
    // 找 AVTransport 的 controlURL
    final serviceBlocks = RegExp(
      r'<service[\s\S]*?</service>',
      caseSensitive: false,
    ).allMatches(xml);
    for (final m in serviceBlocks) {
      final block = m.group(0)!;
      if (!block.toLowerCase().contains('avtransport')) continue;
      final path = _xmlTag(block, 'controlURL') ?? _xmlTag(block, 'controlUrl');
      if (path == null || path.isEmpty) continue;
      return _absolutize(location, path);
    }
    return null;
  }

  String _absolutize(String location, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = Uri.parse(location);
    if (path.startsWith('/')) {
      return '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}$path';
    }
    final dir = location.substring(0, location.lastIndexOf('/') + 1);
    return '$dir$path';
  }

  String? _header(String raw, String key) {
    final re = RegExp('^$key:\\s*(.+?)\\s*\$', multiLine: true, caseSensitive: false);
    return re.firstMatch(raw)?.group(1)?.trim();
  }

  String? _xmlTag(String xml, String tag) {
    final re = RegExp('<$tag[^>]*>([^<]*)</$tag>', caseSensitive: false);
    return re.firstMatch(xml)?.group(1)?.trim();
  }

  String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  Future<void> _soap({
    required String controlUrl,
    required String action,
    required String bodyInner,
  }) async {
    final envelope = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:$action xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      $bodyInner
    </u:$action>
  </s:Body>
</s:Envelope>''';

    final res = await http
        .post(
          Uri.parse(controlUrl),
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction':
                '"urn:schemas-upnp-org:service:AVTransport:1#$action"',
          },
          body: utf8.encode(envelope),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('设备拒绝操作 ($action ${res.statusCode})');
    }
  }

  /// 推送媒体地址并播放
  Future<void> cast({
    required DlnaDevice device,
    required String mediaUrl,
    String title = '哇TV',
  }) async {
    final url = mediaUrl.trim();
    if (url.isEmpty) throw Exception('播放地址为空');
    if (device.isDemo) {
      // 模拟推流耗时
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return;
    }
    await _soap(
      controlUrl: device.controlUrl,
      action: 'SetAVTransportURI',
      bodyInner:
          '<CurrentURI>${_escapeXml(url)}</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>',
    );
    await _soap(
      controlUrl: device.controlUrl,
      action: 'Play',
      bodyInner: '<Speed>1</Speed>',
    );
  }

  Future<void> pause(DlnaDevice device) async {
    if (device.isDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return;
    }
    await _soap(
      controlUrl: device.controlUrl,
      action: 'Pause',
      bodyInner: '',
    );
  }

  Future<void> play(DlnaDevice device) async {
    if (device.isDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return;
    }
    await _soap(
      controlUrl: device.controlUrl,
      action: 'Play',
      bodyInner: '<Speed>1</Speed>',
    );
  }

  Future<void> stop(DlnaDevice device) async {
    if (device.isDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return;
    }
    await _soap(
      controlUrl: device.controlUrl,
      action: 'Stop',
      bodyInner: '',
    );
  }

  void dispose() {
    _searchTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
