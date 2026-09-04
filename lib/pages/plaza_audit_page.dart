import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/plaza_models.dart';
import '../services/plaza_api.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/dialogx/dialogx.dart';
import 'plaza_detail_page.dart';
import '../widgets/app_page_route.dart';

/// 管理员 / 编辑：广场帖子审核
class PlazaAuditPage extends StatefulWidget {
  const PlazaAuditPage({super.key});

  @override
  State<PlazaAuditPage> createState() => _PlazaAuditPageState();
}

class _PlazaAuditPageState extends State<PlazaAuditPage> {
  final _api = PlazaApi();
  final _posts = <PlazaPost>[];
  PlazaStats _stats = const PlazaStats();
  bool _loading = true;
  String? _error;
  int _filter = 0; // 默认待审

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
      final results = await Future.wait([
        _api.adminList(status: _filter, pageSize: 50),
        _api.adminStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll((results[0] as PlazaListResult).list);
        _stats = results[1] as PlazaStats;
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

  Future<void> _approve(PlazaPost p) async {
    HapticFeedback.selectionClick();
    try {
      await _api.adminAudit(id: p.id, approve: true);
      DialogX.showSuccess('已通过');
      _load();
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    }
  }

  Future<void> _reject(PlazaPost p) async {
    HapticFeedback.selectionClick();
    final reasonCtrl = TextEditingController(text: '不符合社区规范');
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('拒绝帖子'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: reasonCtrl,
            placeholder: '拒绝原因',
            maxLines: 3,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('拒绝'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true) return;
    try {
      await _api.adminAudit(
        id: p.id,
        approve: false,
        reason: reason.isEmpty ? '不符合社区规范' : reason,
      );
      DialogX.showSuccess('已拒绝');
      _load();
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: Icon(CupertinoIcons.back, color: AppColors.iosBlue),
        ),
        title: const Text(
          '广场审核',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _stat('待审', _stats.pending, const Color(0xFFFF9500)),
                _stat('通过', _stats.approved, const Color(0xFF34C759)),
                _stat('拒绝', _stats.rejected, AppColors.danger),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('待审核', 0),
                _chip('已通过', 1),
                _chip('已拒绝', 2),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _posts.isEmpty
                        ? const Center(
                            child: Text(
                              '暂无内容',
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                color: AppColors.textHint,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                              itemCount: _posts.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = _posts[i];
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F2F7),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.author.displayName,
                                              style: const TextStyle(
                                                fontFamily: 'AppSans',
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            formatAgo(p.createdMs),
                                            style: const TextStyle(
                                              fontFamily: 'AppSans',
                                              fontSize: 12,
                                              color: AppColors.textHint,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.of(context).push(
                                            AppPageRoute(
                                              builder: (_) => PlazaDetailPage(
                                                postId: p.id,
                                                initial: p,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          p.content,
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'AppSans',
                                            fontSize: 15,
                                            color: AppColors.text,
                                          ),
                                        ),
                                      ),
                                      if (p.displayCover.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Image.network(
                                            p.displayCover,
                                            height: 120,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox.shrink(),
                                          ),
                                        ),
                                      ],
                                      if (p.isPending) ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: CupertinoButton(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                                color: const Color(0xFF34C759),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                onPressed: () => _approve(p),
                                                child: const Text(
                                                  '通过',
                                                  style: TextStyle(
                                                    fontFamily: 'AppSans',
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: CupertinoButton(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                                color: AppColors.danger,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                onPressed: () => _reject(p),
                                                child: const Text(
                                                  '拒绝',
                                                  style: TextStyle(
                                                    fontFamily: 'AppSans',
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int n, Color c) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$n',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int status) {
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = status);
          _load();
        },
        labelStyle: TextStyle(
          fontFamily: 'AppSans',
          fontSize: 13,
          color: selected ? Colors.white : AppColors.text,
        ),
        selectedColor: AppColors.iosBlue,
        backgroundColor: const Color(0xFFF2F2F7),
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }
}
