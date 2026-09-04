import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_models.dart';
import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import '../widgets/figma_loading.dart';
import '../widgets/player/douyin_lite_player.dart';
import '../widgets/player/player_sheets.dart';

class _FeedSlot {
  const _FeedSlot({required this.movieId, required this.ep});
  final String movieId;
  final int ep;
}

/// 竖滑点播 Feed（短剧 / 体育等）：同剧按集竖滑，不进详情页
class VerticalShortFeedPage extends StatefulWidget {
  const VerticalShortFeedPage({
    super.key,
    required this.title,
    required this.typeId,
    this.seed = const [],
    this.initialIndex = 0,
    this.mergeChildTypes = false,
    /// 为 true 时只播 seed 里点中的那一部，竖滑不会切到别的短剧
    this.lockToSeedSeries = false,
  });

  final String title;
  final int typeId;
  final List<Movie> seed;
  final int initialIndex;
  final bool mergeChildTypes;
  final bool lockToSeedSeries;

  @override
  State<VerticalShortFeedPage> createState() => _VerticalShortFeedPageState();
}

class _VerticalShortFeedPageState extends State<VerticalShortFeedPage> {
  final _api = MacCmsApi();
  final _pageCtrl = PageController();
  final List<Movie> _movies = [];
  final Map<String, Movie> _details = {};
  final Set<String> _liked = {};
  List<_FeedSlot> _slots = const [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _index = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (widget.seed.isNotEmpty) {
      if (widget.lockToSeedSeries) {
        final i = widget.initialIndex.clamp(0, widget.seed.length - 1);
        _movies.add(widget.seed[i]);
        _index = 0;
      } else {
        _movies.addAll(widget.seed);
        _index = widget.initialIndex.clamp(0, _movies.length - 1);
      }
      _loading = false;
      _rebuildSlots(preferMovieId: _movies[_index.clamp(0, _movies.length - 1)].id);
    }
    unawaited(_boot());
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _loadLikes();
    if (_movies.isEmpty) {
      await _reload();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(_index);
      });
      unawaited(_prefetchAround(_index));
    }
  }

  Future<void> _loadLikes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('short_feed_likes_v1') ?? const [];
    _liked
      ..clear()
      ..addAll(raw);
  }

  Future<void> _toggleLike(String id) async {
    HapticFeedback.lightImpact();
    setState(() {
      if (!_liked.add(id)) _liked.remove(id);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('short_feed_likes_v1', _liked.toList());
  }

  Future<List<Movie>> _fetchPage(int page, int limit) async {
    if (!widget.mergeChildTypes) {
      return _api.fetchByType(
        typeId: widget.typeId,
        page: page,
        limit: limit,
        applyBannerExclude: false,
      );
    }
    try {
      final types = await _api.fetchVodTypes();
      final kids = [
        for (final t in types)
          if (t.typePid == widget.typeId) t.typeId,
      ];
      final ids = kids.isEmpty ? [widget.typeId] : kids.take(8).toList();
      final pages = await Future.wait([
        for (final id in ids)
          _api.fetchByType(
            typeId: id,
            page: page,
            limit: limit,
            applyBannerExclude: false,
          ),
      ]);
      final seen = <String>{};
      final out = <Movie>[];
      for (final batch in pages) {
        for (final m in batch) {
          if (seen.add(m.id)) out.add(m);
        }
      }
      return out;
    } catch (_) {
      return _api.fetchByType(
        typeId: widget.typeId,
        page: page,
        limit: limit,
        applyBannerExclude: false,
      );
    }
  }

  int _epCount(Movie m) {
    final d = _details[m.id] ?? m;
    final n = d.episodesOf(0).length;
    if (n > 0) return n;
    return (d.playUrlAt(0)?.isNotEmpty == true) ? 1 : 1;
  }

  void _rebuildSlots({String? preferMovieId, int preferEp = 0}) {
    final next = <_FeedSlot>[
      for (final m in _movies)
        for (var e = 0; e < _epCount(m); e++)
          _FeedSlot(movieId: m.id, ep: e),
    ];
    var jump = 0;
    if (preferMovieId != null) {
      final i = next.indexWhere(
        (s) => s.movieId == preferMovieId && s.ep == preferEp,
      );
      if (i >= 0) {
        jump = i;
      } else {
        final j = next.indexWhere((s) => s.movieId == preferMovieId);
        if (j >= 0) jump = j;
      }
    } else if (_slots.isNotEmpty && _index < _slots.length) {
      final cur = _slots[_index];
      final i = next.indexWhere(
        (s) => s.movieId == cur.movieId && s.ep == cur.ep,
      );
      jump = i >= 0 ? i : _index.clamp(0, next.isEmpty ? 0 : next.length - 1);
    }
    _slots = next;
    _index = next.isEmpty ? 0 : jump.clamp(0, next.length - 1);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
    });
    try {
      final list = await _fetchPage(1, 8);
      if (!mounted) return;
      _movies
        ..clear()
        ..addAll(list);
      _rebuildSlots();
      setState(() {
        _loading = false;
        _hasMore = !widget.lockToSeedSeries && list.length >= 4;
      });
      unawaited(_prefetchAround(0));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (widget.lockToSeedSeries || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final more = await _fetchPage(next, 8);
      if (!mounted) return;
      final seen = {for (final m in _movies) m.id};
      final appended = [for (final m in more) if (seen.add(m.id)) m];
      final cur = _slots.isEmpty
          ? null
          : _slots[_index.clamp(0, _slots.length - 1)];
      setState(() {
        _movies.addAll(appended);
        _page = next;
        _hasMore = appended.length >= 3;
        _loadingMore = false;
        _rebuildSlots(
          preferMovieId: cur?.movieId,
          preferEp: cur?.ep ?? 0,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  Future<void> _ensureDetail(String movieId) async {
    final baseIdx = _movies.indexWhere((m) => m.id == movieId);
    if (baseIdx < 0) return;
    final base = _movies[baseIdx];
    final cached = _details[base.id];
    final cachedEps = cached?.episodesOf(0).length ?? 0;
    final baseEps = base.episodesOf(0).length;
    final looksSeries = base.totalEpisodes > 1 ||
        base.remarks.contains('集') ||
        base.remarks.contains('更新') ||
        base.isSeries;
    if (cached != null && (cachedEps > 1 || (!looksSeries && cachedEps >= 1))) {
      return;
    }
    if (!looksSeries &&
        base.playSources.isNotEmpty &&
        base.playUrlAt(0)?.isNotEmpty == true &&
        baseEps <= 1 &&
        cached == null) {
      _details[base.id] = base;
      if (mounted) {
        final cur = _slots.isEmpty
            ? null
            : _slots[_index.clamp(0, _slots.length - 1)];
        setState(() {
          _rebuildSlots(
            preferMovieId: cur?.movieId,
            preferEp: cur?.ep ?? 0,
          );
        });
      }
    }
    try {
      final d = await _api.fetchVodDetail(base.id);
      if (!mounted) return;
      final cur = _slots.isEmpty
          ? null
          : _slots[_index.clamp(0, _slots.length - 1)];
      if (d != null) {
        _details[base.id] = d;
        setState(() {
          _rebuildSlots(
            preferMovieId: cur?.movieId ?? base.id,
            preferEp: cur?.ep ?? 0,
          );
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageCtrl.hasClients && _index < _slots.length) {
            _pageCtrl.jumpToPage(_index);
          }
        });
      } else if (!_details.containsKey(base.id)) {
        _details[base.id] = base;
        setState(() {
          _rebuildSlots(
            preferMovieId: cur?.movieId,
            preferEp: cur?.ep ?? 0,
          );
        });
      }
    } catch (_) {
      if (!_details.containsKey(base.id) && mounted) {
        final cur = _slots.isEmpty
            ? null
            : _slots[_index.clamp(0, _slots.length - 1)];
        _details[base.id] = base;
        setState(() {
          _rebuildSlots(
            preferMovieId: cur?.movieId,
            preferEp: cur?.ep ?? 0,
          );
        });
      }
    }
  }

  Future<void> _prefetchAround(int slotIndex) async {
    if (_slots.isEmpty) return;
    final ids = <String>{};
    for (final i in [slotIndex, slotIndex + 1, slotIndex + 2, slotIndex - 1]) {
      if (i < 0 || i >= _slots.length) continue;
      ids.add(_slots[i].movieId);
    }
    await Future.wait([for (final id in ids) _ensureDetail(id)]);
  }

  void _onPage(int i) {
    setState(() => _index = i);
    unawaited(_prefetchAround(i));
    if (!widget.lockToSeedSeries && i >= _slots.length - 3) {
      unawaited(_loadMore());
    }
  }

  void _jumpToEpisode(String movieId, int ep) {
    final i = _slots.indexWhere((s) => s.movieId == movieId && s.ep == ep);
    if (i < 0) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    if (_pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(i);
    }
  }

  Movie _movieOf(String id) {
    final d = _details[id];
    if (d != null) return d;
    return _movies.firstWhere((m) => m.id == id);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (_loading && _movies.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: FigmaMetaballLoader(size: 48)),
      );
    }
    if (_error != null && _movies.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: TextButton(
            onPressed: () => unawaited(_reload()),
            child: Text(
              '$_error\n点击重试',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'AppSans', color: Colors.white70),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_slots.isEmpty)
            const Center(
              child: Text(
                '暂无内容',
                style: TextStyle(fontFamily: 'AppSans', color: Colors.white70),
              ),
            )
          else
            PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              itemCount: _slots.length,
              onPageChanged: _onPage,
              itemBuilder: (context, i) {
                final slot = _slots[i];
                final movie = _movieOf(slot.movieId);
                final eps = movie.episodesOf(0);
                return _FeedCell(
                  movie: movie,
                  ep: slot.ep,
                  active: i == _index,
                  liked: _liked.contains(movie.id),
                  bottomInset: bottom + 24,
                  onLike: () => unawaited(_toggleLike(movie.id)),
                  onSelectEpisode: eps.length > 1
                      ? (ep) => _jumpToEpisode(movie.id, ep)
                      : null,
                );
              },
            ),
          Positioned(
            left: 4,
            top: top + 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(CupertinoIcons.back, color: Colors.white),
            ),
          ),
          Positioned(
            left: 52,
            top: top + 14,
            child: Text(
              widget.title,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          if (_loadingMore)
            Positioned(
              right: 16,
              bottom: 32,
              child: CupertinoActivityIndicator(color: AppColors.brand),
            ),
        ],
      ),
    );
  }
}

