import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/maccms_user_api.dart';
import '../services/qq_login_service.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/login_brand_widgets.dart';

enum LoginPageMode { login, register }

/// 会员登录 / 注册（白底简洁落地页）
class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.initialMode = LoginPageMode.login,
    this.popOnSuccess = true,
    /// 启动门禁：登录成功后不 pop，由 AuthGate 切到主页
    this.asLaunchGate = false,
  });

  final LoginPageMode initialMode;
  final bool popOnSuccess;
  final bool asLaunchGate;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late LoginPageMode _mode;
  bool _showForm = false;
  bool _obscure = true;
  bool _busy = false;
  bool _agreed = true;
  bool _captchaLoading = false;
  String? _error;
  Uint8List? _captcha;

  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _pwd2Ctrl = TextEditingController();
  final _verifyCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _pwdFocus = FocusNode();
  final _pwd2Focus = FocusNode();
  final _verifyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (_mode == LoginPageMode.register) _showForm = true;
    for (final f in [_userFocus, _pwdFocus, _pwd2Focus, _verifyFocus]) {
      f.addListener(() => setState(() {}));
    }
    _reloadCaptcha();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _pwd2Ctrl.dispose();
    _verifyCtrl.dispose();
    _userFocus.dispose();
    _pwdFocus.dispose();
    _pwd2Focus.dispose();
    _verifyFocus.dispose();
    super.dispose();
  }

  void _openForm(LoginPageMode mode) {
    if (!_agreed) {
      DialogX.showError('请先同意用户协议和隐私政策');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _mode = mode;
      _showForm = true;
      _error = null;
      _obscure = true;
    });
    _reloadCaptcha();
  }

  Future<void> _reloadCaptcha() async {
    setState(() => _captchaLoading = true);
    try {
      final bytes = await CmsAuthController.instance.fetchCaptcha();
      if (!mounted) return;
      setState(() {
        _captcha = bytes;
        _captchaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _captcha = null;
        _captchaLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_agreed) {
      setState(() => _error = '请先同意用户协议和隐私政策');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final name = _userCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    final code = _verifyCtrl.text.trim();
    setState(() => _error = null);

    if (name.isEmpty) {
      setState(() => _error = '请输入账号');
      return;
    }
    if (pwd.length < 6) {
      setState(() => _error = '密码至少 6 位');
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    if (_mode == LoginPageMode.register && _pwd2Ctrl.text != pwd) {
      setState(() => _error = '两次密码不一致');
      return;
    }

    setState(() => _busy = true);
    try {
      if (_mode == LoginPageMode.login) {
        await CmsAuthController.instance.login(
          userName: name,
          password: pwd,
          verify: code,
        );
        DialogX.showSuccess('登录成功');
        await Future<void>.delayed(const Duration(milliseconds: 280));
        if (!mounted) return;
        if (widget.asLaunchGate) {
          // AuthGate 监听登录态后切主页
          return;
        }
        if (widget.popOnSuccess) Navigator.of(context).pop(true);
      } else {
        await CmsAuthController.instance.register(
          userName: name,
          password: pwd,
          password2: _pwd2Ctrl.text,
          verify: code,
        );
        DialogX.showSuccess('注册成功，请登录');
        if (!mounted) return;
        setState(() {
          _busy = false;
          _mode = LoginPageMode.login;
          _verifyCtrl.clear();
        });
        await _reloadCaptcha();
      }
    } on CmsUserException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      await _reloadCaptcha();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '网络异常，请稍后重试';
        });
      }
      await _reloadCaptcha();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final canPop = !widget.asLaunchGate || _showForm;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canPop)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () {
                      if (_showForm) {
                        setState(() => _showForm = false);
                        return;
                      }
                      Navigator.of(context).maybePop(false);
                    },
                    icon: const Icon(CupertinoIcons.back),
                    color: AppColors.text,
                  ),
                )
              else
                const SizedBox(height: 12),
              Expanded(
                child: _showForm
                    ? _buildForm(bottom)
                    : _buildLanding(bottom),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanding(double bottom) {
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 8, 28, 8 + bottom),
      child: Column(
        children: [
          SizedBox(height: 48),
          const _BrandTitle(),
          SizedBox(height: 10),
          Text(
            '哇TV，就是好看',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.3,
              color: Color(0xFFB0B0B0),
            ),
          ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 240,
                height: 200,
                child: CustomPaint(painter: _TvDoodlePainter()),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => _openForm(LoginPageMode.login),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('账号密码登录'),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '其他登录方式',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 12,
              color: Color(0xFFB0B0B0),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: _onQqLogin,
              behavior: HitTestBehavior.opaque,
              child: const Column(
                children: [
                  QqBrandIcon(size: 48),
                  SizedBox(height: 6),
                  Text(
                    'QQ登录',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 11,
                      color: Color(0xFF8A8A8A),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Future<void> _onQqLogin() async {
    if (_busy) return;
    if (!_agreed) {
      DialogX.showError('请先同意用户协议和隐私政策');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final r = await QqLoginService.instance.login();
      if (!mounted) return;
      if (!r.ok) {
        DialogX.showWarning(r.message);
        return;
      }
      DialogX.showSuccess(r.message.isEmpty ? 'QQ 登录成功' : r.message);
      // openId 后续对接 CMS 绑定；审核通过后由后台开通
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      if (widget.asLaunchGate) return;
      if (widget.popOnSuccess) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildForm(double bottom) {
    final isReg = _mode == LoginPageMode.register;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(28, 4, 28, 24 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isReg ? '注册账号' : '账号登录',
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: AppColors.text,
            ),
          ),
          SizedBox(height: 8),
          Text(
            isReg ? '注册后即可同步收藏与播放记录' : '欢迎回来，继续追你的片单',
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 14,
              color: Color(0xFFB0B0B0),
            ),
          ),
          SizedBox(height: 28),
          _LabeledField(
            label: '账号',
            focused: _userFocus.hasFocus,
            child: TextField(
              controller: _userCtrl,
              focusNode: _userFocus,
              maxLength: 16,
              style: _inputStyle,
              cursorColor: AppColors.brand,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _pwdFocus.requestFocus(),
              decoration: _dec('请输入账号'),
            ),
          ),
          SizedBox(height: 14),
          _LabeledField(
            label: '密码',
            focused: _pwdFocus.hasFocus,
            child: TextField(
              controller: _pwdCtrl,
              focusNode: _pwdFocus,
              obscureText: _obscure,
              maxLength: 20,
              style: _inputStyle,
              cursorColor: AppColors.brand,
              textInputAction:
                  isReg ? TextInputAction.next : TextInputAction.next,
              onSubmitted: (_) {
                if (isReg) {
                  _pwd2Focus.requestFocus();
                } else {
                  _verifyFocus.requestFocus();
                }
              },
              decoration: _dec(
                '请输入密码（至少 6 位）',
                suffix: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? CupertinoIcons.eye_slash
                        : CupertinoIcons.eye,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          if (isReg) ...[
            SizedBox(height: 14),
            _LabeledField(
              label: '确认密码',
              focused: _pwd2Focus.hasFocus,
              child: TextField(
                controller: _pwd2Ctrl,
                focusNode: _pwd2Focus,
                obscureText: _obscure,
                maxLength: 20,
                style: _inputStyle,
                cursorColor: AppColors.brand,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _verifyFocus.requestFocus(),
                decoration: _dec('请再次输入密码'),
              ),
            ),
          ],
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _LabeledField(
                  label: '验证码',
                  focused: _verifyFocus.hasFocus,
                  child: TextField(
                    controller: _verifyCtrl,
                    focusNode: _verifyFocus,
                    maxLength: 8,
                    style: _inputStyle,
                    cursorColor: AppColors.brand,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: _dec('输入右侧验证码'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: GestureDetector(
                  onTap: _captchaLoading ? null : _reloadCaptcha,
                  child: Container(
                    width: 118,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F6F8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE6E8EC)),
                    ),
                    child: _captchaLoading
                        ? const CupertinoActivityIndicator()
                        : (_captcha == null
                            ? const Text(
                                '点击刷新',
                                style: TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 12,
                                  color: AppColors.textHint,
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _captcha!,
                                  fit: BoxFit.cover,
                                  width: 118,
                                  height: 52,
                                ),
                              )),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                color: AppColors.danger,
              ),
            ),
          ],
          SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.brand.withValues(alpha: 0.5),
                elevation: 0,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isReg ? '注册' : '登录'),
            ),
          ),
          const SizedBox(height: 16),
          LoginAgreementRow(
            agreed: _agreed,
            onChanged: (v) => setState(() => _agreed = v),
          ),
          const SizedBox(height: 18),
          Center(
            child: GestureDetector(
              onTap: () => _openForm(
                isReg ? LoginPageMode.login : LoginPageMode.register,
              ),
              child: Text(
                isReg ? '已有账号？去登录' : '没有账号？去注册',
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 14,
                  color: Color(0xFF8A8A8A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _inputStyle = TextStyle(
    fontFamily: 'AppSans',
    fontSize: 16,
    height: 1.25,
    color: AppColors.text,
  );

  InputDecoration _dec(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'AppSans',
        fontSize: 15,
        color: Color(0xFFB8B8B8),
      ),
      counterText: '',
      // 覆盖全局 filled，避免白底叠在灰容器上露出左右灰边
      filled: false,
      fillColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
    );
  }
}

/// 品牌标题：粗黑体 + 品牌青点缀
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Text(
          '哇TV',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 46,
            fontWeight: FontWeight.w900,
            height: 1.05,
            color: Color(0xFF1A1A1A),
            letterSpacing: 2,
          ),
        ),
        Positioned(
          top: -2,
          right: 22,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.focused,
    required this.child,
  });

  final String label;
  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: focused ? AppColors.brand : const Color(0xFF6B6B6B),
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? AppColors.brand : const Color(0xFFE5E7EB),
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// 电视机 + 播放键简笔插画（登录落地页）
class _TvDoodlePainter extends CustomPainter {
  const _TvDoodlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width * 0.5;
    final top = size.height * 0.12;
    final tvW = size.width * 0.72;
    final tvH = size.height * 0.52;
    final left = cx - tvW / 2;
    final right = cx + tvW / 2;
    final bottom = top + tvH;
    final r = 16.0;

    // 天线
    canvas.drawLine(
      Offset(cx - 28, top + 4),
      Offset(cx - 48, top - 22),
      paint,
    );
    canvas.drawLine(
      Offset(cx + 28, top + 4),
      Offset(cx + 48, top - 22),
      paint,
    );
    canvas.drawCircle(Offset(cx - 48, top - 22), 3.2, paint);
    canvas.drawCircle(Offset(cx + 48, top - 22), 3.2, paint);

    // 外框
    final body = RRect.fromLTRBR(left, top, right, bottom, Radius.circular(r));
    canvas.drawRRect(body, paint);

    // 屏幕
    final inset = 12.0;
    final screen = RRect.fromLTRBR(
      left + inset,
      top + inset,
      right - inset,
      bottom - inset - 10,
      const Radius.circular(10),
    );
    canvas.drawRRect(screen, paint);

    // 播放三角
    final playCx = cx - 4;
    final playCy = (top + bottom - 10) / 2;
    final tri = Path()
      ..moveTo(playCx - 10, playCy - 16)
      ..lineTo(playCx - 10, playCy + 16)
      ..lineTo(playCx + 18, playCy)
      ..close();
    canvas.drawPath(tri, paint);

    // 底座
    final standTop = bottom + 8;
    canvas.drawLine(Offset(cx - 18, bottom), Offset(cx - 28, standTop + 18), paint);
    canvas.drawLine(Offset(cx + 18, bottom), Offset(cx + 28, standTop + 18), paint);
    canvas.drawLine(
      Offset(cx - 42, standTop + 18),
      Offset(cx + 42, standTop + 18),
      paint,
    );

    // 地面点缀
    canvas.drawLine(
      Offset(cx - 70, standTop + 32),
      Offset(cx + 70, standTop + 32),
      paint..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
