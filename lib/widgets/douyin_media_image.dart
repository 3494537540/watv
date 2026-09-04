import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// 带抖音 Referer 的网络图；支持解密缓存 media_file 与 data URI。
class DouyinMediaImage extends StatefulWidget {
  const DouyinMediaImage({
    super.key,
    required this.url,
    this.mediaFile = '',
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackLabel = '[图片]',
  });

  final String url;
  final String mediaFile;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String fallbackLabel;

  @override
  State<DouyinMediaImage> createState() => _DouyinMediaImageState();
}

class _DouyinMediaImageState extends State<DouyinMediaImage> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DouyinMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.mediaFile != widget.mediaFile) {
      _load();
    }
  }

  /// 粗检是否为常见图片头；避免把 HTML/JSON 喂给 Image.memory 触发 Invalid image data。
  static bool looksLikeImage(Uint8List bytes) {
    if (bytes.length < 8) return false;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    // WEBP: RIFF....WEBP
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    // BMP
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;
    // AVIF / HEIC 常见以 ftyp 开头（ISO BMFF）
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _bytes = null;
    });
    try {
      final src = widget.mediaFile.isNotEmpty
          ? ApiConfig.imMediaUrl(widget.mediaFile)
          : widget.url;
      if (src.isEmpty) {
        setState(() {
          _failed = true;
          _loading = false;
        });
        return;
      }
      if (src.startsWith('data:')) {
        final i = src.indexOf('base64,');
        if (i < 0) throw Exception('bad data uri');
        final bytes = base64Decode(src.substring(i + 7));
        if (!looksLikeImage(bytes)) throw Exception('invalid image data');
        if (!mounted) return;
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
        return;
      }
      final res = await http
          .get(
            Uri.parse(src),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
              'Referer': 'https://www.douyin.com/',
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      final bytes = res.bodyBytes;
      if (res.statusCode >= 200 &&
          res.statusCode < 300 &&
          bytes.isNotEmpty &&
          looksLikeImage(bytes)) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      } else {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _buildInner();
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }

  Widget _fallbackBox() {
    return Container(
      width: widget.width,
      height: widget.height ?? 80,
      alignment: Alignment.center,
      color: const Color(0xFFE5E5EA),
      child: Text(
        widget.fallbackLabel,
        style: const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 13,
          color: Color(0xFF8E8E93),
        ),
      ),
    );
  }

  Widget _buildInner() {
    if (_loading) {
      return SizedBox(
        width: widget.width,
        height: widget.height ?? ((widget.width ?? 120) * 0.6),
        child: const Center(child: CupertinoActivityIndicator()),
      );
    }
    if (_failed || _bytes == null) {
      return _fallbackBox();
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _fallbackBox(),
    );
  }
}
