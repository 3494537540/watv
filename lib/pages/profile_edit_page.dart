import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';

/// 编辑个人资料
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _nickname;
  late final TextEditingController _mobile;
  late final TextEditingController _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final u = AuthController.instance.user;
    _nickname = TextEditingController(text: u?.nickname ?? '');
    _mobile = TextEditingController(text: u?.mobile ?? '');
    _avatar = TextEditingController(text: u?.avatar ?? '');
  }

  @override
  void dispose() {
    _nickname.dispose();
    _mobile.dispose();
    _avatar.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthController.instance.updateProfile(
        nickname: _nickname.text.trim(),
        mobile: _mobile.text.trim(),
        avatar: _avatar.text.trim(),
      );
      DialogX.showSuccess('资料已更新');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    } catch (_) {
      DialogX.showError('更新失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthController.instance.user;
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      navigationBar: CupertinoNavigationBar(
        middle: Text('编辑资料'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _busy ? null : _save,
          child: _busy
              ? const CupertinoActivityIndicator()
              : Text(
                  '保存',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.iosBlue,
                  ),
                ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            Center(
              child: ClipOval(
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: (_avatar.text.trim().isNotEmpty)
                      ? Image.network(
                          _avatar.text.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0xFFD1D1D6),
                            child: Icon(
                              CupertinoIcons.person_fill,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const ColoredBox(
                          color: Color(0xFFD1D1D6),
                          child: Icon(
                            CupertinoIcons.person_fill,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                user == null ? '' : '@${user.username}',
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  color: Color(0xFF8E8E93),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _FieldCard(
              children: [
                _EditRow(
                  label: '昵称',
                  child: TextField(
                    controller: _nickname,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      color: AppColors.text,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '显示昵称',
                      isDense: true,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E5EA)),
                _EditRow(
                  label: '手机',
                  child: TextField(
                    controller: _mobile,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      color: AppColors.text,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '手机号（选填）',
                      isDense: true,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E5EA)),
                _EditRow(
                  label: '头像',
                  child: TextField(
                    controller: _avatar,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      color: AppColors.text,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '头像 URL',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '邮箱与用户名由账号系统管理，如需改密请使用「修改密码」。',
                style: TextStyle(
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

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 15,
                color: AppColors.text,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 修改密码
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _old = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _old.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_old.text.isEmpty || _next.text.length < 6) {
      DialogX.showWarning('请填写完整，新密码至少 6 位');
      return;
    }
    if (_next.text != _confirm.text) {
      DialogX.showWarning('两次新密码不一致');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthController.instance.changePassword(
        oldPassword: _old.text,
        newPassword: _next.text,
      );
      DialogX.showSuccess('密码已修改');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    } catch (_) {
      DialogX.showError('修改失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      navigationBar: const CupertinoNavigationBar(
        middle: Text('修改密码'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _PwdField(
                    controller: _old,
                    hint: '当前密码',
                    obscure: _obscure,
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E5EA)),
                  _PwdField(
                    controller: _next,
                    hint: '新密码',
                    obscure: _obscure,
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E5EA)),
                  _PwdField(
                    controller: _confirm,
                    hint: '确认新密码',
                    obscure: _obscure,
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                child: Text(
                  _obscure ? '显示密码' : '隐藏密码',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    color: AppColors.iosBlue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.text,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _busy
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        '确认修改',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PwdField extends StatelessWidget {
  const _PwdField({
    required this.controller,
    required this.hint,
    required this.obscure,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(
        fontFamily: 'AppSans',
        fontSize: 16,
        color: AppColors.text,
      ),
      decoration: InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
