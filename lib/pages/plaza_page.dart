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
import 'plaza_audit_page.dart';
import 'plaza_compose_page.dart';
import 'plaza_detail_page.dart';
import 'plaza_my_posts_page.dart';
import '../widgets/app_page_route.dart';

/// 广场：社区发帖瀑布流（已审核通过）
class PlazaPage extends StatefulWidget {
  const PlazaPage({super.key});

  @override
  State<PlazaPage> createState() => _PlazaPageState();
}

class _PlazaPageState extends State<PlazaPage> {
  final _api = PlazaApi();
  final _posts = <PlazaPost>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  int _pending = 0;

  bool get _isStaff {
    final role = AuthController.instance.user?.role ?? '';
    return role == 'admin' || role == 'editor';
  }

  @override
  void initState() {
    super.initState();
    AuthController.instance.addListener(_onAuth);
    _load(reset: true);
  }

  @override
  void dispose() {
    AuthController.instance.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    if (mounted) {
      _load(reset: true);
      if (_isStaff) _refreshPending();
    }
  }

  Future<void> _refreshPending() async {
    if (!_isStaff) return;
    try {
      final s = await _api.adminStats();
      if (mounted) setState(() => _pending = s.pending);
    } catch (_) {}
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      if (_loadingMore || _posts.length >= _total) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = reset ? 1 : _page + 1;
      final r = await _api.list(page: page, pageSize: 20);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _posts
            ..clear()
            ..addAll(r.list);
        } else {
          _posts.addAll(r.list);
        }
        _page = page;
        _total = r.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      if (_isStaff) _refreshPending();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = '加载失败';
      });
    }
  }

  Future<bool> _ensureLogin() async {
    if (AuthController.instance.isLoggedIn) return true;
    await showAuthSheet(context);
    return AuthController.instance.isLoggedIn;
  }

  Future<void> _compose() async {
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    final ok = await showPlazaComposeSheet(context);
    if (ok == true) {
      DialogX.showSuccess('审核通过后会显示在广场');
    }
  }

  Future<void> _openMy() async {
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => const PlazaMyPostsPage()),
    );
    _load(reset: true);
  }

  Future<void> _openAudit() async {
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => const PlazaAuditPage()),
    );
    _load(reset: true);
  }

  Future<void> _toggleLike(int index) async {
    if (!await _ensureLogin()) return;
    final p = _posts[index];
    HapticFeedback.selectionClick();
    try {
      final r = await _api.like(p.id);
      if (!mounted) return;
      setState(() {
        _posts[index] = p.copyWith(liked: r.liked, likeCount: r.likeCount);
      });
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    }
  }

  Future<void> _openDetail(PlazaPost p) async {
    final changed = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => PlazaDetailPage(postId: p.id, initial: p),
      ),
    );
    if (changed == true) _load(reset: true);
  }

  double _coverHeight(PlazaPost p) {
    final h = 140.0 + (p.id % 5) * 18.0;
    if (p.images.isEmpty) return 96;
    return h;
  }

  Color _fallbackColor(PlazaPost p) {
    const colors = [
      Color(0xFF5AC8FA),
      Color(0xFFFF9500),
      Color(0xFFAF52DE),
      Color(0xFF34C759),
      Color(0xFF007AFF),
      Color(0xFFFF2D55),
      Color(0xFF5856D6),
    ];
    return colors[p.id % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final left = <(int, PlazaPost)>[];
    final right = <(int, PlazaPost)>[];
    for (var i = 0; i < _posts.length; i++) {
      (i.isEven ? left : right).add((i, _posts[i]));
    }

    return Stack(
      children: [
        CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: () => _load(reset: true)),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, top + 12, 12, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '广场',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                              color: AppColors.text,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '看看大家在聊什么',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 15,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.all(8),
                      onPressed: _openMy,
                      child: const Icon(
                        CupertinoIcons.person_crop_square,
                        color: AppColors.text,
                      ),
                    ),
                    if (_isStaff)
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        onPressed: _openAudit,
                        child: Badge(
                          isLabelVisible: _pending > 0,
                          label: Text('$_pending'),
                          child: const Icon(
                            CupertinoIcons.checkmark_shield,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          color: AppColors.textHint,
                        ),
                      ),
                      CupertinoButton(
                        onPressed: () => _load(reset: true),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_posts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '还没有帖子，来发第一条吧',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 140),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildColumn(left)),
                          SizedBox(width: 10),
                          Expanded(child: _buildColumn(right)),
                        ],
                      ),
                      if (_posts.length < _total)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: CupertinoButton(
                            onPressed: _loadingMore
                                ? null
                                : () => _load(reset: false),
                            child: _loadingMore
                                ? const CupertinoActivityIndicator()
                                : Text('加载更多'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 120,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _compose();
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.iosBlue,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33007AFF),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.plus,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumn(List<(int, PlazaPost)> items) {
    return Column(
      children: [
        for (final entry in items) ...[
          _PostCard(
            post: entry.$2,
            coverHeight: _coverHeight(entry.$2),
            fallbackColor: _fallbackColor(entry.$2),
            onLike: () => _toggleLike(entry.$1),
            onTap: () => _openDetail(entry.$2),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.coverHeight,
    required this.fallbackColor,
    required this.onLike,
    required this.onTap,
  });

  final PlazaPost post;
  final double coverHeight;
  final Color fallbackColor;
  final VoidCallback onLike;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = post.displayCover;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: coverHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: fallbackColor,
                      ),
                    )
                  else
                    ColoredBox(color: fallbackColor),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x66000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formatAgo(post.createdMs),
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: fallbackColor.withValues(alpha: 0.85),
                        backgroundImage: post.author.avatar.isNotEmpty
                            ? NetworkImage(post.author.avatar)
                            : null,
                        child: post.author.avatar.isEmpty
                            ? Text(
                                post.author.displayName.characters.isNotEmpty
                                    ? post.author.displayName.characters.first
                                    : '?',
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          post.author.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: onLike,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Icon(
                              post.liked
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.heart,
                              size: 15,
                              color: post.liked
                                  ? const Color(0xFFFF2D55)
                                  : const Color(0xFF8E8E93),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${post.likeCount}',
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 12,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
