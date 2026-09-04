import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/api_config.dart';
import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../services/douyin_api.dart';
import '../theme/app_colors.dart';
import 'dialogx/dialogx.dart';

Future<bool?> showDouyinQrBindSheet(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'qr',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (ctx, a, b) => const Align(
      alignment: Alignment.bottomCenter,
      child: DouyinQrBindSheet(),
    ),
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class DouyinQrBindSheet extends StatefulWidget {
  const DouyinQrBindSheet({super.key});

  @override
  State<DouyinQrBindSheet> createState() => _DouyinQrBindSheetState();
}

class _DouyinQrBindSheetState extends State<DouyinQrBindSheet> {
  final _api = DouyinApi();
  Timer? _poll;
  Timer? _cookieProbe;
  String? _qrSrc;
  String _status = '正在获取二维码…';
  bool _busy = false;
  bool _tickBusy = false;
  bool _finishing = false;
  bool _showVerify = false;
  bool _webReady = false;
  String _sid = '';
  String _token = '';
  String _verifyUrl = ApiConfig.douyinWebLoginUrl;
  String _bootstrapCookie = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cookieProbe?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    _cookieProbe?.cancel();
    _finishing = false;
    _tickBusy = false;
    _showVerify = false;
    _webReady = false;
    setState(() {
      _busy = true;
      _status = '正在获取二维码…';
      _qrSrc = null;
    });
    try {
      final session = await _api.getQrcode();
      if (!mounted) return;
      var src = session.qrcode;
      if (src.isEmpty && session.qrcodeIndexUrl.isNotEmpty) {
        src =
            'https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${Uri.encodeComponent(session.qrcodeIndexUrl)}';
      }
      setState(() {
        _sid = session.sid;
        _token = session.token;
        _qrSrc = src;
        _status = '请使用抖音 App 扫码';
        _busy = false;
      });
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '获取二维码失败';
      });
    }
  }

  bool _looksLikeMfa(CookieLoginStatus st) {
    if (st.isMfa) return true;
    final t = st.statusText;
    return t.contains('身份验证') ||
        t.contains('验证页') ||
        t.contains('二次验证') ||
        t.contains('2046');
  }

  Future<void> _tick() async {
    if (_sid.isEmpty || _token.isEmpty || _finishing || _tickBusy) return;
    if (_showVerify) return;
    _tickBusy = true;
    try {
      final st = await _api.checkQrconnect(sid: _sid, token: _token);
      if (!mounted) return;
      if (st.statusText.isNotEmpty && !_showVerify) {
        setState(() => _status = st.statusText);
      }
      // 先处理 MFA，绝不能被半截 cookie 抢先绑定
      if (_looksLikeMfa(st)) {
        _verifyUrl = st.verifyUrl.trim().isNotEmpty
            ? st.verifyUrl.trim()
            : ApiConfig.douyinWebLoginUrl;
        _bootstrapCookie = st.bootstrapCookie;
        await _enterVerifyMode();
        return;
      }
      if (st.isConfirmed && st.cookie.isNotEmpty) {
        _poll?.cancel();
        await _finish(st.cookie);
        return;
      }
      if (st.status == 'expired' ||
          st.status == '4' ||
          st.status == 'mfa_timeout') {
        _poll?.cancel();
        setState(() => _status = st.status == 'mfa_timeout'
            ? '验证超时，请刷新二维码重试'
            : '二维码已过期，请刷新');
      }
    } catch (_) {
    } finally {
      _tickBusy = false;
    }
  }

  Future<void> _enterVerifyMode() async {
    if (_showVerify || _finishing) return;
    _poll?.cancel();
    if (_verifyUrl.trim().isEmpty) {
      _verifyUrl = ApiConfig.douyinWebLoginUrl;
    }
    setState(() {
      _showVerify = true;
      _webReady = false;
      _status = '请在下方完成身份验证';
    });
    // 清掉旧会话，避免未验证就用上次 Cookie 误报绑定成功
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    await _injectBootstrapCookies(_stripSessionCookies(_bootstrapCookie));
    if (!mounted) return;
    setState(() => _webReady = true);
    _cookieProbe?.cancel();
    // 延迟再探测，给验证页加载时间
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted || _finishing || !_showVerify) return;
      _cookieProbe =
          Timer.periodic(const Duration(seconds: 2), (_) => _probeWebCookies());
    });
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_finishing || _sid.isEmpty) return;
      try {
        final st2 = await _api.checkQrconnect(sid: _sid, token: _token);
        if (!mounted || _finishing) return;
        if (_looksLikeMfa(st2)) return;
        if (st2.isConfirmed && st2.cookie.isNotEmpty) {
          _poll?.cancel();
          _cookieProbe?.cancel();
          await _finish(st2.cookie);
        }
      } catch (_) {}
    });
  }

  String _stripSessionCookies(String header) {
    if (header.trim().isEmpty) return '';
    final keep = <String>[];
    for (final part in header.split(';')) {
      final p = part.trim();
      if (p.isEmpty || !p.contains('=')) continue;
      final name = p.split('=').first.trim().toLowerCase();
      if (name == 'sessionid' ||
          name == 'sessionid_ss' ||
          name == 'sid_tt' ||
          name == 'sid_guard') {
        continue;
      }
      keep.add(p);
    }
    return keep.join('; ');
  }

  Future<void> _injectBootstrapCookies(String header) async {
    if (header.trim().isEmpty) return;
    final pairs = header
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.contains('='));
    final mgr = CookieManager.instance();
    for (final pair in pairs) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      final name = pair.substring(0, i).trim();
      final value = pair.substring(i + 1).trim();
      if (name.isEmpty) continue;
      for (final host in [
        'https://www.douyin.com/',
        'https://creator.douyin.com/',
        'https://sso.douyin.com/',
        'https://login.douyin.com/',
      ]) {
        try {
          await mgr.setCookie(
            url: WebUri(host),
            name: name,
            value: value,
            domain: '.douyin.com',
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

  Future<void> _probeWebCookies() async {
    if (_finishing || !_showVerify) return;
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
        _cookieProbe?.cancel();
        _poll?.cancel();
        await _finish(header);
      }
    } catch (_) {}
  }

  Future<void> _finish(String cookie) async {
    if (_finishing) return;
    if (!_hasSession(cookie)) {
      if (mounted) setState(() => _status = '登录未完成，请继续验证');
      return;
    }
    _finishing = true;
    _poll?.cancel();
    _cookieProbe?.cancel();
    DialogX.showWait('绑定中…');
    try {
      final user = await _api.getUserInfo(cookie: cookie, sid: _sid);
      if (user.userId.isEmpty) {
        throw ApiException('未获取到抖音账号，请完成验证后重试');
      }
      // 通行证占位名 = 尚未真正登录完成
      if (RegExp(r'^用户\d+$').hasMatch(user.nickname)) {
        _finishing = false;
        DialogX.showWarning('请先完成身份验证');
        if (mounted) {
          setState(() {
            _status = '请先完成身份验证，再等待自动绑定';
            if (!_showVerify) {
              _showVerify = true;
              _webReady = true;
            }
          });
        }
        return;
      }
      await _api.bind(cookie: cookie, user: user, sid: _sid);
      // 绑定后立刻核对列表，避免假成功
      final list = await _api.myList();
      final found = list.any((a) => a.douyinUid == user.userId);
      if (!found) {
        throw ApiException('绑定接口已返回，但列表未出现该账号，请下拉刷新或重试');
      }
      DialogX.showSuccess('绑定成功');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _finishing = false;
      DialogX.showError(e.message);
      if (mounted) setState(() => _status = e.message);
    } catch (_) {
      _finishing = false;
      DialogX.showError('绑定失败');
    }
  }

  Widget? _buildQrImage() {
    final src = _qrSrc;
    if (src == null || src.isEmpty) return null;
    if (src.startsWith('data:image')) {
      final i = src.indexOf('base64,');
      if (i < 0) return null;
      try {
        final bytes = base64Decode(src.substring(i + 7));
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } catch (_) {
        return null;
      }
    }
    return Image.network(
      src,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height;
    final qr = _buildQrImage();

    if (_showVerify) {
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
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: _busy ? null : _start,
                        child: Text(
                          '重扫',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 17,
                            color: AppColors.iosBlue,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
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
                child: !_webReady
                    ? const Center(child: CupertinoActivityIndicator())
                    : InAppWebView(
                        initialUrlRequest: URLRequest(
                          url: WebUri(_verifyUrl),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          domStorageEnabled: true,
                          thirdPartyCookiesEnabled: true,
                          sharedCookiesEnabled: true,
                        ),
                        onLoadStop: (_, __) => _probeWebCookies(),
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + bottom),
                child: Text(
                  _status,
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

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 20 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '扫码绑定',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        '关闭',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 17,
                          color: AppColors.iosBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: 220,
                  height: 220,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _busy
                      ? const CupertinoActivityIndicator()
                      : (qr ??
                          Text(
                            '暂无二维码',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              color: Color(0xFF8E8E93),
                            ),
                          )),
                ),
                SizedBox(height: 16),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    color: Color(0xFF8E8E93),
                  ),
                ),
                if (_status.contains('验证') || _status.contains('身份')) ...[
                  SizedBox(height: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _enterVerifyMode,
                    child: Text(
                      '打开验证页',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.iosBlue,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 12),
                CupertinoButton(
                  onPressed: _busy ? null : _start,
                  child: Text(
                    '刷新二维码',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      color: AppColors.iosBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
