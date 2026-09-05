import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cms_fav_store.dart';
import '../services/maccms_api.dart';
import '../services/maccms_user_api.dart';
import '../services/movie_watch_store.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/movie_poster_mosaic.dart';
import 'movie_detail_page.dart';
import '../widgets/app_page_route.dart';

/// 我的收藏：叠放海报轮播 + 列表（本地镜像 + CMS）
class CmsFavsPage extends StatefulWidget {
  const CmsFavsPage({super.key});

  @override
  State<CmsFavsPage> createState() => _CmsFavsPageState();
}

class _CmsFavsPageState extends State<CmsFavsPage> {
  static const _pageSize = 20;

  /// -1 = CMS 收藏；其余为观影状态 index
  int _chip = -1;
  bool _loading = true;
  String? _error;
  List<CmsUlogItem> _favItems = const [];
  List<MovieWatchEntry> _watchItems = const [];
  List<String> _decorCovers = const [];
  int _page = 1;
  int _pageCount = 1;
  int _total = 0;

  MovieWatchStatus? get _watchStatus {
    if (_chip < 0 || _chip >= MovieWatchStatusX.selectable.length) return null;
    return MovieWatchStatusX.selectable[_chip];
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDecor());
    unawaited(_reload());
  }

  Future<void> _loadDecor() async {
    try {
      final list = await MacCmsApi().fetchHotMovies(limit: 12);
      final urls = <String>[
        for (final m in list)
          if ((m.coverUrl ?? '').trim().isNotEmpty) m.coverUrl!.trim(),
      ];
      if (!mounted || urls.isEmpty) return;
      setState(() => _decorCovers = urls);
    } catch (_) {}
  }

  Future<void> _reload({int? page}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final p = page ?? _page;
    try {
      if (_chip < 0) {
        await _loadCmsFavs(page: p);
      } else {
        await _loadWatch(page: p);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadCmsFavs({required int page}) async {
    List<CmsUlogItem> remote = const [];
    if (CmsAuthController.instance.isLoggedIn) {
      try {
        remote = await CmsAuthController.instance.api
            .fetchUlog(type: 1, limit: 120);
        await CmsFavStore.mergeFromRemote([
          for (final e in remote)
            (
              vodId: e.vodId,
              name: e.name,
              pic: e.pic,
              ulogId: e.id,
            ),
        ]);
      } on CmsUserException catch (e) {
        if (e.code != 401) rethrow;
      }
    }
    final mergedLocal = await CmsFavStore.list();
    final byRemote = {for (final e in remote) CmsFavStore.normId(e.vodId): e};
    final merged = <CmsUlogItem>[
      for (final e in mergedLocal)
        byRemote[e.vodId] ??
            CmsUlogItem(
              id: e.ulogId.isNotEmpty ? e.ulogId : e.vodId,
              vodId: e.vodId,
              name: e.name.isEmpty ? '影片 ${e.vodId}' : e.name,
              pic: e.pic,
              playedAt: e.updatedAt,
              timeText: '',
            ),
    ];
    final localIds = mergedLocal.map((e) => e.vodId).toSet();
    for (final e in remote) {
      final id = CmsFavStore.normId(e.vodId);
      if (id.isNotEmpty && !localIds.contains(id)) {
        merged.add(e);
        await CmsFavStore.add(
          vodId: id,
          name: e.name,
          pic: e.pic,
          ulogId: e.id,
        );
      }
    }

    final total = merged.length;
    final pageCount = total == 0 ? 1 : ((total + _pageSize - 1) ~/ _pageSize);
    final safePage = page.clamp(1, pageCount);
    final start = (safePage - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, total);
    if (!mounted) return;
    setState(() {
      _favItems = start >= total ? const [] : merged.sublist(start, end);
      _watchItems = const [];
      _total = total;
      _pageCount = pageCount;
      _page = safePage;
      _loading = false;
    });
  }
  Future<void> _loadWatch({required int page}) async {
    final status = _watchStatus!;
    final result = await MovieWatchStore.listPage(
      status: status,
      page: page,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _watchItems = result.items;
      _favItems = const [];
      _total = result.total;
      _pageCount = result.pageCount;
      _page = page.clamp(1, result.pageCount);
      _loading = false;
    });
  }

  Future<void> _switchChip(int chip) async {
    if (chip == _chip) return;
    HapticFeedback.selectionClick();
    setState(() {
      _chip = chip;
      _page = 1;
    });
    await _reload(page: 1);
  }

  Future<void> _openVod(String vodId, {String name = '', String pic = ''}) async {
    final id = vodId.trim();
    if (id.isEmpty) return;
    HapticFeedback.selectionClick();
    DialogX.showWait('加载中…');
    try {
      final movie = await MacCmsApi().fetchDetail(id);
      DialogX.dismiss();
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => MovieDetailPage(movie: movie),
        ),
      );
      if (mounted) await _reload();
    } catch (e) {
      DialogX.showError('$e');
    }
  }

  void _goBrowse() {
    HapticFeedback.selectionClick();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  List<FavStackItem> get _stackItems {
    if (_chip < 0) {
      return [
        for (final e in _favItems)
          FavStackItem(id: e.vodId, name: e.name, pic: e.pic),
      ];
    }
    return [
      for (final e in _watchItems)
        FavStackItem(id: e.id, name: e.name, pic: e.pic),
    ];
  }

  bool get _isEmpty {
    if (_chip < 0) return _favItems.isEmpty && _total == 0;
    return _watchItems.isEmpty && _total == 0;
  }

  @override
  Widget build(BuildContext context) {
    final pageBg = AppPalette.page(context);
    final text = AppPalette.text(context);
    final surface = AppPalette.surface(context);
    final line = AppPalette.line(context);
    final loggedIn = CmsAuthController.instance.isLoggedIn;
    final empty = !_loading && _isEmpty;
    final statusLabel = _watchStatus?.label ?? '收藏';

    return CupertinoPageScaffold(
      backgroundColor: pageBg,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: surface,
        border: Border(bottom: BorderSide(color: line, width: 0.5)),
        middle: Text(
          '我的收藏',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                children: [
                  _chipBtn('收藏', -1),
                  SizedBox(width: 8),
                  for (var i = 0; i < MovieWatchStatusX.selectable.length; i++) ...[
                    _chipBtn(MovieWatchStatusX.selectable[i].label, i),
                    if (i < MovieWatchStatusX.selectable.length - 1)
                      SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CupertinoActivityIndicator())
                  : AppPullRefresh(
                      color: AppColors.brand,
                      onRefresh: () => _reload(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                        children: [
                          FavCollectionCarousel(
                            items: _stackItems,
                            decorCovers: _decorCovers,
                            onOpen: empty
                                ? null
                                : (it) => _openVod(
                                      it.id,
                                      name: it.name,
                                      pic: it.pic,
                                    ),
                            title: empty
                                ? (loggedIn || _chip >= 0
                                    ? '从$statusLabel开始'
                                    : '登录后开启收藏')
                                : '我的$statusLabel',
                            subtitle: empty
                                ? (loggedIn || _chip >= 0
                                    ? '把喜欢的影视收进来，随时继续追'
                                    : '登录后同步收藏')
                                : (_stackItems.length == 1
                                    ? '点击海报直接播放'
                                    : _stackItems.length <= 3
                                        ? '点中间播放 · 点侧卡展开'
                                        : '左右滑动换页 · 点中间播放 · 点侧卡展开'),
                            ctaLabel: !loggedIn && _chip < 0
                                ? '去登录'
                                : (_error != null ? '重试' : '去发现好片'),
                            showCta: empty,
                            onCta: () async {
                              if (!loggedIn && _chip < 0) {
                                await showAuthSheet(context);
                                await _reload();
                              } else if (_error != null) {
                                await _reload();
                              } else {
                                _goBrowse();
                              }
                            },
                            height: empty ? 380 : 280,
                            compact: !empty,
                          ),
                          if (_error != null && !empty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 13,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          if (!empty) ...[
                            const SizedBox(height: 4),
                            if (_chip < 0)
                              for (final it in _favItems)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                  child: _FavTile(
                                    name: it.name,
                                    pic: it.pic,
                                    vodId: it.vodId,
                                    badge: '收藏',
                                    onTap: () => _openVod(
                                      it.vodId,
                                      name: it.name,
                                      pic: it.pic,
                                    ),
                                  ),
                                )
                            else
                              for (final it in _watchItems)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                  child: _FavTile(
                                    name: it.name,
                                    pic: it.pic,
                                    vodId: it.id,
                                    badge: it.status.label,
                                    onTap: () => _openVod(
                                      it.id,
                                      name: it.name,
                                      pic: it.pic,
                                    ),
                                  ),
                                ),
                            if (_total > _pageSize)
                              _PagerBar(
                                page: _page,
                                pageCount: _pageCount,
                                total: _total,
                                onPrev: () => _reload(page: _page - 1),
                                onNext: () => _reload(page: _page + 1),
                              ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipBtn(String label, int chip) {
    final on = _chip == chip;
    return GestureDetector(
      onTap: () => _switchChip(chip),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.brand : AppPalette.softFill(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : AppPalette.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

class _PagerBar extends StatelessWidget {
  const _PagerBar({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final hint = AppPalette.textHint(context);
    final canPrev = page > 1;
    final canNext = page < pageCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Text(
            '共 $total 部 · $page / $pageCount',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 12,
              color: hint,
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            onPressed: canPrev ? onPrev : null,
            child: Text(
              '上一页',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                color: canPrev ? AppColors.brand : hint,
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            onPressed: canNext ? onNext : null,
            child: Text(
              '下一页',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                color: canNext ? AppColors.brand : hint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavTile extends StatelessWidget {
  const _FavTile({
    required this.name,
    required this.pic,
    required this.vodId,
    required this.badge,
    required this.onTap,
  });

  final String name;
  final String pic;
  final String vodId;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = AppPalette.text(context);
    final hint = AppPalette.textHint(context);
    return Material(
      color: AppPalette.surface(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 78,
                  child: CmsCoverImage(url: pic, vodId: vodId),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '影片 $vodId' : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      badge,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: hint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 14, color: hint),
            ],
          ),
        ),
      ),
    );
  }
}
