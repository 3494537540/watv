import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../player/player_pip.dart';
import '../services/cms_fav_store.dart';
import '../services/vod_cache_store.dart';
import '../services/local_play_store.dart';
import '../services/maccms_api.dart';
import '../services/maccms_user_api.dart';
import '../services/movie_watch_store.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/cast_avatar.dart';
import '../widgets/cast_sheet.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/media_placeholder.dart';
import '../widgets/player/mango_inline_player.dart';
import '../widgets/player/mango_player_chrome.dart';
import '../widgets/player/mango_watch_panel.dart';
import 'vod_cache_list_page.dart';
import '../widgets/app_page_route.dart';

const _ink = Color(0xFF181818);
const _muted = Color(0xFF6B6B6B);
const _faint = Color(0xFF9A9A9A);
Color get _lime => AppColors.brand;
const _page = Color(0xFFFFFFFF);
const _soft = Color(0xFFF2F2F2);
const _star = Color(0xFFFF9F0A);

/// 影视详情：观影状态 · 星级评分 · 简介/演员/剧集展开 · 站内评论
class MovieDetailPage extends StatefulWidget {
  const MovieDetailPage({
    super.key,
    required this.movie,
    this.autoPlay = false,
    this.forceWatch = false,
    this.initialEpisodeIndex,
    this.initialSourceIndex,
  });

  final Movie movie;
  final bool autoPlay;
  /// 直接进入播放态，不先展示详情页
  final bool forceWatch;
  /// 指定开播集数（如选集列表点某一集）
  final int? initialEpisodeIndex;
  final int? initialSourceIndex;

  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _cms = MacCmsApi();
  final _scroll = ScrollController();
  final _inlinePlayerKey = GlobalKey<MangoInlinePlayerState>();

  late Movie _movie;
  late final AnimationController _enter;
  int _selectedEpisode = 0;
  int _sourceIndex = 0;
  /// 当前集已失败过的线路，自动切换时跳过
  final Set<int> _failedSources = <int>{};
  int _tab = 0; // 0 详情 1 评论
  int _watchTab = 0; // 播放中：0 视频 1 评论
  bool _watching = false;
  bool _landscapeFs = false;
  /// 是否已锁横屏（与 UI 标记分开，保证异常退出也能解锁）
  bool _orientationLocked = false;
  int _playStartMs = 0;
  String? _resumeLabel;
  bool _autoPlayPending = false;
  bool _loading = true;
  double _scrollY = 0;
  String? _error;
  MovieWatchStatus _watch = MovieWatchStatus.none;

  List<MovieComment> _comments = const [];
  bool _commentsLoading = false;
  String? _commentsError;
  bool _commentsLoaded = false;
  int _commentsLoadToken = 0;

  List<Movie> _relatedMovies = const [];
  bool _relatedLoaded = false;
  bool _relatedLoading = false;
  bool _favored = false;
  int _downloadingCount = 0;
  /// 播放器下方展开为完整剧集列表（非弹窗）
  bool _episodesExpanded = false;
  /// 播放器下方展开为下载选集
  bool _downloadPick = false;
  final GlobalKey _cacheIconKey = GlobalKey();
  StreamSubscription<List<VodCacheItem>>? _cacheSub;

  Movie get movie => _movie;
  List<MoviePlayEpisode> get _episodes => movie.episodesOf(_sourceIndex);

  /// 有本机缓存则优先播本地文件
  String? _resolvePlayUrl(int episodeIndex) {
    final cached = VodCacheStore.instance.find(
      vodId: movie.id,
      episodeIndex: episodeIndex,
      sourceIndex: _sourceIndex,
    );
    if (cached != null &&
        cached.isDone &&
        cached.localPath.isNotEmpty &&
        File(cached.localPath).existsSync()) {
      return cached.localPath;
    }
    return movie.playUrlAt(episodeIndex, sourceIndex: _sourceIndex);
  }

  /// 当前线路挂了 → 自动切到下一条可用源（保持当前集尽量不变）
  bool _tryNextPlaySource({int? keepEpisode, bool notify = true}) {
    final sources = movie.playSources;
    if (sources.length <= 1) return false;
    _failedSources.add(_sourceIndex);
    final wantEp = keepEpisode ?? _selectedEpisode;
    final wantName = () {
      final cur = movie.episodesOf(_sourceIndex);
      if (wantEp >= 0 && wantEp < cur.length) return cur[wantEp].name.trim();
      return '';
    }();

    for (var i = 0; i < sources.length; i++) {
      if (_failedSources.contains(i)) continue;
      final eps = sources[i].episodes;
      if (eps.isEmpty) continue;
      var ep = wantEp;
      if (ep < 0 || ep >= eps.length) {
        ep = 0;
        if (wantName.isNotEmpty) {
          final j = eps.indexWhere((e) => e.name.trim() == wantName);
          if (j >= 0) ep = j;
        }
      }
      final url = eps[ep].url.trim();
      if (url.isEmpty) continue;
      setState(() {
        _sourceIndex = i;
        _selectedEpisode = ep;
        _playStartMs = 0;
        _watching = true;
      });
      if (notify) {
        DialogX.showWarning('当前线路异常，已自动切换');
      }
      return true;
    }
    return false;
  }

  Future<bool> _onPlayerSourceFailover() async {
    return _tryNextPlaySource(keepEpisode: _selectedEpisode);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _movie = widget.movie;
    _autoPlayPending = widget.autoPlay || widget.forceWatch;
    if (widget.initialSourceIndex != null) {
      _sourceIndex = widget.initialSourceIndex!;
    }
    if (widget.initialEpisodeIndex != null) {
      _selectedEpisode = widget.initialEpisodeIndex!;
    }
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _scroll.addListener(() => setState(() => _scrollY = _scroll.offset));
    _loadDetail();
    _loadWatch();
    unawaited(_refreshCacheFlag());
    unawaited(_loadFavored());
    _cacheSub = VodCacheStore.instance.stream.listen((_) {
      if (!mounted) return;
      final n = VodCacheStore.instance.activeCountFor(movie.id);
      if (n != _downloadingCount) {
        setState(() => _downloadingCount = n);
      }
      unawaited(_refreshCacheFlag());
    });
  }

