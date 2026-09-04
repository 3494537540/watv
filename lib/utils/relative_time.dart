String _hm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

String _weekday(DateTime dt) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return names[dt.weekday - 1];
}

/// 与 fetch_im.js `toEpochMs` 对齐：ns / us / ms / s → 毫秒
int toEpochMs(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) {
    final n = raw.toDouble();
    if (n <= 0) return 0;
    if (n > 1e17) return (n / 1e6).round(); // ns
    if (n > 1e14) return (n / 1e3).round(); // us
    if (n > 1e11) return n.round(); // ms
    if (n > 1e8) return (n * 1000).round(); // s
    return 0;
  }
  final s = '$raw'.trim();
  if (s.isEmpty) return 0;
  // 纯数字
  final asInt = int.tryParse(s);
  if (asInt != null) return toEpochMs(asInt);
  // 小数秒
  final asDouble = double.tryParse(s);
  if (asDouble != null) return toEpochMs(asDouble);
  // 尝试解析常见日期字符串
  final dt = DateTime.tryParse(s);
  if (dt != null) return dt.millisecondsSinceEpoch;
  return 0;
}

/// 兼容旧调用
int resolveTimeMs({required int timeMs, String time = ''}) {
  if (timeMs > 0) {
    // 后端偶发把微秒写进 time_ms
    return toEpochMs(timeMs);
  }
  return toEpochMs(time);
}

/// 会话列表时间：今天只显示几点；昨天「昨天 + 几点」；一周内其它天只显示周几；更早只显示月/日
String formatConversationTime(int timeMs, {DateTime? now}) {
  final ms = toEpochMs(timeMs);
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final hm = _hm(dt);

  if (day == today) return hm;
  if (day == today.subtract(const Duration(days: 1))) return '昨天 $hm';

  final weekAgo = today.subtract(const Duration(days: 6));
  if (!day.isBefore(weekAgo)) return _weekday(dt);

  if (dt.year == n.year) return '${dt.month}/${dt.day}';
  return '${dt.year}/${dt.month}/${dt.day}';
}

/// 聊天记录时间条：完整日期时间，避免时区/相对时间误解
String formatMessageTime(int timeMs, {DateTime? now}) {
  final ms = toEpochMs(timeMs);
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final hm = _hm(dt);

  if (day == today) return hm;
  if (day == today.subtract(const Duration(days: 1))) return '昨天 $hm';
  if (dt.year == n.year) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hm';
  }
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hm';
}

/// 两条消息间隔 ≥5 分钟时插入时间条
bool shouldShowMessageTimeChip({
  required int currentMs,
  required int olderMs,
  DateTime? now,
}) {
  final cur = toEpochMs(currentMs);
  final older = toEpochMs(olderMs);
  if (cur <= 0) return false;
  if (older <= 0) return true;
  return (cur - older).abs() >= 5 * 60 * 1000;
}

String formatRelativeTime(int timeMs, {DateTime? now}) =>
    formatConversationTime(timeMs, now: now);

/// 广场等场景：刚刚 / N分钟前 / N小时前 / 昨天 / 月日
String formatAgo(int timeMs, {DateTime? now}) {
  final ms = toEpochMs(timeMs);
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final n = now ?? DateTime.now();
  final diff = n.difference(dt);
  if (diff.isNegative || diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  if (day == today.subtract(const Duration(days: 1))) return '昨天';
  if (dt.year == n.year) return '${dt.month}月${dt.day}日';
  return '${dt.year}/${dt.month}/${dt.day}';
}

/// 评论时间：优先 timeMs；已是相对文案则保留；绝对时间再换算
String formatCommentTime(String raw, {int timeMs = 0, DateTime? now}) {
  if (timeMs > 0) {
    final label = formatAgo(timeMs, now: now);
    if (label.isNotEmpty) return label;
  }
  final t = raw.trim();
  if (t.isEmpty) return '刚刚';
  // CMS 常把刚发的都写成「刚刚」，若有 timeMs 已在上面处理
  if (RegExp(r'^\d+\s*(秒|分钟|小时|天)前$').hasMatch(t)) {
    return t.replaceAll(' ', '');
  }
  if (t.contains('前') && t != '刚刚') {
    return t.replaceAll(' ', '');
  }
  final m = RegExp(
    r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})[日]?(?:\s+(\d{1,2}):(\d{2}))?',
  ).firstMatch(t);
  if (m != null) {
    final dt = DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.tryParse(m.group(4) ?? '') ?? 0,
      int.tryParse(m.group(5) ?? '') ?? 0,
    );
    final label = formatAgo(dt.millisecondsSinceEpoch, now: now);
    return label.isEmpty ? '刚刚' : label;
  }
  final parsed = DateTime.tryParse(t.replaceAll('/', '-'));
  if (parsed != null) {
    final label = formatAgo(parsed.millisecondsSinceEpoch, now: now);
    return label.isEmpty ? '刚刚' : label;
  }
  return t == '刚刚' ? '刚刚' : t;
}
