import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/huihuo_panel_api.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/dialogx/dialogx.dart';

/// 兑福利 / 兑换码
class RedeemPage extends StatefulWidget {
  const RedeemPage({super.key});

  @override
  State<RedeemPage> createState() => _RedeemPageState();
}

class _RedeemPageState extends State<RedeemPage> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    if (!CmsAuthController.instance.isLoggedIn) {
      final ok = await showAuthSheet(context);
      if (!ok || !mounted) return;
    }
    final code = _ctrl.text.trim();
    if (code.isEmpty) {
      DialogX.showWarning('请输入兑换码');
      return;
    }
    final user = CmsAuthController.instance.user;
    if (user == null || user.userId <= 0) {
      DialogX.showWarning('请先登录');
      return;
    }

    setState(() => _busy = true);
    DialogX.showWait('兑换中…');
    try {
      final r = await HuihuoPanelApi.redeemCode(
        code: code,
        userId: user.userId,
        userName: user.userName,
      );
      DialogX.dismiss();
      _ctrl.clear();
      try {
        await CmsAuthController.instance.refreshProfile();
      } catch (_) {}
      if (!mounted) return;
      DialogX.showSuccess('${r.msg}\n${r.rewardText}');
    } catch (e) {
      DialogX.dismiss();
      final msg = '$e'.replaceFirst('Bad state: ', '').replaceFirst('StateError: ', '');
      DialogX.showError(msg.isEmpty ? '兑换失败' : msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = AppPalette.page(context);
    final text = AppPalette.text(context);
    final secondary = AppPalette.textSecondary(context);
    final surface = AppPalette.surface(context);
    final line = AppPalette.line(context);
    final user = CmsAuthController.instance.user;

    return CupertinoPageScaffold(
      backgroundColor: page,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: surface,
        border: Border(bottom: BorderSide(color: line, width: 0.5)),
        middle: Text(
          '兑福利',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '兑换码领福利',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '输入活动兑换码，领取积分或会员天数',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: secondary,
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '当前：${user.userName.isEmpty ? '会员' : user.userName}'
                      ' · 积分 ${user.points}',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextField(
                    controller: _ctrl,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: text,
                    ),
                    decoration: InputDecoration(
                      hintText: '请输入兑换码',
                      hintStyle: TextStyle(
                        fontFamily: 'AppSans',
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: AppPalette.textHint(context),
                      ),
                      filled: true,
                      fillColor: AppPalette.softFill(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 16,
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
                          : const Text('立即兑换'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '说明',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '· 每个兑换码仅可使用一次\n'
              '· 需登录会员账号后兑换\n'
              '· 积分 / 会员奖励到账可能有短暂延迟，下拉个人中心刷新即可',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                height: 1.55,
                color: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