  Future<void> _refreshCacheFlag() async {
    await VodCacheStore.instance.ensureLoaded();
    if (!mounted) return;
    final n = VodCacheStore.instance.activeCountFor(movie.id);
    if (n != _downloadingCount) {
      setState(() => _downloadingCount = n);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cacheSub?.cancel() ?? Future<void>.value());
    unawaited(_forceUnlockOrientation());
    unawaited(stopAllInlinePlayback());
    _enter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _watching) {
      unawaited(_applyImmersiveWatchUi());
    }
  }

  Future<void> _exitWatch() async {
    await _exitLandscapeFs();
    await PlayerPip.cancelAutoOnLeave();
    await _inlinePlayerKey.currentState?.forceStop();
    await _restoreSystemUi();
    if (!mounted) return;
    // 首页小卡 forceWatch：返回应退出详情，否则会卡在「forceWatch && !_watching」加载页
    if (widget.forceWatch) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    setState(() {
      _watching = false;
      _episodesExpanded = false;
      _downloadPick = false;
    });
  }

  /// 播放中保持 edgeToEdge：画面铺进状态栏/挖孔。
  /// 勿切 manual/immersive 藏栏——部分机型会腾出黑条并把内容往下顶。
  Future<void> _applyImmersiveWatchUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
    } catch (_) {}
  }

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );
    } catch (_) {}
  }

  Future<void> _forceUnlockOrientation() async {
    _orientationLocked = false;
    try {
      await _restoreSystemUi();
      // 先强制回竖屏，避免卡在横屏首页
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  Future<void> _enterLandscapeFs() async {
    if (_landscapeFs) return;
    try {
      // 先锁横屏，等尺寸稳定后再铺满，避免半屏/LEFT OVERFLOW 闪一下
      await _applyImmersiveWatchUi();
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _orientationLocked = true;
      for (var i = 0; i < 24; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (!mounted) {
          await _forceUnlockOrientation();
          return;
        }
        final s = MediaQuery.sizeOf(context);
        if (s.width > s.height) break;
      }
      if (mounted) setState(() => _landscapeFs = true);
    } catch (_) {
      await _forceUnlockOrientation();
      if (mounted) setState(() => _landscapeFs = false);
    }
  }

  Future<void> _exitLandscapeFs() async {
    if (!_landscapeFs && !_orientationLocked) return;
    // 必须先转回竖屏，再收起全屏布局，否则横屏宽度下 9:16 高度会撑爆 Column
    await _forceUnlockOrientation();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
      final s = MediaQuery.sizeOf(context);
      if (s.height >= s.width) break;
    }
    if (mounted) setState(() => _landscapeFs = false);
    // 仍在观看：继续沉浸，避免竖屏播放又露出系统顶栏黑边
    if (mounted && _watching) {
      await _applyImmersiveWatchUi();
    }
  }

  /// 原位横屏全屏，复用同一播放器实例，不重新加载
  Future<void> _toggleFullscreen() async {
    if (_landscapeFs) {
      await _exitLandscapeFs();
    } else {
      await _enterLandscapeFs();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // 热重载不退出播放，只确保方向解锁标记不脏
  }

  Future<void> _loadWatch() async {
    final s = await MovieWatchStore.get(widget.movie.id);
    final prev = await LocalPlayStore.get(widget.movie.id);
    if (!mounted) return;
    setState(() {
      _watch = s;
      final forcedEp = widget.initialEpisodeIndex;
      if (forcedEp != null) {
        final max = movie.episodesOf(_sourceIndex).length;
        _selectedEpisode =
            max > 0 ? forcedEp.clamp(0, max - 1) : forcedEp;
        if (prev != null &&
            prev.episodeIndex == _selectedEpisode &&
            prev.positionMs > 3000) {
          _playStartMs = prev.positionMs;
          _resumeLabel = prev.episodeLabel.trim().isNotEmpty
              ? prev.episodeLabel.trim()
              : '第${_selectedEpisode + 1}集';
        }
        return;
      }
      if (prev != null && prev.episodeIndex >= 0) {
        final max = movie.episodesOf(_sourceIndex).length;
        if (max > 0) {
          _selectedEpisode = prev.episodeIndex.clamp(0, max - 1);
        } else {
          _selectedEpisode = prev.episodeIndex;
        }
        if (prev.positionMs > 3000) {
          _playStartMs = prev.positionMs;
          _resumeLabel = prev.episodeLabel.trim().isNotEmpty
              ? prev.episodeLabel.trim()
              : '第${prev.episodeIndex + 1}集';
        }
      }
    });
  }

  void _maybeAutoPlay() {
    if (!_autoPlayPending || _loading || _watching) return;
    _autoPlayPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play(episodeIndex: _selectedEpisode);
    });
  }

  Future<void> _loadFavored() async {
    final id = CmsFavStore.normId(movie.id);
    if (id.isEmpty) return;
    final local = await CmsFavStore.contains(id);
    if (!CmsAuthController.instance.isLoggedIn) {
      if (mounted) setState(() => _favored = local);
      return;
    }
    try {
      final list =
          await CmsAuthController.instance.api.fetchUlog(type: 1, limit: 120);
      final hit = list.any((e) => CmsFavStore.normId(e.vodId) == id);
      if (hit) {
        final row = list.firstWhere((e) => CmsFavStore.normId(e.vodId) == id);
        await CmsFavStore.add(
          vodId: id,
          name: row.name,
          pic: row.pic,
          ulogId: row.id,
        );
      }
      if (!mounted) return;
      setState(() => _favored = local || hit);
    } catch (_) {
      if (mounted) setState(() => _favored = local);
    }
  }

  bool _favBusy = false;

  Future<void> _toggleFav() async {
    if (_favBusy) return;
    if (!CmsAuthController.instance.isLoggedIn) {
      DialogX.showWarning('请先登录后再收藏');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _favBusy = true);
    final id = CmsFavStore.normId(movie.id);
    try {
      if (_favored) {
        // 先本地取消，保证下次打开状态正确
        await CmsFavStore.remove(id);
        if (mounted) setState(() => _favored = false);
        try {
          final list =
              await CmsAuthController.instance.api.fetchUlog(type: 1, limit: 120);
          CmsUlogItem? row;
          for (final e in list) {
            if (CmsFavStore.normId(e.vodId) == id) {
              row = e;
              break;
            }
          }
          final ulogId = row?.id.trim() ?? '';
          if (ulogId.isNotEmpty) {
            await CmsAuthController.instance.api.delUlog(ids: ulogId, type: 2);
          }
        } catch (_) {}
        DialogX.showSuccess('已取消收藏');
      } else {
        await CmsFavStore.add(
          vodId: id,
          name: movie.title,
          pic: movie.coverUrl ?? '',
        );
        if (mounted) setState(() => _favored = true);
        try {
          await CmsAuthController.instance.api.setUlog(
            vodId: id,
            type: MacCmsUserApi.ulogFav,
          );
        } catch (_) {
          // 本地已收藏；CMS 失败不回滚，避免「打开又没了」
        }
        DialogX.showSuccess('已加入收藏');
      }
    } catch (e) {
      DialogX.showError('$e');
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  void _shareMovie() {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: movie.title));
    DialogX.showSuccess('片名已复制，可分享给好友');
  }

  Future<void> _loadRelated() async {
    if (_relatedLoading) return;
    if (_relatedLoaded && _relatedMovies.isNotEmpty) return;
    _relatedLoaded = true;
    if (mounted) setState(() => _relatedLoading = true);
    try {
      final exclude = movie.id;
      List<Movie> list = const [];

      // 优先同 CMS 分类
      if (movie.typeId > 0) {
        list = await _cms.fetchByType(typeId: movie.typeId, limit: 18);
      }
      // 再用类型名 / 首个题材搜同类型
      if (list.length < 6) {
        final key = movie.subtitle.trim().isNotEmpty
            ? movie.subtitle.trim()
            : (movie.genres.isNotEmpty ? movie.genres.first : '');
        if (key.isNotEmpty) {
          final byType = await _cms.search(key, limit: 16);
          list = [...list, ...byType];
        }
      }
      if (list.length < 6 && movie.genres.isNotEmpty) {
        for (final g in movie.genres.take(2)) {
          if (g == movie.area || g == movie.subtitle) continue;
          final byGenre = await _cms.search(g, limit: 12);
          list = [...list, ...byGenre];
          if (list.length >= 10) break;
        }
      }
      if (list.length < 4) {
        final hot = await _cms.fetchHotMovies(limit: 16);
        list = [...list, ...hot];
      }

      final preferSeries = movie.isSeries;
      final ranked = [...list]..sort((a, b) {
          final as = preferSeries
              ? (a.isSeries ? 0 : 1)
              : (a.isSeries ? 1 : 0);
          final bs = preferSeries
              ? (b.isSeries ? 0 : 1)
              : (b.isSeries ? 1 : 0);
          if (as != bs) return as.compareTo(bs);
          return b.score.compareTo(a.score);
        });

      final seen = <String>{exclude};
      final out = <Movie>[];
      for (final m in ranked) {
        if (seen.add(m.id)) out.add(m);
        if (out.length >= 10) break;
      }
      if (!mounted) return;
      setState(() {
        _relatedMovies = out;
        _relatedLoading = false;
      });
    } catch (_) {
      try {
        final hot = await _cms.fetchHotMovies(limit: 10);
        if (!mounted) return;
        setState(() {
          _relatedMovies =
              hot.where((m) => m.id != movie.id).take(8).toList(growable: false);
          _relatedLoading = false;
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _relatedLoaded = false;
            _relatedLoading = false;
          });
        }
      }
    }
  }

  Future<void> _openDownloadPick() async {
    HapticFeedback.selectionClick();
    await VodCacheStore.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _episodesExpanded = false;
      _downloadPick = true;
    });
  }

  void _collapseDownloadPick() {
    HapticFeedback.selectionClick();
    setState(() => _downloadPick = false);
  }

  Set<int> get _cachedEpisodeIndexes {
    final out = <int>{};
    for (final e in VodCacheStore.instance.items) {
      if (e.vodId == movie.id &&
          e.sourceIndex == _sourceIndex &&
          e.isDone) {
        out.add(e.episodeIndex);
      }
    }
    return out;
  }

  Future<void> _submitDownloadPick(List<int> indexes) async {
    if (indexes.isEmpty) return;
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
    final cover = (movie.coverUrl ?? '').trim();
    for (final i in indexes) {
      final url = movie.playUrlAt(i, sourceIndex: _sourceIndex);
      if (url == null || url.isEmpty) continue;
      jobs.add((
        vodId: movie.id,
        title: movie.title,
        episodeIndex: i,
        episodeLabel: _episodeLabelAt(i),
        sourceIndex: _sourceIndex,
        url: url,
        coverUrl: cover,
      ));
    }
    if (jobs.isEmpty) {
      DialogX.showWarning('所选剧集暂无地址');
      return;
    }

    await _playPackIntoCacheIcon(count: jobs.length);
    if (!mounted) return;
    setState(() {
      _downloadPick = false;
      _downloadingCount =
          VodCacheStore.instance.activeCountFor(movie.id) + jobs.length;
    });

    final added = await VodCacheStore.instance.enqueueMany(jobs: jobs);
    if (!mounted) return;
    setState(() {
      _downloadingCount = VodCacheStore.instance.activeCountFor(movie.id);
    });
    if (added <= 0) {
      DialogX.showSuccess('所选剧集已全部缓存');
    } else {
      DialogX.showSuccess('已加入 $added 集下载');
    }
  }

  /// 选中剧集「收纳进行李箱」飞向下载图标
  Future<void> _playPackIntoCacheIcon({required int count}) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    Offset target;
    final targetCtx = _cacheIconKey.currentContext;
    final targetBox = targetCtx?.findRenderObject() as RenderBox?;
    if (targetBox != null && targetBox.hasSize) {
      target = targetBox.localToGlobal(targetBox.size.center(Offset.zero));
    } else {
      final size = MediaQuery.sizeOf(context);
      final pad = MediaQuery.paddingOf(context);
      // 顶栏下载图标大致位置（右上）
      target = Offset(size.width - 72, pad.top + 56);
    }
    final size = MediaQuery.sizeOf(context);
    final start = Offset(size.width * 0.5, size.height * 0.58);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return _PackFlyOverlay(
          start: start,
          end: target,
          count: count.clamp(1, 8),
          onDone: () {
            entry.remove();
          },
        );
      },
    );
    overlay.insert(entry);
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 780));
  }

  String get _watchGenreLabel {
    if (movie.genres.isNotEmpty) return movie.genres.first;
    if (movie.totalEpisodes > 1 || _episodes.length > 1) return '电视剧';
    return '影视';
  }

  String get _watchSourceLine {
    return '哇TV · $_watchGenreLabel';
  }

  /// 正片旁短介绍：更新至xx集 / 完结 等
  String? get _episodeIntro {
    final r = movie.remarks.trim();
    if (r.isEmpty) return null;
    // 常见备注整段展示（更新至24集）
    if (r.length <= 12) return r;
    final badge = movie.cornerBadge;
    if (badge != null && badge.length <= 4) return badge;
    return r.length > 12 ? '${r.substring(0, 12)}…' : r;
  }

  void _openWatchInfo() {
    final synopsis =
        movie.synopsis.trim().isEmpty ? '暂无简介' : movie.synopsis.trim();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                movie.title,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                synopsis,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 14,
                  height: 1.55,
                  color: Color(0xFF555555),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setWatch(MovieWatchStatus s) async {
    HapticFeedback.selectionClick();
    final next = _watch == s ? MovieWatchStatus.none : s;
    setState(() => _watch = next);
    await MovieWatchStore.set(
      movie.id,
      next,
      name: movie.title,
      pic: movie.coverUrl ?? '',
    );
  }

  Future<void> _loadDetail() async {
    final id = widget.movie.id.trim();
    if (id.isEmpty || id.startsWith('m')) {
      setState(() => _loading = false);
      _maybeAutoPlay();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _cms.fetchDetail(id);
      if (!mounted) return;
      setState(() {
        _movie = detail;
        _loading = false;
        if (widget.initialSourceIndex != null) {
          final maxSrc = detail.playSources.length;
          _sourceIndex = maxSrc > 0
              ? widget.initialSourceIndex!.clamp(0, maxSrc - 1)
              : 0;
        } else {
          _sourceIndex = 0;
        }
        final maxEp = detail.episodesOf(_sourceIndex).length;
        if (widget.initialEpisodeIndex != null && maxEp > 0) {
          _selectedEpisode =
              widget.initialEpisodeIndex!.clamp(0, maxEp - 1);
        } else if (_selectedEpisode >= maxEp) {
          _selectedEpisode = 0;
        }
      });
      // 详情到位后按最终片名/ID 再拉一次评论
      unawaited(_loadComments(force: true));
      _maybeAutoPlay();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadComments({bool force = false}) async {
    // force 刷新时不要被进行中的请求挡掉（发表后刷新常踩中）
    if (_commentsLoading && !force) return;
    if (_commentsLoaded && !force) return;
    final id = movie.id.trim();
    final title = movie.title.trim().isNotEmpty
        ? movie.title.trim()
        : widget.movie.title.trim();
    // 允许仅有片名时也拉评论（id 异常/本地占位）
    if ((id.isEmpty || id.startsWith('m')) && title.isEmpty) {
      setState(() {
        _comments = const [];
        _commentsLoaded = true;
        _commentsLoading = false;
      });
      return;
    }
    final token = ++_commentsLoadToken;
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });
    try {
      _cms.adoptCmsSessionCookie(
        CmsAuthController.instance.api.sessionCookie,
      );
      final list = await _cms
          .fetchComments(id, title: title)
          .timeout(const Duration(seconds: 12));
      if (!mounted || token != _commentsLoadToken) return;
      final prevLocals = [
        for (final c in _comments)
          if (c.id.startsWith('local_')) c,
      ];
      final remoteContents = {for (final c in list) c.content.trim()};
      final keepLocals = [
        for (final c in prevLocals)
          if (!remoteContents.contains(c.content.trim())) c,
      ];
      setState(() {
        _comments = [...keepLocals, ...list];
        _commentsLoading = false;
        _commentsLoaded = true;
      });
    } catch (e) {
      if (!mounted || token != _commentsLoadToken) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = '$e';
        _commentsLoaded = true;
      });
    }
  }

  void _play({int? episodeIndex}) {
    HapticFeedback.mediumImpact();
    if (_loading) {
      DialogX.showWarning('正在加载片源…');
      return;
    }
    final ep = episodeIndex ?? (movie.isSeries ? _selectedEpisode : 0);
    if (ep != _selectedEpisode) {
      _failedSources.clear();
    }
    var url = _resolvePlayUrl(ep);
    if (url == null || url.isEmpty) {
      if (_tryNextPlaySource(keepEpisode: ep)) return;
      DialogX.showError('暂无可用播放地址，请稍后重试');
      _loadDetail();
      return;
    }
    final vodId = movie.id;
    final sid = _sourceIndex + 1;
    final nid = ep + 1;
    final startMs = (ep == _selectedEpisode) ? _playStartMs : 0;

    setState(() {
      _watching = true;
      _selectedEpisode = ep;
      _playStartMs = startMs;
      _watchTab = 0;
      _resumeLabel = null;
    });
    unawaited(_refreshCacheFlag());
    unawaited(_applyImmersiveWatchUi());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_watching) return;
      final rect = _inlinePlayerKey.currentState?.playerScreenRect();
      unawaited(PlayerPip.enableAutoOnLeave(sourceRect: rect));
    });
    // 进入播放即拉评论，Tab 角标不必点进评论才出现
    unawaited(_loadComments());
    unawaited(_loadRelated());

    () async {
      var resumeMs = startMs;
      try {
        final labels = movie.episodeLabels;
        final label = (labels.isNotEmpty && ep >= 0 && ep < labels.length)
            ? labels[ep]
            : '第${ep + 1}集';
        final prev = await LocalPlayStore.get(vodId);
        if (prev != null && prev.episodeIndex == ep && prev.positionMs > 0) {
          resumeMs = prev.positionMs;
        }
        unawaited(
          LocalPlayStore.add(
            vodId: vodId,
            name: movie.title,
            pic: movie.coverUrl ?? '',
            remarks: movie.remarks,
            episodeIndex: ep,
            episodeLabel: label,
            positionMs: prev?.positionMs ?? 0,
            durationMs: prev?.durationMs ?? 0,
          ),
        );
      } catch (_) {}
      if (CmsAuthController.instance.isLoggedIn) {
        try {
          final api = CmsAuthController.instance.api;
          await api.setUlog(
            vodId: vodId,
            type: MacCmsUserApi.ulogPlay,
            sid: sid,
            nid: nid,
          );
          unawaited(api.updateHits(vodId: vodId));
        } catch (_) {}
      }
      if (!mounted) return;
      if (resumeMs > 3000 && resumeMs != _playStartMs) {
        setState(() => _playStartMs = resumeMs);
        await _inlinePlayerKey.currentState?.seekTo(
          Duration(milliseconds: resumeMs),
        );
      }
    }();
  }

  void _savePlayProgress(Duration pos, Duration dur) {
    if (pos.inMilliseconds <= 0 && dur.inMilliseconds <= 0) return;
    final eps = _episodes;
    final label = (_selectedEpisode >= 0 && _selectedEpisode < eps.length)
        ? eps[_selectedEpisode].name
        : '第${_selectedEpisode + 1}集';
    unawaited(
      LocalPlayStore.add(
        vodId: movie.id,
        name: movie.title,
        pic: movie.coverUrl ?? '',
        remarks: movie.remarks,
        episodeIndex: _selectedEpisode,
        episodeLabel: label,
        positionMs: pos.inMilliseconds,
        durationMs: dur.inMilliseconds,
      ),
    );
  }

  void _showAllEpisodesInline() {
    HapticFeedback.selectionClick();
    setState(() {
      _downloadPick = false;
      _episodesExpanded = true;
    });
  }

  void _collapseEpisodesInline() {
    HapticFeedback.selectionClick();
    setState(() => _episodesExpanded = false);
  }

  String _episodeLabelAt(int index) {
    final eps = _episodes;
    if (eps.length > 1) {
      return '第${(index + 1).toString().padLeft(2, '0')}集';
    }
    if (index >= 0 && index < eps.length) return eps[index].name;
    if (eps.isEmpty) return '正片';
    return '第${index + 1}集';
  }

  String _watchTag() {
    final eps = _episodes;
    if (eps.length > 1) return '全${eps.length}集';
    final remarks = movie.remarks.trim();
    if (remarks.isNotEmpty) return remarks;
    final sub = movie.subtitle.trim();
    if (sub.isNotEmpty) return sub;
    return '高清';
  }

  void _onCastTap() {
    final url = movie.playUrlAt(_selectedEpisode, sourceIndex: _sourceIndex);
    unawaited(
      showCastSheet(
        context: context,
        mediaUrl: url ?? '',
        title: movie.title,
        onCastStarted: () {
          unawaited(_inlinePlayerKey.currentState?.pause());
        },
        onCastStopped: () {
          unawaited(_inlinePlayerKey.currentState?.play());
        },
      ),
    );
  }

  Widget _buildImmersivePlayer(
    BuildContext context, {
    required String? url,
    required List<MoviePlayEpisode> episodes,
    bool expand = false,
    double topInset = 0,
    EdgeInsets safeInset = EdgeInsets.zero,
  }) {
    // 尺寸由外层 AnimatedContainer / expand 控制，避免双重固定高度溢出
    return url != null
        ? MangoInlinePlayer(
            key: _inlinePlayerKey,
            url: url,
            startPositionMs: _playStartMs,
            immersiveTop: true,
            episodes: episodes,
            selectedEpisode: _selectedEpisode,
            onEpisodeSelect: (i) => _play(episodeIndex: i),
            sourceNames: [for (final s in movie.playSources) s.name],
            sourceIndex: _sourceIndex,
            onRequestSourceFailover: _onPlayerSourceFailover,
            onPrepareRetry: () async {
              _failedSources.clear();
              if (_sourceIndex != 0) {
                setState(() {
                  _sourceIndex = 0;
                  _playStartMs = 0;
                });
              }
            },
            onFullscreen: _toggleFullscreen,
            onProgress: _savePlayProgress,
            vodId: movie.id,
            danmakuTitle: movie.title,
            danmakuEpisode: _selectedEpisode,
            danmakuEpisodeLabel: episodes.isNotEmpty
                ? _episodeLabelAt(_selectedEpisode)
                : '',
            showNextEpisode: _selectedEpisode < episodes.length - 1,
            onNextEpisode: _selectedEpisode < episodes.length - 1
                ? () => _play(episodeIndex: _selectedEpisode + 1)
                : null,
            onCast: _onCastTap,
            showEpisodesInMenu: expand,
            topOverlay: MangoWatchTopBar(
              topInset: topInset,
              safeInset: expand ? safeInset : null,
              showSysStatus: expand,
              title: movie.title,
              episodeLabel: episodes.length > 1
                  ? _episodeLabelAt(_selectedEpisode)
                  : '',
              tag: _watchTag(),
              onCast: _onCastTap,
              onPip: () {
                unawaited(
                  _inlinePlayerKey.currentState?.enterPictureInPicture() ??
                      PlayerPip.enter(),
                );
              },
              onSeekForward: () =>
                  unawaited(_inlinePlayerKey.currentState?.seekBySeconds(10)),
              onSettings: () =>
                  _inlinePlayerKey.currentState?.openSettings(),
              onBack: () {
                if (_landscapeFs) {
                  unawaited(_exitLandscapeFs());
                } else {
                  unawaited(_exitWatch());
                }
              },
            ),
          )
        : const ColoredBox(color: Colors.black);
  }

  Widget _buildMangoWatchScaffold(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewPad = MediaQuery.viewPaddingOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final url = _resolvePlayUrl(_selectedEpisode);
    final episodes = _episodes;

    // 物理仍横屏时继续铺满，避免提前用竖屏 9:16 算高度导致 BOTTOM OVERFLOW
    final physicallyWide = size.width > size.height;
    final expandPlayer = _landscapeFs || physicallyWide;

    // 竖屏高度含 viewPad.top；小窗高度可能 < 160，clamp 上下界不能反
    final idealH = size.width * 9 / 16;
    final maxPortraitH = size.height * 0.52;
    final minPortraitH = maxPortraitH < 160.0 ? 0.0 : 160.0;
    final portraitVideoH =
        (idealH + viewPad.top).clamp(minPortraitH, maxPortraitH);

    // 顶栏竖直避让只用 top；左右挖孔由 TopBar 的 safeInset 水平处理。
    // 切勿把 left/right 并进 topInset，横屏会把整块顶栏顶下去。
    final chromeTopInset = viewPad.top;

    final player = _buildImmersivePlayer(
      context,
      url: url,
      episodes: episodes,
      expand: expandPlayer,
      topInset: chromeTopInset,
      safeInset: viewPad,
    );

    final intro = (_episodeIntro?.trim().isNotEmpty == true)
        ? _episodeIntro!.trim()
        : (movie.remarks.trim().isNotEmpty
            ? movie.remarks.trim()
            : (movie.tagline.trim().isNotEmpty ? movie.tagline.trim() : ''));

    final markVip = () {
      final r = movie.remarks.toUpperCase();
      if (r.contains('VIP') || movie.remarks.contains('会员')) return 2;
      return null;
    }();

    // 顶栏（标题+收藏/下载）常驻，便于下载飞入动画对准图标
    final chrome = Padding(
      padding: const EdgeInsets.fromLTRB(
        MangoWatchStyle.hPad,
        14,
        MangoWatchStyle.hPad,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MangoWatchHeader(
            title: movie.title,
            sourceLine: _watchSourceLine,
            onTitleTap: _openWatchInfo,
          ),
          const SizedBox(height: MangoWatchStyle.gapMetaTabs),
          MangoWatchTabs(
            index: _watchTab,
            commentCount: _comments.length,
            onChanged: (i) {
              setState(() {
                _watchTab = i;
                _downloadPick = false;
                _episodesExpanded = false;
              });
              if (i == 1) _loadComments();
            },
            onFavorite: _toggleFav,
            favored: _favored,
            onShare: _shareMovie,
            onCache: () => unawaited(_openDownloadPick()),
            downloadingCount: _downloadingCount,
            cacheIconKey: _cacheIconKey,
          ),
        ],
      ),
    );

    final panel = SafeArea(
      top: false,
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chrome,
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              // 默认居中会在评论 Tab 上方留一大块空白
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: _downloadPick
                  ? MangoDownloadPickPanel(
                      key: const ValueKey('download-pick'),
                      episodes: episodes,
                      selectedEpisode: _selectedEpisode,
                      doneIndexes: _cachedEpisodeIndexes,
                      bottomInset: bottom,
                      markVipFromIndex: markVip,
                      onClose: _collapseDownloadPick,
                      onOpenCacheList: () {
    Navigator.of(context).push(
      AppPageRoute<void>(
                            builder: (_) => const VodCacheListPage(),
                          ),
                        );
                      },
                      onSubmit: (idxs) =>
                          unawaited(_submitDownloadPick(idxs)),
                    )
                  : _episodesExpanded
                      ? MangoEpisodeAllPanel(
                          key: const ValueKey('episodes-all'),
                          episodes: episodes,
                          selectedEpisode: _selectedEpisode,
                          intro: intro,
                          markVipFromIndex: markVip,
                          bottomInset: bottom,
                          onClose: _collapseEpisodesInline,
                          onSelect: (i) => _play(episodeIndex: i),
                        )
                      : SingleChildScrollView(
                          key: const ValueKey('watch-panel'),
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              MangoWatchPanel(
                                title: movie.title,
                                sourceLine: _watchSourceLine,
                                tabIndex: _watchTab,
                                commentCount: _comments.length,
                                onTabChanged: (i) {
                                  setState(() => _watchTab = i);
                                  if (i == 1) _loadComments();
                                },
                                episodes: episodes,
                                selectedEpisode: _selectedEpisode,
                                onEpisodeSelect: (i) =>
                                    _play(episodeIndex: i),
                                relatedMovies: _relatedMovies,
                                relatedLoading: _relatedLoading,
                                hideChrome: true,
                                onShowAllEpisodes: _showAllEpisodesInline,
                                episodeIntro: _episodeIntro,
                                relatedTitle: movie.isSeries
                                    ? '同类型剧集'
                                    : '同类型影视',
                                markVipFromIndex: markVip,
                                onRelatedTap: (m) {
                                  Navigator.of(context).pushReplacement(
                                    AppPageRoute<void>(
                                      builder: (_) =>
                                          MovieDetailPage(movie: m),
                                    ),
                                  );
                                },
                                commentPanel: _CommentPanel(
                                  cms: _cms,
                                  movieId: movie.id,
                                  comments: _comments,
                                  loading: _commentsLoading,
                                  error: _commentsError,
                                  onRefresh: () =>
                                      _loadComments(force: true),
                                  onPosted: () =>
                                      _loadComments(force: true),
                                  onLocalComment: (c) {
                                    setState(() {
                                      _comments = [c, ..._comments];
                                    });
                                  },
                                  onClose: () =>
                                      setState(() => _watchTab = 0),
                                ),
                              ),
                              SizedBox(height: 24 + bottom),
                            ],
                          ),
                        ),
            ),
          ),
        ],
      ),
    );

    Widget watchBody;
    if (expandPlayer) {
      watchBody = SizedBox.expand(child: player);
    } else {
      // 播放器节点位置固定；小窗时只把下方面板换成黑底，避免拆 Texture 崩引擎
      watchBody = Column(
        children: [
          SizedBox(
            height: portraitVideoH,
            width: double.infinity,
            child: ColoredBox(color: Colors.black, child: player),
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: PlayerPip.inPip,
              builder: (context, pip, child) {
                if (pip) return const ColoredBox(color: Colors.black);
                return child!;
              },
              child: panel,
            ),
          ),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: expandPlayer ? Colors.black : _page,
        extendBody: true,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        body: MediaQuery.removeViewPadding(
          context: context,
          removeTop: true,
          removeBottom: expandPlayer,
          removeLeft: expandPlayer,
          removeRight: expandPlayer,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: expandPlayer,
            removeLeft: expandPlayer,
            removeRight: expandPlayer,
            child: watchBody,
          ),
        ),
      ),
    );
  }

  List<String> get _metaTags {
    final parts = <String>[
      if (movie.year > 0) '${movie.year}',
      if (movie.area.isNotEmpty) movie.area,
      ...movie.genres.take(3),
      if (movie.totalEpisodes > 0) '全${movie.totalEpisodes}集',
      if (movie.remarks.isNotEmpty) movie.remarks,
    ];
    final seen = <String>{};
    return [
      for (final p in parts)
        if (seen.add(p.trim()) && p.trim().isNotEmpty) p.trim(),
    ];
  }

  Animation<double> _stagger(double a, double b) => CurvedAnimation(
        parent: _enter,
        curve: Interval(a, b, curve: Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.forceWatch && !_watching) {
      final cover = movie.coverUrl?.trim() ?? '';
    return ColoredBox(
        color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
            if (cover.isNotEmpty)
              Opacity(
                opacity: 0.45,
                child: CmsCoverImage(
                  url: cover,
                  fit: BoxFit.cover,
                ),
              ),
            const ColoredBox(color: Color(0x66000000)),
            Center(
                        child: Column(
                mainAxisSize: MainAxisSize.min,
                          children: [
                  const CupertinoActivityIndicator(color: Colors.white),
                  if (movie.title.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                              movie.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                          fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                        ),
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

    if (_watching) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_downloadPick) {
            _collapseDownloadPick();
          } else if (_episodesExpanded) {
            _collapseEpisodesInline();
          } else if (_landscapeFs) {
            unawaited(_exitLandscapeFs());
          } else {
            unawaited(_exitWatch());
          }
        },
        child: _buildMangoWatchScaffold(context),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final cover = movie.coverUrl?.trim() ?? '';
    final episodes = _episodes;
    final synopsis =
        movie.synopsis.trim().isEmpty ? '暂无简介' : movie.synopsis.trim();
    final heroH = size.height * 0.48;
    final parallax = (_scrollY * 0.22).clamp(0.0, 40.0);
    // 背景含状态栏高度，内容顶距同步下移
    final contentTop = heroH + top - 72;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: Stack(
          children: [
            Positioned(
              top: -parallax,
              left: 0,
              right: 0,
              // 背景上推一点，盖住状态栏区域
              height: heroH + parallax + top,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const MediaPlaceholder(kind: MediaPlaceholderKind.film),
                  if (cover.isNotEmpty)
                    Image.network(
                      cover,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.12),
                      errorBuilder: (_, _, _) => const MediaPlaceholder(
                        kind: MediaPlaceholderKind.film,
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x55000000),
                          Color(0x00000000),
                          Color(0x66FFFFFF),
                          Color(0xFFF5F5F7),
                        ],
                        stops: [0, 0.35, 0.82, 1],
                  ),
                ),
              ),
                ],
              ),
            ),

            CustomScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: contentTop)),

              SliverToBoxAdapter(
                  child: _FadeSlide(
                    animation: _stagger(0.05, 0.4),
                child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        movie.title,
                                        style: const TextStyle(
                                          fontFamily: 'AppSans',
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          height: 1.2,
                                          letterSpacing: -0.4,
                                          color: _ink,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      if (_metaTags.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            for (final tag in _metaTags)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _soft,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  tag,
                                                  style: const TextStyle(
                                                    fontFamily: 'AppSans',
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: _muted,
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                          ],
                        ],
                      ),
                                ),
                                const SizedBox(width: 12),
                                _FavBtn(
                                  busy: _favBusy,
                                  active: _favored,
                                  onTap: _toggleFav,
                                ),
                                const SizedBox(width: 10),
                                _PlayBtn(
                                  loading: _loading,
                                  onTap: () => _play(),
                                ),
                              ],
                            ),
                            if (movie.score > 0) ...[
                      const SizedBox(height: 14),
                              _StarRatingRow(
                                score: movie.score,
                                stars: movie.starRating,
                                count: movie.scoreCount,
                              ),
                            ],
                            if (_resumeLabel != null && !_watching) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () => _play(),
                                child: Container(
                              padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                    '继续观看 · $_resumeLabel',
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFB5482A),
                                  decoration: TextDecoration.none,
                                    ),
                                ),
                              ),
                            ),
                        ],
                            const SizedBox(height: 14),
                            _WatchStatusBar(
                              value: _watch,
                              onChanged: _setWatch,
                            ),
                            if (movie.director.isNotEmpty ||
                                movie.writer.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              if (movie.director.isNotEmpty)
                                _QuietLine('导演', movie.director),
                              if (movie.writer.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                _QuietLine('编剧', movie.writer),
                              ],
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: _loadDetail,
                                child: const Text(
                                  '加载失败，点击重试',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                                    fontSize: 13,
                                    color: Color(0xFFB54708),
                          decoration: TextDecoration.none,
                        ),
                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: _FadeSlide(
                    animation: _stagger(0.12, 0.45),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _SegmentTabs(
                        index: _tab,
                        labels: const ['详情', '评论'],
                        onChanged: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _tab = i);
                          if (i == 1) _loadComments();
                        },
                      ),
                    ),
                  ),
                ),

                if (_tab == 0) ...[
                  if (episodes.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _FadeSlide(
                        animation: _stagger(0.12, 0.48),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: _ExpandableEpisodeCard(
                            episodes: episodes,
                            selected: _selectedEpisode,
                            intro: _episodeIntro,
                            markVipFromIndex: () {
                              final r = movie.remarks.toUpperCase();
                              if (r.contains('VIP') ||
                                  movie.remarks.contains('会员')) {
                                return 2;
                              }
                              return null;
                            }(),
                            onSelect: (i) {
                              setState(() => _selectedEpisode = i);
                              _play(episodeIndex: i);
                            },
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _FadeSlide(
                      animation: _stagger(0.18, 0.52),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _MorphSynopsisCard(text: synopsis),
                      ),
                    ),
                  ),
                  if (movie.cast.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _FadeSlide(
                        animation: _stagger(0.25, 0.6),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: _ExpandableCastCard(cast: movie.cast),
                        ),
                      ),
                    ),
                ] else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                      child: _CommentPanel(
                        cms: _cms,
                        movieId: movie.id,
                        comments: _comments,
                        loading: _commentsLoading,
                        error: _commentsError,
                        onRefresh: () => _loadComments(force: true),
                        onPosted: () => _loadComments(force: true),
                        onLocalComment: (c) {
                          setState(() {
                            _comments = [c, ..._comments];
                          });
                        },
                      ),
                    ),
                  ),
                ],

                SliverToBoxAdapter(child: SizedBox(height: 36 + bottom)),
              ],
            ),

            Positioned(
              top: top + 8,
              left: 14,
              child: _FadeSlide(
                animation: _stagger(0, 0.3),
                child: _GlassBack(onTap: () => Navigator.of(context).pop()),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// 选中条目飞向下载图标（收纳进「行李箱」）
class _PackFlyOverlay extends StatefulWidget {
  const _PackFlyOverlay({
    required this.start,
    required this.end,
    required this.count,
    required this.onDone,
  });

  final Offset start;
  final Offset end;
  final int count;
  final VoidCallback onDone;

  @override
  State<_PackFlyOverlay> createState() => _PackFlyOverlayState();
}

class _PackFlyOverlayState extends State<_PackFlyOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = Curves.easeInCubic.transform(_ctrl.value);
            return Stack(
              children: [
                for (var i = 0; i < widget.count; i++)
                  Builder(
                    builder: (_) {
                      final spread = (i - (widget.count - 1) / 2) * 28.0;
                      final mid = Offset(
                        widget.start.dx + spread,
                        widget.start.dy - 90 - i * 10.0,
                      );
                      final u = t;
                      final p = Offset(
                        (1 - u) * (1 - u) * widget.start.dx +
                            2 * (1 - u) * u * mid.dx +
                            u * u * widget.end.dx,
                        (1 - u) * (1 - u) * widget.start.dy +
                            2 * (1 - u) * u * mid.dy +
                            u * u * widget.end.dy,
                      );
                      final scale = (1.15 - 0.7 * t).clamp(0.35, 1.15);
                      final opacity = (1.0 - t * 0.05).clamp(0.0, 1.0);
                      return Positioned(
                        left: p.dx - 14,
                        top: p.dy - 14,
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9F0A),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x55000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.download_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StarRatingRow extends StatelessWidget {
  const _StarRatingRow({
    required this.score,
    required this.stars,
    required this.count,
  });

  final double score;
  final double stars;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
                      Text(
          score.toStringAsFixed(1),
                        style: const TextStyle(
                          fontFamily: 'AppSans',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1,
            color: _star,
                          decoration: TextDecoration.none,
                        ),
                      ),
        const SizedBox(width: 10),
        _Stars(value: stars, size: 16),
        const SizedBox(width: 10),
        Text(
          count > 0 ? '$count人评过' : '暂无评分人数',
          style: const TextStyle(
                            fontFamily: 'AppSans',
            fontSize: 12,
            color: _faint,
                            decoration: TextDecoration.none,
                          ),
                        ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.size = 16});
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final left = value - i;
        final IconData icon;
        if (left >= 0.75) {
          icon = CupertinoIcons.star_fill;
        } else if (left >= 0.25) {
          icon = CupertinoIcons.star_lefthalf_fill;
        } else {
          icon = CupertinoIcons.star;
        }
        return Padding(
          padding: EdgeInsets.only(right: i == 4 ? 0 : 2),
          child: Icon(icon, size: size, color: _star),
        );
      }),
    );
  }
}

class _WatchStatusBar extends StatelessWidget {
  const _WatchStatusBar({required this.value, required this.onChanged});
  final MovieWatchStatus value;
  final ValueChanged<MovieWatchStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
        itemCount: MovieWatchStatusX.selectable.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
          final s = MovieWatchStatusX.selectable[i];
          final on = value == s;
          return GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                color: on ? _ink : _soft,
                borderRadius: BorderRadius.circular(17),
                                ),
                                child: Text(
                s.label,
                style: TextStyle(
                                    fontFamily: 'AppSans',
                  fontSize: 13,
                                    fontWeight: FontWeight.w600,
                  color: on ? Colors.white : _muted,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == i ? _ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: index == i ? Colors.white : _muted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: 0.72),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 0.8,
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _FadeSlide extends StatelessWidget {
  const _FadeSlide({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 16),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _FavBtn extends StatelessWidget {
  const _FavBtn({
    required this.onTap,
    this.busy = false,
    this.active = false,
  });
  final VoidCallback onTap;
  final bool busy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFE8EC) : _soft,
          shape: BoxShape.circle,
        ),
        child: busy
            ? const CupertinoActivityIndicator()
            : Icon(
                active ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                size: 20,
                color: active ? const Color(0xFFFF2D55) : _ink,
              ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  const _PlayBtn({required this.onTap, this.loading = false});
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _lime,
          shape: BoxShape.circle,
        ),
        child: loading
            ? const CupertinoActivityIndicator()
            : const Icon(
                CupertinoIcons.play_fill,
                size: 20,
                                    color: Colors.white,
              ),
      ),
    );
  }
}

