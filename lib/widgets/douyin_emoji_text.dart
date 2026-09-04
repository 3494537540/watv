import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import 'douyin_media_image.dart';

/// 抖音内置文字表情 `[微笑]` → CDN 图
class DouyinEmojiMap {
  DouyinEmojiMap._();
  static Map<String, String>? _map;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_map != null) return Future.value();
    return _loading ??= () async {
      try {
        final raw = await rootBundle.loadString('assets/douyin_emoji_map.json');
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _map = decoded.map((k, v) => MapEntry('$k', '$v'));
        } else {
          _map = {};
        }
      } catch (_) {
        _map = {};
      }
    }();
  }

  static String? urlOf(String token) {
    final m = _map;
    if (m == null || m.isEmpty) return null;
    return m[token];
  }

  static bool get ready => _map != null;
}

/// 文本气泡内联渲染 `[微笑]` 等抖音表情
class DouyinEmojiText extends StatefulWidget {
  const DouyinEmojiText({
    super.key,
    required this.text,
    required this.style,
    this.emojiSize = 22,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final double emojiSize;
  final TextAlign? textAlign;

  @override
  State<DouyinEmojiText> createState() => _DouyinEmojiTextState();
}

class _DouyinEmojiTextState extends State<DouyinEmojiText> {
  @override
  void initState() {
    super.initState();
    DouyinEmojiMap.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (!text.contains('[')) {
      return Text(text, style: widget.style, textAlign: widget.textAlign);
    }
    final spans = <InlineSpan>[];
    final re = RegExp(r'\[[^\[\]]{1,20}\]');
    var start = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      final token = m.group(0)!;
      final url = DouyinEmojiMap.urlOf(token);
      if (url != null && url.isNotEmpty) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: DouyinMediaImage(
                url: url,
                width: widget.emojiSize,
                height: widget.emojiSize,
                fit: BoxFit.contain,
                fallbackLabel: token,
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: token));
      }
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}
