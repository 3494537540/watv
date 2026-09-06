import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../models/movie_models.dart';
import '../services/maccms_api.dart';
import '../state/theme_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/figma_loading.dart';
import '../widgets/movie_poster_card.dart';
import '../widgets/press_scale.dart';
import 'movie_detail_page.dart';

class _FilterChannel {
  const _FilterChannel({required this.name, this.typeId});
  final String name;
  final int? typeId;
}

/// 影视片库：频道来自 CMS class[]，子类完整加载
class VodFilterPage extends StatefulWidget {
  const VodFilterPage({super.key});

  @override
  State<VodFilterPage> createState() => _VodFilterPageState();
}

class _VodFilterPageState extends State<VodFilterPage> {
  Color get _ink => AppPalette.text(context);
  Color get _muted => AppPalette.textHint(context);
  Color get _pageBg => AppPalette.page(context);
  static Color get _accent => AppColors.brand;
  static const _pageSize = 30;
  static const _excludeRoots = {20, 30}; // 成人 / 里番

  final _cms = MacCmsApi();
  final _scroll = ScrollController();

  List<MacCmsTypeNode> _allTypes = const [];
  List<_FilterChannel> _channels = const [
    _FilterChannel(name: '全部'),
    _FilterChannel(name: '电影', typeId: 1),
    _FilterChannel(name: '电视剧', typeId: 2),
    _FilterChannel(name: '综艺', typeId: 3),
    _FilterChannel(name: '动漫', typeId: 4),
    _FilterChannel(name: '短剧', typeId: ApiConfig.macCmsShortDramaTypeId),
  ];

  int _channel = 1;
  int? _classTypeId;
  String _area = '全部';
  String _year = '全部';
  bool _typesReady = false;

  List<Movie> _movies = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _pageIndex = 1;
  int _loadSeq = 0;
  String? _error;

  _FilterChannel get _ch =>
      _channels[_channel.clamp(0, _channels.length - 1)];

  List<MacCmsClassOption> get _classOptions {
    final root = _ch.typeId;
    if (root == null) {
      // 「全部」频道不堆全部子类，避免横滑过长；选具体频道再出分类
      return const [MacCmsClassOption(label: '全部')];
    }
    final kids = <MacCmsClassOption>[
      const MacCmsClassOption(label: '全部'),
      for (final t in _allTypes)
        if (t.typePid == root)
          MacCmsClassOption(label: t.typeName.trim(), typeId: t.typeId),
    ];
    return kids;
  }

  List<String> get _areas {
    final f = ApiConfig.macCmsLibraryFiltersFor(_ch.name);
    if (f.areas.length > 1) return f.areas;
    return const [
      '全部',
      '大陆',
      '内地',
      '香港',
      '台湾',
      '日本',
      '韩国',
      '美国',
      '英国',
      '法国',
      '泰国',
      '其他',
    ];
  }