class _QuietLine extends StatelessWidget {
  const _QuietLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 13,
                                    decoration: TextDecoration.none,
                                  ),
        children: [
          TextSpan(text: '$label  ', style: const TextStyle(color: _faint)),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CastTile extends StatelessWidget {
  const _CastTile({required this.cast, required this.index});
  final MovieCast cast;
  final int index;

  @override
  Widget build(BuildContext context) {
    const greys = [
      Color(0xFF3A3A3C),
      Color(0xFF48484A),
      Color(0xFF636366),
      Color(0xFF2C2C2E),
      Color(0xFF555558),
    ];
    final bg = cast.color == const Color(0xFF8E8E93)
        ? greys[index % greys.length]
        : cast.color;
    final role = cast.role.trim();
    final showRole = role.isNotEmpty && role != '主演';

    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: bg.withValues(alpha: 0.28),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: CastAvatarImage(
              name: cast.name,
              color: bg,
              avatarUrl: cast.avatarUrl,
              size: 54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
            cast.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
              fontSize: 11,
                                  fontWeight: FontWeight.w600,
              color: _ink,
                                  decoration: TextDecoration.none,
                                ),
                              ),
          if (showRole) ...[
            const SizedBox(height: 2),
                              Text(
              role.startsWith('饰') ? role : '饰 $role',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: _ink.withValues(alpha: 0.45),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderExpand extends StatelessWidget {
  const _HeaderExpand({
    required this.title,
    required this.expanded,
    required this.canExpand,
    required this.onToggle,
    this.trailing,
  });

  final String title;
  final bool expanded;
  final bool canExpand;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _MarkTitle(title)),
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 10),
        ],
        if (canExpand)
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  expanded ? '收起' : '展开全部',
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 320),
                  child: const Icon(
                    CupertinoIcons.chevron_down,
                    size: 14,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 简介：右上角展开 + 圆角变形
class _MorphSynopsisCard extends StatefulWidget {
  const _MorphSynopsisCard({required this.text});
  final String text;

  @override
  State<_MorphSynopsisCard> createState() => _MorphSynopsisCardState();
}

class _MorphSynopsisCardState extends State<_MorphSynopsisCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  bool _expanded = false;

  bool get _long => widget.text.length > 72;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_long) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final v = _t.value.clamp(0.0, 1.0);
        final radius = 28.0 - 10.0 * v;
        final padV = 14.0 + 4.0 * v;
        final padH = 16.0 + 2.0 * v;
        final scaleY = 0.98 + 0.02 * v;

        return Transform.scale(
          scaleY: scaleY,
          alignment: Alignment.topCenter,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: Color.lerp(
                    Colors.white.withValues(alpha: 0.72),
                    Colors.white.withValues(alpha: 0.88),
                    v,
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    _HeaderExpand(
                      title: '简介',
                      expanded: _expanded,
                      canExpand: _long,
                      onToggle: _toggle,
                    ),
                    SizedBox(height: 10 + 2 * v),
                    GestureDetector(
                      onTap: _toggle,
                          child: Text(
                        widget.text,
                        maxLines: _expanded || !_long ? null : 3,
                        overflow: _expanded || !_long
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                              fontFamily: 'AppSans',
                          fontSize: 14,
                          height: 1.65,
                          color: _muted,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpandableCastCard extends StatefulWidget {
  const _ExpandableCastCard({required this.cast});
  final List<MovieCast> cast;

  @override
  State<_ExpandableCastCard> createState() => _ExpandableCastCardState();
}

class _ExpandableCastCardState extends State<_ExpandableCastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  bool _expanded = false;

  bool get _canExpand => widget.cast.length > 5;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_canExpand) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final v = _t.value.clamp(0.0, 1.0);
        final radius = 28.0 - 10.0 * v;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 16, 16, 14 + 4 * v),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.72),
                  Colors.white.withValues(alpha: 0.88),
                  v,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderExpand(
                    title: '演员',
                    expanded: _expanded,
                    canExpand: _canExpand,
                    onToggle: _toggle,
                  ),
                  const SizedBox(height: 14),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _expanded
                        ? LayoutBuilder(
                            builder: (context, c) {
                              const cols = 4;
                              const gap = 10.0;
                              final tileW =
                                  (c.maxWidth - gap * (cols - 1)) / cols;
                              return Wrap(
                                spacing: gap,
                                runSpacing: 14,
                                children: [
                                  for (var i = 0;
                                      i < widget.cast.length;
                                      i++)
                                    SizedBox(
                                      width: tileW,
                                      child: _CastTile(
                                        cast: widget.cast[i],
                                        index: i,
                                      ),
                                    ),
                                ],
                              );
                            },
                          )
                        : SizedBox(
                            height: 108,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: widget.cast.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (context, i) => SizedBox(
                                width: 64,
                                child: _CastTile(
                                  cast: widget.cast[i],
                                  index: i,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpandableEpisodeCard extends StatefulWidget {
  const _ExpandableEpisodeCard({
    required this.episodes,
    required this.selected,
    required this.onSelect,
    this.intro,
    this.markVipFromIndex,
  });

  final List<MoviePlayEpisode> episodes;
  final int selected;
  final ValueChanged<int> onSelect;
  final String? intro;
  final int? markVipFromIndex;

  @override
  State<_ExpandableEpisodeCard> createState() => _ExpandableEpisodeCardState();
}

class _ExpandableEpisodeCardState extends State<_ExpandableEpisodeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  final _hScroll = ScrollController();
  bool _expanded = false;
  static const _batchSize = 50;
  late int _batch;

  bool get _canExpand => widget.episodes.length > 8;

  @override
  void initState() {
    super.initState();
    _batch = widget.selected ~/ _batchSize;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant _ExpandableEpisodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.episodes.length != widget.episodes.length) {
      final next = widget.selected ~/ _batchSize;
      if (next != _batch) _batch = next;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_canExpand) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _scrollToSelected() {
    if (_expanded || !_hScroll.hasClients) return;
    final i = widget.selected.clamp(0, widget.episodes.length - 1);
    var offset = 0.0;
    for (var k = 0; k < i; k++) {
      final label = MangoEpisodeRow.chipLabel(
        widget.episodes[k].name,
        k,
        total: widget.episodes.length,
      );
      offset += _chipW(label) + MangoWatchStyle.chipGap;
    }
    final max = _hScroll.position.maxScrollExtent;
    final target = (offset - 24).clamp(0.0, max);
    _hScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  double _chipW(String label) {
    if (label.length <= 2) return MangoWatchStyle.chipSize;
    return MangoWatchStyle.chipSize + (label.length - 2) * 10.0;
  }

  String? _badge(int i) {
    final ep = widget.episodes[i];
    if (MangoEpisodeChip.isVipLabel(ep.name) ||
        (widget.markVipFromIndex != null && i >= widget.markVipFromIndex!)) {
      return 'VIP';
    }
    if (i == widget.episodes.length - 1 && widget.episodes.length > 1) {
      return '新';
    }
    if (ep.name.contains('预告') || ep.name.toUpperCase().contains('PREVIEW')) {
      return '预';
    }
    return null;
  }

  Widget _chip(int i, {bool expand = false}) {
    final label = MangoEpisodeRow.chipLabel(
      widget.episodes[i].name,
      i,
      total: widget.episodes.length,
    );
    return MangoEpisodeChip(
      label: label,
      selected: i == widget.selected,
      expand: expand,
      cornerBadge: _badge(i),
      width: expand ? null : _chipW(label),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onSelect(i);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tip = widget.intro?.trim();
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final v = _t.value.clamp(0.0, 1.0);
        final radius = 28.0 - 10.0 * v;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.72),
                  Colors.white.withValues(alpha: 0.88),
                  v,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderExpand(
                    title: '选集',
                    expanded: _expanded,
                    canExpand: _canExpand,
                    onToggle: _toggle,
                    trailing: Text(
                      '${widget.episodes.length} 集',
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                        color: _faint,
                            decoration: TextDecoration.none,
                          ),
                        ),
                  ),
                  if (tip != null && tip.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      tip,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFF888888),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _expanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                              if (widget.episodes.length > _batchSize)
                                MangoEpisodeBatchBar(
                                  total: widget.episodes.length,
                                  batchSize: _batchSize,
                                  batchIndex: _batch,
                                  onChanged: (i) =>
                                      setState(() => _batch = i),
                                ),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: () {
                                  final start = _batch * _batchSize;
                                  final end = (start + _batchSize)
                                      .clamp(0, widget.episodes.length);
                                  return end - start;
                                }(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 5,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 1.05,
                                ),
                                itemBuilder: (_, local) {
                                  final i = _batch * _batchSize + local;
                                  return _chip(i, expand: true);
                                },
                              ),
                            ],
                          )
                        : SizedBox(
                            height: MangoWatchStyle.chipSize + 10,
                            child: ListView.separated(
                              controller: _hScroll,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(top: 6, right: 6),
                              physics: const BouncingScrollPhysics(),
                              itemCount: widget.episodes.length,
                              separatorBuilder: (_, _) => const SizedBox(
                                width: MangoWatchStyle.chipGap,
                              ),
                              itemBuilder: (context, i) => _chip(i),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommentPanel extends StatefulWidget {
  const _CommentPanel({
    required this.cms,
    required this.movieId,
    required this.comments,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onPosted,
    this.onLocalComment,
    this.onClose,
  });

  final MacCmsApi cms;
  final String movieId;
  final List<MovieComment> comments;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onPosted;
  final ValueChanged<MovieComment>? onLocalComment;
  final VoidCallback? onClose;

  @override
  State<_CommentPanel> createState() => _CommentPanelState();
}

class _CommentPanelState extends State<_CommentPanel> {
  /// false=最新，true=最热
  bool _sortHot = false;
  bool _composeOpen = false;
  String? _replyHint;

  final _content = TextEditingController();
  final _verify = TextEditingController();
  final _focus = FocusNode();
  Uint8List? _captcha;
  bool _posting = false;
  bool _captchaLoading = false;

  @override
  void dispose() {
    _content.dispose();
    _verify.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<MovieComment> get _sorted {
    final list = [...widget.comments];
    if (_sortHot) {
      list.sort((a, b) {
        final d = b.up.compareTo(a.up);
        if (d != 0) return d;
        return b.down.compareTo(a.down);
      });
    }
    return list;
  }

  Future<void> _toggleCompose({String? replyTo}) async {
    HapticFeedback.selectionClick();
    if (!CmsAuthController.instance.isLoggedIn) {
      DialogX.showWarning('请先登录后再评论');
      return;
    }
    setState(() {
      if (replyTo != null) {
        _composeOpen = true;
        _replyHint = replyTo;
      } else {
        _composeOpen = !_composeOpen;
        if (!_composeOpen) _replyHint = null;
      }
    });
    if (_composeOpen) {
      if (_captcha == null && !_captchaLoading) {
        unawaited(_reloadCaptcha());
      }
      // 不自动弹键盘，由用户点输入框再出
    } else {
      _focus.unfocus();
    }
  }

  Future<void> _reloadCaptcha() async {
    setState(() => _captchaLoading = true);
    try {
      widget.cms.adoptCmsSessionCookie(
        CmsAuthController.instance.api.sessionCookie,
      );
      final bytes = await widget.cms.fetchCommentCaptcha();
      if (!mounted) return;
      setState(() {
        _captcha = bytes;
        _captchaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _captcha = null;
        _captchaLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_posting) return;
    final text = _content.text.trim();
    final code = _verify.text.trim();
    if (text.isEmpty) {
      DialogX.showWarning('请输入评论内容');
      return;
    }
    if (code.isEmpty) {
      DialogX.showWarning('请输入验证码');
      return;
    }

    setState(() => _posting = true);
    DialogX.showWait('发表中…');
    try {
      widget.cms.adoptCmsSessionCookie(
        CmsAuthController.instance.api.sessionCookie,
      );
      final body = (_replyHint != null && _replyHint!.isNotEmpty)
          ? '回复 @$_replyHint：$text'
          : text;
      await widget.cms.postComment(
        vodId: widget.movieId,
        content: body,
        verify: code,
      );
      DialogX.showSuccess('评论已提交');
      if (!mounted) return;
      final optimistic = MovieComment(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        userName: () {
          final u = CmsAuthController.instance.user;
          if (u == null) return '我';
          final nick = u.nickName.trim();
          if (nick.isNotEmpty) return nick;
          final name = u.userName.trim();
          return name.isEmpty ? '我' : name;
        }(),
        content: body,
        timeText: '刚刚',
        timeMs: DateTime.now().millisecondsSinceEpoch,
        avatarUrl: CmsAuthController.instance.user?.avatarUrl,
      );
      _content.clear();
      _verify.clear();
      _focus.unfocus();
      setState(() {
        _composeOpen = false;
        _replyHint = null;
        _captcha = null;
      });
      widget.onLocalComment?.call(optimistic);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await widget.onPosted().timeout(const Duration(seconds: 10));
      } catch (_) {}
    } catch (e) {
      DialogX.showError('$e');
      await _reloadCaptcha();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _digg(MovieComment c, String type) async {
    HapticFeedback.lightImpact();
    try {
      widget.cms.adoptCmsSessionCookie(
        CmsAuthController.instance.api.sessionCookie,
      );
      await widget.cms.diggComment(commentId: c.id, type: type);
      if (!mounted) return;
      await widget.onRefresh();
      DialogX.showSuccess(type == 'up' ? '已点赞' : '已反对');
    } catch (e) {
      DialogX.showError('$e');
    }
  }

  Widget _sortTextTab(String label, bool hot) {
    final on = _sortHot == hot;
    return GestureDetector(
                            onTap: () {
        if (_sortHot == hot) return;
                              HapticFeedback.selectionClick();
        setState(() => _sortHot = hot);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 14,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              color: on ? _lime : _faint,
              decoration: TextDecoration.none,
            ),
          ),
          SizedBox(height: 4),
          AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
            width: on ? 16 : 0,
            height: 3,
                              decoration: BoxDecoration(
              color: _lime,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composeEditor() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_replyHint != null) ...[
            Row(
              children: [
                const Icon(
                  CupertinoIcons.reply,
                  size: 14,
                  color: _muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                              child: Text(
                    '回复 @$_replyHint',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                                  fontFamily: 'AppSans',
                      fontSize: 12,
                                  fontWeight: FontWeight.w600,
                      color: _muted,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
              ],
            ),
            SizedBox(height: 10),
          ],
          TextField(
            controller: _content,
            focusNode: _focus,
            autofocus: false,
            maxLines: 4,
            minLines: 3,
            maxLength: 255,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 15,
              height: 1.45,
              color: _ink,
            ),
            decoration: InputDecoration(
              hintText: '写下你的观后感…',
              hintStyle: const TextStyle(
                color: _faint,
                fontFamily: 'AppSans',
                fontSize: 15,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFEEEEF0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _lime, width: 1.2),
              ),
              contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              counterStyle: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 11,
                color: _faint,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _verify,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    color: _ink,
                  ),
                  decoration: InputDecoration(
                    hintText: '验证码',
                    hintStyle: const TextStyle(
                      color: _faint,
                      fontFamily: 'AppSans',
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(
                      CupertinoIcons.lock,
                      size: 16,
                      color: _faint,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEEEEF0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _lime, width: 1.2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _reloadCaptcha,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
              child: Container(
                    width: 108,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFEEEEF0)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _captchaLoading
                        ? Center(child: CupertinoActivityIndicator())
                        : _captcha == null
                            ? Center(
                                child: Text(
                                  '获取验证码',
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 12,
                                    color: _faint,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              )
                            : Image.memory(_captcha!, fit: BoxFit.cover),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: GestureDetector(
              onTap: _posting ? null : _submit,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _lime,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33C8F000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: _posting
                    ? const CupertinoActivityIndicator()
                    : const Text(
                        '发表评论',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          decoration: TextDecoration.none,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final comments = _sorted;
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '评论',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onRefresh,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: _faint,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _toggleCompose(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _composeOpen ? '收起' : '写评论',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _composeOpen ? _ink : _lime,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    CupertinoIcons.xmark,
                      size: 18,
                    color: _faint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _sortTextTab('最新', false),
              const SizedBox(width: 18),
              _sortTextTab('最热', true),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _composeOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _composeEditor(),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 10),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (widget.error != null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: GestureDetector(
                onTap: widget.onRefresh,
                child: Text(
                  '${widget.error}\n点击重试',
                  textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFFB54708),
                        decoration: TextDecoration.none,
                      ),
                    ),
              ),
            )
          else if (comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  '暂无评论',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    color: _faint,
                    decoration: TextDecoration.none,
              ),
            ),
          ),
            )
          else
            for (final c in comments) ...[
              _CommentTile(
                comment: c,
                onUp: () => _digg(c, 'up'),
                onDown: () => _digg(c, 'down'),
                onReply: () => _toggleCompose(
                  replyTo: c.userName.trim().isEmpty
                      ? '访客'
                      : c.userName.trim(),
                ),
              ),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onUp,
    required this.onDown,
    required this.onReply,
  });

  final MovieComment comment;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onReply;

  static String _cleanBody(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(
      RegExp(
        r'(?:^|[\s\|·•]*)(?:举报|支持|赞成|反对|回复)\s*[\(（]?\s*\d*\s*[\)）]?',
      ),
      ' ',
    );
    return s.replaceAll(RegExp(r'[\s\|·•]+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final name =
        comment.userName.trim().isEmpty ? '访客' : comment.userName.trim();
    final time = formatCommentTime(comment.timeText, timeMs: comment.timeMs);
    final body = _cleanBody(comment.content);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: _soft,
          child: (comment.avatarUrl ?? '').isEmpty
              ? Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                  ),
                )
              : ClipOval(
                  child: Image.network(
                    comment.avatarUrl!,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stackTrace) => Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF333333),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      time,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: _faint,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  _CommentAction(
                    icon: Icons.thumb_up_alt_outlined,
                    count: comment.up,
                    onTap: onUp,
                  ),
                  const SizedBox(width: 12),
                  _CommentAction(
                    icon: Icons.thumb_down_alt_outlined,
                    count: comment.down,
                    onTap: onDown,
                  ),
                  const SizedBox(width: 12),
                  _CommentAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    count: comment.replyCount,
                    onTap: onReply,
                    hideZero: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 统一尺寸的加粗线框图标 + 右侧数量
class _CommentAction extends StatelessWidget {
  const _CommentAction({
    required this.icon,
    required this.count,
    required this.onTap,
    this.hideZero = false,
  });

  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final bool hideZero;

  @override
  Widget build(BuildContext context) {
    final showCount = count > 0 || !hideZero;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF666666),
              weight: 600,
              fill: 0,
              grade: 0,
              opticalSize: 24,
            ),
          ),
          if (showCount) ...[
            const SizedBox(width: 3),
          Text(
              '$count',
              style: const TextStyle(
              fontFamily: 'AppSans',
                fontSize: 12,
              fontWeight: FontWeight.w600,
                color: Color(0xFF666666),
              decoration: TextDecoration.none,
            ),
          ),
          ],
        ],
      ),
    );
  }
}

class _MarkTitle extends StatelessWidget {
  const _MarkTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    // 不用 Stack：ScrollView 内无界高度会触发 size.isFinite 断言
    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: _ink,
              decoration: TextDecoration.none,
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -6),
            child: Container(
              width: 32,
              height: 6,
              decoration: BoxDecoration(
                color: _lime.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBack extends StatelessWidget {
  const _GlassBack({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: Container(
            width: 36,
            height: 36,
        alignment: Alignment.center,
            color: const Color(0x44FFFFFF),
            child: const Icon(
              CupertinoIcons.back,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
