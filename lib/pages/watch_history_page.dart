import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_play_store.dart';
import '../services/maccms_api.dart';
import '../services/maccms_user_api.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/figma_loading.dart';
import 'movie_detail_page.dart';
import '../widgets/app_page_route.dart';

/// ?????B ????
class WatchHistoryPage extends StatefulWidget {
  const WatchHistoryPage({super.key});

  @override
  State<WatchHistoryPage> createState() => _WatchHistoryPageState();
}

class _WatchHistoryPageState extends State<WatchHistoryPage> {
  static const _accent = Color(0xFF00A1D6);
  static const _accentSoft = Color(0xFFD6F3FA);
  static const _chipOff = Color(0xFFF4F4F4);
  static const _ink = Color(0xFF18191C);
  static const _muted = Color(0xFF9499A0);

  static const _cats = [
    '全部',
    '电视剧',
    '动漫',
    '电影',
    '短视频',
    '综艺',
  ];

  int _topTab = 0;
  int _cat = 0;
  bool _editing = false;
  bool _loading = true;
  List<CmsUlogItem> _items = const [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final started = DateTime.now();
    try {
      // Local first so skeleton never blocks on CMS
      final local = await LocalPlayStore.list(limit: 80);
      var plays = <CmsUlogItem>[
        for (final e in local)
          CmsUlogItem(
            id: e.vodId,
            vodId: e.vodId,
            name: e.name,
            pic: e.pic,
            remarks: e.remarks,
            playedAt: e.playedAt,
            episodeLabel: e.episodeLabel,
            episodeNid: e.episodeIndex + 1,
            progress: e.progress,
          ),
      ];
      plays.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      if (!mounted) return;
      // ?????????????????????
      final left = const Duration(milliseconds: 1100) -
          DateTime.now().difference(started);
      if (left > Duration.zero) {
        await Future<void>.delayed(left);
      }
      if (!mounted) return;
      setState(() {
        _items = plays;
        _loading = false;
      });

      if (CmsAuthController.instance.isLoggedIn) {
        try {
          final cms = await CmsAuthController.instance.api
              .fetchUlog(type: 2, limit: 60)
              .timeout(const Duration(seconds: 8));
          final byLocal = {for (final e in plays) e.vodId: e};
          final ids = cms.map((e) => e.vodId).toSet();
          plays = [
            for (final p in cms)
              () {
                final loc = byLocal[p.vodId];
                return CmsUlogItem(
                  id: p.id,
                  vodId: p.vodId,
                  name: p.name,
                  pic: p.pic.trim().isNotEmpty ? p.pic : (loc?.pic ?? ''),
                  remarks: p.remarks.trim().isNotEmpty
                      ? p.remarks
                      : (loc?.remarks ?? ''),
                  typeName: p.typeName,
                  link: p.link,
                  playedAt: (loc?.playedAt ?? 0) > 0
                      ? loc!.playedAt
                      : p.playedAt,
                  timeText: p.timeText,
                  episodeLabel: (loc?.episodeLabel ?? '').isNotEmpty
                      ? loc!.episodeLabel
                      : p.episodeDisplay,
                  episodeNid: p.episodeNid > 0
                      ? p.episodeNid
                      : (loc?.episodeNid ?? 0),
                  progress: loc?.progress ?? p.progress,
                );
              }(),
            for (final loc in plays)
              if (!ids.contains(loc.vodId)) loc,
          ];
          plays.sort((a, b) => b.playedAt.compareTo(a.playedAt));
          if (mounted) setState(() => _items = plays);
        } catch (_) {}
      }

      unawaited(_enrichCovers(plays));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _enrichCovers(List<CmsUlogItem> items) async {
    final need = items
        .where((e) => CmsCoverImage.resolve(e.pic) == null)
        .take(16)
        .toList();
    if (need.isEmpty) return;
    final cms = MacCmsApi();
    final map = <String, String>{};
    await Future.wait([
      for (final it in need)
        () async {
          try {
            final m = await cms
                .fetchDetail(it.vodId)
                .timeout(const Duration(seconds: 10));
            final pic = (m.coverUrl ?? m.slideUrl ?? '').trim();
            if (pic.isNotEmpty) {
              map[it.vodId] = pic;
              unawaited(LocalPlayStore.updatePic(vodId: it.vodId, pic: pic));
            }
          } catch (_) {}
        }(),
    ]);
    if (!mounted || map.isEmpty) return;
    setState(() {
      _items = [
        for (final p in _items)
          if (map.containsKey(p.vodId))
            CmsUlogItem(
              id: p.id,
              vodId: p.vodId,
              name: p.name,
              pic: map[p.vodId]!,
              remarks: p.remarks,
              typeName: p.typeName,
              link: p.link,
              timeText: p.timeText,
              playedAt: p.playedAt,
              episodeLabel: p.episodeLabel,
              episodeNid: p.episodeNid,
              progress: p.progress,
            )
          else
            p,
      ];
    });
  }

  List<CmsUlogItem> get _filtered {
    var list = _items;
    if (_topTab == 1) {
      list = [
        for (final e in list)
          if (e.progress > 0.02 && e.progress < 0.98) e,
      ];
    }
    if (_cat > 0) {
      final key = _cats[_cat];
      list = [for (final e in list) if (_matchCat(e, key)) e];
    }
    return list;
  }

  bool _matchCat(CmsUlogItem e, String key) {
    final t = '${e.typeName}${e.remarks}${e.name}'.toLowerCase();
    switch (key) {
      case '电视剧':
        return t.contains('剧') || t.contains('电视');
      case '动漫':
        return t.contains('漫') || t.contains('动漫') || t.contains('动画');
      case '电影':
        return t.contains('电影') || t.contains('片');
      case '短视频':
        return t.contains('短');
      case '综艺':
        return t.contains('综') || t.contains('综艺');
      default:
        return true;
    }
  }

  Map<String, List<CmsUlogItem>> _grouped(List<CmsUlogItem> list) {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final week0 = today0.subtract(const Duration(days: 7));
    final today = <CmsUlogItem>[];
    final week = <CmsUlogItem>[];
    final earlier = <CmsUlogItem>[];
    for (final e in list) {
      final dt = e.playedAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(e.playedAt)
          : DateTime.fromMillisecondsSinceEpoch(0);
      if (!dt.isBefore(today0)) {
        today.add(e);
      } else if (!dt.isBefore(week0)) {
        week.add(e);
      } else {
        earlier.add(e);
      }
    }
    return {
      if (today.isNotEmpty) '今天': today,
      if (week.isNotEmpty) '近一周': week,
      if (earlier.isNotEmpty) '更早': earlier,
    };
  }

  String _timeLabel(CmsUlogItem e) {
    if (e.playedAt <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(e.playedAt);
    final now = DateTime.now();
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final today0 = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today0) return hm;
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hm';
  }

  String _progressLine(CmsUlogItem e) {
    final ep = e.episodeDisplay;
    final pct = (e.progress.clamp(0.0, 1.0) * 100).round();
    if (ep.isNotEmpty && e.progress > 0.01) {
      return '$ep · 观看至$pct%';
    }
    if (ep.isNotEmpty) return ep;
    if (e.progress > 0.01) return '观看至$pct%';
    return e.remarks.trim().isNotEmpty ? e.remarks.trim() : '暂无进度';
  }

  Future<void> _open(CmsUlogItem item) async {
    if (_editing) {
      setState(() {
        if (_selected.contains(item.vodId)) {
          _selected.remove(item.vodId);
        } else {
          _selected.add(item.vodId);
        }
      });
      return;
    }
    final id = item.vodId.trim();
    if (id.isEmpty) return;
    HapticFeedback.selectionClick();
    DialogX.showWait('加载中…');
    try {
      final movie = await MacCmsApi().fetchDetail(id);
      DialogX.dismiss();
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => MovieDetailPage(movie: movie, autoPlay: true),
        ),
      );
      if (mounted) unawaited(_load());
    } catch (e) {
      DialogX.showError('$e');
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    HapticFeedback.mediumImpact();
    await LocalPlayStore.removeIds(_selected);
    setState(() {
      _items = [for (final e in _items) if (!_selected.contains(e.vodId)) e];
      _selected.clear();
      _editing = false;
    });
    DialogX.showSuccess('已删除');
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final groups = _grouped(filtered);

    return Scaffold(
      backgroundColor: AppPalette.page(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildNav(),
            _buildChips(),
            Expanded(
              child: _loading
                  ? const _WatchHistorySkeleton()
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无观看记录',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 14,
                              color: _muted,
                            ),
                          ),
                        )
                      : AppPullRefresh(
                          color: _accent,
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              14,
                              4,
                              16,
                              24 + MediaQuery.paddingOf(context).bottom,
                            ),
                            children: [
                              for (final entry in groups.entries) ...[
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(2, 14, 2, 10),
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontFamily: 'AppSans',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                    ),
                                  ),
                                ),
                                for (final it in entry.value)
                                  _HistoryTile(
                                    item: it,
                                    progressLine: _progressLine(it),
                                    timeLabel: _timeLabel(it),
                                    editing: _editing,
                                    selected: _selected.contains(it.vodId),
                                    onTap: () => unawaited(_open(it)),
                                  ),
                              ],
                            ],
                          ),
                        ),
            ),
            if (_editing) _buildEditBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: _ink,
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _navTab('观看历史', 0),
                  const SizedBox(width: 22),
                  _navTab('猜你在追', 1),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _editing = !_editing;
                  if (!_editing) _selected.clear();
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Text(
                  _editing ? '完成' : '编辑',
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTab(String label, int i) {
    final on = _topTab == i;
    return GestureDetector(
      onTap: () {
        if (_topTab == i) return;
        HapticFeedback.selectionClick();
        setState(() => _topTab = i);
      },
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: on ? 17 : 15,
          fontWeight: on ? FontWeight.w800 : FontWeight.w500,
          color: on ? _ink : _muted,
        ),
      ),
    );
  }

  Widget _buildChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        itemCount: _cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = _cat == i;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _cat = i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? _accentSoft : _chipOff,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _cats[i],
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? const Color(0xFF0087B0) : const Color(0xFF61666D),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppPalette.page(context),
        border: Border(top: BorderSide(color: AppPalette.line(context))),
      ),
      child: Row(
        children: [
          Text(
            '已选 ${_selected.length} 项',
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 14,
              color: _muted,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed:
                _selected.isEmpty ? null : () => unawaited(_deleteSelected()),
            child: Text(
              '删除',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _selected.isEmpty ? _muted : const Color(0xFFE47470),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.progressLine,
    required this.timeLabel,
    required this.editing,
    required this.selected,
    required this.onTap,
  });

  final CmsUlogItem item;
  final String progressLine;
  final String timeLabel;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;

  static const _accent = Color(0xFF00A1D6);
  static const _ink = Color(0xFF18191C);
  static const _muted = Color(0xFF9499A0);
  static const _thumbW = 148.0;
  static const _thumbH = 84.0;

  @override
  Widget build(BuildContext context) {
    final progress = item.progress.clamp(0.0, 1.0);
    final badge = item.remarks.trim();
    final showBadge = badge.isNotEmpty &&
        badge.length <= 8 &&
        !badge.contains('http');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (editing) ...[
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  selected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  size: 22,
                  color: selected ? _accent : const Color(0xFFC9CCD0),
                ),
              ),
            ],
            SizedBox(
              width: _thumbW,
              height: _thumbH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CmsCoverImage(
                      url: item.pic,
                      vodId: item.vodId,
                    ),
                    if (showBadge)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB027),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    if (item.episodeDisplay.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: 6,
                        child: Text(
                          item.episodeDisplay,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.1,
                            shadows: [
                              Shadow(
                                color: Color(0xCC000000),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Image1-style: thin track on cover bottom, cyan width = progress
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 3,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final p = progress.clamp(0.0, 1.0);
                          final fill = c.maxWidth * p;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              // ????????????
                              const ColoredBox(color: Color(0x66FFFFFF)),
                              if (fill > 0.5)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: fill,
                                    height: 3,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0xFF00A1D6),
                                        borderRadius: BorderRadius.horizontal(
                                          right: Radius.circular(1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: _thumbH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progressLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: _muted,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.device_phone_portrait,
                          size: 13,
                          color: _muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '本机${timeLabel.isNotEmpty ? '  $timeLabel' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              color: _muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchHistorySkeleton extends StatelessWidget {
  const _WatchHistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: FigmaSkeletonColors.bg,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 20, 14, 10),
            child: Center(child: FigmaMetaballLoader(size: 64)),
          ),
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 4, 16, 24),
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, _) => const _WatchHistorySkeletonRow(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchHistorySkeletonRow extends StatelessWidget {
  const _WatchHistorySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return FigmaSkeletonPulse(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: const SizedBox(
              width: 148,
              height: 84,
              child: FigmaCoverPlaceholder(iconSize: 32),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FigmaSkeletonBone(height: 14, radius: 7),
                SizedBox(height: 8),
                FigmaSkeletonBone(width: 120, height: 12, radius: 6),
                SizedBox(height: 8),
                FigmaSkeletonBone(width: 88, height: 11, radius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