  /// 年代始终按当前年往前排，不再用停在 2018 的写死表
  List<String> get _years {
    final y = DateTime.now().year;
    return [
      '全部',
      for (var i = 0; i < 25; i++) '${y - i}',
    ];
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_boot());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final types = await _cms.fetchVodTypes();
      if (!mounted) return;
      if (types.isNotEmpty) {
        final roots = [
          for (final t in types)
            if (t.typePid == 0 && !_excludeRoots.contains(t.typeId)) t,
        ];
        // 主流频道靠前，其余按 id
        const prefer = [1, 2, 3, 4, 44, 48];
        roots.sort((a, b) {
          final pa = prefer.indexOf(a.typeId);
          final pb = prefer.indexOf(b.typeId);
          final ia = pa < 0 ? 1000 + a.typeId : pa;
          final ib = pb < 0 ? 1000 + b.typeId : pb;
          return ia.compareTo(ib);
        });
        final channels = <_FilterChannel>[
          const _FilterChannel(name: '全部'),
          for (final t in roots)
            _FilterChannel(name: t.typeName.trim(), typeId: t.typeId),
        ];
        final hasShort = channels.any(
          (c) => c.typeId == ApiConfig.macCmsShortDramaTypeId,
        );
        if (!hasShort) {
          channels.add(
            const _FilterChannel(
              name: '短剧',
              typeId: ApiConfig.macCmsShortDramaTypeId,
            ),
          );
        }
        setState(() {
          _allTypes = types;
          _channels = channels;
          _typesReady = true;
          // 默认电影，找不到则第 1 个有 id 的频道
          final movieIdx = channels.indexWhere(
            (c) => c.typeId == 1 || c.name.contains('电影'),
          );
          _channel = movieIdx >= 0 ? movieIdx : 1.clamp(0, channels.length - 1);
        });
      } else {
        setState(() => _typesReady = true);
      }
    } catch (_) {
      if (mounted) setState(() => _typesReady = true);
    }
    await _reload();
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 640) {
      unawaited(_loadMore());
    }
  }

  Future<void> _onChannel(int i) async {
    if (i == _channel) return;
    HapticFeedback.selectionClick();
    setState(() {
      _channel = i;
      _classTypeId = null;
      _area = '全部';
      _year = '全部';
    });
    await _reload();
  }

  Future<void> _onClass(MacCmsClassOption opt) async {
    if (opt.typeId == _classTypeId) return;
    HapticFeedback.selectionClick();
    setState(() => _classTypeId = opt.typeId);
    await _reload();
  }

  Future<void> _onArea(String area) async {
    if (area == _area) return;
    HapticFeedback.selectionClick();
    setState(() => _area = area);
    await _reload();
  }

  Future<void> _onYear(String year) async {
    if (year == _year) return;
    HapticFeedback.selectionClick();
    setState(() => _year = year);
    await _reload();
  }

  Future<List<Movie>> _fetchPage(int page) {
    return _cms.fetchLibraryShow(
      channelTypeId: _ch.typeId,
      classTypeId: _classTypeId,
      area: _area,
      year: _year,
      page: page,
      limit: _pageSize,
    );
  }

  Future<void> _reload() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
      _pageIndex = 1;
      _hasMore = true;
      _movies = const [];
    });
    try {
      final list = await _fetchPage(1);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _movies = list;
        _loading = false;
        _hasMore = list.length >= (_pageSize * 0.5).floor();
        _pageIndex = 1;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _movies = const [];
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    final next = _pageIndex + 1;
    final seq = _loadSeq;
    try {
      final more = await _fetchPage(next);
      if (!mounted || seq != _loadSeq) return;
      final seen = {for (final m in _movies) m.id};
      final appended = [
        for (final m in more)
          if (seen.add(m.id)) m,
      ];
      setState(() {
        _movies = [..._movies, ...appended];
        _pageIndex = next;
        _hasMore = appended.length >= (_pageSize * 0.35).floor();
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _openDetail(Movie movie) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => MovieDetailPage(movie: movie),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final classes = _classOptions;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: _pageBg,
        child: AppPullRefresh(
          color: AppColors.brand,
          edgeOffset: top,
          onRefresh: _reload,
          child: CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: top + 6)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '片库',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          height: 1.05,
                          letterSpacing: 0.5,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          !_typesReady || _loading
                              ? '加载中…'
                              : '${_movies.length} 部',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _muted,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_typesReady)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: WatvPageLoader(size: 48),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _FilterTextRow(
                              accent: _accent,
                              labels: [for (final c in _channels) c.name],
                              selected: _ch.name,
                              onSelected: (name) {
                                final i =
                                    _channels.indexWhere((c) => c.name == name);
                                if (i >= 0) unawaited(_onChannel(i));
                              },
                            ),
                            const _FilterDots(),
                            _FilterTextRow(
                              accent: _accent,
                              labels: [for (final c in classes) c.label],
                              selected: () {
                                for (final c in classes) {
                                  if (c.typeId == _classTypeId) return c.label;
                                }
                                return '全部';
                              }(),
                              onSelected: (name) {
                                for (final c in classes) {
                                  if (c.label == name) {
                                    unawaited(_onClass(c));
                                    break;
                                  }
                                }
                              },
                            ),
                            const _FilterDots(),
                            _FilterTextRow(
                              accent: _accent,
                              labels: _areas,
                              selected: _area,
                              onSelected: (a) => unawaited(_onArea(a)),
                            ),
                            const _FilterDots(),
                            _FilterTextRow(
                              accent: _accent,
                              labels: _years,
                              selected: _year,
                              onSelected: (y) => unawaited(_onYear(y)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ..._bodySlivers(bottom),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bodySlivers(double bottom) {
    if (_loading && _movies.isEmpty) {
      return [
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(0, 24, 0, 40),
          sliver: SliverToBoxAdapter(
            child: WatvPageLoader(size: 48),
          ),
        ),
      ];
    }
    if (_error != null && _movies.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: TextButton(
              onPressed: () => unawaited(_reload()),
            child: Text(
                '加载失败，点击重试',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 14,
                  color: _muted,
                ),
              ),
            ),
          ),
        ),
      ];
    }
    if (_movies.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              '暂无内容，换个筛选试试',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                color: _muted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ];
    }

    return [
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
              final m = _movies[i];
              return MoviePosterCard(
                movie: m,
                width: double.infinity,
                onTap: () => _openDetail(m),
              );
            },
            childCount: _movies.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 96 + bottom),
          child: FigmaLoadMoreFooter(
            loading: _loadingMore,
            hasMore: _hasMore,
          ),
        ),
      ),
    ];
  }
}

class _FilterDots extends StatelessWidget {
  const _FilterDots();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CustomPaint(
        painter: _DotsPainter(color: const Color(0xFFD8DCE3)),
        child: const SizedBox(width: double.infinity, height: 1),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const step = 5.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawCircle(Offset(x, size.height / 2), 0.8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FilterTextRow extends StatelessWidget {
  const _FilterTextRow({
    required this.labels,
    required this.selected,
    required this.onSelected,
    required this.accent,
  });

  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final name = labels[i];
          final on = name == selected;
          return PressScale(
            scale: 0.94,
            onTap: () => onSelected(name),
            child: AnimatedDefaultTextStyle(
              duration: ThemeController.instance.scaled(
                const Duration(milliseconds: 160),
              ),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? accent : AppPalette.text(context),
                decoration: TextDecoration.none,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, textAlign: TextAlign.left),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: ThemeController.instance.scaled(
                      const Duration(milliseconds: 180),
                    ),
                    curve: Curves.easeOutCubic,
                    height: 2.5,
                    width: on ? 16 : 0,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
