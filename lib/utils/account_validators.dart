/// 注册账号校验（拦截一眼假的 QQ 测试号）
abstract final class AccountValidators {
  AccountValidators._();

  /// 注册用：有问题返回错误文案，通过返回 null
  static String? registerUsernameError(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '请输入账号';

    // 纯数字按 QQ 号规则校验
    if (RegExp(r'^\d+$').hasMatch(s)) {
      if (s.length < 5 || s.length > 11) {
        return 'QQ 号一般为 5～11 位数字';
      }
      if (isFakeLookingQq(s)) {
        return '请勿使用 123456、666666 等测试号，请填写真实 QQ 号';
      }
    }
    return null;
  }

  /// 一眼假的数字号：全相同、连号、简单重复段、常见黑名单
  static bool isFakeLookingQq(String digits) {
    final s = digits.trim();
    if (!RegExp(r'^\d{5,12}$').hasMatch(s)) return false;

    // 11111 / 666666 / 000000
    if (s.split('').every((c) => c == s[0])) return true;

    // 12345… / 54321…
    if (_isStrictSequential(s, 1) || _isStrictSequential(s, -1)) return true;

    // 121212、123123、112211 等短周期重复
    if (_isShortPeriodRepeat(s)) return true;

    // 常见测试号
    const banned = <String>{
      '12345',
      '123456',
      '1234567',
      '12345678',
      '123456789',
      '1234567890',
      '012345',
      '0123456',
      '01234567',
      '54321',
      '654321',
      '7654321',
      '87654321',
      '987654321',
      '11111',
      '22222',
      '33333',
      '44444',
      '55555',
      '66666',
      '77777',
      '88888',
      '99999',
      '00000',
      '111111',
      '222222',
      '333333',
      '444444',
      '555555',
      '666666',
      '777777',
      '888888',
      '999999',
      '000000',
      '112233',
      '123321',
      '111222',
      '121212',
      '131313',
      '5201314',
      '1314520',
    };
    return banned.contains(s);
  }

  static bool _isStrictSequential(String s, int step) {
    for (var i = 1; i < s.length; i++) {
      final prev = s.codeUnitAt(i - 1) - 48;
      final cur = s.codeUnitAt(i) - 48;
      if ((prev + step + 10) % 10 != cur) return false;
    }
    // 全相同已被上面拦住；这里要求至少有真实步进
    return step != 0;
  }

  /// 周期 1～3 且整串由同一段重复填满（如 121212、123123）
  static bool _isShortPeriodRepeat(String s) {
    for (var period = 1; period <= 3; period++) {
      if (s.length < period * 2) continue;
      if (s.length % period != 0) continue;
      final unit = s.substring(0, period);
      // 周期 1 = 全相同，已单独处理；仍允许检测
      var ok = true;
      for (var i = period; i < s.length; i += period) {
        if (s.substring(i, i + period) != unit) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }
}
