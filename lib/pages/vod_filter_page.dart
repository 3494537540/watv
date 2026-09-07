import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../models/movie_models.dart';
import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import '../widgets/app_page_route.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/figma_loading.dart';
import '../widgets/press_scale.dart';
import 'movie_detail_page.dart';

class _DiscoverChannel {
  const _DiscoverChannel({required this.name, this.typeId});
  final String name;
  final int? typeId;
}

/// 发现页：周热榜单（海报 + 排名角标 + 标签）
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

  final _cms = MacCmsApi();

  List<_DiscoverChannel> _channels = const [
    _DiscoverChannel(name: '全部'),
    _DiscoverChannel(name: '电影', typeId: 1),
    _DiscoverChannel(name: '电视剧', typeId: 2),
    _DiscoverChannel(name: '综艺', typeId: 3),
    _DiscoverChannel(name: '动漫', typeId: 4),
    _DiscoverChannel(name: '短剧', typeId: ApiConfig.macCmsShortDramaTypeId),
  ];

  int _channel = 0;
  List<Movie> _movies = const [];
  bool _loading = true;
  String? _error;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final types = await _cms.fetchVodTypes();
      if (!mounted) return;
      if (types.isNotEmpty) {
        final roots = [
          for (final t in types)
            if (t.typePid == 0 && t.typeId != 20 && t.typeId != 30) t,
        ];
        const prefer = [1, 2, 3, 4, 44, 48];
        roots.sort((a, b) {
          final pa = prefer.indexOf(a.typeId);
          final pb = prefer.indexOf(b.typeId);
          final ia = pa < 0 ? 1000 + a.typeId : pa;
          final ib = pb < 0 ? 1000 + b.typeId : pb;
          return ia.compareTo(ib);
        });
        final channels = <_DiscoverChannel>[
          const _DiscoverChannel(name: '全部'),
          for (final t in roots)
            _DiscoverChannel(name: t.typeName.trim(), typeId: t.typeId),
        ];
        final hasShort = channels.any(
          (c) => c.typeId == ApiConfig.macCmsShortDramaTypeId,
        );
        if (!hasShort) {
          channels.add(
            const _DiscoverChannel(
              name: '短剧',
              typeId: ApiConfig.macCmsShortDramaTypeId,
            ),
          );
        }
        setState(() => _channels = channels);
      }
    } catch (_) {}
    await _reload();
  }

  Future<void> _onChannel(int i) async {
    if (i == _channel) return;
    HapticFeedback.selectionClick();
    setState(() => _channel = i);
    await _reload();
  }

  Future<void> _reload() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ch = _channels[_channel.clamp(0, _channels.length - 1)];
      final list = ch.typeId == null
          ? await _cms.fetchHotMovies(limit: 50)
          : await _cms.fetchWeekHot(typeId: ch.typeId!, limit: 50);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _movies = list;
        _loading = false;
        _error = list.isEmpty ? '暂无榜单内容' : null;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _error = e is MacCmsException ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  void _openMovie(Movie m) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(builder: (_) => MovieDetailPage(movie: m)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: _pageBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: top),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              '发现',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _channels.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == _channel;
                return PressScale(
                  onTap: () => unawaited(_onChannel(i)),
                  scale: 0.96,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? _accent.withValues(alpha: 0.14)
                          : AppPalette.surface(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? _accent.withValues(alpha: 0.45)
                            : AppPalette.line(context),
                      ),
                    ),
                    child: Text(
                      _channels[i].name,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? _accent : _ink,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AppPullRefresh(
              onRefresh: _reload,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _movies.isEmpty) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 8,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: FigmaSkeletonPulse(
            child: SizedBox(
              height: 118,
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    height: 118,
                    child: FigmaCoverPlaceholder(iconSize: 28, radius: 8),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: FigmaCoverPlaceholder(iconSize: 20, radius: 8),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_error != null && _movies.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Text(
                  _error!,
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => unawaited(_reload()),
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: _movies.length,
      itemBuilder: (context, i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _DiscoverScrollIn(
            index: i,
            child: _DiscoverRankRow(
              rank: i + 1,
              movie: _movies[i],
              onTap: () => _openMovie(_movies[i]),
            ),
          ),
        );
      },
    );
  }
}

/// 列表项滑入淡入动效（滚入可视区时播放）
class _DiscoverScrollIn extends StatefulWidget {
  const _DiscoverScrollIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_DiscoverScrollIn> createState() => _DiscoverScrollInState();
}

class _DiscoverScrollInState extends State<_DiscoverScrollIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryPlay());
  }

  void _tryPlay() {
    if (!mounted || _played) return;
    _played = true;
    final delay = (widget.index % 8) * 35;
    Future<void>.delayed(Duration(milliseconds: delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class _DiscoverRankRow extends StatelessWidget {
  const _DiscoverRankRow({
    required this.rank,
    required this.movie,
    required this.onTap,
  });

  final int rank;
  final Movie movie;
  final VoidCallback onTap;

  Color get _badgeColor {
    if (rank == 1) return const Color(0xFFE53935);
    if (rank == 2) return const Color(0xFFFF8A00);
    if (rank == 3) return const Color(0xFF42A5F5);
    return const Color(0xFF5A5A5A);
  }

  List<String> get _tags {
    final out = <String>[];
    for (final g in movie.genres) {
      final t = g.trim();
      if (t.isEmpty || t == movie.area || out.contains(t)) continue;
      out.add(t);
      if (out.length >= 3) break;
    }
    return out;
  }

  String get _statusLine {
    final r = movie.remarks.trim();
    if (r.isNotEmpty) return r;
    final a = movie.area.trim();
    if (a.isNotEmpty) return a;
    if (movie.totalEpisodes > 0) return '全${movie.totalEpisodes}集';
    return movie.subtitle.trim();
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.text(context);
    final muted = AppPalette.textHint(context);
    final chipBg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFF0F0F0);
    final tags = _tags;

    return PressScale(
      onTap: onTap,
      scale: 0.98,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            height: 118,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CmsCoverImage(
                      url: movie.coverUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _badgeColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 118,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: ink,
                      height: 1.2,
                    ),
                  ),
                  Expanded(
                    child: Align(
                      // 类型标签：上下居中（相对片名与底部状态之间）
                      alignment: Alignment.centerLeft,
                      child: tags.isEmpty
                          ? const SizedBox.shrink()
                          : Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final t in tags)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: chipBg,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      t,
                                      style: TextStyle(
                                        fontFamily: 'AppSans',
                                        fontSize: 11,
                                        color: muted,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  if (_statusLine.isNotEmpty)
                    Text(
                      _statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: ink.withValues(alpha: 0.72),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    movie.year > 0 ? '${movie.year}' : '',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
