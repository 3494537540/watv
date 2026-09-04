import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import 'app_onboarding.dart';
import 'media_placeholder.dart';

/// 首页顶区：
/// - Banner 铺满背景（含状态栏）
/// - 搜索 / Tab 浮在图上（无品牌字）
/// - 底部：左标题介绍 / 右进度点
class HomeImmersiveHeader extends StatefulWidget {
  const HomeImmersiveHeader({
    super.key,
    required this.movies,
    required this.tabs,
    required this.tabIndex,
    required this.searchHints,
    required this.onTabChanged,
    required this.onSearchTap,
    this.onBannerTap,
    this.onInboxTap,
    this.onHistoryTap,
    this.onRankTap,
    this.onPageChanged,
    this.brandName = '哇TV',
    this.showBackdrop = true,
    this.showTopChrome = true,
    this.pageIndex,
  });

  final List<Movie> movies;
  final List<String> tabs;
  final int tabIndex;
  final List<String> searchHints;
  final String brandName;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onSearchTap;
  final ValueChanged<Movie>? onBannerTap;
  final VoidCallback? onInboxTap;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onRankTap;
  final ValueChanged<int>? onPageChanged;
  /// false：不画海报（由外层固定底图承担）
  final bool showBackdrop;
  /// false：不画搜索/Tab（由 [HomeStickyTopBar] 固定在页面顶层）
  final bool showTopChrome;
  /// 外控页码（[showBackdrop] 为 false 时用）
  final int? pageIndex;

  /// 搜索 + Tab 区域高度（不含状态栏）
  static const double chromeBodyH = 76;

  /// 与 [build] 内高度公式一致
  static double heightOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bannerBody = mq.size.width * 0.68;
    return mq.padding.top + chromeBodyH + bannerBody;
  }

  static double stickyChromeHeight(BuildContext context) =>
      MediaQuery.paddingOf(context).top + chromeBodyH;

  @override
  State<HomeImmersiveHeader> createState() => _HomeImmersiveHeaderState();
}

