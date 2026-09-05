import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../services/maccms_user_api.dart';
import '../services/qq_login_service.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/ios_edge_back.dart';
import '../widgets/login_brand_widgets.dart';

enum LoginPageMode { login, register }

/// 会员登录 / 注册
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

class _LoginPageState extends State<LoginPage>
    with TickerProviderStateMixin {
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

  late final AnimationController _enter;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (_mode == LoginPageMode.register) _showForm = true;
    for (final f in [_userFocus, _pwdFocus, _pwd2Focus, _verifyFocus]) {
      f.addListener(() => setState(() {}));
    }
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _reloadCaptcha();
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
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

  void _replayEnter() {
    _enter
      ..reset()
      ..forward();
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
    _replayEnter();
    _reloadCaptcha();
  }

  void _backToLanding() {
    _dismissKeyboard();
    setState(() {
      _showForm = false;
      _error = null;
    });
    _replayEnter();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _handleBack() {
    _dismissKeyboard();
    if (_showForm) {
      _backToLanding();
      return;
    }
    if (!widget.asLaunchGate) {
      Navigator.of(context).maybePop(false);
    }
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
    DialogX.showWait(_mode == LoginPageMode.login ? '登录中…' : '注册中…');
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
        if (widget.asLaunchGate) return;
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
        _replayEnter();
        await _reloadCaptcha();
      }
    } on CmsUserException catch (e) {
      DialogX.dismiss();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      await _reloadCaptcha();
    } catch (_) {
      DialogX.dismiss();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '网络异常，请稍后重试';
        });
      }
      await _reloadCaptcha();
    }
  }

  Future<void> _onQqLogin() async {
    if (_busy) return;
    if (!_agreed) {
      DialogX.showError('请先同意用户协议和隐私政策');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    DialogX.showWait('QQ 登录中…');
    try {
      final r = await QqLoginService.instance.login();
      if (!mounted) return;
      if (!r.ok) {
        DialogX.showWarning(r.message);
        return;
      }
      DialogX.showSuccess(r.message.isEmpty ? 'QQ 登录成功' : r.message);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      if (widget.asLaunchGate) return;
      if (widget.popOnSuccess) Navigator.of(context).pop(true);
    } catch (_) {
      DialogX.showError('QQ 登录失败，请稍后重试');
    } finally {
      DialogX.dismiss();
      if (mounted) setState(() => _busy = false);
    }
  }

  Animation<double> _stagger(double start, double end) {
    return CurvedAnimation(
      parent: _enter,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Widget _fadeSlide({
    required Animation<double> animation,
    required Widget child,
    Offset begin = const Offset(0, 0.06),
  }) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero)
            .animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final canPop = !widget.asLaunchGate || _showForm;
    // 表单页拦截系统返回 → 回到引导页；引导页才真正 pop
    final routeCanPop = !_showForm && !widget.asLaunchGate;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: PopScope(
        canPop: routeCanPop,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_showForm) _backToLanding();
        },
        child: IosEdgeBack(
          enabled: !routeCanPop,
          onBack: () {
            if (_showForm) {
              _backToLanding();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissKeyboard,
            child: Scaffold(
              backgroundColor: Colors.white,
              resizeToAvoidBottomInset: true,
              body: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          if (canPop)
                            IconButton(
                              onPressed: _handleBack,
                              icon: const Icon(CupertinoIcons.back),
                              color: AppColors.text,
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.04, 0),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          );
                        },
                        child: _showForm
                            ? KeyedSubtree(
                                key: ValueKey('form-$_mode'),
                                child: _buildForm(bottom),
                              )
                            : KeyedSubtree(
                                key: const ValueKey('landing'),
                                child: _buildLanding(bottom),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanding(double bottom) {
    final a1 = _stagger(0.0, 0.45);
    final a2 = _stagger(0.12, 0.55);
    final a3 = _stagger(0.22, 0.7);
    final a4 = _stagger(0.38, 0.85);
    final a5 = _stagger(0.5, 1.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 28, 24, 14 + bottom),
      child: Column(
        children: [
          _fadeSlide(
            animation: a1,
            begin: const Offset(0, -0.08),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '哇TV',
                    style: TextStyle(
                      fontFamily: 'ZCOOLKuaiLe',
                      fontSize: 46,
                      height: 1,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '好看的影视，一哇就来',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 15,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _fadeSlide(
              animation: a2,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final s = 1 + (_pulse.value * 0.018);
                    return Transform.scale(scale: s, child: child);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: ColoredBox(
                      color: const Color(0xFFF6FBFC),
                      child: Lottie.asset(
                        'assets/lottie/login_girl_hi.json',
                        width: 300,
                        fit: BoxFit.contain,
                        repeat: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _fadeSlide(
            animation: a3,
            child: _PressScale(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => _openForm(LoginPageMode.login),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('账号密码登录'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _fadeSlide(
            animation: a4,
            child: _PressScale(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: _busy ? null : _onQqLogin,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    backgroundColor: const Color(0xFFF8F8F8),
                    side: BorderSide.none,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      QqBrandIcon(size: 22),
                      SizedBox(width: 8),
                      Text('QQ 登录'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _fadeSlide(
            animation: a5,
            child: LoginAgreementRow(
              agreed: _agreed,
              onChanged: (v) => setState(() => _agreed = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(double bottom) {
    final isReg = _mode == LoginPageMode.register;
    final a1 = _stagger(0.0, 0.4);
    final a2 = _stagger(0.1, 0.55);
    final a3 = _stagger(0.22, 0.75);
    final a4 = _stagger(0.4, 0.95);

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fadeSlide(
            animation: a1,
            begin: const Offset(0, -0.05),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReg ? '注册账号' : '欢迎回来',
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          color: AppColors.text,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isReg ? '同步收藏、播放记录到云端' : '登录后继续追你的片单',
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '哇TV',
                    style: TextStyle(
                      fontFamily: 'ZCOOLKuaiLe',
                      fontSize: 16,
                      color: AppColors.brand,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _fadeSlide(
            animation: a2,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FA),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                children: [
                  _RoundField(
                    focused: _userFocus.hasFocus,
                    child: TextField(
                      controller: _userCtrl,
                      focusNode: _userFocus,
                      maxLength: 16,
                      style: _inputStyle,
                      cursorColor: AppColors.brand,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      keyboardAppearance: Brightness.light,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      onSubmitted: (_) => _pwdFocus.requestFocus(),
                      decoration: _dec('账号'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _RoundField(
                    focused: _pwdFocus.hasFocus,
                    child: TextField(
                      controller: _pwdCtrl,
                      focusNode: _pwdFocus,
                      obscureText: _obscure,
                      maxLength: 20,
                      style: _inputStyle,
                      cursorColor: AppColors.brand,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.next,
                      keyboardAppearance: Brightness.light,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      onSubmitted: (_) {
                        if (isReg) {
                          _pwd2Focus.requestFocus();
                        } else {
                          _verifyFocus.requestFocus();
                        }
                      },
                      decoration: _dec(
                        '密码（至少 6 位）',
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
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
                    const SizedBox(height: 10),
                    _RoundField(
                      focused: _pwd2Focus.hasFocus,
                      child: TextField(
                        controller: _pwd2Ctrl,
                        focusNode: _pwd2Focus,
                        obscureText: _obscure,
                        maxLength: 20,
                        style: _inputStyle,
                        cursorColor: AppColors.brand,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.next,
                        keyboardAppearance: Brightness.light,
                        autocorrect: false,
                        enableSuggestions: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        onSubmitted: (_) => _verifyFocus.requestFocus(),
                        decoration: _dec('确认密码'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _RoundField(
                          focused: _verifyFocus.hasFocus,
                          child: TextField(
                            controller: _verifyCtrl,
                            focusNode: _verifyFocus,
                            maxLength: 8,
                            style: _inputStyle,
                            cursorColor: AppColors.brand,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.done,
                            keyboardAppearance: Brightness.light,
                            autocorrect: false,
                            enableSuggestions: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            onSubmitted: (_) => _submit(),
                            decoration: _dec('验证码'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _PressScale(
                        child: GestureDetector(
                          onTap: _captchaLoading ? null : _reloadCaptcha,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 118,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _captchaLoading
                                    ? AppColors.brand
                                    : AppColors.line,
                              ),
                            ),
                            child: _captchaLoading
                                ? const CupertinoActivityIndicator()
                                : (_captcha == null
                                    ? Text(
                                        '刷新',
                                        style: TextStyle(
                                          fontFamily: 'AppSans',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.brand,
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.memory(
                                          _captcha!,
                                          fit: BoxFit.cover,
                                          width: 118,
                                          height: 54,
                                        ),
                                      )),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _fadeSlide(
              animation: a3,
              child: Text(
                _error!,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  color: AppColors.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _fadeSlide(
            animation: a3,
            child: _PressScale(
              child: SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.brand.withValues(alpha: 0.45),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(isReg ? '注册' : '登录'),
                ),
              ),
            ),
          ),
          if (!isReg) ...[
            const SizedBox(height: 12),
            _fadeSlide(
              animation: a3,
              child: _PressScale(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _onQqLogin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      backgroundColor: const Color(0xFFF8F8F8),
                      side: BorderSide.none,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        QqBrandIcon(size: 22),
                        SizedBox(width: 8),
                        Text('QQ 登录'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _fadeSlide(
            animation: a4,
            child: LoginAgreementRow(
              agreed: _agreed,
              onChanged: (v) => setState(() => _agreed = v),
            ),
          ),
          const SizedBox(height: 18),
          _fadeSlide(
            animation: a4,
            child: Center(
              child: GestureDetector(
                onTap: () => _openForm(
                  isReg ? LoginPageMode.login : LoginPageMode.register,
                ),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                      children: [
                        TextSpan(text: isReg ? '已有账号？' : '没有账号？'),
                        TextSpan(
                          text: isReg ? '去登录' : '去注册',
                          style: TextStyle(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
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
        color: AppColors.textHint,
      ),
      counterText: '',
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(
        minWidth: 44,
        minHeight: 44,
      ),
    );
  }
}

class _RoundField extends StatelessWidget {
  const _RoundField({
    required this.focused,
    required this.child,
  });

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      transform: Matrix4.identity()..scale(focused ? 1.01 : 1.0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: focused ? AppColors.brand : const Color(0xFFE8ECEE),
          width: focused ? 1.6 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});

  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