class _FeedCell extends StatelessWidget {
  const _FeedCell({
    required this.movie,
    required this.ep,
    required this.active,
    required this.liked,
    required this.bottomInset,
    required this.onLike,
    this.onSelectEpisode,
  });

  final Movie movie;
  final int ep;
  final bool active;
  final bool liked;
  final double bottomInset;
  final VoidCallback onLike;
  final ValueChanged<int>? onSelectEpisode;

  @override
  Widget build(BuildContext context) {
    final m = movie;
    final eps = m.episodesOf(0);
    final playUrl = eps.isEmpty
        ? (m.playUrlAt(0) ?? '')
        : eps[ep.clamp(0, eps.length - 1)].url;
    final cover = m.coverUrl?.trim() ?? m.bannerUrl?.trim() ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        DouyinLitePlayer(
          key: ValueKey('${m.id}_$ep'),
          url: playUrl,
          active: active && playUrl.isNotEmpty,
          coverUrl: cover.isEmpty ? null : cover,
          bottomInset: bottomInset + 56,
        ),
        Positioned(
          right: 10,
          bottom: bottomInset + 88,
          child: Column(
            children: [
              _SideAction(
                icon: liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                color: liked ? const Color(0xFFFF2D55) : Colors.white,
                label: liked ? '已赞' : '点赞',
                onTap: onLike,
              ),
              if (eps.length > 1 && onSelectEpisode != null) ...[
                const SizedBox(height: 18),
                _SideAction(
                  icon: CupertinoIcons.list_bullet,
                  label: '选集',
                  onTap: () => unawaited(_openEpisodes(context, eps)),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ep + 1}/${eps.length}',
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 14,
          right: 72,
          bottom: bottomInset + 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                ),
              ),
              if (eps.length > 1) ...[
                const SizedBox(height: 4),
                Text(
                  '第${ep + 1}集 · 共${eps.length}集',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 12,
                    color: Color(0xFFE0E0E0),
                  ),
                ),
              ] else if (m.remarks.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  m.remarks,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 12,
                    color: Color(0xFFE0E0E0),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openEpisodes(
    BuildContext context,
    List<MoviePlayEpisode> eps,
  ) async {
    HapticFeedback.selectionClick();
    await showPlayerEpisodeSheet(
      context: context,
      episodes: eps,
      selected: ep.clamp(0, eps.length - 1),
      onSelect: (i) => onSelectEpisode?.call(i),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
