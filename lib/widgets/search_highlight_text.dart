import 'package:flutter/material.dart';

/// 标题里匹配查询词的部分高亮（橙）
class SearchHighlightText extends StatelessWidget {
  const SearchHighlightText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines = 1,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int maxLines;

  static const highlightColor = Color(0xFFE67E22);

  @override
  Widget build(BuildContext context) {
    final base = style ??
        const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1A1A),
          decoration: TextDecoration.none,
        );
    final hi = highlightStyle ??
        base.copyWith(color: highlightColor, fontWeight: FontWeight.w700);

    final spans = _spans(text, query.trim(), base, hi);
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  static List<InlineSpan> _spans(
    String text,
    String query,
    TextStyle base,
    TextStyle hi,
  ) {
    if (text.isEmpty) return [TextSpan(text: text, style: base)];
    if (query.isEmpty) return [TextSpan(text: text, style: base)];

    final lowerText = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQ);
    if (idx >= 0) {
      return [
        if (idx > 0) TextSpan(text: text.substring(0, idx), style: base),
        TextSpan(text: text.substring(idx, idx + query.length), style: hi),
        if (idx + query.length < text.length)
          TextSpan(text: text.substring(idx + query.length), style: base),
      ];
    }

    // 逐字：查询里每个汉字若出现在标题中则高亮对应字（适配短拼音后的中文结果）
    final qChars = query.runes
        .map(String.fromCharCode)
        .where((c) => RegExp(r'[\u4e00-\u9fff]').hasMatch(c))
        .toSet();
    if (qChars.isEmpty) {
      return [TextSpan(text: text, style: base)];
    }
    final out = <InlineSpan>[];
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      out.add(TextSpan(text: ch, style: qChars.contains(ch) ? hi : base));
    }
    return out;
  }
}
