import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../services/local_play_store.dart';
import '../services/maccms_api.dart';
import '../services/vod_cache_store.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/ios_edge_back.dart';
import '../widgets/player/mango_inline_player.dart';
import '../widgets/player/mango_player_chrome.dart';
import 'vod_download_page.dart';
import '../widgets/app_page_route.dart';

String cacheFmtBytes(int n) {
  if (n <= 0) return '0B';
  const u = ['B', 'KB', 'MB', 'GB'];
  var v = n.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = (v >= 10 || i == 0) ? 0 : 1;
  final unit = u[i] == 'MB' ? 'M' : u[i];
  return '${v.toStringAsFixed(digits)}$unit';
}

/// 合集内页：仅已下载集数，点集直接全屏播本地文件
class VodCacheAlbumPage extends StatefulWidget {
  const VodCacheAlbumPage({
    super.key,
    required this.vodId,
    required this.title,
    required this.coverUrl,
  });

  final String vodId;
  final String title;
  final String coverUrl;

  @override
  State<VodCacheAlbumPage> createState() => _VodCacheAlbumPageState();
}

class _VodCacheAlbumPageState extends State<VodCacheAlbumPage> {
  static const _ink = Color(0xFF1A1A1A);
  static const _accent = Color(0xFF1ECAD3);

  List<VodCacheItem> _eps = const [];
  StreamSubscription<List<VodCacheItem>>? _sub;
  LocalPlayItem? _watch;
  bool _editing = false;
  final Set<String> _selected = {};
  final _cms = MacCmsApi();
  bool _opening = false;
  String? _coverOverride;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = VodCacheStore.instance.stream.listen((_) => _reload());
    unawaited(_loadWatch());
    unawaited(_ensureCover());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() {
    final list = VodCacheStore.instance.items
        .where((e) => e.vodId == widget.vodId && e.isDone)
        .toList()
      ..sort((a, b) => a.episodeIndex.compareTo(b.episodeIndex));
    if (!mounted) return;
    setState(() => _eps = list);
  }

  Future<void> _loadWatch() async {
    final w = await LocalPlayStore.get(widget.vodId);
    if (!mounted) return;
    setState(() => _watch = w);
  }

  Future<void> _ensureCover() async {
    if (widget.coverUrl.trim().isNotEmpty) return;
    if (_eps.any((e) => e.coverUrl.trim().isNotEmpty)) return;
    try {
      final m = await _cms.fetchDetail(widget.vodId);
      final cover = (m.coverUrl ?? m.slideUrl ?? '').trim();
      if (cover.isEmpty || !mounted) return;
      setState(() => _coverOverride = cover);
    } catch (_) {}
  }

  String _watchLabel(VodCacheItem e) {
    final w = _watch;
    if (w == null || w.episodeIndex != e.episodeIndex) return '未观看';
    if (w.durationMs > 0 && w.positionMs >= w.durationMs - 15000) {
      return '已看完';
    }
    if (w.positionMs > 3000) return '观看至 ${_fmtPos(w.positionMs)}';
    return '未观看';
  }

