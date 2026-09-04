import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../models/movie_models.dart';
import '../services/cms_app_config.dart';
import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import '../widgets/figma_loading.dart';
import '../widgets/movie_poster_card.dart';
import 'vertical_short_feed_page.dart';
import '../widgets/app_page_route.dart';

/// 体育分区：对接 CMS type=48 子类 + 体育赛事
class SportsPage extends StatefulWidget {
  const SportsPage({super.key});

  @override
  State<SportsPage> createState() => _SportsPageState();
}

class _SportsPageState extends State<SportsPage> {
  final _api = MacCmsApi();
  final _scroll = ScrollController();

  List<MacCmsTypeNode> _tabs = const [];
  int _tab = 0;
  List<Movie> _movies = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  int _rootId = ApiConfig.macCmsSportsTypeId;
  int _eventId = ApiConfig.macCmsSportsEventTypeId;

  int? get _typeId {
    if (_tabs.isEmpty) return _rootId;
    return _tabs[_tab.clamp(0, _tabs.length - 1)].typeId;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_boot());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final cfg = CmsAppConfigStore.instance.config;
    _rootId = cfg.sportsTypeId;
    _eventId = cfg.sportsEventTypeId;
    try {
      final types = await _api.fetchVodTypes();
      final kids = [
        for (final t in types)
          if (t.typePid == _rootId) t,
      ];
      kids.sort((a, b) => a.typeId.compareTo(b.typeId));
      final tabs = <MacCmsTypeNode>[
        MacCmsTypeNode(typeId: _rootId, typePid: 0, typeName: '全部'),
        ...kids,
        if (!kids.any((t) => t.typeId == _eventId) &&
            types.any((t) => t.typeId == _eventId))
          MacCmsTypeNode(
            typeId: _eventId,
            typePid: 0,
            typeName: '赛事录像',
          ),
      ];
      if (!mounted) return;
      setState(() {
        _tabs = tabs;
        _tab = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tabs = [
          MacCmsTypeNode(typeId: _rootId, typePid: 0, typeName: '全部'),
          const MacCmsTypeNode(typeId: 49, typePid: 48, typeName: '足球'),
          const MacCmsTypeNode(typeId: 54, typePid: 48, typeName: 'NBA'),
          MacCmsTypeNode(
            typeId: _eventId,
            typePid: 0,
            typeName: '赛事录像',
          ),
        ];
      });
    }
    await _reload();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reload() async {
    final tid = _typeId;
    if (tid == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _movies = const [];
    });
    try {
      List<Movie> list;
      if (tid == _rootId) {
        // 父类常空：合并子类第一页
        final types = _tabs.where((t) => t.typeId != _rootId).toList();
        final pages = await Future.wait([
          for (final t in types.take(8))
            _api.fetchByType(
              typeId: t.typeId,
              page: 1,
              limit: 12,
              applyBannerExclude: false,
            ),
        ]);
        final seen = <String>{};
        list = [
          for (final p in pages)
            for (final m in p)
              if (seen.add(m.id)) m,
        ];
      } else {
        list = await _api.fetchByType(
          typeId: tid,
          page: 1,
          limit: 24,
          applyBannerExclude: false,
        );
      }
      if (!mounted) return;
      setState(() {
        _movies = list;
        _loading = false;
        _hasMore = list.length >= 10;
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
    final tid = _typeId;
    if (tid == null || tid == _rootId) {
      setState(() => _hasMore = false);
      return;
    }
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final more = await _api.fetchByType(
        typeId: tid,
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
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: top + 8),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '体育',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF181818),
              ),
            ),
          ),
          if (_tabs.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _tabs.length,
                separatorBuilder: (_, _) => SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final on = i == _tab;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = i);
                      unawaited(_reload());
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on
                            ? AppColors.brand.withValues(alpha: 0.15)
                            : const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _tabs[i].typeName,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              on ? AppColors.brand : const Color(0xFF8E8E93),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _boot,
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
                          '该分类暂无内容',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
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
                                    builder: (_) => VerticalShortFeedPage(
                                      title: '体育',
                                      typeId: _typeId ?? _rootId,
                                      seed: _movies,
                                      initialIndex: i,
                                      mergeChildTypes: _typeId == _rootId,
                                    ),
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
                        padding: const EdgeInsets.only(bottom: 120, top: 8),
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
          ),
        ],
      ),
    );
  }
}
