import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../services/douyin_api.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';
import 'account_manage_page.dart';
import '../widgets/app_page_route.dart';

/// 选择好友并自动续火花
class SparkRenewPage extends StatefulWidget {
  const SparkRenewPage({super.key, this.accountId});

  final int? accountId;

  @override
  State<SparkRenewPage> createState() => _SparkRenewPageState();
}

class _SparkRenewPageState extends State<SparkRenewPage> {
  final _api = DouyinApi();
  final _msgCtrl = TextEditingController();

  List<DouyinAccount> _accounts = [];
  DouyinAccount? _account;
  List<DouyinSparkFriend> _friends = [];
  final Set<String> _checked = {};
  int _flame = 0;
  int _flameCostPer = 1;
  bool _loading = true;
  bool _renewing = false;
  String? _error;
  String _hint = '';

  String _keyOf(DouyinSparkFriend f) {
    if (f.conversationId.isNotEmpty) return f.conversationId;
    if (f.peerUid.isNotEmpty) return 'uid:${f.peerUid}';
    return 'nick:${f.nickname}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await _api.myList();
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _accounts = [];
          _account = null;
          _friends = [];
          _loading = false;
          _error = '请先绑定抖音账号';
        });
        return;
      }
      DouyinAccount? selected;
      if (widget.accountId != null) {
        for (final a in accounts) {
          if (a.id == widget.accountId) {
            selected = a;
            break;
          }
        }
      }
      selected ??= accounts.first;
      setState(() {
        _accounts = accounts;
        _account = selected;
      });
      await _loadFriends();
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

  Future<void> _loadFriends() async {
    final acc = _account;
    if (acc == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.sparkFriends(accountId: acc.id);
      if (!mounted) return;
      _checked
        ..clear()
        ..addAll(res.list.where((e) => e.selected).map(_keyOf));
      setState(() {
        _friends = res.list;
        _flame = res.flame;
        _flameCostPer = res.flameCostPer > 0 ? res.flameCostPer : 1;
        _hint = res.hint;
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
        _error = '拉取好友失败';
      });
    }
  }

  Future<void> _pickAccount() async {
    if (_accounts.length <= 1) return;
    HapticFeedback.selectionClick();
    final picked = await showCupertinoModalPopup<DouyinAccount>(
      context: context,
      builder: (ctx) {
        return CupertinoActionSheet(
          title: const Text('选择抖音账号'),
          actions: [
            for (final a in _accounts)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, a),
                child: Text(a.nickname.isEmpty ? '账号#${a.id}' : a.nickname),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _account = picked);
    await _loadFriends();
  }

  void _toggle(DouyinSparkFriend f) {
    HapticFeedback.selectionClick();
    final k = _keyOf(f);
    setState(() {
      if (_checked.contains(k)) {
        _checked.remove(k);
      } else {
        _checked.add(k);
      }
    });
  }

  void _selectAll(bool all) {
    HapticFeedback.selectionClick();
    setState(() {
      _checked.clear();
      if (all) {
        _checked.addAll(_friends.map(_keyOf));
      }
    });
  }

  List<DouyinSparkFriend> get _selectedFriends =>
      _friends.where((f) => _checked.contains(_keyOf(f))).toList();

  Future<void> _save() async {
    final acc = _account;
    if (acc == null) return;
    final targets = _selectedFriends;
    try {
      await _api.sparkTargetsSave(accountId: acc.id, targets: targets);
      if (!mounted) return;
      DialogX.showSuccess('已保存 ${targets.length} 位续火好友');
      await _loadFriends();
    } on ApiException catch (e) {
      DialogX.showWarning(e.message);
    } catch (_) {
      DialogX.showWarning('保存失败');
    }
  }

  Future<void> _renew() async {
    final acc = _account;
    if (acc == null) return;
    final targets = _selectedFriends;
    if (targets.isEmpty) {
      DialogX.showWarning('请先勾选至少一位好友');
      return;
    }
    final need = targets.length * _flameCostPer;
    if (_flame < need) {
      DialogX.showWarning(
        '火苗不足：续火 ${targets.length} 人需要 $need 火苗（每人 $_flameCostPer），当前 $_flame',
      );
      return;
    }

    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('立即续火'),
        content: Text(
          '将向 ${targets.length} 位好友发送私信（成功每人消耗 $_flameCostPer 火苗）。\n'
          '由服务器代发，手机不会弹出浏览器。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _renewing = true);
    try {
      await _api.sparkTargetsSave(accountId: acc.id, targets: targets);
      final res = await _api.sparkRenew(
        accountId: acc.id,
        message: _msgCtrl.text.trim(),
        flameCost: true,
      );
      if (!mounted) return;
      setState(() => _flame = res.flame);
      final msg = res.hint.isNotEmpty
          ? '${res.hint}\n成功 ${res.okCount} / 失败 ${res.failCount}'
          : '成功 ${res.okCount} / 失败 ${res.failCount}，剩余火苗 ${res.flame}';
      if (res.okCount > 0) {
        DialogX.showSuccess(msg);
      } else {
        DialogX.showWarning(msg);
      }
      await _loadFriends();
    } on ApiException catch (e) {
      DialogX.showWarning(e.message);
    } catch (_) {
      DialogX.showWarning('续火失败');
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc = _account;
    final title = acc == null
        ? '续火花'
        : (acc.nickname.isNotEmpty ? '${acc.nickname} · 续火花' : '续火花');

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        middle: GestureDetector(
          onTap: _accounts.length > 1 ? _pickAccount : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_accounts.length > 1) ...[
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_down, size: 14),
              ],
            ],
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _loading || _renewing ? null : _loadFriends,
          child: const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '火苗 $_flame · 每人 $_flameCostPer · 已选 ${_checked.length}'
                        '${_hint.isEmpty ? '' : ' · $_hint'}',
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                      const SizedBox(height: 10),
                      CupertinoTextField(
                        controller: _msgCtrl,
                        placeholder: '续火文案（可空=随机，如：你好呀🔥）',
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _ChipBtn(
                            label: '全选',
                            onTap: () => _selectAll(true),
                          ),
                          const SizedBox(width: 8),
                          _ChipBtn(
                            label: '清空',
                            onTap: () => _selectAll(false),
                          ),
                          const Spacer(),
                          _ChipBtn(label: '保存勾选', onTap: _save),
                          const SizedBox(width: 8),
                          _ChipBtn(
                            label: '立即续火',
                            primary: true,
                            onTap: _renewing ? null : _renew,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
            if (_renewing)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(radius: 14, color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        '正在续火，请稍候…',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_error != null && _friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 16),
              if (_error!.contains('绑定'))
                CupertinoButton.filled(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      AppPageRoute<void>(
                        builder: (_) => const AccountManagePage(),
                      ),
                    );
                    if (mounted) _bootstrap();
                  },
                  child: const Text('去绑定'),
                )
              else
                CupertinoButton(
                  onPressed: _bootstrap,
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }
    if (_friends.isEmpty) {
      return Center(
        child: Text(
          '暂无私信好友',
          style: TextStyle(fontFamily: 'AppSans', color: Color(0xFF8E8E93)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => SizedBox(height: 8),
      itemBuilder: (context, i) {
        final f = _friends[i];
        final checked = _checked.contains(_keyOf(f));
        return Material(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _toggle(f),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Icon(
                    checked
                        ? CupertinoIcons.checkmark_square_fill
                        : CupertinoIcons.square,
                    color: checked ? AppColors.iosBlue : const Color(0xFFC7C7CC),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: f.avatarUrl.isNotEmpty
                          ? Image.network(
                              f.avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const ColoredBox(color: Color(0xFFD1D1D6)),
                            )
                          : const ColoredBox(color: Color(0xFFD1D1D6)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.lastMessage.isEmpty ? '暂无最近消息' : f.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        f.sparkDays > 0 || f.spark
                            ? '🔥${f.sparkDays > 0 ? f.sparkDays : ''}'
                            : '无火花',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          color: f.sparkDays > 0 || f.spark
                              ? const Color(0xFFC2410C)
                              : const Color(0xFF8E8E93),
                        ),
                      ),
                      if (f.lastStatus.isNotEmpty)
                        Text(
                          f.lastStatus,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 11,
                            color: f.lastStatus == 'ok'
                                ? const Color(0xFF059669)
                                : const Color(0xFFB91C1C),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChipBtn extends StatelessWidget {
  const _ChipBtn({
    required this.label,
    this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.iosBlue : const Color(0xFFE5E5EA),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: primary ? Colors.white : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
