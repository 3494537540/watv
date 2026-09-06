import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../services/maccms_api.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/figma_loading.dart';
import 'movie_detail_page.dart';

/// 我的评论记录
class MyCommentsPage extends StatefulWidget {
  const MyCommentsPage({super.key});

  @override
  State<MyCommentsPage> createState() => _MyCommentsPageState();
}

class _MyCommentsPageState extends State<MyCommentsPage> {
  final _cms = MacCmsApi();
  bool _loading = true;
  String? _error;
  List<MovieComment> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final u = CmsAuthController.instance.user;
    final uid = u?.userId ?? 0;
    if (uid <= 0 && (u?.userName.trim().isEmpty ?? true)) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '请先登录';
        _items = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _cms.adoptCmsSessionCookie(
        CmsAuthController.instance.api.sessionCookie,
      );
      final list = await _cms.fetchMyComments(
        userId: uid,
        userName: u?.userName ?? '',
        nickName: (u?.nickName.trim().isNotEmpty ?? false)
            ? u!.nickName
            : (u?.displayName ?? ''),
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请稍后重试';
      });
    }
  }

  Future<void> _openVod(MovieComment c) async {
    final id = c.vodId.trim();
    if (id.isEmpty) {
      DialogX.showWarning('无法打开该影片');
      return;
    }
    HapticFeedback.selectionClick();
    DialogX.showWait('加载中…');
    try {
      final movie = await _cms.fetchDetail(id);
      DialogX.dismiss();
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute<void>(builder: (_) => MovieDetailPage(movie: movie)),
      );
    } catch (e) {
      DialogX.showError('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppPalette.page(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text(
          '我的评论',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: AppPullRefresh(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: _MyCommentsSkeleton(),
                  ),
                ),
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
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 14,
                          color: AppPalette.textHint(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          if (_error == '请先登录') {
                            await showAuthSheet(context);
                            if (!mounted) return;
                            if (CmsAuthController.instance.isLoggedIn) {
                              unawaited(_load());
                            }
                            return;
                          }
                          unawaited(_load());
                        },
                        child: Text(_error == '请先登录' ? '去登录' : '重试'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    '还没有评论记录',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 14,
                      color: AppPalette.textHint(context),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                sliver: SliverList.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = _items[i];
                    return _MyCommentTile(
                      comment: c,
                      onTap: () => unawaited(_openVod(c)),
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

class _MyCommentTile extends StatelessWidget {
  const _MyCommentTile({required this.comment, required this.onTap});

  final MovieComment comment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = comment.vodName.trim().isEmpty ? '影片' : comment.vodName.trim();
    final time = formatCommentTime(comment.timeText, timeMs: comment.timeMs);
    return Material(
      color: AppPalette.surface(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 72,
                  child: comment.vodPic.isEmpty
                      ? ColoredBox(
                          color: AppPalette.softFill(context),
                          child: const Icon(
                            CupertinoIcons.film,
                            size: 20,
                            color: Color(0xFFAEAEB2),
                          ),
                        )
                      : CmsCoverImage(url: comment.vodPic, vodId: comment.vodId),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                              fontWeight: FontWeight.w700,
                              color: AppPalette.text(context),
                            ),
                          ),
                        ),
                        Text(
                          time,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 11,
                            color: AppPalette.textHint(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      comment.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        height: 1.35,
                        color: AppPalette.text(context).withValues(alpha: 0.82),
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

class _MyCommentsSkeleton extends StatelessWidget {
  const _MyCommentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return FigmaSkeletonPulse(
      child: Column(
        children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FigmaSkeletonBone(width: 52, height: 72, radius: 8),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FigmaSkeletonBone(height: 14, radius: 7),
                      SizedBox(height: 10),
                      FigmaSkeletonBone(height: 12, radius: 6),
                      SizedBox(height: 6),
                      FigmaSkeletonBone(width: 160, height: 12, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
