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

/// 我的帖子（含待审/拒绝状态）
class PlazaMyPostsPage extends StatefulWidget {
  const PlazaMyPostsPage({super.key});

  @override
  State<PlazaMyPostsPage> createState() => _PlazaMyPostsPageState();
}

class _PlazaMyPostsPageState extends State<PlazaMyPostsPage> {
  final _api = PlazaApi();
  final _posts = <PlazaPost>[];
  bool _loading = true;
  String? _error;
  int? _filter; // null=全部

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
      final r = await _api.myList(status: _filter, pageSize: 40);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(r.list);
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

  Future<void> _open(PlazaPost p) async {
    final changed = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => PlazaDetailPage(postId: p.id, initial: p),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(PlazaPost p) async {
    HapticFeedback.selectionClick();
    try {
      await _api.delete(p.id);
      DialogX.showSuccess('已删除');
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
          '我的帖子',
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('全部', null),
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
                              '暂无帖子',
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
                                return GestureDetector(
                                  onTap: () => _open(p),
                                  child: Container(
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
                                            Text(
                                              formatAgo(p.createdMs),
                                              style: const TextStyle(
                                                fontFamily: 'AppSans',
                                                fontSize: 12,
                                                color: AppColors.textHint,
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              p.statusLabel,
                                              style: TextStyle(
                                                fontFamily: 'AppSans',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: p.isPending
                                                    ? const Color(0xFFFF9500)
                                                    : p.isApproved
                                                        ? const Color(
                                                            0xFF34C759)
                                                        : AppColors.danger,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          p.content,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'AppSans',
                                            fontSize: 15,
                                            color: AppColors.text,
                                          ),
                                        ),
                                        if (p.rejectReason.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            p.rejectReason,
                                            style: const TextStyle(
                                              fontFamily: 'AppSans',
                                              fontSize: 12,
                                              color: AppColors.danger,
                                            ),
                                          ),
                                        ],
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: CupertinoButton(
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _delete(p),
                                            child: const Text(
                                              '删除',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppColors.danger,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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

  Widget _chip(String label, int? status) {
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
