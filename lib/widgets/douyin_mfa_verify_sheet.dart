import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/api_config.dart';
import '../theme/app_colors.dart';

/// 扫码二次验证：App 内弹出 WebView 显示抖音身份验证页
Future<String?> showDouyinMfaVerifySheet(
  BuildContext context, {
  required String verifyUrl,
  required String bootstrapCookie,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'mfa-verify',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 360),
    pageBuilder: (ctx, a, b) => Align(
      alignment: Alignment.bottomCenter,
      child: DouyinMfaVerifySheet(
        verifyUrl: verifyUrl,
        bootstrapCookie: bootstrapCookie,
      ),
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

class DouyinMfaVerifySheet extends StatefulWidget {
  const DouyinMfaVerifySheet({
    super.key,
    required this.verifyUrl,
    required this.bootstrapCookie,
  });

  final String verifyUrl;
  final String bootstrapCookie;

  @override
  State<DouyinMfaVerifySheet> createState() => _DouyinMfaVerifySheetState();
}

class _DouyinMfaVerifySheetState extends State<DouyinMfaVerifySheet> {
  Timer? _probe;
  bool _ready = false;
  bool _done = false;
  String _hint = '请在下方完成身份验证';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    await _injectBootstrapCookies(widget.bootstrapCookie);
    if (!mounted) return;
    setState(() => _ready = true);
    _probe = Timer.periodic(const Duration(seconds: 2), (_) => _probeCookies());
  }

  Future<void> _injectBootstrapCookies(String header) async {
    final pairs = header
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.contains('='));
    final domains = [
      '.douyin.com',
      '.snssdk.com',
      '.bytedance.com',
    ];
    final mgr = CookieManager.instance();
    for (final pair in pairs) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      final name = pair.substring(0, i).trim();
      final value = pair.substring(i + 1).trim();
      if (name.isEmpty) continue;
      for (final domain in domains) {
        try {
          await mgr.setCookie(
            url: WebUri('https://${domain.replaceFirst('.', '')}/'),
            name: name,
            value: value,
            domain: domain,
            path: '/',
            isSecure: true,
          );
        } catch (_) {}
      }
    }
  }

  bool _hasSession(String cookie) {
    final c = cookie.toLowerCase();
    return c.contains('sessionid=') ||
        c.contains('sessionid_ss=') ||
        c.contains('sid_tt=');
  }

  Future<void> _probeCookies() async {
    if (_done) return;
    try {
      final mgr = CookieManager.instance();
      final all = <String, String>{};
      for (final host in [
        'https://www.douyin.com',
        'https://creator.douyin.com',
        'https://sso.douyin.com',
        'https://login.douyin.com',
      ]) {
        final jar = await mgr.getCookies(url: WebUri(host));
        for (final c in jar) {
          if (c.name.isNotEmpty) all[c.name] = c.value;
        }
      }
      if (all.isEmpty) return;
      final header = all.entries.map((e) => '${e.key}=${e.value}').join('; ');
      if (_hasSession(header)) {
        _done = true;
        _probe?.cancel();
        if (!mounted) return;
        Navigator.of(context).pop(header);
      }
    } catch (_) {}
  }

  String get _url {
    final u = widget.verifyUrl.trim();
    if (u.startsWith('http')) return u;
    return ApiConfig.douyinWebLoginUrl;
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
                        '身份验证',
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
                      onPressed: () => Navigator.pop(context),
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
              child: !_ready
                  ? const Center(child: CupertinoActivityIndicator())
                  : InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_url)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        thirdPartyCookiesEnabled: true,
                        sharedCookiesEnabled: true,
                      ),
                      onLoadStop: (_, __) async {
                        if (mounted) {
                          setState(() => _hint = '完成验证后将自动继续绑定');
                        }
                        await _probeCookies();
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + bottom),
              child: Text(
                _hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  color: Color(0xFF8E8E93),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
