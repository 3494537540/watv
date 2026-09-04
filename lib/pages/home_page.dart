import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../data/movie_mock.dart';
import '../models/movie_models.dart';
import '../services/cms_message_store.dart';
import '../services/home_feed_cache.dart';
import '../services/local_play_store.dart';
import '../services/maccms_api.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_onboarding.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/figma_loading.dart';
import '../widgets/home_continue_watch.dart';
import '../widgets/home_top_chrome.dart';
import '../widgets/movie_poster_card.dart';
import 'cms_messages_page.dart';
import 'movie_detail_page.dart';
import 'movie_search_page.dart';
import 'redeem_page.dart';
import 'vertical_short_feed_page.dart';
import 'watch_history_page.dart';
import '../widgets/app_page_route.dart';

/// 首页：沉浸式 Banner + 热门双列 + 类型标签切换
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _tabs = ['推荐', '电影', '电视剧', '综艺', '动漫', '短剧'];

  static const _quickIconColor = Color(0xFF1A1A1A);

  static const _quickEntries = [
    HomeQuickEntry(
      label: '分类',
      icon: CupertinoIcons.tv_fill,
      color: _quickIconColor,
    ),
    HomeQuickEntry(
      label: '榜单',
      icon: CupertinoIcons.chart_bar_alt_fill,
      color: _quickIconColor,
    ),
    HomeQuickEntry(
      label: '会员',
      icon: CupertinoIcons.star_circle_fill,
      color: _quickIconColor,
    ),
    HomeQuickEntry(
      label: '追番表',
      icon: CupertinoIcons.calendar_today,
      color: _quickIconColor,
    ),
    HomeQuickEntry(
      label: '兑福利',
      icon: CupertinoIcons.gift_fill,
      color: _quickIconColor,
    ),
  ];

  final _cms = MacCmsApi();

  int _tabIndex = 0;
  int _bannerPage = 0;
  MacCmsGenreTag? _selectedFilter;
  List<Movie> _heroMovies = const [];
  List<Movie> _hotMovies = const [];
  List<Movie> _genreMovies = const [];
  bool _bannerLoading = true;
  bool _genreLoading = true;
  /// false=列表 true=宫格
  bool _hotGridMode = true;
  String? _bannerError;
  int _inboxBadge = 0;
  List<String> _hotHints = const [];

  /// Tab → 热门缓存；Tab+filter → 类型列表缓存
  final Map<int, List<Movie>> _hotByTab = {};
  final Map<String, List<Movie>> _genreCache = {};
  int _hotLoadSeq = 0;
  int _genreLoadSeq = 0;
  final ScrollController _scroll = ScrollController();
  /// 0 = 沉浸透明顶栏，1 = 白底顶栏
  double _chromeLight = 0;
  LocalPlayItem? _continueItem;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CmsMessageStore.instance.addListener(_onMessageStore);
    _selectedFilter = _defaultFilter;
    _scroll.addListener(_onHomeScroll);
    unawaited(_bootstrapFast());
  }

  void _onMessageStore() {
    if (!mounted) return;
    final n = CmsMessageStore.instance.unreadCount;
    if (n != _inboxBadge) {
      setState(() => _inboxBadge = n);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInboxBadge());
    }
  }

  /// 先读磁盘缓存秒开，再后台刷新
  Future<void> _bootstrapFast() async {
    unawaited(_loadContinueWatch());
    unawaited(_refreshInboxBadge());
    final tab = _currentTab;
    final cached = await HomeFeedCache.load(tab);
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty) {
      _hotByTab[_tabIndex] = cached;
      setState(() {
        _hotMovies = cached;
        _heroMovies = cached.take(6).toList();
        _genreMovies = cached.take(18).toList();
        _hotHints = [for (final m in cached.take(12)) m.title];
        _bannerLoading = false;
        _genreLoading = false;
        _bannerError = null;
      });
      _precacheCovers(cached.take(8));
    }
    await _loadHotContent(force: true);
  }

  Future<void> _refreshInboxBadge() async {
    try {
      final uid = CmsAuthController.instance.user?.userId ?? 0;
      await CmsMessageStore.instance.bootstrap(userId: uid);
      final api = CmsAuthController.instance.api;
      await CmsMessageStore.instance.refresh(api, userId: uid);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _inboxBadge = CmsMessageStore.instance.unreadCount);
  }

  void _precacheCovers(Iterable<Movie> movies) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final m in movies) {
        final url = (m.bannerUrl ?? m.coverUrl)?.trim() ?? '';
        if (url.isEmpty) continue;
        precacheImage(NetworkImage(url), context).catchError((_) => null);
      }
    });
  }

  void _openInbox() {
    HapticFeedback.selectionClick();
    Navigator.of(context)
        .push(
      AppPageRoute<void>(
        builder: (_) => const CmsMessagesPage(),
      ),
    )
        .then((_) {
      if (!mounted) return;
      setState(() => _inboxBadge = CmsMessageStore.instance.unreadCount);
    });
  }

  void _openHistory() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => const WatchHistoryPage(),
      ),
    );
  }

  void _openRank() {
    HapticFeedback.selectionClick();
    final section = MovieSection(
      title: _hotSectionTitle,
      movies: _hotMovies.isNotEmpty
          ? _hotMovies
          : (_heroMovies.isNotEmpty
              ? _heroMovies
              : MovieMock.sections.first.movies),
    );
    _openSectionAll(context, section);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CmsMessageStore.instance.removeListener(_onMessageStore);
    _scroll.removeListener(_onHomeScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadContinueWatch() async {
    final item = await HomeContinueWatchCard.loadUnfinished();
    if (!mounted) return;
    setState(() => _continueItem = item);
  }

  Future<void> _openContinueWatch() async {
    final item = _continueItem;
    if (item == null) return;
    final movie = Movie(
      id: item.vodId,
      title: item.name,
      subtitle: item.remarks,
      year: DateTime.now().year,
      score: 0,
      genres: const ['影视'],
      coverColor: const Color(0xFFE8E9ED),
      tagline: item.name,
      synopsis: '',
      icon: CupertinoIcons.film,
      coverUrl: item.pic.isEmpty ? null : item.pic,
      remarks: item.remarks,
      typeId: 0,
    );
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => MovieDetailPage(
          movie: movie,
          initialEpisodeIndex:
              item.episodeIndex >= 0 ? item.episodeIndex : null,
          autoPlay: true,
          forceWatch: true,
        ),
      ),
    );
    if (mounted) unawaited(_loadContinueWatch());
  }

  Future<void> _dismissContinueWatch() async {
    final item = _continueItem;
    if (item == null) return;
    await HomeContinueWatchCard.dismissItem(item);
    if (!mounted) return;
    setState(() => _continueItem = null);
  }

  void _onHomeScroll() {
    if (!mounted) return;
    // 拉长过渡距离 + 缓动，避免顶栏生硬跳白
    final raw = ((_scroll.offset - 8) / 160).clamp(0.0, 1.0);
    final next = Curves.easeOutCubic.transform(raw);
    if ((next - _chromeLight).abs() < 0.008) return;
    _safeSetState(() => _chromeLight = next);
  }

  /// Tab 切换 / 滚动回调里避免在 build 期间 setState
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      setState(fn);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(fn);
    });
  }

  String get _currentTab => _tabs[_tabIndex.clamp(0, _tabs.length - 1)];

  bool get _isShortDramaTab => _currentTab == '短剧';

  MacCmsGenreTag get _defaultFilter =>
      ApiConfig.macCmsQuickFiltersFor(_currentTab).first;

  MacCmsGenreTag get _filter => _selectedFilter ?? _defaultFilter;

  String get _hotSectionTitle {
    final tab = _currentTab;
    if (tab == '推荐') return '本周热门';
    return '$tab热门';
  }

  List<MacCmsGenreTag> get _quickFilters =>
      ApiConfig.macCmsQuickFiltersFor(_currentTab);

  List<MacCmsFilterGroup> get _sheetGroups =>
      ApiConfig.macCmsSheetFilterGroupsFor(_currentTab);

  Set<String> get _hotIds => {for (final m in _hotMovies) m.id};

  static List<Movie> _dedupe(List<Movie> list) {
    final seen = <String>{};
    return [for (final m in list) if (seen.add(m.id)) m];
  }

  String _filterCacheKey(MacCmsGenreTag tag) =>
      '$_tabIndex:${tag.mode.name}:${tag.typeId ?? -1}:${tag.label}';

  Future<void> _loadHotContent({bool force = false}) async {
    final tabIndex = _tabIndex;
    final tab = _tabs[tabIndex];

    if (!force && _hotByTab.containsKey(tabIndex)) {
      final cached = _hotByTab[tabIndex]!;
      if (!mounted || _tabIndex != tabIndex) return;
      _safeSetState(() {
        _hotMovies = cached;
        _heroMovies = cached.take(6).toList();
        _bannerPage = 0;
        _bannerLoading = false;
        _bannerError = cached.isEmpty ? '暂无热门数据' : null;
        _selectedFilter = ApiConfig.macCmsQuickFiltersFor(tab).first;
      });
      await _loadGenreContent(force: force);
      return;
    }

    final seq = ++_hotLoadSeq;
    // 有缓存时不闪骨架，静默刷新
    final hasWarm = _hotMovies.isNotEmpty || _heroMovies.isNotEmpty;
    if (!hasWarm) {
      setState(() {
        _bannerLoading = true;
        _bannerError = null;
        _selectedFilter = ApiConfig.macCmsQuickFiltersFor(tab).first;
        _genreMovies = const [];
      });
    } else {
      setState(() {
        _bannerError = null;
        _selectedFilter = ApiConfig.macCmsQuickFiltersFor(tab).first;
      });
    }
    try {
      final list = _dedupe(await _cms.fetchHotMovies(limit: 18, tab: tab));
      if (!mounted || seq != _hotLoadSeq) return;
      _hotByTab[tabIndex] = list;
      unawaited(HomeFeedCache.save(tab, list));
      if (_tabIndex != tabIndex) return;
      setState(() {
        _hotMovies = list;
        _heroMovies = list.take(6).toList();
        _hotHints = [for (final m in list.take(12)) m.title];
        _bannerPage = 0;
        _bannerLoading = false;
        _bannerError = list.isEmpty ? '暂无热门数据' : null;
      });
      _precacheCovers(list.take(8));
      await _loadGenreContent(force: true);
    } catch (e) {
      if (!mounted || seq != _hotLoadSeq) return;
      if (_tabIndex != tabIndex) return;
      if (hasWarm) {
        setState(() => _bannerLoading = false);
        return;
      }
      setState(() {
        _bannerLoading = false;
        _bannerError = '$e';
        _heroMovies = [
          for (var i = 0; i < 3; i++) MovieMock.bannerMovie(i),
        ];
        _bannerPage = 0;
        _hotMovies = _heroMovies;
        _genreMovies = const [];
        _genreLoading = false;
      });
    }
  }

  Future<void> _loadGenreContent({bool force = false}) async {
    final tag = _filter;
    final cacheKey = _filterCacheKey(tag);

    // 「全部 / 周热」直接复用热门列表，避免和上方轮播重复请求、又互斥排空
    final useHot = tag.mode == MacCmsGenreMode.weekHot || tag.label == '全部';
    if (useHot && _hotMovies.isNotEmpty) {
      if (!mounted) return;
      final movies = _dedupe(_hotMovies).take(18).toList();
      _genreCache[cacheKey] = movies;
      setState(() {
        _genreMovies = movies;
        _genreLoading = false;
      });
      return;
    }

    if (!force && _genreCache.containsKey(cacheKey)) {
      if (!mounted) return;
      setState(() {
        _genreMovies = _genreCache[cacheKey]!;
        _genreLoading = false;
      });
      return;
    }

    final seq = ++_genreLoadSeq;
    final keepShowing = _genreMovies.isNotEmpty || _hotMovies.isNotEmpty;
    if (!keepShowing) {
      setState(() => _genreLoading = true);
    }
    try {
      final list = await _cms.fetchByGenreTag(
        tag,
        limit: 18,
        excludeIds: useHot ? const {} : _hotIds,
      );
      if (!mounted || seq != _genreLoadSeq) return;
      final movies = _dedupe(list);
      _genreCache[cacheKey] = movies;
      setState(() {
        _genreMovies = movies;
        _genreLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _genreLoadSeq) return;
      setState(() {
        _genreMovies = const [];
        _genreLoading = false;
      });
    }
  }

  Future<void> _onTabChanged(int i) async {
    if (i == _tabIndex) return;
    _safeSetState(() {
      _tabIndex = i;
      _selectedFilter = ApiConfig.macCmsQuickFiltersFor(_tabs[i]).first;
    });
    // 等本帧 build 结束再拉数据，避免「短剧」等 Tab 切页时 setState during build
    await Future<void>.delayed(Duration.zero);
    if (!mounted || _tabIndex != i) return;
    await _loadHotContent();
  }

  Future<void> _onFilterChanged(MacCmsGenreTag tag) async {
    if (_filter.sameAs(tag)) return;
    setState(() => _selectedFilter = tag);
    await _loadGenreContent();
  }

  Future<void> _openFilterSheet() async {
    HapticFeedback.selectionClick();
    final picked = await showHomeGenreFilterSheet(
      context: context,
      groups: _sheetGroups,
      selected: _filter,
    );
    if (picked == null || !mounted) return;
    await _onFilterChanged(picked);
  }

  Future<void> _loadBanners() {
    _hotByTab.remove(_tabIndex);
    _genreCache.removeWhere((k, _) => k.startsWith('$_tabIndex:'));
    return _loadHotContent(force: true);
  }

  void _onQuickEntryTap(int i) {
    if (i == 0) {
      _openFilterSheet();
      return;
    }
    if (i == 1) {
      final section = MovieSection(
        title: _hotSectionTitle,
        movies: _hotMovies.isNotEmpty
            ? _hotMovies
            : (_heroMovies.isNotEmpty
                ? _heroMovies
                : MovieMock.sections.first.movies),
      );
      _openSectionAll(context, section);
      return;
    }
    if (i == 4) {
      HapticFeedback.selectionClick();
      Navigator.of(context).push(
        AppPageRoute<void>(builder: (_) => const RedeemPage()),
      );
    }
  }

  void _openDetail(BuildContext context, Movie movie) {
    if (_isShortDramaTab) {
      final list = _displayMovies.isNotEmpty ? _displayMovies : _hotMovies;
      final idx = list.indexWhere((m) => m.id == movie.id);
      Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => VerticalShortFeedPage(
            title: '短剧',
            typeId: ApiConfig.macCmsShortDramaTypeId,
            seed: list.isEmpty ? [movie] : list,
            initialIndex: idx < 0 ? 0 : idx,
            lockToSeedSeries: true,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => MovieDetailPage(movie: movie),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => const MovieSearchPage(),
      ),
    );
  }

  void _openSectionAll(BuildContext context, MovieSection section) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _SectionAllPage(section: section),
      ),
    );
  }

  String get _searchHintFallback {
    if (_hotHints.isNotEmpty) return _hotHints.first;
    if (_heroMovies.isNotEmpty) return _heroMovies.first.title;
    final pool = MovieMock.all;
    if (pool.isEmpty) return '搜索影片、演员';
    return pool[DateTime.now().day % pool.length].title;
  }

  List<String> get _searchHints {
    if (_hotHints.isNotEmpty) return _hotHints;
    if (_heroMovies.isNotEmpty) {
      return [for (final m in _heroMovies.take(8)) m.title];
    }
    return [_searchHintFallback];
  }

  List<Movie> get _displayMovies {
    if (_genreLoading) return const [];
    if (_genreMovies.isNotEmpty) return _genreMovies.take(18).toList();
    if (_hotMovies.length >= 2) return _hotMovies.take(8).toList();
    if (_heroMovies.length >= 2) return _heroMovies.take(8).toList();
    return const [];
  }

  String? _listBadge(Movie m, {bool inHotTop = false}) {
    final fromData = m.cornerBadge;
    if (fromData != null) return fromData;
    // 本周热门前列才标「热门」，不是固定第 1/2 张图
    if (inHotTop) return '热门';
    return null;
  }

  Color _listBadgeColor(String? badge) {
    return switch (badge) {
      '独家' => const Color(0xFF7B61FF),
      '免费' || '限免' => const Color(0xFFFF6B4A),
      '会员' => const Color(0xFFE6A23C),
      '热播' || '热门' => const Color(0xFFE85D5D),
      '高分' => const Color(0xFF2BB673),
      '更新' => const Color(0xFF3B82F6),
      '完结' => const Color(0xFF64748B),
      '抢先' || '预告' => const Color(0xFFEC4899),
      _ => const Color(0xFF7B61FF),
    };
  }

  Widget _buildMovieGrid(List<Movie> movies) {
    final hotTopIds = {
      for (final m in _hotMovies.take(5)) m.id,
    };
    if (!_hotGridMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: Column(
          children: [
            for (final m in movies)
              Builder(
                builder: (_) {
                  final badge =
                      _listBadge(m, inHotTop: hotTopIds.contains(m.id));
                  return HomeMediaListTile(
                    movie: m,
                    badge: badge,
                    badgeColor: _listBadgeColor(badge),
                    onTap: () => _openDetail(context, m),
                  );
                },
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          const gap = 10.0;
          final w = (c.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: 14,
            children: [
              for (var i = 0; i < movies.length; i++)
                SizedBox(
                  width: w,
                  child: Builder(
                    builder: (_) {
                      final m = movies[i];
                      final badge = _listBadge(
                        m,
                        inHotTop: hotTopIds.contains(m.id),
                      );
                      return HomeLandscapeCard(
                        movie: m,
                        badge: badge,
                        badgeColor: _listBadgeColor(badge),
                        onTap: () => _openDetail(context, m),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stickyH = HomeImmersiveHeader.stickyChromeHeight(context);
    final headerH = HomeImmersiveHeader.heightOf(context);
    final light = _chromeLight > 0.72;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            light ? Brightness.dark : Brightness.light,
        statusBarBrightness: light ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        color: const Color(0xFFF5F6F8),
        child: Stack(
          children: [
            // 轮播钉住：下滑不露灰底空区，白底内容盖上去
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: headerH,
              child: HomePinnedBannerLayer(
                movies: _heroMovies,
                page: _bannerPage,
              ),
            ),
            if (_bannerLoading && _heroMovies.isEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: headerH,
                child: const IgnorePointer(
                  child: HomeBannerMetaballLoading(),
                ),
              ),
            AppPullRefresh(
              color: AppColors.brand,
              edgeOffset: stickyH,
              onDark: true,
              onRefresh: _loadBanners,
              child: CustomScrollView(
                controller: _scroll,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: HomeImmersiveHeader(
                      movies: _heroMovies,
                      tabs: _tabs,
                      tabIndex: _tabIndex,
                      searchHints: _searchHints,
                      showBackdrop: false,
                      showTopChrome: false,
                      pageIndex: _bannerPage,
                      onPageChanged: (i) {
                        if (_bannerPage == i) return;
                        setState(() => _bannerPage = i);
                      },
                      onTabChanged: _onTabChanged,
                      onSearchTap: () => _openSearch(context),
                      onBannerTap: (m) => _openDetail(context, m),
                      onRankTap: _openRank,
                      onHistoryTap: _openHistory,
                      onInboxTap: _openInbox,
                    ),
                  ),
                  if (_bannerError != null)
                    SliverToBoxAdapter(
                      child: GestureDetector(
                        onTap: _loadBanners,
                        child: Container(
                          width: double.infinity,
                          color: const Color(0xFFFFF4E5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: const Text(
                            '轮播加载失败，点击重试',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              color: Color(0xFFB54708),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TourTarget(
                            id: 'tour_quick',
                            child: HomeQuickEntries(
                              items: _quickEntries,
                              onTap: _onQuickEntryTap,
                            ),
                          ),
                          HomeSectionTitle(
                            title: _hotSectionTitle,
                            trailing: HomeLayoutToggle(
                              gridMode: _hotGridMode,
                              onChanged: (v) =>
                                  setState(() => _hotGridMode = v),
                            ),
                          ),
                          HomeGenreFilterBar(
                            quickTags: _quickFilters,
                            selected: _filter,
                            onSelected: _onFilterChanged,
                            onOpenSheet: _openFilterSheet,
                          ),
                          if (_genreLoading)
                            const TourTarget(
                              id: 'tour_feed',
                              child: HomeListSkeleton(),
                            )
                          else if (_displayMovies.isEmpty)
                            const TourTarget(
                              id: 'tour_feed',
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                                child: Text(
                                  '该类型暂无内容',
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 13,
                                    color: Color(0xFF999999),
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            )
                          else
                            Stack(
                              children: [
                                _buildMovieGrid(_displayMovies),
                                // 只高亮列表顶部一块，避免整页挖孔过大
                                const Positioned(
                                  left: 14,
                                  right: 14,
                                  top: 4,
                                  height: 220,
                                  child: IgnorePointer(
                                    child: TourTarget(
                                      id: 'tour_feed',
                                      child: SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 160),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: HomeStickyTopBar(
                tabs: _tabs,
                tabIndex: _tabIndex,
                searchHints: _searchHints,
                lightProgress: _chromeLight,
                onTabChanged: _onTabChanged,
                onSearchTap: () => _openSearch(context),
                onRankTap: _openRank,
                onHistoryTap: _openHistory,
                onInboxTap: _openInbox,
                inboxBadge: _inboxBadge,
              ),
            ),
            if (_continueItem != null)
              HomeContinueWatchCard(
                item: _continueItem!,
                // 悬浮底栏约 72–90 + 安全区，抬高避免被挡住
                bottomInset: 128,
                onTap: () => unawaited(_openContinueWatch()),
                onDismissed: () => unawaited(_dismissContinueWatch()),
              ),
          ],
        ),
      ),
    );
  }

}

class _SectionAllPage extends StatelessWidget {
  const _SectionAllPage({required this.section});

  final MovieSection section;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8, top + 4, 16, 8),
            child: Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Icon(
                    CupertinoIcons.back,
                    color: AppColors.iosBlue,
                  ),
                ),
                Expanded(
                  child: Text(
                    section.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.52,
              ),
              itemCount: section.movies.length,
              itemBuilder: (context, i) {
                final m = section.movies[i];
                return LayoutBuilder(
                  builder: (context, c) {
                    return MoviePosterCard(
                      movie: m,
                      width: c.maxWidth,
                      onTap: () {
                        Navigator.of(context).push(
                          AppPageRoute<void>(
                            builder: (_) => MovieDetailPage(movie: m),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
