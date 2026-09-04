import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../services/douyin_api.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/douyin_qr_bind_sheet.dart';
import '../widgets/douyin_web_bind_sheet.dart';

/// 管理账号：绑定方式 + 已绑抖音列表
class AccountManagePage extends StatefulWidget {
  const AccountManagePage({super.key});

  @override
  State<AccountManagePage> createState() => _AccountManagePageState();
}

class _AccountManagePageState extends State<AccountManagePage> {
  final _api = DouyinApi();
  List<DouyinAccount> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.myList();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败';
        _loading = false;
      });
    }
  }

  Future<void> _onQrBind() async {
    HapticFeedback.selectionClick();
    final ok = await showDouyinQrBindSheet(context);
    if (ok == true) await _reload();
  }

  Future<void> _onWebBind() async {
    HapticFeedback.selectionClick();
    final ok = await showDouyinWebBindSheet(context);
    if (ok == true) await _reload();
  }

  Future<void> _unbind(DouyinAccount a) async {
    final yes = await DialogX.confirm(
      context: context,
      title: '解除绑定',
      message: '确定解绑「${a.nickname}」？',
      confirmLabel: '解绑',
      destructive: true,
    );
    if (yes != true) return;
    DialogX.showWait('解绑中…');
    try {
      await _api.unbind(a.id);
      DialogX.showSuccess('已解绑');
      await _reload();
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    } catch (_) {
      DialogX.showError('解绑失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return CupertinoPageScaffold(
      backgroundColor: AppColors.white,
      child: Material(
        type: MaterialType.transparency,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, top + 4, 16, 8),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.back,
                            color: AppColors.iosBlue,
                            size: 22,
                          ),
                          Text(
                            '我的',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 17,
                              color: AppColors.iosBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _loading ? null : _reload,
                      child: Icon(
                        CupertinoIcons.refresh,
                        color: AppColors.iosBlue,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  '管理账号',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '绑定方式',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _BindMethodCard(
                            icon: CupertinoIcons.qrcode_viewfinder,
                            title: '扫码绑定',
                            subtitle: '抖音扫一扫登录',
                            onTap: _onQrBind,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BindMethodCard(
                            icon: CupertinoIcons.globe,
                            title: '网页绑定',
                            subtitle: '应用内登录取 Cookie',
                            onTap: _onWebBind,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      '已绑定抖音',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 15,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: _reload,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_list.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, 0),
                  child: Text(
                    '暂无绑定账号\n请选择上方方式完成绑定',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList.separated(
                  itemCount: _list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final a = _list[i];
                    return _AccountTile(
                      account: a,
                      onUnbind: () => _unbind(a),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BindMethodCard extends StatelessWidget {
  const _BindMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.iosBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.onUnbind});

  final DouyinAccount account;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 48,
              height: 48,
              child: account.avatarUrl.isNotEmpty
                  ? Image.network(
                      account.avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFFD1D1D6),
                        child: Icon(
                          CupertinoIcons.person_fill,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const ColoredBox(
                      color: Color(0xFFD1D1D6),
                      child: Icon(
                        CupertinoIcons.person_fill,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.nickname,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  account.uniqueId.isNotEmpty
                      ? '抖音号 ${account.uniqueId}'
                      : 'UID ${account.douyinUid}',
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: onUnbind,
            child: const Text(
              '解绑',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 15,
                color: Color(0xFFFF3B30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
