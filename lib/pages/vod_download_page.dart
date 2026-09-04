import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/movie_models.dart';
import '../services/vod_cache_store.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/player/mango_watch_panel.dart';
import 'vod_cache_list_page.dart';
import '../widgets/app_page_route.dart';

/// 下载页：选集 + 画质设置（对齐参考图）
class VodDownloadPage extends StatefulWidget {
  const VodDownloadPage({super.key, required this.movie, this.sourceIndex = 0});

  final Movie movie;
  final int sourceIndex;

  @override
  State<VodDownloadPage> createState() => _VodDownloadPageState();
}

class _VodDownloadPageState extends State<VodDownloadPage> {
  static const _accent = Color(0xFF1ECAD3);
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF8A8F98);
  static const _chipBg = Color(0xFFF3F3F5);
  static const _vipFromRatio = 0.35;

  late List<MoviePlayEpisode> _eps;
  late List<({int start, int end, String label})> _ranges;
  int _rangeIndex = 0;
  String _quality = '720P';
  String _freeSpace = '';
  StreamSubscription<List<VodCacheItem>>? _sub;

  @override
  void initState() {
    super.initState();
    _eps = widget.movie.playEpisodes.isNotEmpty
        ? widget.movie.playEpisodes
        : [
            for (var i = 0; i < widget.movie.episodeLabels.length; i++)
              MoviePlayEpisode(
                name: widget.movie.episodeLabels[i],
                url: '',
              ),
          ];
    _ranges = _buildRanges(_eps.length);
    if (_ranges.isNotEmpty) _rangeIndex = 0;
    unawaited(VodCacheStore.instance.ensureLoaded());
    unawaited(_loadFreeSpace());
    _sub = VodCacheStore.instance.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadFreeSpace() async {
    try {
      await getTemporaryDirectory();
      if (!mounted) return;
      setState(() => _freeSpace = '下载将保存到本机缓存');
    } catch (_) {}
  }

  List<({int start, int end, String label})> _buildRanges(int total) {
    if (total <= 0) return const [];
    const step = 50;
    final out = <({int start, int end, String label})>[];
    for (var s = 0; s < total; s += step) {
      final e = (s + step - 1).clamp(0, total - 1);
      out.add((start: s, end: e, label: '${s + 1}-${e + 1}'));
    }
    return out;
  }

  Set<int> get _done {
    final out = <int>{};
    for (final e in VodCacheStore.instance.items) {
      if (e.vodId == widget.movie.id &&
          e.sourceIndex == widget.sourceIndex &&
          e.isDone) {
        out.add(e.episodeIndex);
      }
    }
    return out;
  }

  int get _vipFrom =>
      (_eps.length * _vipFromRatio).floor().clamp(0, _eps.length);

  void _toggle(int i) {
    if (_done.contains(i)) return;
    final active = VodCacheStore.instance.find(
      vodId: widget.movie.id,
      episodeIndex: i,
      sourceIndex: widget.sourceIndex,
    );
    if (active != null && active.isActive) return;
    HapticFeedback.selectionClick();
    unawaited(_enqueue([i]));
  }

  Future<void> _enqueue(List<int> indexes) async {
    if (indexes.isEmpty) {
      DialogX.showWarning('请先选择要下载的集数');
      return;
    }
    final jobs = <
        ({
          String vodId,
          String title,
          int episodeIndex,
          String episodeLabel,
          int sourceIndex,
          String url,
          String coverUrl,
        })>[];
    final cover = (widget.movie.coverUrl ?? '').trim();
    for (final i in indexes) {
      final url = widget.movie.playUrlAt(i, sourceIndex: widget.sourceIndex);
      if (url == null || url.isEmpty) continue;
      jobs.add((
        vodId: widget.movie.id,
        title: widget.movie.title,
        episodeIndex: i,
        episodeLabel: _eps[i].name,
        sourceIndex: widget.sourceIndex,
        url: url,
        coverUrl: cover,
      ));
    }
    if (jobs.isEmpty) {
      DialogX.showWarning('所选剧集暂无地址');
      return;
    }
    final added = await VodCacheStore.instance.enqueueMany(jobs: jobs);
    if (!mounted) return;
    if (added <= 0) {
      DialogX.showSuccess('所选剧集已全部缓存');
    } else {
      DialogX.showSuccess('已加入 $added 集下载');
    }
  }

  Future<void> _pickQuality() async {
    final q = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _QualitySheet(current: _quality),
    );
    if (q != null && mounted) setState(() => _quality = q);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final range = _ranges.isEmpty
        ? (start: 0, end: -1, label: '')
        : _ranges[_rangeIndex.clamp(0, _ranges.length - 1)];
    final slice = [
      for (var i = range.start; i <= range.end && i < _eps.length; i++) i,
    ];
    final done = _done;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(CupertinoIcons.back, color: _ink),
        ),
        title: const Text(
          '点击集数即可下载',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: GestureDetector(
              onTap: () => unawaited(_pickQuality()),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '下载音画设置',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Text(
                      '$_quality >',
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 14,
                        color: _muted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_ranges.length > 1)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                itemCount: _ranges.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final on = i == _rangeIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _rangeIndex = i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on
                            ? _accent.withValues(alpha: 0.15)
                            : _chipBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _ranges[i].label,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: on ? _accent : _muted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                MangoWatchStyle.hPad,
                4,
                MangoWatchStyle.hPad,
                12,
              ),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: MangoWatchStyle.chipGap,
                crossAxisSpacing: MangoWatchStyle.chipGap,
                childAspectRatio: 1,
              ),
              itemCount: slice.length,
              itemBuilder: (context, j) {
                final i = slice[j];
                final ep = _eps[i];
                final isDone = done.contains(i);
                final cache = VodCacheStore.instance.find(
                  vodId: widget.movie.id,
                  episodeIndex: i,
                  sourceIndex: widget.sourceIndex,
                );
                final downloading = cache?.status == VodCacheStatus.downloading;
                final queued = cache?.status == VodCacheStatus.queued;
                final on = downloading || queued;
                String? badge;
                if (isDone) {
                  badge = '已存';
                } else if (downloading) {
                  final pct = ((cache?.progress ?? 0) * 100)
                      .clamp(0, 100)
                      .toStringAsFixed(0);
                  badge = '$pct%';
                } else if (queued) {
                  badge = '排队';
                } else if (MangoEpisodeChip.isVipLabel(ep.name) ||
                    i >= _vipFrom) {
                  badge = 'VIP';
                } else if (i > 0) {
                  badge = '限免';
                }
                return Opacity(
                  opacity: isDone ? 0.45 : 1,
                  child: MangoEpisodeChip(
                    label: MangoEpisodeRow.chipLabel(
                      ep.name,
                      i,
                      total: _eps.length,
                    ),
                    selected: on && !isDone,
                    expand: true,
                    cornerBadge: badge,
                    onTap: () => _toggle(i),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottom),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () {
                            final all = [
                              for (var i = 0; i < _eps.length; i++)
                                if (!done.contains(i)) i,
                            ];
                            unawaited(_enqueue(all));
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _ink,
                            backgroundColor: _chipBg,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(23),
                            ),
                          ),
                          child: const Text(
                            '下载全部',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              AppPageRoute<void>(
                                builder: (_) => const VodCacheListPage(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(23),
                            ),
                          ),
                          child: Text(
                            '查看下载列表',
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_freeSpace.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _freeSpace,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: _muted,
                      decoration: TextDecoration.none,
                    ),
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

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({required this.current});

  final String current;

  static const _items = <({String id, String sub, String? badge})>[
    (id: '臻彩MAX', sub: 'SDR增强', badge: 'SVIP'),
    (id: '4K', sub: '超清', badge: 'SVIP'),
    (id: '臻彩1080P', sub: '高清', badge: 'VIP'),
    (id: '1080P', sub: '高清', badge: 'VIP'),
    (id: '720P', sub: '准高清', badge: null),
    (id: '480P', sub: '标清', badge: null),
    (id: '270P', sub: '流畅', badge: null),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Spacer(),
              const Text(
                '下载音画设置',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.xmark, size: 18),
              ),
            ],
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '画质',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.55,
            ),
            itemBuilder: (context, i) {
              final it = _items[i];
              final on = it.id == current;
              return GestureDetector(
                onTap: () => Navigator.pop(context, it.id),
                child: Container(
                  decoration: BoxDecoration(
                    color: on
                        ? const Color(0xFF1ECAD3).withValues(alpha: 0.15)
                        : const Color(0xFFF3F3F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        it.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: on
                              ? const Color(0xFF1ECAD3)
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        it.sub,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 11,
                          color: on
                              ? const Color(0xFF1ECAD3)
                              : const Color(0xFF8A8F98),
                        ),
                      ),
                      if (it.badge != null)
                        Text(
                          it.badge!,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 10,
                            color: Color(0xFFE0B13A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '音质',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1ECAD3).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '标准',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1ECAD3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
