import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/api_config.dart';
import '../models/auth_models.dart';
import '../services/douyin_api.dart';
import '../theme/app_colors.dart';
import 'dialogx/dialogx.dart';

/// 图一效果：底部弹出式网页绑定（右上角关闭）
Future<bool?> showDouyinWebBindSheet(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'web-bind',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (ctx, a, b) => const Align(
      alignment: Alignment.bottomCenter,
      child: DouyinWebBindSheet(),
    ),
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class DouyinWebBindSheet extends StatefulWidget {
  const DouyinWebBindSheet({super.key});

  @override
  State<DouyinWebBindSheet> createState() => _DouyinWebBindSheetState();
}

class _DouyinWebBindSheetState extends State<DouyinWebBindSheet> {
  final _api = DouyinApi();
  Timer? _cookieTimer;
  Timer? _serverPoll;
  bool _finishing = false;
  String _hint = '请在页面中登录抖音账号';
  String _serverSid = '';

  /// App / 模拟器：只在应用内 WebView 登录，绝不拉起本机 Edge。
  /// Flutter Web：无法嵌可靠 Cookie WebView，才回退服务端浏览器登录。
  bool get _useEmbeddedWeb => !kIsWeb;

  @override
  void initState() {
    super.initState();
    if (_useEmbeddedWeb) {
      _cookieTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _probeCookies(),
      );
    } else {
      _startServerWebLogin();
    }
  }

  @override
  void dispose() {
    _cookieTimer?.cancel();
    _serverPoll?.cancel();
    super.dispose();
  }

  bool _hasSession(String cookie) {
    final c = cookie.toLowerCase();
    return c.contains('sessionid=') ||
        c.contains('sessionid_ss=') ||
        c.contains('sid_tt=');
  }

  Future<void> _probeCookies() async {
    if (_finishing || !_useEmbeddedWeb) return;
    try {
      final jar = await CookieManager.instance().getCookies(
        url: WebUri('https://www.douyin.com'),
      );
      final jar2 = await CookieManager.instance().getCookies(
        url: WebUri('https://creator.douyin.com'),
      );
      final jar3 = await CookieManager.instance().getCookies(
        url: WebUri('https://sso.douyin.com'),
      );
      final all = <String, String>{};
      for (final c in [...jar, ...jar2, ...jar3]) {
        if (c.name.isNotEmpty) all[c.name] = c.value;
      }
      if (all.isEmpty) return;
      final header = all.entries.map((e) => '${e.key}=${e.value}').join('; ');
      if (_hasSession(header)) {
        await _finishWithCookie(header);
      }
    } catch (_) {}
  }

  Future<void> _startServerWebLogin() async {
    setState(() => _hint = '正在启动网页登录…');
    try {
      _serverSid = await _api.webLoginStart();
      if (!mounted) return;
      setState(() => _hint = '请在弹出的浏览器窗口完成登录，成功后将自动绑定');
      _serverPoll?.cancel();
      _serverPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_finishing || _serverSid.isEmpty) return;
        try {
          final st = await _api.browserLoginStatus(_serverSid);
          if (!mounted) return;
          if (st.statusText.isNotEmpty) {
            setState(() => _hint = st.statusText);
          }
          if (st.isConfirmed && st.cookie.isNotEmpty) {
            _serverPoll?.cancel();
            await _finishWithCookie(st.cookie, sid: _serverSid);
          }
        } catch (_) {}
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _hint = e.message);
    } catch (_) {
      if (mounted) setState(() => _hint = '启动失败，请改用扫码绑定');
    }
  }

  Future<void> _finishWithCookie(String cookie, {String sid = ''}) async {
    if (_finishing) return;
    _finishing = true;
    _cookieTimer?.cancel();
    _serverPoll?.cancel();
    DialogX.showWait('绑定中…');
    try {
      final user = await _api.getUserInfo(cookie: cookie, sid: sid);
      await _api.bind(cookie: cookie, user: user, sid: sid);
      DialogX.showSuccess('绑定成功');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _finishing = false;
      DialogX.showError(e.message);
      if (mounted) setState(() => _hint = e.message);
    } catch (_) {
      _finishing = false;
      DialogX.showError('绑定失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        height: height * 0.92,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(width: 64),
                    const Expanded(
                      child: Text(
                        '网页绑定',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        '关闭',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 17,
                          color: AppColors.iosBlue,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(
              height: 0.5,
              thickness: 0.5,
              color: Color(0xFFE5E5EA),
            ),
            Expanded(
              child: _useEmbeddedWeb
                  ? InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(ApiConfig.douyinWebLoginUrl),
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        thirdPartyCookiesEnabled: true,
                        sharedCookiesEnabled: true,
                      ),
                      onLoadStop: (c, url) async {
                        setState(() => _hint = '登录成功后将自动完成绑定');
                        await _probeCookies();
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CupertinoActivityIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              _hint,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 15,
                                height: 1.4,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (_useEmbeddedWeb)
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + bottom),
                child: Column(
                  children: [
                    Text(
                      _hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.only(top: 4),
                      onPressed: _probeCookies,
                      child: Text(
                        '我已登录，继续绑定',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 15,
                          color: AppColors.iosBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
