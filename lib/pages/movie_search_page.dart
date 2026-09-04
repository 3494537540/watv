import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../config/api_config.dart';
import '../services/maccms_api.dart';
import '../services/search_history_store.dart';
import '../utils/search_text_match.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/figma_loading.dart';
import '../widgets/movie_poster_card.dart';
import '../widgets/player/mango_watch_panel.dart';
import '../widgets/request_vod_sheet.dart';
import '../widgets/search_highlight_text.dart';
import 'episode_list_page.dart';
import 'movie_detail_page.dart';
import 'vod_download_page.dart';
import 'vod_filter_page.dart';
import '../widgets/app_page_route.dart';

enum _SearchPhase { idle, suggest, results }

/// 搜索页：历史/榜单 + 联想 + 最佳匹配结果
class MovieSearchPage extends StatefulWidget {
  const MovieSearchPage({super.key});

  @override
  State<MovieSearchPage> createState() => _MovieSearchPageState();
}

class _MovieSearchPageState extends State<MovieSearchPage> {
  static const _bg = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF191919);
  static const _muted = Color(0xFF9A9A9A);
  static const _chipBg = Color(0xFFF3F3F5);
  static const _hintPool = ['仙逆', '凡人修仙传', '花开锦绣', '藏海花', '盗墓笔记'];

  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _cms = MacCmsApi();
  final _rankPageCtrl = PageController(viewportFraction: 0.88);

  List<String> _history = const [];
  bool _historyExpanded = false;

  /// 0 榜单 / 1 找片
  int _discoverTab = 0;

  List<Movie> _hotBoard = const [];
  List<Movie> _tvBoard = const [];
  List<Movie> _movieBoard = const [];
  List<Movie> _varietyBoard = const [];
  List<Movie> _animeBoard = const [];
  bool _boardsLoading = true;

  List<Movie> _findMovies = const [];
  int _findChannel = 0;
  bool _findLoading = false;

  _SearchPhase _phase = _SearchPhase.idle;
  List<_SuggestRich> _suggestRich = const [];
  List<String> _suggestTexts = const [];
  bool _suggestLoading = false;

  List<Movie> _results = const [];
  Movie? _bestMatch;
  String _resultQuery = '';
  String _resultCat = '全部';
  int _resultTopTab = 0;
  /// true=宫格（其他作品默认） false=列表长条
  bool _resultsGridMode = true;
  bool _loading = false;
  String? _error;
  /// 结果页顶栏过渡 0=沉浸 1=白底
  double _resultsChrome = 0;
  /// 本地片库缓存：拼音/英文联想与搜索兜底
  List<Movie> _searchCatalog = const [];
  bool _catalogLoading = false;
  Timer? _debounce;
  int _searchSeq = 0;

  /// CMS 搜索顶栏频道（全部 + 一级分类含短剧）
  List<MacCmsSearchChannel> _searchChannels =
      ApiConfig.macCmsSearchChannelDefaults;
  List<MacCmsTypeNode> _vodTypes = const [];
  Set<int>? _channelTypeIds;

  static const _accentTeal = Color(0xFF1ECAD3);

  String get _placeholder =>
      _hintPool[DateTime.now().day % _hintPool.length];

  static const _findChannels = ['电影', '电视剧', '综艺', '动漫'];

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
    unawaited(_loadBoards());
    unawaited(_loadSearchChannels());
    unawaited(_ensureSearchCatalog());
  }

  Future<void> _ensureSearchCatalog() async {
    if (_catalogLoading) return;
    if (_searchCatalog.length >= 120) return;
    _catalogLoading = true;
    try {
      final hot = await _cms.fetchHotMovies(limit: 60);
      final latest = await _cms.fetchLatest(page: 1, limit: 100);
      final map = <String, Movie>{};
      for (final m in [...hot, ...latest, ..._searchCatalog]) {
        if (m.id.trim().isEmpty) continue;
        map[m.id] = m;
      }
      // 再补几页最新，拼音命中率更高
      if (map.length < 160) {
        try {
          final more = await _cms.fetchLatest(page: 2, limit: 100);
          for (final m in more) {
            if (m.id.trim().isEmpty) continue;
            map[m.id] = m;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      _searchCatalog = map.values.toList(growable: false);
    } catch (_) {
      // 忽略，仍可用 CMS 关键词搜
    } finally {
      _catalogLoading = false;
    }
  }

  List<Movie> _mergeMovies(Iterable<Movie> a, Iterable<Movie> b) {
    final map = <String, Movie>{};
    for (final m in [...a, ...b]) {
      if (m.id.trim().isEmpty) continue;
      map.putIfAbsent(m.id, () => m);
    }
    return map.values.toList();
  }

  bool _isLatinQuery(String q) {
    final n = SearchTextMatch.normalize(q);
    return n.isNotEmpty && RegExp(r'^[a-z0-9]+$').hasMatch(n);
  }

  Future<List<Movie>> _searchMovies(String q, {int limit = 48}) async {
    final cms = await _cms.search(q, limit: limit);
    if (!_isLatinQuery(q)) {
      var list = [
        for (final m in cms)
          if (SearchTextMatch.matchesMovie(m, q)) m,
      ];
      if (list.isEmpty) list = cms;
      // 中文也可叠加本地库，提升漏网命中
      await _ensureSearchCatalog();
      final local = [
        for (final m in _searchCatalog)
          if (SearchTextMatch.matchesMovie(m, q)) m,
      ];
      return _mergeMovies(list, local);
    }

    // 拼音 / 英文：CMS 常搜不到中文片名，必须靠本地片库 + 弱匹配
    await _ensureSearchCatalog();
    final matchedCms = [
      for (final m in cms)
        if (SearchTextMatch.matchesMovie(m, q)) m,
    ];
    final local = [
      for (final m in _searchCatalog)
        if (SearchTextMatch.matchesMovie(m, q)) m,
    ];
    var merged = _mergeMovies(matchedCms, local);
    if (merged.isEmpty && cms.isNotEmpty) {
      // CMS 偶发带英文字段时放宽
      merged = [
        for (final m in cms)
          if (SearchTextMatch.matchesMovie(m, q) ||
              SearchTextMatch.normalize(m.nameEn).contains(
                SearchTextMatch.normalize(q),
              ))
            m,
      ];
    }
    return merged;
  }

  Future<void> _loadSearchChannels() async {
    try {
      final types = await _cms.fetchVodTypes();
      final channels = await _cms.fetchSearchChannels();
      if (!mounted) return;
      setState(() {
        _vodTypes = types;
        _searchChannels = channels;
        if (_resultTopTab >= _searchChannels.length) {
          _resultTopTab = 0;
        }
        _syncChannelTypeIds();
      });
    } catch (_) {
      // 保持默认频道
    }
  }

  void _syncChannelTypeIds() {
    if (_resultTopTab < 0 || _resultTopTab >= _searchChannels.length) {
      _channelTypeIds = null;
      return;
    }
    _channelTypeIds = _typeIdsForChannel(_searchChannels[_resultTopTab]);
  }

  Set<int>? _typeIdsForChannel(MacCmsSearchChannel ch) {
    final tid = ch.typeId;
    if (tid == null) return null;
    if (_vodTypes.isEmpty) {
      if (tid == ApiConfig.macCmsShortDramaTypeId) {
        return {
          tid,
          64,
          74,
          75,
          76,
          77,
          78,
          79,
          91,
          92,
          94,
        };
      }
      return {tid, ...ApiConfig.macCmsChildTypeIds(tid)};
    }
    return MacCmsApi.typeIdsUnder(tid, _vodTypes);
  }

  int _countForChannel(MacCmsSearchChannel ch) {
    if (_results.isEmpty) return 0;
    final allow = _typeIdsForChannel(ch);
    if (allow == null || allow.isEmpty) return _results.length;
    var n = 0;
    for (final m in _results) {
      if (allow.contains(m.typeId)) n++;
    }
    return n;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _rankPageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await SearchHistoryStore.list();
    if (!mounted) return;
    setState(() => _history = list);
  }

  Future<void> _loadBoards() async {
    setState(() => _boardsLoading = true);
    try {
      final results = await Future.wait([
        _cms.fetchHotMovies(limit: 6, tab: '推荐'),
        _cms.fetchHotMovies(limit: 6, tab: '电视剧'),
        _cms.fetchHotMovies(limit: 6, tab: '电影'),
        _cms.fetchHotMovies(limit: 6, tab: '综艺'),
        _cms.fetchHotMovies(limit: 6, tab: '动漫'),
      ]);
      if (!mounted) return;
    setState(() {
        _hotBoard = results[0];
        _tvBoard = results[1];
        _movieBoard = results[2];
        _varietyBoard = results[3];
        _animeBoard = results[4];
        _boardsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _boardsLoading = false);
    }
  }

  Future<void> _loadFind(int channel) async {
    setState(() {
      _findChannel = channel;
      _findLoading = true;
    });
    try {
      final tab = _findChannels[channel];
      final list = await _cms.fetchHotMovies(limit: 18, tab: tab);
      if (!mounted) return;
      setState(() {
        _findMovies = list;
        _findLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _findMovies = const [];
        _findLoading = false;
      });
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _phase = _SearchPhase.idle;
        _suggestRich = const [];
        _suggestTexts = const [];
        _suggestLoading = false;
        _loading = false;
        _results = const [];
        _bestMatch = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _phase = _SearchPhase.suggest;
      _suggestLoading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_runSuggest(trimmed));
    });
  }

  Future<void> _runSuggest(String q) async {
    final seq = ++_searchSeq;
    try {
      var list = await _searchMovies(q, limit: 36);
      list.sort((a, b) => SearchTextMatch.compareMovies(a, b, q));
      if (!mounted || seq != _searchSeq) return;
      final rich = _buildSuggestRich(list, q);
      final texts = _buildSuggestTexts(list, q, rich);
      setState(() {
        _suggestRich = rich;
        _suggestTexts = texts;
        _suggestLoading = false;
        _phase = _SearchPhase.suggest;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _suggestRich = const [];
        _suggestTexts = const [];
        _suggestLoading = false;
      });
    }
  }

  List<_SuggestRich> _buildSuggestRich(List<Movie> list, String q) {
    if (list.isEmpty) return const [];
    final groups = <String, List<Movie>>{};
    for (final m in list) {
      final key = m.title.length >= 2 ? m.title.substring(0, 2) : m.title;
      (groups[key] ??= []).add(m);
    }
    final out = <_SuggestRich>[];
    final used = <String>{};
    for (final m in list) {
      if (out.length >= 5) break;
      final key = m.title.length >= 2 ? m.title.substring(0, 2) : m.title;
      final g = groups[key] ?? const <Movie>[];
      if (g.length >= 3 && !used.contains('series:$key')) {
        used.add('series:$key');
        out.add(_SuggestRich.series(
          title: key,
          cover: g.first,
          count: g.length,
        ));
        continue;
      }
      if (used.contains(m.id)) continue;
      used.add(m.id);
      out.add(_SuggestRich.movie(m));
    }
    return out;
  }

  List<String> _buildSuggestTexts(
    List<Movie> list,
    String q,
    List<_SuggestRich> rich,
  ) {
    final skip = <String>{
      for (final r in rich) r.title,
    };
    final out = <String>[];
    for (final m in list) {
      if (out.length >= 10) break;
      final t = m.title.trim();
      if (t.isEmpty || skip.contains(t)) continue;
      if (out.contains(t)) continue;
      out.add(t);
      if (out.length < 10 && !t.endsWith('全集')) {
        final full = '$t全集';
        if (!out.contains(full)) out.add(full);
      }
    }
    return out;
  }

  Future<void> _runSearch(String q, {bool saveHistory = true}) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    final seq = ++_searchSeq;
    _focus.unfocus();
    setState(() {
      _phase = _SearchPhase.results;
      _loading = true;
      _error = null;
      _resultQuery = trimmed;
      _bestMatch = null;
      _resultCat = '全部';
      _resultTopTab = 0;
      _resultsChrome = 0;
    });
    if (saveHistory) {
      final next = await SearchHistoryStore.add(trimmed);
      if (mounted) setState(() => _history = next);
    }
    try {
      var list = await _searchMovies(trimmed, limit: 48);
      if (!mounted || seq != _searchSeq) return;
      list.sort((a, b) => SearchTextMatch.compareMovies(a, b, trimmed));
      final best = _pickBest(list, trimmed);
      // 回填本地片库，后续拼音联想更准
      if (list.isNotEmpty) {
        _searchCatalog = _mergeMovies(_searchCatalog, list);
      }
      setState(() {
        _results = list;
        _bestMatch = best;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _results = const [];
        _bestMatch = null;
      });
    }
  }

  Movie? _pickBest(List<Movie> list, String q) {
    if (list.isEmpty) return null;
    final ranked = [...list]
      ..sort((a, b) => SearchTextMatch.compareMovies(a, b, q));
    return ranked.first;
  }

  void _applyKeyword(String q, {bool toResults = true}) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    _debounce?.cancel();
    if (toResults) {
      unawaited(_runSearch(q));
    } else {
      unawaited(_runSuggest(q.trim()));
    }
  }

  void _open(Movie movie) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => MovieDetailPage(movie: movie),
      ),
    );
  }

  Future<Movie> _ensurePlayable(Movie movie) async {
    if (movie.playEpisodes.isNotEmpty || movie.playSources.isNotEmpty) {
      return movie;
    }
    try {
      return await _cms.fetchDetail(movie.id);
    } catch (_) {
      return movie;
    }
  }

  Future<void> _openEpisodeList(Movie movie) async {
    HapticFeedback.selectionClick();
    final m = await _ensurePlayable(movie);
    if (!mounted) return;
    if (m.playEpisodes.isEmpty && m.episodeLabels.isEmpty) {
      _open(m);
      return;
    }
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => EpisodeListPage(movie: m),
      ),
    );
  }

  Future<void> _openDownload(Movie movie) async {
    HapticFeedback.selectionClick();
    final m = await _ensurePlayable(movie);
    if (!mounted) return;
    if (m.playEpisodes.isEmpty && m.episodeLabels.isEmpty) {
      DialogX.showWarning('暂无可下载剧集');
      return;
    }
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => VodDownloadPage(movie: m),
      ),
    );
  }

  String categoryOf(Movie m) {
    return MacCmsApi.rootCategoryName(
      m.typeId,
      _vodTypes,
      fallback: m.genres.isNotEmpty ? m.genres.first : '影视',
    );
  }

  static String categoryOfStatic(Movie m, [List<MacCmsTypeNode> types = const []]) {
    return MacCmsApi.rootCategoryName(
      m.typeId,
      types,
      fallback: m.genres.isNotEmpty ? m.genres.first : '影视',
    );
  }

  Future<void> _clearHistory() async {
    HapticFeedback.selectionClick();
    await SearchHistoryStore.clear();
    if (!mounted) return;
    setState(() {
      _history = const [];
      _historyExpanded = false;
    });
  }

  String? get _resultCoverUrl {
    final m = _bestMatch ?? (_results.isNotEmpty ? _results.first : null);
    return m?.coverUrl ?? m?.bannerUrl;
  }

  /// 0 沉浸 / 1 白底（搜索中、无结果强制白底）
  double get _chromeT {
    if (_loading || _results.isEmpty || _error != null) return 1;
    return _resultsChrome.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final resultsMode = _phase == _SearchPhase.results;
    final lightBar = !resultsMode || _chromeT > 0.55;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            lightBar ? Brightness.dark : Brightness.light,
        statusBarBrightness:
            lightBar ? Brightness.light : Brightness.dark,
      ),
      child: resultsMode
          ? _buildResultsShell(top)
          : ColoredBox(
              color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: top + 4),
                  _buildSearchBar(dark: false),
                  Expanded(
                    child: switch (_phase) {
                      _SearchPhase.idle => _buildDiscover(),
                      _SearchPhase.suggest => _buildSuggest(),
                      _SearchPhase.results => const SizedBox.shrink(),
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildResultsShell(double top) {
    final t = _chromeT;
    final showCats = !_loading &&
        _channelResults.isNotEmpty &&
        t < 0.92 &&
        (_searchChannels.isEmpty ||
            _searchChannels[_resultTopTab.clamp(0, _searchChannels.length - 1)]
                    .typeId ==
                null);
    final radius = 18.0 * (1.0 - t);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 封面模糊底始终在，白底按滚动渐显，避免硬切
        if (!_loading && _results.isNotEmpty)
          Positioned.fill(
            child: _SearchCoverBlurBg(coverUrl: _resultCoverUrl),
          )
        else
          const ColoredBox(color: Colors.white),
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
              color: Color.lerp(Colors.transparent, Colors.white, t)!,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: top + 2),
            _buildSearchBar(lightProgress: t),
            _buildResultTopTabs(lightProgress: t),
            if (showCats)
              Opacity(
                opacity: (1.0 - t).clamp(0.0, 1.0),
                child: _buildResultCatStrip(dark: t < 0.45),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  child: _buildResultsScrollHost(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultsScrollHost() {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_results.isEmpty || _loading) return false;
        if (n.metrics.axis != Axis.vertical) return false;
        final raw = (n.metrics.pixels / 140).clamp(0.0, 1.0);
        final next = Curves.easeOutCubic.transform(raw);
        if ((next - _resultsChrome).abs() < 0.01) return false;
        setState(() => _resultsChrome = next);
        return false;
      },
      child: _buildResultsBody(),
    );
  }

  Widget _buildResultTopTabs({required double lightProgress}) {
    final t = lightProgress.clamp(0.0, 1.0);
    final tabs = _orderedSearchChannels;
    final showBadge = !_loading && _results.isNotEmpty;
    final selected = (_resultTopTab >= 0 && _resultTopTab < _searchChannels.length)
        ? _searchChannels[_resultTopTab]
        : null;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, i) {
          final ch = tabs[i];
          final on = selected != null &&
              selected.name == ch.name &&
              selected.typeId == ch.typeId;
          final label = ch.name;
          final count = showBadge ? _countForChannel(ch) : 0;
          final Color onColor =
              Color.lerp(Colors.white, _ink, t)!;
          final Color offColor = Color.lerp(
            Colors.white.withValues(alpha: 0.72),
            const Color(0xFF8E8E93),
            t,
          )!;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              final orig = _searchChannels.indexWhere(
                (c) => c.name == ch.name && c.typeId == ch.typeId,
              );
              setState(() {
                _resultTopTab = orig >= 0 ? orig : 0;
                _resultCat = '全部';
                _syncChannelTypeIds();
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Stack(
                  clipBehavior: Clip.none,
        children: [
          Padding(
                      padding: EdgeInsets.only(
                        right: showBadge && count > 0 ? 10 : 0,
                        top: showBadge && count > 0 ? 4 : 0,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: on ? 16 : 14,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on ? onColor : offColor,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (showBadge && count > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.1,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: 16,
                  height: 3,
                  decoration: BoxDecoration(
                    color: on
                        ? Color.lerp(Colors.white, _accentTeal, t)!
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 「全部」置顶；其余按命中数降序，有数据优先
  List<MacCmsSearchChannel> get _orderedSearchChannels {
    if (_searchChannels.isEmpty) return const [];
    final all = <MacCmsSearchChannel>[];
    final rest = <MacCmsSearchChannel>[];
    for (final c in _searchChannels) {
      if (c.typeId == null) {
        all.add(c);
      } else {
        rest.add(c);
      }
    }
    rest.sort((a, b) {
      final ca = _countForChannel(a);
      final cb = _countForChannel(b);
      if (ca != cb) return cb.compareTo(ca);
      return a.name.compareTo(b.name);
    });
    return [...all, ...rest];
  }

  Widget _buildResultCatStrip({required bool dark}) {
    if (_loading || _results.isEmpty) {
      return const SizedBox(height: 8);
    }
    final cats = _resultCats();
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = cats[i];
          final on = c.name == _resultCat;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _resultCat = c.name);
            },
            child: _ResultCatChip(
              label: c.name,
              count: c.count,
              coverUrl: c.cover?.coverUrl,
              selected: on,
              dark: dark,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar({bool dark = false, double? lightProgress}) {
    final Color fill;
    final Color icon;
    final Color text;
    final Color hint;
    if (lightProgress != null) {
      final t = lightProgress.clamp(0.0, 1.0);
      fill = Color.lerp(
        Colors.white.withValues(alpha: 0.18),
        const Color(0xFFF2F3F5),
        t,
      )!;
      icon = Color.lerp(
        Colors.white.withValues(alpha: 0.75),
        const Color(0xFFB0B3B8),
        t,
      )!;
      text = Color.lerp(Colors.white, const Color(0xFF1C1C1E), t)!;
      hint = Color.lerp(
        Colors.white.withValues(alpha: 0.55),
        const Color(0xFFB0B3B8),
        t,
      )!;
    } else if (dark) {
      fill = Colors.white.withValues(alpha: 0.18);
      icon = Colors.white.withValues(alpha: 0.75);
      text = Colors.white;
      hint = Colors.white.withValues(alpha: 0.55);
    } else {
      fill = const Color(0xFFF2F3F5);
      icon = const Color(0xFFB0B3B8);
      text = const Color(0xFF1C1C1E);
      hint = const Color(0xFFB0B3B8);
    }
    final darkCursor = lightProgress != null
        ? lightProgress < 0.5
        : dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Row(
              children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.search_rounded, size: 20, color: icon),
                    const SizedBox(width: 6),
                Expanded(
                      child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                        autofocus: false,
                        textInputAction: TextInputAction.search,
                        cursorWidth: 1.5,
                        cursorColor: darkCursor
                            ? Colors.white
                            : const Color(0xFF007AFF),
                        style: TextStyle(
                      fontFamily: 'AppSans',
                          fontSize: 15,
                          height: 1.2,
                          color: text,
                          decoration: TextDecoration.none,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          filled: false,
                          hintText: _placeholder,
                          hintStyle: TextStyle(
                      fontFamily: 'AppSans',
                            fontSize: 15,
                            height: 1.2,
                            color: hint,
                            decoration: TextDecoration.none,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (q) {
                          setState(() {});
                          _onQueryChanged(q);
                        },
                        onSubmitted: (q) {
                          _debounce?.cancel();
                          unawaited(_runSearch(q));
                        },
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _controller.clear();
                          setState(() {});
                          _onQueryChanged('');
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.cancel_rounded,
                            size: 18,
                            color: icon,
                          ),
                        ),
                      ),
                    if (!(lightProgress != null ? lightProgress < 0.5 : dark))
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
                          child: Icon(
                            Icons.mic_none_rounded,
                            size: 20,
                            color: icon,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 12),
              ],
            ),
          ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '取消',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: text,
                  height: 1,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscover() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(child: _buildHistory()),
        SliverToBoxAdapter(child: _buildDiscoverTabs()),
        if (_discoverTab == 0)
          ..._rankSlivers()
        else
          ..._findSlivers(),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) return const SizedBox(height: 4);

    final collapsed = !_historyExpanded && _history.length > 6;
    final shown = collapsed ? _history.take(6).toList() : _history;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
        children: [
          const Text(
                '历史',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _ink,
              decoration: TextDecoration.none,
            ),
          ),
              const Spacer(),
              GestureDetector(
                onTap: () => unawaited(_clearHistory()),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    CupertinoIcons.trash,
                    size: 18,
                    color: Color(0xFF9AA0A6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in shown)
                GestureDetector(
                  onTap: () => _applyKeyword(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _chipBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      q,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: Color(0xFF3A3A3C),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_history.length > 6) ...[
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _historyExpanded = !_historyExpanded);
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _historyExpanded ? '收起' : '展开',
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: _muted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Icon(
                      _historyExpanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 14,
                      color: _muted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscoverTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          _DiscoverTab(
            label: '榜单',
            selected: _discoverTab == 0,
            onTap: () => setState(() => _discoverTab = 0),
          ),
          const SizedBox(width: 22),
          _DiscoverTab(
            label: '找片',
            selected: _discoverTab == 1,
            onTap: () {
              setState(() => _discoverTab = 1);
              if (_findMovies.isEmpty && !_findLoading) {
                unawaited(_loadFind(_findChannel));
              }
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _rankSlivers() {
    final boards = <({
      String title,
      String? hotBadge,
      Color accent,
      List<Movie> items,
    })>[
      (
        title: '热搜',
        hotBadge: 'HOT',
        accent: const Color(0xFFFF3B5C),
        items: _hotBoard,
      ),
      (
        title: '电视剧',
        hotBadge: null,
        accent: const Color(0xFFFF6A00),
        items: _tvBoard,
      ),
      (
        title: '电影',
        hotBadge: null,
        accent: const Color(0xFFFF6A00),
        items: _movieBoard,
      ),
      (
        title: '综艺',
        hotBadge: null,
        accent: const Color(0xFFFF6A00),
        items: _varietyBoard,
      ),
      (
        title: '动漫',
        hotBadge: null,
        accent: const Color(0xFFFF6A00),
        items: _animeBoard,
      ),
    ];

    if (_boardsLoading && boards.every((b) => b.items.isEmpty)) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: FigmaMetaballLoader(size: 56)),
          ),
        ),
      ];
    }

    const boardH = 528.0;

    return [
      SliverToBoxAdapter(
        child: SizedBox(
          height: boardH,
          child: PageView.builder(
            controller: _rankPageCtrl,
            padEnds: false,
            itemCount: boards.length,
            itemBuilder: (context, i) {
              final b = boards[i];
              return Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 16 : 6,
                  right: i == boards.length - 1 ? 16 : 0,
                  bottom: 8,
                ),
                child: _RankBoardCard(
                  title: b.title,
                  hotBadge: b.hotBadge,
                  accent: b.accent,
                  items: b.items,
                  onTapItem: _open,
                  onTitleTap: () {
                    if (b.hotBadge != null) return;
                    Navigator.of(context).push(
                      AppPageRoute<void>(
                        builder: (_) => const VodFilterPage(),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    ];
  }

  List<Widget> _findSlivers() {
    return [
      SliverToBoxAdapter(
        child: SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: _findChannels.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final on = i == _findChannel;
              return GestureDetector(
                onTap: () => unawaited(_loadFind(i)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? _ink : _chipBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _findChannels[i],
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: on ? Colors.white : const Color(0xFF4B5563),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      if (_findLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: FigmaMetaballLoader(size: 48)),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 0.52,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final m = _findMovies[i];
                return MoviePosterCard(
                  movie: m,
                  width: double.infinity,
                  onTap: () => _open(m),
                );
              },
              childCount: _findMovies.length,
            ),
          ),
        ),
    ];
  }

  Widget _buildSuggest() {
    if (_suggestLoading && _suggestRich.isEmpty && _suggestTexts.isEmpty) {
      return const Center(child: FigmaMetaballLoader(size: 48));
    }
    final q = _controller.text.trim();
    if (_suggestRich.isEmpty && _suggestTexts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '暂无联想结果',
                style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 14,
                  color: _muted,
                        decoration: TextDecoration.none,
                ),
              ),
              if (q.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '没搜到「$q」相关内容',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFFB0B0B5),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => unawaited(
                      showRequestVodSheet(context, keyword: q),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accentTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    child: const Text(
                      '求片',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        for (final item in _suggestRich) ...[
          _SuggestRichTile(
            item: item,
            query: q,
            onTap: () {
              if (item.isSeries) {
                _applyKeyword(item.title, toResults: true);
              } else if (item.movie != null) {
                unawaited(_runSearch(item.movie!.title));
                _controller.text = item.movie!.title;
              }
            },
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
        ],
        for (final t in _suggestTexts) ...[
          _SuggestTextTile(
            text: t,
            query: q,
            onTap: () => _applyKeyword(t, toResults: true),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),
        ],
      ],
    );
  }

  List<Movie> get _channelResults {
    final allow = _channelTypeIds;
    if (allow == null || allow.isEmpty) return _results;
    return [for (final m in _results) if (allow.contains(m.typeId)) m];
  }

  List<({String name, int count, Movie? cover})> _resultCats() {
    final pool = _channelResults;
    final counts = <String, int>{'全部': pool.length};
    final covers = <String, Movie>{};
    final order = <String>['全部'];
    for (final m in pool) {
      final c = categoryOf(m);
      if (!counts.containsKey(c)) {
        counts[c] = 0;
        order.add(c);
      }
      counts[c] = (counts[c] ?? 0) + 1;
      covers.putIfAbsent(c, () => m);
    }
    if (pool.isNotEmpty) covers.putIfAbsent('全部', () => pool.first);
    // 有数据优先，按数量降序
    order.sort((a, b) {
      if (a == '全部') return -1;
      if (b == '全部') return 1;
      final ca = counts[a] ?? 0;
      final cb = counts[b] ?? 0;
      if (ca != cb) return cb.compareTo(ca);
      return a.compareTo(b);
    });
    return [
      for (final name in order)
        if (name == '全部' || (counts[name] ?? 0) > 0)
          (name: name, count: counts[name] ?? 0, cover: covers[name]),
    ];
  }

  List<Movie> get _filteredResults {
    final pool = _channelResults;
    if (_resultCat == '全部') return pool;
    return [
      for (final m in pool)
        if (categoryOf(m) == _resultCat) m,
    ];
  }

  (Movie? best, List<Movie> others) _splitFiltered() {
    final list = _filteredResults;
    if (list.isEmpty) return (null, const []);
    Movie? best = _bestMatch;
    if (best == null || !list.any((m) => m.id == best!.id)) {
      best = _pickBest(list, _resultQuery) ?? list.first;
    }
    final bestId = best.id;
    final others = [
      for (final m in list)
        if (m.id != bestId) m,
    ];
    return (best, others);
  }

  Widget _buildResultsBody() {
    if (_loading) {
      return const Center(child: FigmaMetaballLoader(size: 56));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                color: _muted,
                decoration: TextDecoration.none,
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_runSearch(_controller.text)),
              style: TextButton.styleFrom(foregroundColor: _accentTeal),
              child: const Text(
                '重试',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      final q = _resultQuery.trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
          '没有找到相关内容',
          style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A3A3C),
                  decoration: TextDecoration.none,
                ),
              ),
              if (q.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '「$q」暂无资源',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFFAEAEB2),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: () => unawaited(
                      showRequestVodSheet(context, keyword: q),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accentTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(23),
                      ),
                    ),
                    child: const Text(
                      '求片',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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

    final split = _splitFiltered();
    final best = split.$1;
    final others = split.$2;

    if (best == null && others.isEmpty) {
      final ch = _searchChannels.isEmpty
          ? '该分类'
          : _searchChannels[
                  _resultTopTab.clamp(0, _searchChannels.length - 1)]
              .name;
      final q = _resultQuery.trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '「$q」在$ch下暂无结果',
                textAlign: TextAlign.center,
                style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 15,
                  color: _muted,
            decoration: TextDecoration.none,
                ),
              ),
              if (q.isNotEmpty) ...[
                const SizedBox(height: 22),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: () => unawaited(
                      showRequestVodSheet(context, keyword: q),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accentTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(23),
                      ),
                    ),
                    child: const Text(
                      '求片',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        if (best != null)
          SliverToBoxAdapter(
            child: _BestMatchCard(
              movie: best,
              gridMode: _resultsGridMode,
              onLayoutChanged: (v) => setState(() => _resultsGridMode = v),
              onOpen: () => _open(best),
              onPlay: () => _open(best),
              onDownload: () => unawaited(_openDownload(best)),
              onMoreEpisodes: () => unawaited(_openEpisodeList(best)),
            ),
          ),
        if (others.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(
                _resultQuery.isEmpty
                    ? '其他作品'
                    : '$_resultQuery其他作品',
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          // 其他作品：默认宫格（图一）；切换列表后为竖图长条（图二）
          if (_resultsGridMode)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.52,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final m = others[i];
            return MoviePosterCard(
              movie: m,
                      width: double.infinity,
              onTap: () => _open(m),
            );
          },
                  childCount: others.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final m = others[i];
                    return _SearchResultListTile(
                      movie: m,
                      onTap: () => _open(m),
                    );
                  },
                  childCount: others.length,
                ),
              ),
            ),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

/// 搜索结果顶栏：封面图放大模糊取色
class _SearchCoverBlurBg extends StatelessWidget {
  const _SearchCoverBlurBg({this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = CmsCoverImage.resolve(coverUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF3D241F)),
        if (url != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Transform.scale(
              scale: 1.25,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.low,
                headers: CmsCoverImage.headers,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.28),
                Colors.black.withValues(alpha: 0.42),
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: selected ? 20 : 16,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          color: selected ? const Color(0xFF1A1A1A) : const Color(0xFF9AA0A6),
          height: 1.1,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _RankBoardCard extends StatelessWidget {
  const _RankBoardCard({
    required this.title,
    required this.accent,
    required this.items,
    required this.onTapItem,
    this.hotBadge,
    this.onTitleTap,
  });

  final String title;
  final String? hotBadge;
  final Color accent;
  final List<Movie> items;
  final ValueChanged<Movie> onTapItem;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECECED)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onTitleTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                if (hotBadge != null) ...[
                  ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      colors: [Color(0xFFFF2D55), Color(0xFFFF7A45)],
                    ).createShader(rect),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hotBadge!,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: accent.withValues(alpha: 0.9),
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ] else
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      height: 1.1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                const Spacer(),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 15,
                  color: (hotBadge != null ? accent : accent)
                      .withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      '暂无榜单',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: Color(0xFF9AA0A6),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < items.length.clamp(0, 6); i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _RankRow(
                          rank: i + 1,
                          movie: items[i],
                          onTap: () => onTapItem(items[i]),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.movie,
    required this.onTap,
  });

  final int rank;
  final Movie movie;
  final VoidCallback onTap;

  Color get _badgeColor => switch (rank) {
        1 => const Color(0xFFFF3B30),
        2 => const Color(0xFFFF9500),
        3 => const Color(0xFFFFCC00),
        _ => const Color(0xFF3A3A3C),
      };

  List<({IconData icon, String text})> get _tags {
    final out = <({IconData icon, String text})>[];
    if (movie.scoreCount > 0) {
      final n = movie.scoreCount >= 10000
          ? '${(movie.scoreCount / 10000).toStringAsFixed(1)}万'
          : '${movie.scoreCount}';
      out.add((icon: CupertinoIcons.chat_bubble_fill, text: '讨论破 $n'));
    }
    if (movie.score > 0) {
      out.add((
        icon: CupertinoIcons.flame_fill,
        text: '评分 ${movie.scoreLabel}',
      ));
    } else if (movie.remarks.trim().isNotEmpty) {
      final r = movie.remarks.trim();
      if (r.length <= 12) {
        out.add((icon: CupertinoIcons.flame_fill, text: r));
      }
    }
    return out.take(2).toList();
  }

  String get _meta {
    final parts = <String>[];
    if (movie.year > 0) parts.add('${movie.year}');
    parts.add(_categoryOf(movie));
    final actors = [
      for (final c in movie.cast.take(3))
        if (c.name.trim().isNotEmpty) c.name.trim(),
    ];
    if (actors.isEmpty && movie.director.trim().isNotEmpty) {
      parts.add(movie.director.trim());
    } else {
      parts.addAll(actors);
    }
    return parts.join(' ');
  }

  static String _categoryOf(Movie m) {
    return _MovieSearchPageState.categoryOfStatic(m);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            height: 66,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ColoredBox(
                      color: const Color(0xFFF0F0F2),
                      child: CmsCoverImage(
                        url: movie.coverUrl,
                        vodId: movie.id,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _badgeColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                    decoration: TextDecoration.none,
                  ),
                ),
                if (_tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final t in _tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x14FF6A00),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.icon, size: 10, color: const Color(0xFFFF6A00)),
                              const SizedBox(width: 2),
                              Text(
                                t.text,
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 10,
                                  color: Color(0xFFFF6A00),
                                  height: 1.1,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 11,
                    color: Color(0xFF9AA0A6),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestRich {
  const _SuggestRich._({
    required this.title,
    required this.isSeries,
    this.movie,
    this.cover,
    this.count = 0,
  });

  factory _SuggestRich.movie(Movie m) => _SuggestRich._(
        title: m.title,
        isSeries: false,
        movie: m,
        cover: m,
      );

  factory _SuggestRich.series({
    required String title,
    required Movie cover,
    required int count,
  }) =>
      _SuggestRich._(
        title: title,
        isSeries: true,
        cover: cover,
        count: count,
      );

  final String title;
  final bool isSeries;
  final Movie? movie;
  final Movie? cover;
  final int count;
}

class _SuggestRichTile extends StatelessWidget {
  const _SuggestRichTile({
    required this.item,
    required this.query,
    required this.onTap,
  });

  final _SuggestRich item;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final movie = item.cover ?? item.movie;
    final tag = item.isSeries
        ? '系列'
        : (movie == null
            ? '影视'
            : _MovieSearchPageState.categoryOfStatic(movie));
    final tagGreen = item.isSeries;
    final sub = item.isSeries
        ? '共${item.count}部作品'
        : _metaLine(movie);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 44,
                height: 60,
                child: ColoredBox(
                  color: const Color(0xFFF0F0F2),
                  child: movie == null
                      ? const SizedBox.shrink()
                      : CmsCoverImage(url: movie.coverUrl, vodId: movie.id),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: SearchHighlightText(
                          text: item.isSeries
                              ? item.title
                              : (movie?.title ?? item.title),
                          query: query,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _TypeTag(label: tag, green: tagGreen),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: Color(0xFF9A9A9A),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _metaLine(Movie? m) {
    if (m == null) return '';
    final actors = [
      for (final c in m.cast.take(3))
        if (c.name.trim().isNotEmpty) c.name.trim(),
    ];
    final parts = <String>[
      if (m.year > 0) '${m.year}',
      ...actors,
    ];
    if (parts.isEmpty && m.director.trim().isNotEmpty) {
      return m.director.trim();
    }
    return parts.join(' · ');
  }
}

class _SuggestTextTile extends StatelessWidget {
  const _SuggestTextTile({
    required this.text,
    required this.query,
    required this.onTap,
  });

  final String text;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: SearchHighlightText(
          text: text,
          query: query,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1A1A1A),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.label, this.green = false});

  final String label;
  final bool green;

  @override
  Widget build(BuildContext context) {
    final bg = green ? const Color(0x1A34C759) : const Color(0x1A5AC8FA);
    final fg = green ? const Color(0xFF34C759) : const Color(0xFF5AC8FA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}


class _ResultCatChip extends StatelessWidget {
  const _ResultCatChip({
    required this.label,
    required this.count,
    required this.selected,
    this.coverUrl,
    this.dark = false,
  });

  final String label;
  final int count;
  final bool selected;
  final String? coverUrl;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? Colors.white
        : (dark
            ? Colors.white.withValues(alpha: 0.16)
            : const Color(0xFFF7F7F8));
    final fg = selected
        ? const Color(0xFF1A1A1A)
        : (dark ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF1A1A1A));
    final sub = selected
        ? const Color(0xFF8E8E93)
        : (dark
            ? Colors.white.withValues(alpha: 0.7)
            : const Color(0xFF8E8E93));
    final arrow = selected ? Colors.white : Colors.transparent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 58,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? null
                : Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFFE8E8EA),
                  ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 26,
                  height: 34,
                  child: ColoredBox(
                    color: const Color(0xFFE8E8EA),
                    child: coverUrl == null || coverUrl!.isEmpty
                        ? const Icon(
                            Icons.movie,
                            size: 12,
                            color: Color(0xFFB0B0B0),
                          )
                        : CmsCoverImage(url: coverUrl),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        height: 1.1,
                        color: fg,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count部',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                        color: sub,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (selected)
          CustomPaint(
            size: const Size(12, 6),
            painter: _CatArrowPainter(color: arrow),
          )
        else
          const SizedBox(height: 6),
      ],
    );
  }
}

class _CatArrowPainter extends CustomPainter {
  _CatArrowPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CatArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _BestMatchCard extends StatelessWidget {
  const _BestMatchCard({
    required this.movie,
    required this.gridMode,
    required this.onLayoutChanged,
    required this.onOpen,
    required this.onPlay,
    required this.onDownload,
    required this.onMoreEpisodes,
  });

  final Movie movie;
  final bool gridMode;
  final ValueChanged<bool> onLayoutChanged;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final VoidCallback onMoreEpisodes;

  @override
  Widget build(BuildContext context) {
    final eps = movie.episodeLabels;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.flame_fill,
                size: 16,
                color: Color(0xFFFF3B30),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  '正在热播',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              _SearchLayoutToggle(
                gridMode: gridMode,
                onChanged: onLayoutChanged,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 最佳匹配始终竖海报+信息+播放/下载；布局开关只改「其他作品」
          _SearchResultListTile(
            movie: movie,
            onTap: onOpen,
            showRankTags: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: onPlay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1ECAD3),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    icon: const Icon(CupertinoIcons.play_fill, size: 18),
                    label: const Text(
                      '立即播放',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: onDownload,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A1A1A),
                      backgroundColor: const Color(0xFFF3F3F5),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    icon: const Icon(
                      CupertinoIcons.arrow_down_to_line,
                      size: 18,
                    ),
                    label: const Text(
                      '下载',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (eps.length > 1) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const chip = MangoWatchStyle.chipSize;
                const gap = MangoWatchStyle.chipGap;
                final slots = ((constraints.maxWidth + gap) / (chip + gap))
                    .floor()
                    .clamp(2, 16);
                final epIdx = _epIndexes(eps.length, slots);
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final i in epIdx)
                      SizedBox(
                        width: chip,
                        height: chip,
                        child: i < 0
                            ? MangoEpisodeChip(
                                label: '…',
                                selected: false,
                                size: chip,
                                onTap: onMoreEpisodes,
                              )
                            : MangoEpisodeChip(
                                label: '${i + 1}',
                                selected: false,
                                size: chip,
                                onTap: onOpen,
                              ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  static List<int> _epIndexes(int total, int slots) {
    if (total <= 0 || slots <= 0) return const [];
    if (total <= slots) return [for (var i = 0; i < total; i++) i];
    if (slots < 5) {
      return [for (var i = 0; i < slots; i++) i];
    }
    const tail = 3;
    final head = slots - 1 - tail;
    return [
      for (var i = 0; i < head; i++) i,
      -1,
      for (var i = total - tail; i < total; i++) i,
    ];
  }
}

class _SearchLayoutToggle extends StatelessWidget {
  const _SearchLayoutToggle({
    required this.gridMode,
    required this.onChanged,
  });

  final bool gridMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!gridMode);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              gridMode
                  ? CupertinoIcons.list_bullet
                  : CupertinoIcons.square_grid_2x2,
              size: 15,
              color: const Color(0xFF1ECAD3),
            ),
            const SizedBox(width: 4),
            Text(
              gridMode ? '列表' : '宫格',
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1ECAD3),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultListTile extends StatelessWidget {
  const _SearchResultListTile({
    required this.movie,
    required this.onTap,
    this.showRankTags = false,
  });

  final Movie movie;
  final VoidCallback onTap;
  final bool showRankTags;

  static const _posterW = 92.0;
  static const _posterH = 128.0;

  List<({IconData icon, String text})> get _tags {
    final out = <({IconData icon, String text})>[];
    final cat = _MovieSearchPageState.categoryOfStatic(movie);
    if (movie.score > 0) {
      out.add((
        icon: CupertinoIcons.star_fill,
        text: '评分 ${movie.scoreLabel}',
      ));
    }
    if (movie.scoreCount > 0) {
      final n = movie.scoreCount >= 10000
          ? '${(movie.scoreCount / 10000).toStringAsFixed(1)}万'
          : '${movie.scoreCount}';
      out.add((
        icon: CupertinoIcons.flame_fill,
        text: '$cat热搜 · 讨论$n',
      ));
    }
    return out.take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cat = _MovieSearchPageState.categoryOfStatic(movie);
    final badge = movie.cornerBadge;
    final actors = [
      for (final c in movie.cast.take(5))
        if (c.name.trim().isNotEmpty) c.name.trim(),
    ].join(' ');
    final blurb = actors.isNotEmpty
        ? actors
        : (movie.synopsis.trim().isNotEmpty
            ? movie.synopsis.trim()
            : movie.tagline);
    final meta = [
      cat,
      if (movie.area.trim().isNotEmpty) movie.area.trim(),
      if (movie.lang.trim().isNotEmpty) movie.lang.trim(),
    ].join(' ');
    final tags = showRankTags ? _tags : const <({IconData icon, String text})>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: _posterW,
                height: _posterH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: const Color(0xFFF0F0F2),
                      child: CmsCoverImage(
                        url: movie.coverUrl,
                        vodId: movie.id,
                      ),
                    ),
                    if (movie.year > 0)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: _PosterBadge('${movie.year}'),
                      ),
                    if (badge != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: _PosterBadge(
                          badge,
                          color: const Color(0xFFFF6A00),
                        ),
                      ),
                    if (cat.isNotEmpty)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: _PosterBadge(cat),
                      ),
                    if (movie.remarks.trim().isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: _PosterBadge(
                          movie.remarks.trim().length > 6
                              ? movie.remarks.trim().substring(0, 6)
                              : movie.remarks.trim(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                      height: 1.25,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final t in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1E8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  t.icon,
                                  size: 11,
                                  color: const Color(0xFFFF6A00),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  t.text,
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF6A00),
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  if (blurb.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      blurb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF8E8E93),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge(this.text, {this.color = const Color(0x99000000)});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 10,
          color: Colors.white,
          height: 1.1,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
