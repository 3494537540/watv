import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/plaza_models.dart';
import '../services/plaza_api.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/dialogx/dialogx.dart';

class PlazaDetailPage extends StatefulWidget {
  const PlazaDetailPage({super.key, required this.postId, this.initial});

  final int postId;
  final PlazaPost? initial;

  @override
  State<PlazaDetailPage> createState() => _PlazaDetailPageState();
}

class _PlazaDetailPageState extends State<PlazaDetailPage> {
  final _api = PlazaApi();
  PlazaPost? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _post == null;
      _error = null;
    });
    try {
      final p = await _api.get(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = p;
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

  Future<void> _toggleLike() async {
    if (!AuthController.instance.isLoggedIn) {
      await showAuthSheet(context);
      return;
    }
    final p = _post;
    if (p == null || !p.isApproved) return;
    HapticFeedback.selectionClick();
    try {
      final r = await _api.like(p.id);
      if (!mounted) return;
      setState(() {
        _post = p.copyWith(liked: r.liked, likeCount: r.likeCount);
      });
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    }
  }

  Future<void> _delete() async {
    final ok = await DialogX.confirm(
      context: context,
      title: '删除帖子',
      message: '确定删除这条帖子吗？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await _api.delete(widget.postId);
      DialogX.showSuccess('已删除');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.white,
        systemNavigationBarDividerColor: AppColors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).maybePop(),
            child: Icon(CupertinoIcons.back, color: AppColors.iosBlue),
          ),
          title: const Text(
            '帖子详情',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontWeight: FontWeight.w600,
              color: AppColors.text,
              fontSize: 17,
            ),
          ),
          actions: [
            if (p?.isMine == true)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: _delete,
                child: const Icon(
                  CupertinoIcons.trash,
                  color: AppColors.danger,
                  size: 20,
                ),
              ),
          ],
        ),
        body: ColoredBox(
          color: AppColors.white,
          child: _loading
              ? const Center(child: CupertinoActivityIndicator())
              : _error != null && p == null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          color: AppColors.textHint,
                        ),
                      ),
                    )
                  : p == null
                      ? const SizedBox.shrink()
                      : ListView(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
                          children: [
                            Row(
                              children: [
                                _Avatar(author: p.author),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.author.displayName,
                                        style: const TextStyle(
                                          fontFamily: 'AppSans',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: AppColors.text,
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
                                ),
                                if (!p.isApproved)
                                  _StatusChip(
                                    label: p.statusLabel.isNotEmpty
                                        ? p.statusLabel
                                        : (p.isPending ? '待审核' : '已拒绝'),
                                    color: p.isPending
                                        ? const Color(0xFFFF9500)
                                        : AppColors.danger,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              p.content,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 16,
                                height: 1.45,
                                color: AppColors.text,
                              ),
                            ),
                            if (p.rejectReason.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                '拒绝原因：${p.rejectReason}',
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 13,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                            if (p.images.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              ...p.images.map(
                                (url) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder: (_, __, ___) => Container(
                                        height: 160,
                                        color: const Color(0xFFF2F2F7),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          CupertinoIcons.photo,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            if (p.isApproved)
                              GestureDetector(
                                onTap: _toggleLike,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  children: [
                                    Icon(
                                      p.liked
                                          ? CupertinoIcons.heart_fill
                                          : CupertinoIcons.heart,
                                      size: 22,
                                      color: p.liked
                                          ? const Color(0xFFFF2D55)
                                          : const Color(0xFF8E8E93),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${p.likeCount}',
                                      style: const TextStyle(
                                        fontFamily: 'AppSans',
                                        fontSize: 15,
                                        color: Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.author});
  final PlazaAuthor author;

  @override
  Widget build(BuildContext context) {
    final letter = author.displayName.characters.isNotEmpty
        ? author.displayName.characters.first
        : '?';
    if (author.avatar.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(author.avatar),
        onBackgroundImageError: (_, __) {},
        backgroundColor: const Color(0xFF007AFF),
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFF007AFF),
      child: Text(
        letter,
        style: const TextStyle(
          fontFamily: 'AppSans',
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