class _HomeImmersiveHeaderState extends State<HomeImmersiveHeader> {
  late final PageController _controller;
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _restartAutoPlay();
  }

  @override
  void didUpdateWidget(covariant HomeImmersiveHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.movies.length != widget.movies.length ||
        (oldWidget.movies.isNotEmpty &&
            widget.movies.isNotEmpty &&
            oldWidget.movies.first.id != widget.movies.first.id) ||
        (oldWidget.movies.isEmpty != widget.movies.isEmpty);
    if (!changed) return;
    _page = 0;
    if (_controller.hasClients) {
      _controller.jumpToPage(0);
    }
    widget.onPageChanged?.call(0);
    _restartAutoPlay();
  }

  void _restartAutoPlay() {
    _timer?.cancel();
    if (widget.movies.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.movies.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _rankLabel {
    final tab = widget.tabs.isEmpty
        ? '推荐'
        : widget.tabs[widget.tabIndex.clamp(0, widget.tabs.length - 1)];
    return switch (tab) {
      '电影' => '电影榜',
      '电视剧' => '剧集榜',
      '综艺' => '综艺榜',
      '动漫' => '动漫榜',
      '资讯' => '资讯榜',
      _ => '热播榜',
    };
  }

  String _typeLabel(Movie m) {
    final s = m.subtitle.trim();
    if (s.isNotEmpty) return s;
    if (m.genres.isNotEmpty) return m.genres.first;
    return '影视';
  }

  Color _typeColor(String label) {
    if (label.contains('剧')) return const Color(0xFF2BB673);
    if (label.contains('电影') || label.contains('动作') || label.contains('喜剧')) {
      return const Color(0xFFE6A23C);
    }
    if (label.contains('综')) return const Color(0xFF7B61FF);
    if (label.contains('漫') || label.contains('番')) {
      return const Color(0xFFE85D8A);
    }
    return const Color(0xFF2BB673);
  }

  void _swipeBanner(DragEndDetails d) {
    final movies = widget.movies;
    if (!_controller.hasClients || movies.length < 2) return;
    final v = d.primaryVelocity ?? 0;
    if (v < -120 && _page < movies.length - 1) {
      unawaited(
        _controller.nextPage(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    } else if (v > 120 && _page > 0) {
      unawaited(
        _controller.previousPage(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// 禁用 PageView 自带滚动，避免吃掉纵向下拉/列表滑动；左右滑用手势切页
  Widget _bannerPager({required bool paintSlides}) {
    final movies = widget.movies;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: _swipeBanner,
      child: PageView.builder(
        physics: const NeverScrollableScrollPhysics(),
        controller: _controller,
        itemCount: movies.length,
        onPageChanged: (i) {
          HapticFeedback.selectionClick();
          setState(() => _page = i);
          widget.onPageChanged?.call(i);
        },
        itemBuilder: (context, i) {
          return GestureDetector(
            onTap: () => widget.onBannerTap?.call(movies[i]),
            behavior: HitTestBehavior.opaque,
            child: paintSlides
                ? _BannerSlide(movie: movies[i])
                : const ColoredBox(color: Colors.transparent),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    // 顶栏：仅搜索 + Tab，更矮
    const chromeH = HomeImmersiveHeader.chromeBodyH;
    // Banner 缩短，避免占满大半屏
    final bannerBody = mq.size.width * 0.68;
    final totalH = top + chromeH + bannerBody;

    final movies = widget.movies;
    final page = widget.pageIndex ?? _page;
    final current =
        movies.isEmpty ? null : movies[page.clamp(0, movies.length - 1)];

    return SizedBox(
      height: totalH,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.showBackdrop) ...[
            if (movies.isNotEmpty)
              _bannerPager(paintSlides: true)
            else
              const MediaPlaceholder(kind: MediaPlaceholderKind.film),
          ] else if (movies.isNotEmpty)
            // Invisible pager: swipe here, poster is painted by pinned layer (profile-style)
            _bannerPager(paintSlides: false),

          // 仅底部轻渐变保标题可读，顶部不再压暗遮罩
          if (movies.isNotEmpty || widget.showBackdrop)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 96,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 浮层：搜索 + Tab（可由页面顶层 HomeStickyTopBar 固定接管）
          if (widget.showTopChrome)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: HomeStickyTopBar(
                tabs: widget.tabs,
                tabIndex: widget.tabIndex,
                searchHints: widget.searchHints,
                onTabChanged: widget.onTabChanged,
                onSearchTap: widget.onSearchTap,
                onRankTap: widget.onRankTap,
                onHistoryTap: widget.onHistoryTap,
                onInboxTap: widget.onInboxTap,
              ),
            ),

          // 底部：左标题介绍 / 右进度点
          if (current != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onBannerTap?.call(current),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BannerMetaBadges(
                            rank: page + 1,
                            rankLabel: _rankLabel,
                            typeLabel: _typeLabel(current),
                            typeColor: _typeColor(_typeLabel(current)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: 0.6,
                              color: Colors.white,
                              decoration: TextDecoration.none,
                              shadows: [
                                Shadow(
                                  color: Color(0x99000000),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            current.tagline.isNotEmpty
                                ? current.tagline
                                : current.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              height: 1.3,
                              color: Colors.white.withValues(alpha: 0.82),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (movies.length > 1) ...[
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < movies.length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              margin: const EdgeInsets.only(left: 4),
                              width: i == page ? 14 : 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: i == page
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
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

/// 轮播角标：TOP n 热播榜 + 分类
class _BannerMetaBadges extends StatelessWidget {
  const _BannerMetaBadges({
    required this.rank,
    required this.rankLabel,
    required this.typeLabel,
    required this.typeColor,
  });

  final int rank;
  final String rankLabel;
  final String typeLabel;
  final Color typeColor;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(3));
    const textStyle = TextStyle(
      fontFamily: 'AppSans',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1.1,
      color: Colors.white,
      decoration: TextDecoration.none,
    );

    return Row(
      children: [
        ClipRRect(
          borderRadius: radius,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: const Color(0xFFFF7A1A),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text('TOP $rank', style: textStyle),
              ),
              Container(
                color: const Color(0xFF3A3A3A),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(rankLabel, style: textStyle),
              ),
            ],
          ),
        ),
        if (typeLabel.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: typeColor,
              borderRadius: radius,
            ),
            child: Text(typeLabel, style: textStyle),
          ),
        ],
      ],
    );
  }
}

/// 单页 Banner：仅海报铺底（标题/进度在外层统一布局）
/// 首页固定顶栏：搜索 + 热榜/历史 + 分类 Tab
/// [lightProgress] 0=沉浸透明（带固定压暗遮罩），1=白底
class HomeStickyTopBar extends StatelessWidget {
  const HomeStickyTopBar({
    super.key,
    required this.tabs,
    required this.tabIndex,
    required this.searchHints,
    required this.onTabChanged,
    required this.onSearchTap,
    this.lightProgress = 0,
    this.onRankTap,
    this.onHistoryTap,
    this.onInboxTap,
    this.inboxBadge = 0,
  });

  final List<String> tabs;
  final int tabIndex;
  final List<String> searchHints;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onSearchTap;
  final double lightProgress;
  final VoidCallback? onRankTap;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onInboxTap;
  final int inboxBadge;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final t = lightProgress.clamp(0.0, 1.0);
    final h = top + HomeImmersiveHeader.chromeBodyH;
    final bg = Color.lerp(Colors.transparent, Colors.white, t)!;
    final scrimOpacity = (1.0 - t).clamp(0.0, 1.0);
    final blurSigma = 14.0 * (1.0 - t);

    final searchFill = Color.lerp(
      Colors.black.withValues(alpha: 0.38),
      const Color(0xFFF2F3F5),
      t,
    )!;
    final searchFg = Color.lerp(
      Colors.white.withValues(alpha: 0.78),
      const Color(0xFF8E8E93),
      t,
    )!;
    final searchBorder = Color.lerp(
      Colors.white.withValues(alpha: 0.22),
      const Color(0xFFE5E5EA),
      t,
    )!;
    final iconBtnBg = Color.lerp(
      Colors.black.withValues(alpha: 0.32),
      const Color(0xFFF2F3F5),
      t,
    )!;
    final iconBtnFg = Color.lerp(
      const Color(0xFFD0D0D5),
      const Color(0xFF8E8E93),
      t,
    )!;
    final iconBtnBorder = Color.lerp(
      Colors.white.withValues(alpha: 0.18),
      const Color(0xFFE5E5EA),
      t,
    )!;

    return SizedBox(
      height: h,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (scrimOpacity > 0.01)
            IgnorePointer(
              child: Opacity(
                opacity: scrimOpacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.58),
                        Colors.black.withValues(alpha: 0.32),
                        Colors.black.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ColoredBox(color: bg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: top + 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
                child: TourTarget(
                  id: 'tour_search',
                  child: SizedBox(
                  height: 34,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onSearchTap,
                          behavior: HitTestBehavior.opaque,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(17),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: blurSigma < 0.5 ? 0.01 : blurSigma,
                                sigmaY: blurSigma < 0.5 ? 0.01 : blurSigma,
                              ),
                              child: Container(
                                height: 34,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: searchFill,
                                  borderRadius: BorderRadius.circular(17),
                                  border: Border.all(color: searchBorder),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.search,
                                      size: 15,
                                      color: searchFg,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: _HotSearchHintTicker(
                                          hints: searchHints,
                                          color: searchFg,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ChromePillButton(
                        icon: CupertinoIcons.flame_fill,
                        label: '热榜',
                        accent: const Color(0xFFFF6A3D),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onRankTap?.call();
                        },
                      ),
                      const SizedBox(width: 8),
                      _ChromeIconButton(
                        icon: CupertinoIcons.time,
                        bg: iconBtnBg,
                        fg: iconBtnFg,
                        border: iconBtnBorder,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onHistoryTap?.call();
                        },
                      ),
                      const SizedBox(width: 8),
                      _ChromeIconButton(
                        icon: CupertinoIcons.tray,
                        bg: iconBtnBg,
                        fg: iconBtnFg,
                        border: iconBtnBorder,
                        badge: inboxBadge,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onInboxTap?.call();
                        },
                      ),
                    ],
                  ),
                ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: TourTarget(
                  id: 'tour_tabs',
                  child: _OverlayTabs(
                    tabs: tabs,
                    index: tabIndex,
                    lightProgress: t,
                    onChanged: onTabChanged,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

/// 首页固定轮播底图：列表下滑时海报不动，由滚动层盖住
class HomePinnedBannerLayer extends StatelessWidget {
  const HomePinnedBannerLayer({
    super.key,
    required this.movies,
    required this.page,
  });

  final List<Movie> movies;
  final int page;

  @override
  Widget build(BuildContext context) {
    final h = HomeImmersiveHeader.heightOf(context);
    final has = movies.isNotEmpty;
    final i = has ? page.clamp(0, movies.length - 1) : 0;
    return SizedBox(
      height: h,
      width: double.infinity,
      child: has
          ? _BannerSlide(movie: movies[i])
          : const ColoredBox(color: Color(0xFF1C1C1E)),
    );
  }
}

class _BannerSlide extends StatelessWidget {
  const _BannerSlide({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    return _CoverBackdrop(coverUrl: movie.bannerUrl);
  }
}

/// 海报背景：优先真实封面图铺满顶部，失败则占位图
class HomeCoverBackdrop extends StatelessWidget {
  const HomeCoverBackdrop({super.key, this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const MediaPlaceholder(kind: MediaPlaceholderKind.film),
          Image.network(
            url,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.15),
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) =>
                const MediaPlaceholder(kind: MediaPlaceholderKind.film),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Stack(
                fit: StackFit.expand,
                children: [
                  const MediaPlaceholder(kind: MediaPlaceholderKind.film),
                  Opacity(
                    opacity: progress.expectedTotalBytes != null
                        ? (progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!)
                            .clamp(0.2, 1.0)
                        : 0.4,
                    child: child,
                  ),
                ],
              );
            },
          ),
        ],
      );
    }
    return const MediaPlaceholder(kind: MediaPlaceholderKind.film);
  }
}

/// 海报背景：优先真实封面图铺满顶部，失败则占位图
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return HomeCoverBackdrop(coverUrl: coverUrl);
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.onTap,
    required this.bg,
    required this.fg,
    required this.border,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  final Color border;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: border),
                ),
                child: Icon(icon, size: 17, color: fg),
              ),
            ),
            if (badge > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
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
      ),
    );
  }
}

/// 热搜名轮播（搜索框占位）
class _HotSearchHintTicker extends StatefulWidget {
  const _HotSearchHintTicker({
    required this.hints,
    required this.color,
  });

  final List<String> hints;
  final Color color;

  @override
  State<_HotSearchHintTicker> createState() => _HotSearchHintTickerState();
}

class _HotSearchHintTickerState extends State<_HotSearchHintTicker> {
  Timer? _timer;
  int _index = 0;

  List<String> get _pool {
    final raw = [
      for (final h in widget.hints)
        if (h.trim().isNotEmpty) h.trim(),
    ];
    if (raw.isEmpty) return const ['搜索影片、演员'];
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant _HotSearchHintTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hints.join('|') != widget.hints.join('|')) {
      _index = 0;
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (_pool.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _pool.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pool = _pool;
    final text = pool[_index.clamp(0, pool.length - 1)];
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.55),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Text(
          text,
          key: ValueKey(text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            color: widget.color,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// 搜索旁强调胶囊（热榜）
class _ChromePillButton extends StatelessWidget {
  const _ChromePillButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayTabs extends StatelessWidget {
  const _OverlayTabs({
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.lightProgress = 0,
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final double lightProgress;

  @override
  Widget build(BuildContext context) {
    final t = lightProgress.clamp(0.0, 1.0);
    final activeColor =
        Color.lerp(Colors.white, const Color(0xFF1A1A1A), t)!;
    final idleColor = Color.lerp(
      Colors.white.withValues(alpha: 0.88),
      const Color(0xFF8E8E93),
      t,
    )!;
    final indicator = Color.lerp(Colors.white, AppColors.brand, t)!;
    final shadowAlpha = (1.0 - t).clamp(0.0, 1.0);

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        physics: const BouncingScrollPhysics(),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final active = i == index;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  tabs[i],
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: active ? 16 : 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? activeColor : idleColor,
                    height: 1.1,
                    decoration: TextDecoration.none,
                    shadows: shadowAlpha < 0.05
                        ? null
                        : [
                            Shadow(
                              color: Color.fromRGBO(0, 0, 0, 0.8 * shadowAlpha),
                              blurRadius: 8,
                              offset: const Offset(0, 1),
                            ),
                          ],
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: active ? 16 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: indicator,
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
}

/// 下方五宫格快捷入口
class HomeQuickEntry {
  const HomeQuickEntry({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

class HomeQuickEntries extends StatelessWidget {
  const HomeQuickEntries({
    super.key,
    required this.items,
    this.onTap,
  });

  final List<HomeQuickEntry> items;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap?.call(i);
                },
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    SizedBox(
                      height: 44,
                      child: Icon(
                        items[i].icon,
                        size: 32,
                        color: items[i].color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF333333),
                        decoration: TextDecoration.none,
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

/// 首页筛选栏：全部 / 最新 + 底部「筛选」完整类型
class HomeGenreFilterBar extends StatelessWidget {
  const HomeGenreFilterBar({
    super.key,
    required this.quickTags,
    required this.selected,
    required this.onSelected,
    required this.onOpenSheet,
  });

  final List<MacCmsGenreTag> quickTags;
  final MacCmsGenreTag selected;
  final ValueChanged<MacCmsGenreTag> onSelected;
  final VoidCallback onOpenSheet;

  bool get _isSheetSelection =>
      !quickTags.any((t) => t.sameAs(selected));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
        children: [
          for (final tag in quickTags) ...[
            _GenreChip(
              label: tag.label,
              selected: tag.sameAs(selected),
              onTap: () => onSelected(tag),
            ),
            const SizedBox(width: 10),
          ],
          if (_isSheetSelection) ...[
            _GenreChip(
              label: selected.label,
              selected: true,
              onTap: () => onSelected(selected),
            ),
            SizedBox(width: 10),
          ],
          _GenreChip(
            label: '筛选',
            selected: false,
            outlined: true,
            trailing: Icons.keyboard_arrow_down_rounded,
            onTap: onOpenSheet,
          ),
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.outlined = false,
    this.trailing,
  });

  final String label;
  final bool selected;
  final bool outlined;
  final IconData? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.brand
        : outlined
            ? Colors.white
            : const Color(0xFFF2F3F5);
    final fg = selected ? Colors.white : const Color(0xFF555555);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.fromLTRB(12, 5, trailing != null ? 8 : 12, 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: outlined
              ? Border.all(color: const Color(0xFFE5E7EB))
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
                decoration: TextDecoration.none,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 2),
              Icon(trailing, size: 18, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

/// 底部筛选面板：完整类型网格
Future<MacCmsGenreTag?> showHomeGenreFilterSheet({
  required BuildContext context,
  required List<MacCmsFilterGroup> groups,
  required MacCmsGenreTag selected,
}) {
  return showModalBottomSheet<MacCmsGenreTag>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return _HomeGenreFilterSheet(groups: groups, selected: selected);
    },
  );
}

class _HomeGenreFilterSheet extends StatelessWidget {
  const _HomeGenreFilterSheet({
    required this.groups,
    required this.selected,
  });

  final List<MacCmsFilterGroup> groups;
  final MacCmsGenreTag selected;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD8D8D8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '扩展筛选',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF181818),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: const Color(0xFF888888),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in groups) ...[
                    if (groups.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 10),
                        child: Text(
                          group.title,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF888888),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final tag in group.tags)
                          _SheetTagChip(
                            label: tag.label,
                            selected: tag.sameAs(selected),
                            onTap: () => Navigator.pop(context, tag),
                          ),
                      ],
                    ),
                    SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTagChip extends StatelessWidget {
  const _SheetTagChip({
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : const Color(0xFFF2F3F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF444444),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// @Deprecated 保留兼容；请用 [HomeGenreFilterBar]
class HomeGenreChips extends StatelessWidget {
  const HomeGenreChips({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final selected = i == index;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                labels[i],
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : const Color(0xFF555555),
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

/// 横图双列卡片（封面 + 标题 + 一句话简介）
class HomeLandscapeCard extends StatelessWidget {
  const HomeLandscapeCard({
    super.key,
    required this.movie,
    this.badge,
    this.badgeColor = const Color(0xFF7B61FF),
    this.onTap,
  });

  final Movie movie;
  final String? badge;
  final Color badgeColor;
  final VoidCallback? onTap;

  String get _caption {
    final blurb = movie.synopsis.trim();
    if (blurb.isNotEmpty && blurb != movie.title) return blurb;
    final remarks = movie.remarks.trim();
    if (remarks.isNotEmpty) return remarks;
    return movie.tagline;
  }

  @override
  Widget build(BuildContext context) {
    final url = movie.coverUrl?.trim() ?? '';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const MediaPlaceholder(kind: MediaPlaceholderKind.image),
                  if (url.isNotEmpty)
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.2),
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const MediaPlaceholder(
                        kind: MediaPlaceholderKind.image,
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const MediaLoadingPlaceholder(
                          kind: MediaPlaceholderKind.image,
                          radius: 8,
                        );
                      },
                    ),
                  if (badge != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.2,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: Color(0xFF181818),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 12,
              height: 1.25,
              color: Color(0xFF999999),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // 绿色 marker 条大致盖住标题前 2～3 个字
    final markerW = (title.length >= 3 ? 3 : title.length) * 17.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  bottom: 1,
                  child: Container(
                    width: markerW.clamp(36, 64),
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: Color(0xFF181818),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Align(
              alignment: Alignment.centerRight,
              child: trailing!,
            ),
        ],
      ),
    );
  }
}

/// 列表 / 宫格：单击切换（灰色图标 + 灰色名称）
class HomeLayoutToggle extends StatelessWidget {
  const HomeLayoutToggle({
    super.key,
    required this.gridMode,
    required this.onChanged,
  });

  final bool gridMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const gray = Color(0xFF8E8E93);
    final label = gridMode ? '列表' : '宫格';
    final icon = gridMode
        ? CupertinoIcons.list_bullet
        : CupertinoIcons.square_grid_2x2;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!gridMode);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: gray),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1,
                  color: gray,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 本周热门列表行：左封面 + 右标题/简介
class HomeMediaListTile extends StatelessWidget {
  const HomeMediaListTile({
    super.key,
    required this.movie,
    this.badge,
    this.badgeColor = const Color(0xFF7B61FF),
    this.onTap,
  });

  final Movie movie;
  final String? badge;
  final Color badgeColor;
  final VoidCallback? onTap;

  String get _caption {
    final blurb = movie.synopsis.trim();
    if (blurb.isNotEmpty && blurb != movie.title) return blurb;
    final remarks = movie.remarks.trim();
    if (remarks.isNotEmpty) return remarks;
    return movie.tagline;
  }

  @override
  Widget build(BuildContext context) {
    final url = movie.coverUrl?.trim() ?? '';
    final meta = [
      if (movie.year > 0) '${movie.year}',
      if (movie.area.trim().isNotEmpty) movie.area.trim(),
      if (movie.remarks.trim().isNotEmpty) movie.remarks.trim(),
    ].join(' · ');

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 118,
                height: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const MediaPlaceholder(kind: MediaPlaceholderKind.image),
                    if (url.isNotEmpty)
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.2),
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const MediaPlaceholder(
                          kind: MediaPlaceholderKind.image,
                        ),
                      ),
                    if (badge != null)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 10,
                              color: Colors.white,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 76,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF181818),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (meta.isNotEmpty)
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
                    const Spacer(),
                    Text(
                      _caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        height: 1.3,
                        color: Color(0xFF8E8E93),
                        decoration: TextDecoration.none,
                      ),
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
