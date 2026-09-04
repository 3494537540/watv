import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/movie_models.dart';
import '../services/cms_app_config.dart';
import '../services/live_source_store.dart';
import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import '../widgets/figma_loading.dart';
import '../widgets/player/douyin_lite_player.dart';

enum _ShortChannel { commentary, cctv }

/// 短视频底栏：抖音式竖滑；仅「影视解说」(默认) + CCTV
class ShortVideoHubPage extends StatefulWidget {
  const ShortVideoHubPage({super.key});

  @override
  State<ShortVideoHubPage> createState() => _ShortVideoHubPageState();
}

class _ShortVideoHubPageState extends State<ShortVideoHubPage> {
  static const _navClearance = 108.0;

  final _api = MacCmsApi();
  final _pageCtrl = PageController();
  final Set<String> _liked = {};

  _ShortChannel _channel = _ShortChannel.commentary;
  bool _armed = true;

  final List<Movie> _movies = [];
  final List<LiveChannel> _lives = [];
  final Map<String, Movie> _details = {};
  int? _commentaryTypeId;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _index = 0;
  String? _error;

  bool get _isLive => _channel == _ShortChannel.cctv;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
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
    await _reload();
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

  Future<void> _switchChannel(_ShortChannel ch) async {
    if (ch == _channel) return;
    HapticFeedback.selectionClick();
    setState(() {
      _channel = ch;
      _armed = ch == _ShortChannel.commentary;
      _index = 0;
      _movies.clear();
      _lives.clear();
      _details.clear();
      _error = null;
    });
    if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    await _reload();
  }

  Future<int> _resolveCommentaryTypeId() async {
    if (_commentaryTypeId != null) return _commentaryTypeId!;
    final found = await _api.findTypeIdByName('解说');
    _commentaryTypeId = found ?? ApiConfig.macCmsCommentaryTypeId;
    return _commentaryTypeId!;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
    });
    try {
      if (_channel == _ShortChannel.cctv) {
        await LiveSourceStore.instance.bootstrap();
        await LiveSourceStore.instance
            .refreshFromConfig(CmsAppConfigStore.instance.config);
        final all = LiveSourceStore.instance.all
            .where((c) => !c.url.contains('example.invalid'))
            .toList();
        if (!mounted) return;
        _lives
          ..clear()
          ..addAll(all);
        setState(() {
          _loading = false;
          _hasMore = false;
        });
        return;
      }

      final tid = await _resolveCommentaryTypeId();
      final list = await _api.fetchByType(
        typeId: tid,
        page: 1,
        limit: 8,
        applyBannerExclude: false,
      );
      if (!mounted) return;
      _movies
        ..clear()
        ..addAll(list);
      setState(() {
        _loading = false;
        _hasMore = list.length >= 4;
      });
      if (_armed) unawaited(_prefetchAround(0));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLive || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final tid = await _resolveCommentaryTypeId();
      final more = await _api.fetchByType(
        typeId: tid,
        page: next,
        limit: 8,
        applyBannerExclude: false,
      );
      if (!mounted) return;
      final seen = {for (final m in _movies) m.id};
      final appended = [for (final m in more) if (seen.add(m.id)) m];
      setState(() {
        _movies.addAll(appended);
        _page = next;
        _hasMore = appended.length >= 3;
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

  Future<void> _ensureDetail(int i) async {
    if (_isLive || i < 0 || i >= _movies.length) return;
    final base = _movies[i];
    if (_details.containsKey(base.id)) return;
    if (base.playSources.isNotEmpty && base.playUrlAt(0)?.isNotEmpty == true) {
      _details[base.id] = base;
      if (mounted) setState(() {});
      return;
    }
    try {
      final d = await _api.fetchVodDetail(base.id);
      if (!mounted) return;
      if (d != null) {
        _details[base.id] = d;
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _prefetchAround(int i) async {
    await Future.wait([
      _ensureDetail(i),
      _ensureDetail(i + 1),
      _ensureDetail(i + 2),
    ]);
  }

  void _onPage(int i) {
    setState(() => _index = i);
    if (!_armed) setState(() => _armed = true);
    unawaited(_prefetchAround(i));
    if (!_isLive && i >= _movies.length - 2) unawaited(_loadMore());
  }

  int get _itemCount => _isLive ? _lives.length : _movies.length;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom =
        MediaQuery.paddingOf(context).bottom + _navClearance;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading && _itemCount == 0)
            const Center(child: FigmaMetaballLoader(size: 48))
          else if (_error != null && _itemCount == 0)
            Center(
              child: TextButton(
                onPressed: () => unawaited(_reload()),
                child: Text(
                  '$_error\n点击重试',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    color: Colors.white70,
                  ),
                ),
              ),
            )
          else if (_itemCount == 0)
            const Center(
              child: Text(
                '暂无内容',
                style: TextStyle(fontFamily: 'AppSans', color: Colors.white70),
              ),
            )
          else if (!_armed && _channel == _ShortChannel.cctv)
            _ArmOverlay(
              onPlay: () {
                setState(() => _armed = true);
              },
            )
          else
            PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              itemCount: _itemCount,
              onPageChanged: _onPage,
              itemBuilder: (context, i) {
                if (_isLive) {
                  final c = _lives[i];
                  return _LiveCell(
                    channel: c,
                    active: _armed && i == _index,
                    bottomInset: bottom,
                  );
                }
                final base = _movies[i];
                final movie = _details[base.id] ?? base;
                return _VodCell(
                  movie: movie,
                  active: _armed && i == _index,
                  liked: _liked.contains(movie.id),
                  bottomInset: bottom,
                  onLike: () => unawaited(_toggleLike(movie.id)),
                );
              },
            ),
          Positioned(
            left: 0,
            right: 0,
            top: top + 6,
            child: _ChannelBar(
              channel: _channel,
              onSelect: (c) => unawaited(_switchChannel(c)),
            ),
          ),
          if (_loadingMore)
            Positioned(
              right: 16,
              bottom: bottom + 24,
              child: CupertinoActivityIndicator(color: AppColors.brand),
            ),
        ],
      ),
    );
  }
}

