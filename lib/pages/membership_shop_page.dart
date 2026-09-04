import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/membership_models.dart';
import '../services/membership_api.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';

/// 开通 / 续费会员
class MembershipShopPage extends StatefulWidget {
  const MembershipShopPage({super.key});

  @override
  State<MembershipShopPage> createState() => _MembershipShopPageState();
}

class _MembershipShopPageState extends State<MembershipShopPage> {
  final _api = MembershipApi();
  bool _loading = true;
  bool _buying = false;
  String? _error;
  List<VipPackage> _list = const [];
  int? _selectedId;
  int _freeMax = 3;
  int _vipMax = 20;
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
      final res = await _api.vipCatalog();
      if (!mounted) return;
      if (res.me != null) {
        await AuthController.instance.applyUser(res.me!);
      }
      setState(() {
        _list = res.list;
        _freeMax = res.freeMaxAccounts;
        _vipMax = res.vipMaxAccounts;
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

  VipPackage? get _selected {
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
        title: Text('开通 ${pkg.name}'),
        content: Text(
          _mockPay
              ? '确认支付 ¥${pkg.priceYuan}？\n（当前为模拟支付，确认后立即到账）'
              : '将创建订单 ¥${pkg.priceYuan}，支付后由管理员核销到账。',
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
      final res = await _api.createOrder(type: 'vip', packageId: pkg.id);
      if (res.user != null) {
        await AuthController.instance.applyUser(res.user!);
      } else {
        await AuthController.instance.refreshMe();
      }
      DialogX.showSuccess(res.message.isNotEmpty ? res.message : '开通成功');
      if (mounted) Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      DialogX.showWarning(e.message);
    } catch (_) {
      DialogX.showWarning('开通失败');
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthController.instance.user;
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
                    '哇TV会员',
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
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.isVip == true
                                      ? (user!.vipLabel)
                                      : '开通哇TV会员',
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  user?.isVip == true
                                      ? (user!.vipExpireAt.isNotEmpty
                                          ? '有效期至 ${user.vipExpireAt}'
                                          : '永久会员')
                                      : '更多绑号额度 · 续火花权益优先',
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 13,
                                    color: Color(0xFFAEAEB2),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '免费最多绑 $_freeMax 个账号 · 会员最多 $_vipMax 个',
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 12,
                                    color: Color(0xFFE8A87C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            '选择套餐',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final p in _list) ...[
                            _PkgTile(
                              selected: _selectedId == p.id,
                              title: p.name,
                              subtitle: [
                                p.labelDays.isNotEmpty
                                    ? p.labelDays
                                    : (p.days > 0 ? '${p.days} 天' : '永久'),
                                if (p.flameBonus > 0) '赠 ${p.flameBonus} 火苗',
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
                  child: Text(_mockPay ? '立即开通' : '提交订单'),
                ),
              ),
            ),
          ),
        ],
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
