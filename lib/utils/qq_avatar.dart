/// 把登录账号 / 展示名当成 QQ 号，拼 QQ 头像地址
class QqAvatar {
  QqAvatar._();

  /// 从账号、昵称、「用户12345」等提取 QQ 号
  static String? extractQq(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s == 'null') return null;
    if (RegExp(r'^\d{5,12}$').hasMatch(s)) return s;
    final userPrefix = RegExp(r'^用户(\d{5,12})$').firstMatch(s);
    if (userPrefix != null) return userPrefix.group(1);
    final qqLabel = RegExp(
      r'(?:qq|QQ)[:：\s]*(\d{5,12})',
    ).firstMatch(s);
    if (qqLabel != null) return qqLabel.group(1);
    return null;
  }

  /// QQ 官方头像（无需鉴权）
  static String? urlFromAccount(String? account, {int size = 100}) {
    final qq = extractQq(account);
    if (qq == null) return null;
    final s = switch (size) {
      <= 40 => 40,
      <= 100 => 100,
      <= 140 => 140,
      _ => 640,
    };
    return 'https://q1.qlogo.cn/g?b=qq&nk=$qq&s=$s';
  }

  /// 多个候选里取第一个能解析出 QQ 的
  static String? urlFromCandidates(Iterable<String?> candidates, {int size = 100}) {
    for (final c in candidates) {
      final u = urlFromAccount(c, size: size);
      if (u != null) return u;
    }
    return null;
  }
}