  static String _fmtPos(int ms) {
    final s = (ms / 1000).floor();
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _playAt(int listIndex) async {
    if (_editing || _opening) return;
    if (listIndex < 0 || listIndex >= _eps.length) return;
    final e = _eps[listIndex];
    if (!await File(e.localPath).exists()) {
      DialogX.showWarning('本地文件已丢失');
      await VodCacheStore.instance.remove(e.id);
      return;
    }
    setState(() => _opening = true);
    HapticFeedback.selectionClick();
    try {
      var startMs = 0;
      final prev = await LocalPlayStore.get(widget.vodId);
      if (prev != null &&
          prev.episodeIndex == e.episodeIndex &&
          prev.positionMs > 3000) {
        startMs = prev.positionMs;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _CachedLocalPlayerPage(
            title: widget.title,
            coverUrl: widget.coverUrl.isNotEmpty
                ? widget.coverUrl
                : e.coverUrl,
            episodes: _eps,
            index: listIndex,
            startPositionMs: startMs,
          ),
        ),
      );
      await _loadWatch();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _downloadMore() async {
    HapticFeedback.selectionClick();
    Movie? movie;
    try {
      movie = await _cms.fetchDetail(widget.vodId);
    } catch (_) {}
    movie ??= Movie(
      id: widget.vodId,
      title: widget.title,
      subtitle: '',
      year: 0,
      score: 0,
      genres: const [],
      coverColor: const Color(0xFFCCCCCC),
      tagline: '',
      synopsis: '',
      coverUrl: widget.coverUrl.isEmpty ? null : widget.coverUrl,
      playEpisodes: [
        for (final e in _eps)
          MoviePlayEpisode(name: e.episodeLabel, url: e.url),
      ],
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => VodDownloadPage(movie: movie!),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) {
      DialogX.showWarning('请先选择集数');
      return;
    }
    final ok = await DialogX.confirm(
      context: context,
      title: '删除下载',
      message: '确定删除所选 ${_selected.length} 集？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    await VodCacheStore.instance.removeMany(_selected);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _editing = false;
    });
    if (_eps.isEmpty && mounted) Navigator.of(context).pop();
    DialogX.showSuccess('已删除');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final cover = (_coverOverride ?? widget.coverUrl).trim().isNotEmpty
        ? (_coverOverride ?? widget.coverUrl).trim()
        : (_eps.isNotEmpty ? _eps.first.coverUrl : '');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actionsPadding: const EdgeInsets.only(right: 12),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.back, color: _ink),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _editing = !_editing;
                if (!_editing) _selected.clear();
              });
            },
            child: Text(
              _editing ? '取消' : '编辑',
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 15,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _eps.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _DownloadMoreRow(onTap: () => unawaited(_downloadMore()));
                }
                final e = _eps[i - 1];
                final selected = _selected.contains(e.id);
                return _EpisodeRow(
                  item: e,
                  coverUrl: e.coverUrl.isNotEmpty ? e.coverUrl : cover,
                  status: _watchLabel(e),
                  editing: _editing,
                  selected: selected,
                  onSelect: () {
                    setState(() {
                      if (selected) {
                        _selected.remove(e.id);
                      } else {
                        _selected.add(e.id);
                      }
                    });
                  },
                  onTap: () {
                    if (_editing) {
                      setState(() {
                        if (selected) {
                          _selected.remove(e.id);
                        } else {
                          _selected.add(e.id);
                        }
                      });
                      return;
                    }
                    unawaited(_playAt(i - 1));
                  },
                );
              },
            ),
          ),
          if (_editing)
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEBEBEB))),
              ),
              padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + bottom),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selected.length == _eps.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(_eps.map((e) => e.id));
                          }
                        });
                      },
                      child: const Text(
                        '全选',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 22,
                    color: const Color(0xFFE5E5EA),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => unawaited(_deleteSelected()),
                      child: const Text(
                        '删除',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
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

class _DownloadMoreRow extends StatelessWidget {
  const _DownloadMoreRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 128,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.download_rounded,
              size: 28,
              color: Color(0xFFB0B0B8),
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            '下载更多集数',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.item,
    required this.coverUrl,
    required this.status,
    required this.editing,
    required this.selected,
    required this.onSelect,
    required this.onTap,
  });

  final VodCacheItem item;
  final String coverUrl;
  final String status;
  final bool editing;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          if (editing) ...[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: onSelect,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF1ECAD3)
                          : const Color(0xFFCCCCCC),
                      width: 1.6,
                    ),
                    color: selected
                        ? const Color(0xFF1ECAD3)
                        : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 128,
              height: 72,
              child: coverUrl.trim().isEmpty
                  ? Container(
                      color: const Color(0xFFF0F0F3),
                      child: const Icon(
                        Icons.movie_outlined,
                        color: Color(0xFFB0B0B8),
                      ),
                    )
                  : CmsCoverImage(
                      url: coverUrl,
                      vodId: item.vodId,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.episodeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFF8A8F98),
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

/// 仅播本地缓存，不进详情页
class _CachedLocalPlayerPage extends StatefulWidget {
  const _CachedLocalPlayerPage({
    required this.title,
    required this.coverUrl,
    required this.episodes,
    required this.index,
    this.startPositionMs = 0,
  });

  final String title;
  final String coverUrl;
  final List<VodCacheItem> episodes;
  final int index;
  final int startPositionMs;

  @override
  State<_CachedLocalPlayerPage> createState() => _CachedLocalPlayerPageState();
}

class _CachedLocalPlayerPageState extends State<_CachedLocalPlayerPage> {
  final _playerKey = GlobalKey<MangoInlinePlayerState>();
  late int _index;
  late int _startMs;

  @override
  void initState() {
    super.initState();
    _index = widget.index.clamp(0, math.max(0, widget.episodes.length - 1));
    _startMs = widget.startPositionMs;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _restoreUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exit() {
    _restoreUi();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _restoreUi();
    super.dispose();
  }

  VodCacheItem get _cur => widget.episodes[_index];

  List<MoviePlayEpisode> get _labels => [
        for (final e in widget.episodes)
          MoviePlayEpisode(name: e.episodeLabel, url: e.localPath),
      ];

  bool get _hasNext => _index < widget.episodes.length - 1;

  void _saveProgress(Duration pos, Duration dur) {
    final e = _cur;
    LocalPlayStore.add(
      vodId: e.vodId,
      name: e.title,
      pic: widget.coverUrl,
      remarks: '',
      episodeIndex: e.episodeIndex,
      episodeLabel: e.episodeLabel,
      positionMs: pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
    );
  }

  void _playIndex(int i) {
    if (i < 0 || i >= widget.episodes.length) return;
    setState(() {
      _index = i;
      _startMs = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final e = _cur;

    return InterceptPopScope(
      onIntercept: _exit,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MangoInlinePlayer(
          key: _playerKey,
          url: e.localPath,
          startPositionMs: _startMs,
          immersiveTop: true,
          episodes: _labels,
          selectedEpisode: _index,
          onEpisodeSelect: _playIndex,
          onProgress: _saveProgress,
          showNextEpisode: _hasNext,
          onNextEpisode: _hasNext ? () => _playIndex(_index + 1) : null,
          showEpisodesInMenu: true,
          vodId: e.vodId,
          danmakuTitle: widget.title,
          danmakuEpisode: e.episodeIndex,
          danmakuEpisodeLabel: e.episodeLabel,
          topOverlay: MangoWatchTopBar(
            topInset: top,
            title: widget.title,
            episodeLabel: e.episodeLabel,
            tag: '缓存',
            onSettings: () => _playerKey.currentState?.openSettings(),
            onBack: _exit,
          ),
        ),
      ),
    );
  }
}
