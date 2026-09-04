import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../pages/login_page.dart';
import 'app_page_route.dart';

enum AuthSheetMode { login, register, forgot }

/// 打开 CMS 会员登录页
Future<bool> showAuthSheet(
  BuildContext context, {
  AuthSheetMode initialMode = AuthSheetMode.login,
}) async {
  HapticFeedback.selectionClick();
  final mode = initialMode == AuthSheetMode.register
      ? LoginPageMode.register
      : LoginPageMode.login;
  final result = await Navigator.of(context).push<bool>(
    AppPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => LoginPage(initialMode: mode),
    ),
  );
  return result == true;
}
