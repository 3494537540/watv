import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 豆瓣图床反爬：必须带浏览器 UA + Referer，否则 418
const _doubanImageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  'Referer': 'https://m.douban.com/',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
};

/// 本地生成演员头像 PNG（外网失败时兜底）
class CastAvatarPainter {
  CastAvatarPainter._();

  static final Map<String, Uint8List> _cache = {};

  static Future<Uint8List> pngFor(String name, Color color, {int size = 128}) async {
    final key = '$name-${color.r}-${color.g}-${color.b}-$size';
    final hit = _cache[key];
    if (hit != null) return hit;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final s = size.toDouble();
    final center = Offset(s / 2, s / 2);
    final radius = s / 2;

    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(s * 0.15, s * 0.1),
        Offset(s * 0.9, s * 0.95),
        [
          color,
          Color.lerp(color, const Color(0xFF111111), 0.35)!,
        ],
      );
    canvas.drawCircle(center, radius, paint);

    final shine = Paint()
      ..shader = ui.Gradient.radial(
        Offset(s * 0.35, s * 0.28),
        s * 0.45,
        [
          Colors.white.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0),
        ],
      );
    canvas.drawCircle(center, radius, shine);

    final initials = _initials(name);
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontWeight: FontWeight.w700,
        fontSize: initials.length >= 2 ? s * 0.32 : s * 0.42,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: Colors.white,
        fontFamily: 'AppSans',
      ))
      ..addText(initials);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: s));
    canvas.drawParagraph(
      paragraph,
      Offset(0, (s - paragraph.height) / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = bytes!.buffer.asUint8List();
    _cache[key] = out;
    return out;
  }

  static String _initials(String name) {
    final n = name.trim();
    if (n.isEmpty) return '?';
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(n[0])) {
      return n.length >= 2 ? n.substring(0, 2) : n[0];
    }
    final parts = n.split(RegExp(r'[\s·•.]+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return n[0].toUpperCase();
  }
}

/// 优先真人网图（http 带 Referer 拉取），失败回退本地生成头像
class CastAvatarImage extends StatefulWidget {
  const CastAvatarImage({
    super.key,
    required this.name,
    required this.color,
    this.avatarUrl,
    this.size = 54,
  });

  final String name;
  final Color color;
  final String? avatarUrl;
  final double size;

  @override
  State<CastAvatarImage> createState() => _CastAvatarImageState();
}

class _CastAvatarImageState extends State<CastAvatarImage> {
  static final Map<String, Uint8List> _netCache = {};

  Uint8List? _localBytes;
  Uint8List? _netBytes;
  int _loadGen = 0;

  String get _url => widget.avatarUrl?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _prepareLocal();
    _loadNetwork();
  }

  @override
  void didUpdateWidget(covariant CastAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name || oldWidget.color != widget.color) {
      _prepareLocal();
    }
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _netBytes = null;
      _loadNetwork();
    }
  }

  Future<void> _prepareLocal() async {
    final bytes = await CastAvatarPainter.pngFor(
      widget.name,
      widget.color,
      size: (widget.size * 2).round().clamp(64, 256),
    );
    if (!mounted) return;
    setState(() => _localBytes = bytes);
  }

  Future<void> _loadNetwork() async {
    final url = _url;
    final gen = ++_loadGen;
    if (url.isEmpty) {
      if (mounted && gen == _loadGen) setState(() => _netBytes = null);
      return;
    }

    final cached = _netCache[url];
    if (cached != null) {
      if (mounted && gen == _loadGen) setState(() => _netBytes = cached);
      return;
    }

    try {
      final res = await http
          .get(Uri.parse(url), headers: _doubanImageHeaders)
          .timeout(const Duration(seconds: 12));
      if (gen != _loadGen || !mounted) return;
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final bytes = res.bodyBytes;
        _netCache[url] = bytes;
        setState(() => _netBytes = bytes);
      }
    } catch (_) {
      // 保留本地头像
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final bytes = _netBytes ?? _localBytes;

    return ClipOval(
      child: SizedBox(
        width: s,
        height: s,
        child: bytes == null
            ? Container(color: widget.color.withValues(alpha: 0.35))
            : Image.memory(
                bytes,
                width: s,
                height: s,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
