import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/membership_models.dart';
import '../pages/redeem_page.dart';
import '../services/maccms_user_api.dart';
import '../services/membership_api.dart';
import '../state/auth_controller.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_page_route.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/dialogx/dialogx.dart';

/// 会员开通弹窗（底部浮层，高度随内容，贴底无大留白）
Future<void> showMembershipShopSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (ctx) {
      return const MembershipShopPage(asSheet: true);
    },
  );
}

/// 开通 / 续费会员（对接苹果 CMS `user/upgrade` 积分升级）
class MembershipShopPage extends StatefulWidget {
  const MembershipShopPage({super.key, this.asSheet = false});

  final bool asSheet;

  @override
  State<MembershipShopPage> createState() => _MembershipShopPageState();
}

class _MembershipShopPageState extends State<MembershipShopPage> {
  bool _loading = true;
  bool _buying = false;
  String? _error;
  List<CmsVipPlan> _list = const [];
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _keyOf(CmsVipPlan p) => '${p.groupId}|${p.long}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!CmsAuthController.instance.isLoggedIn) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = '请先登录后再开通会员';
        });
        return;
      }
      try {
        await CmsAuthController.instance.refreshProfile();
      } catch (_) {}
      final plans =
          await CmsAuthController.instance.api.fetchVipPlans();
      if (!mounted) return;
      setState(() {
        _list = plans;
        _selectedKey = plans.isNotEmpty ? _keyOf(plans.first) : null;
        _loading = false;
        if (plans.isEmpty) {
          _error = '暂无会员套餐，请稍后再试或使用兑换码';
        }
      });
    } on CmsUserException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  CmsVipPlan? get _selected {
    final key = _selectedKey;
    if (key == null) return null;
    for (final p in _list) {
      if (_keyOf(p) == key) return p;
    }
    return null;
  }

  Future<void> _buy() async {
    final pkg = _selected;
    if (pkg == null) return;
    if (!CmsAuthController.instance.isLoggedIn) {
      final ok = await showAuthSheet(context);
      if (!ok || !mounted) return;
      await _load();
      return;
    }

    final points = CmsAuthController.instance.user?.points ?? 0;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('开通 ${pkg.displayName}'),
        content: Text(
          '将消耗 ${pkg.points} 积分开通「${pkg.groupName} · ${pkg.longLabel}」。\n'
          '当前积分：$points',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认开通'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (points < pkg.points) {
      DialogX.showWarning('积分不足（需要 ${pkg.points}，当前 $points）');
      return;
    }

    setState(() => _buying = true);
    DialogX.showWait('开通中…');
    try {
      final msg = await CmsAuthController.instance.api.upgradeVip(
        groupId: pkg.groupId,
        long: pkg.long,
      );
      try {
        await CmsAuthController.instance.refreshProfile();
      } catch (_) {}
      DialogX.showSuccess(msg.isEmpty ? '开通成功' : msg);
      if (mounted) Navigator.of(context).maybePop();
    } on CmsUserException catch (e) {
      DialogX.showWarning(e.message);
    } catch (_) {
      DialogX.showWarning('开通失败');
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<void> _openRedeem() async {
    await Navigator.of(context).push(
      AppPageRoute<void>(builder: (_) => const RedeemPage()),
    );
    try {
      await CmsAuthController.instance.refreshProfile();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = CmsAuthController.instance.user;
    final sheet = widget.asSheet;
    final top = sheet ? 0.0 : MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final vip = user?.isVip == true;
    final expire = user == null
        ? null
        : CmsUser.formatVipEndDate(user.endTime);
    final points = user?.points ?? 0;

    final body = Column(
      mainAxisSize: sheet ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (sheet) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 2),
        ] else
          SizedBox(height: top),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 12, 6),
          child: Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Icon(
                  sheet ? CupertinoIcons.xmark : CupertinoIcons.back,
                  color: AppColors.text,
                  size: 20,
                ),
              ),
              const Expanded(
                child: Text(
                  '哇TV会员',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: _openRedeem,
                child: Text(
                  '兑换码',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (_error != null && _list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    color: Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: () async {
                    if (!CmsAuthController.instance.isLoggedIn) {
                      final ok = await showAuthSheet(context);
                      if (!ok || !mounted) return;
                    }
                    await _load();
                  },
                  child: Text(
                    CmsAuthController.instance.isLoggedIn ? '重试' : '去登录',
                  ),
                ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vip
                              ? ((user?.groupName.trim().isNotEmpty == true)
                                  ? user!.groupName
                                  : 'VIP会员')
                              : '开通哇TV会员',
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          vip
                              ? (expire == null
                                  ? '已开通'
                                  : (expire == 'permanent'
                                      ? '永久有效'
                                      : (expire == 'expired'
                                          ? '已过期，请续费'
                                          : expire)))
                              : '积分升级 · 或用兑换码',
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '积分 $points',
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB7791F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择套餐',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final w = (constraints.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final p in _list)
                      SizedBox(
                        width: w,
                        child: _VipPlanCard(
                          selected: _selectedKey == _keyOf(p),
                          title: p.groupName,
                          period: p.longLabel,
                          points: p.points,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedKey = _keyOf(p));
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 10 + (sheet ? bottom : 0)),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _buying || _selected == null ? null : _buy,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  disabledBackgroundColor:
                      AppColors.brand.withValues(alpha: 0.35),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _selected == null
                      ? '积分开通'
                      : '积分开通 · ${_selected!.points}',
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (sheet) {
      return Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: body,
      );
    }
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      child: SafeArea(top: false, child: body),
    );
  }
}

/// 套餐小卡片（两列）
class _VipPlanCard extends StatelessWidget {
  const _VipPlanCard({
    required this.selected,
    required this.title,
    required this.period,
    required this.points,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String period;
  final int points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? AppColors.brand : const Color(0xFFE8E8ED);
    final bg = selected
        ? AppColors.brand.withValues(alpha: 0.10)
        : const Color(0xFFF7F8FA);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: selected ? 1.8 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.brand : AppColors.text,
                    ),
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.brand : Colors.transparent,
                    shape: BoxShape.circle,
                    border: selected
                        ? null
                        : Border.all(color: const Color(0xFFC7C7CC), width: 1.5),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              period,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$points',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.brand : AppColors.text,
                      height: 1,
                    ),
                  ),
                  const TextSpan(
                    text: ' 积分',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8E8E93),
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

/// 充值火苗
class FlameShopPage extends StatefulWidget {
  const FlameShopPage({super.key});

  @override
  State<FlameShopPage> createState() => _FlameShopPageState();
}

class _FlameShopPageState extends State<FlameShopPage> {
  final _api = MembershipApi();
  bool _loading = true;
  bool _buying = false;
  String? _error;
  List<FlamePackage> _list = const [];
  int? _selectedId;
  int _cost = 1;
  bool _mockPay = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.flameCatalog();
      if (!mounted) return;
      if (res.me != null) {
        await AuthController.instance.applyUser(res.me!);
      }
      setState(() {
        _list = res.list;
        _cost = res.flameCostSparkRenew;
        _mockPay = res.mockPay;
        _selectedId = res.list.isNotEmpty ? res.list.first.id : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  FlamePackage? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final p in _list) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _buy() async {
    final pkg = _selected;
    if (pkg == null) return;

    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('充值 ${pkg.name}'),
        content: Text(
          _mockPay
              ? '确认支付 ¥${pkg.priceYuan} 获得 ${pkg.flameAmount} 火苗？\n（模拟支付，确认后立即到账）'
              : '将创建订单，支付后由管理员核销到账。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _buying = true);
    DialogX.showWait('处理中…');
    try {
      final res = await _api.createOrder(type: 'flame', packageId: pkg.id);
      if (res.user != null) {
        await AuthController.instance.applyUser(res.user!);
      } else {
        await AuthController.instance.refreshMe();
      }
      DialogX.showSuccess(res.message.isNotEmpty ? res.message : '充值成功');
      if (mounted) Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      DialogX.showWarning(e.message);
    } catch (_) {
      DialogX.showWarning('充值失败');
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flame = AuthController.instance.user?.flame ?? 0;
    final top = MediaQuery.paddingOf(context).top;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      child: Column(
        children: [
          SizedBox(height: top),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Icon(CupertinoIcons.back, color: AppColors.text),
                ),
                const Expanded(
                  child: Text(
                    '充值火苗',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : (_error != null)
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!,
                                style:
                                    const TextStyle(color: Color(0xFF8E8E93))),
                            CupertinoButton(
                                onPressed: _load, child: const Text('重试')),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.flame_fill,
                                    color: Color(0xFFFF6B35), size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '当前火苗 $flame',
                                        style: const TextStyle(
                                          fontFamily: 'AppSans',
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '续火花成功每人消耗 $_cost 火苗',
                                        style: const TextStyle(
                                          fontFamily: 'AppSans',
                                          fontSize: 13,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          for (final p in _list) ...[
                            _PkgTile(
                              selected: _selectedId == p.id,
                              title: p.name,
                              subtitle: [
                                '${p.flameAmount} 火苗',
                                if (p.remark.isNotEmpty) p.remark,
                              ].join(' · '),
                              price: '¥${p.priceYuan}',
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedId = p.id);
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _buying || _selectedId == null ? null : _buy,
                  child: Text(_mockPay ? '立即充值' : '提交订单'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PkgTile extends StatelessWidget {
  const _PkgTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.iosBlue : const Color(0xFFE5E5EA),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected ? AppColors.iosBlue : const Color(0xFFC7C7CC),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              price,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