class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.channel, required this.onSelect});

  final _ShortChannel channel;
  final ValueChanged<_ShortChannel> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_ShortChannel.commentary, '解说'),
      (_ShortChannel.cctv, 'CCTV'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (ch, label) = items[i];
          final on = ch == channel;
          return GestureDetector(
            onTap: () => onSelect(ch),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: on
                      ? Colors.white.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  color: on ? Colors.white : Colors.white70,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArmOverlay extends StatelessWidget {
  const _ArmOverlay({required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '已切换到 CCTV',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
          SizedBox(height: 16),
          FilledButton(
            onPressed: onPlay,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text(
              '开始播放',
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
}

class _VodCell extends StatefulWidget {
  const _VodCell({
    required this.movie,
    required this.active,
    required this.liked,
    required this.bottomInset,
    required this.onLike,
  });

  final Movie movie;
  final bool active;
  final bool liked;
  final double bottomInset;
  final VoidCallback onLike;

  @override
  State<_VodCell> createState() => _VodCellState();
}

class _VodCellState extends State<_VodCell> {
  int _ep = 0;

  @override
  void didUpdateWidget(covariant _VodCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.id != widget.movie.id) _ep = 0;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.movie;
    final eps = m.episodesOf(0);
    final playUrl = eps.isEmpty
        ? (m.playUrlAt(0) ?? '')
        : eps[_ep.clamp(0, eps.length - 1)].url;
    final cover = m.coverUrl?.trim() ?? m.bannerUrl?.trim() ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        DouyinLitePlayer(
          url: playUrl,
          active: widget.active && playUrl.isNotEmpty,
          coverUrl: cover.isEmpty ? null : cover,
          bottomInset: widget.bottomInset + 64,
        ),
        Positioned(
          right: 12,
          bottom: widget.bottomInset + 80,
          child: Column(
            children: [
              _LikeBtn(
                liked: widget.liked,
                onTap: widget.onLike,
              ),
              if (eps.length > 1) ...[
                SizedBox(height: 18),
                Text(
                  '选集',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(height: 6),
                SizedBox(
                  height: 140,
                  width: 48,
                  child: ListView.separated(
                    itemCount: eps.length.clamp(0, 40),
                    separatorBuilder: (_, _) => SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final on = i == _ep;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _ep = i);
                        },
                        child: Container(
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: on
                                ? AppColors.brand
                                : Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: on ? Colors.white : Colors.white70,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          left: 14,
          right: 72,
          bottom: widget.bottomInset + 18,
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
              if (m.remarks.isNotEmpty) ...[
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
}

class _LiveCell extends StatelessWidget {
  const _LiveCell({
    required this.channel,
    required this.active,
    required this.bottomInset,
  });

  final LiveChannel channel;
  final bool active;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DouyinLitePlayer(
          url: channel.url,
          active: active,
          bottomInset: bottomInset + 48,
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: bottomInset + 18,
          child: Text(
            '${channel.group} · ${channel.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
            ),
          ),
        ),
      ],
    );
  }
}

class _LikeBtn extends StatelessWidget {
  const _LikeBtn({required this.liked, required this.onTap});

  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              shape: BoxShape.circle,
            ),
            child: Icon(
              liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              color: liked ? const Color(0xFFFF2D55) : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            liked ? '已赞' : '点赞',
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
