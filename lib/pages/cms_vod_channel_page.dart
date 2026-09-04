import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/movie_models.dart';
import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import '../widgets/figma_loading.dart';
import '../widgets/movie_poster_card.dart';
import 'movie_detail_page.dart';
import '../widgets/app_page_route.dart';

/// 按 CMS 分类浏览（解说等）
class CmsVodChannelPage extends StatefulWidget {
  const CmsVodChannelPage({
    super.key,
    required this.title,
    required this.typeId,
  });

  final String title;
  final int typeId;

  @override
  State<CmsVodChannelPage> createState() => _CmsVodChannelPageState();
}

class _CmsVodChannelPageState extends State<CmsVodChannelPage> {
  final _api = MacCmsApi();
  final _scroll = ScrollController();
  List<Movie> _movies = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final list = await _api.fetchByType(
        typeId: widget.typeId,
        page: 1,
        limit: 24,
        applyBannerExclude: false,
      );
      if (!mounted) return;
      setState(() {
        _movies = list;
        _loading = false;
        _hasMore = list.length >= 12;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final more = await _api.fetchByType(
        typeId: widget.typeId,
        page: next,
        limit: 24,
        applyBannerExclude: false,
      );
      if (!mounted) return;
      final seen = {for (final m in _movies) m.id};
      final appended = [for (final m in more) if (seen.add(m.id)) m];
      setState(() {
        _movies = [..._movies, ...appended];
        _page = next;
        _hasMore = appended.length >= 8;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF181818),
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _reload,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            if (_loading && _movies.isEmpty)
              const SliverFillRemaining(
                child: Center(child: FigmaMetaballLoader(size: 48)),
              )
            else if (_error != null && _movies.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: TextButton(
                    onPressed: () => unawaited(_reload()),
                    child: Text(
                      '$_error\n点击重试',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                ),
              )
            else if (_movies.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Text(
                    '暂无内容',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.52,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final m = _movies[i];
                      return MoviePosterCard(
                        movie: m,
                        width: double.infinity,
                        onTap: () {
                          Navigator.of(context).push(
                            AppPageRoute<void>(
                              builder: (_) => MovieDetailPage(movie: m),
                            ),
                          );
                        },
                      );
                    },
                    childCount: _movies.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 8),
                  child: Center(
                    child: _loadingMore
                        ? const CupertinoActivityIndicator()
                        : Text(
                            _hasMore ? '' : '没有更多了',
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              color: Color(0xFFB0B0B5),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 解说专区：自动匹配 CMS「解说」分类
class CmsCommentaryPage extends StatefulWidget {
  const CmsCommentaryPage({super.key});

  @override
  State<CmsCommentaryPage> createState() => _CmsCommentaryPageState();
}

class _CmsCommentaryPageState extends State<CmsCommentaryPage> {
  final _api = MacCmsApi();
  int? _typeId;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    try {
      final id = await _api.findTypeIdByName('解说');
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _loading = false;
          _error = '未找到「解说」分类，请在后台添加后重试';
        });
        return;
      }
      setState(() {
        _typeId = id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: FigmaMetaballLoader(size: 48)),
      );
    }
    if (_error != null || _typeId == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF181818),
          title: const Text(
            '解说',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ),
        body: Center(
          child: Text(
            _error ?? '未找到分类',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'AppSans',
              color: Color(0xFF8E8E93),
            ),
          ),
        ),
      );
    }
    return CmsVodChannelPage(title: '解说', typeId: _typeId!);
  }
}
