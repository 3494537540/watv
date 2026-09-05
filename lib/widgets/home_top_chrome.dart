import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import 'app_onboarding.dart';
import 'brand_sunlight_text.dart';
import 'figma_loading.dart';
import 'media_placeholder.dart';
import 'movie_watch_menu.dart';

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
    this.onFilterTap,
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
  final VoidCallback? onFilterTap;
  /// false：不画海报（由外层固定底图承担）
  final bool showBackdrop;
  /// false：不画搜索/Tab（由 [HomeStickyTopBar] 固定在页面顶层）
  final bool showTopChrome;
  /// 外控页码（[showBackdrop] 为 false 时用）
  final int? pageIndex;

  /// 搜索 + Tab 区域高度（不含状态栏）
  static const double chromeBodyH = 80;

  /// 顶栏以下可见海报高度（相对屏宽）
  static const double bannerWidthFactor = 0.48;

  /// 与 [build] 内高度公式一致：顶栏占位 + 海报区
  static double heightOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    return stickyChromeHeight(context) +
        mq.size.width * bannerWidthFactor;
  }

  static double stickyChromeHeight(BuildContext context) =>
      MediaQuery.paddingOf(context).top + chromeBodyH;

  @override
  State<HomeImmersiveHeader> createState() => _HomeImmersiveHeaderState();
}

class _HomeImmersiveHeaderState extends State<HomeImmersiveHeader> {
  int _page = 0;
  Timer? _timer;

  int get _effectivePage {
    if (widget.pageIndex != null) return widget.pageIndex!;
    return _page;
  }

  @override
  void initState() {
    super.initState();
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
    widget.onPageChanged?.call(0);
    _restartAutoPlay();
  }

  void _goToPage(int i) {
    final movies = widget.movies;
    if (movies.isEmpty) return;
    final next = i.clamp(0, movies.length - 1);
    if (next == _effectivePage) return;
    HapticFeedback.selectionClick();
    setState(() => _page = next);
    widget.onPageChanged?.call(next);
  }

  void _restartAutoPlay() {
    _timer?.cancel();
    if (widget.movies.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.movies.length < 2) return;
      final cur = _effectivePage;
      _goToPage((cur + 1) % widget.movies.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _swipeBanner(DragEndDetails d) {
    final movies = widget.movies;
    if (movies.length < 2) return;
    final v = d.primaryVelocity ?? 0;
    final cur = _effectivePage;
    if (v < -120 && cur < movies.length - 1) {
      _goToPage(cur + 1);
    } else if (v > 120 && cur > 0) {
      _goToPage(cur - 1);
    }
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
    final area = m.area.trim();
    if (area.isNotEmpty) return area;
    if (m.genres.isNotEmpty) return m.genres.first;
    final s = m.subtitle.trim();
    if (s.isNotEmpty) return s;
    return '影视';
  }

  Color _typeColor(String label) {
    if (label.contains('剧') ||
        label.contains('大陆') ||
        label.contains('国产') ||
        label.contains('内地')) {
      return const Color(0xFF2BB673);
    }
    if (label.contains('电影') ||
        label.contains('动作') ||
        label.contains('喜剧') ||
        label.contains('港') ||
        label.contains('台')) {
      return const Color(0xFFE6A23C);
    }
    if (label.contains('综')) return const Color(0xFF7B61FF);
    if (label.contains('漫') ||
        label.contains('番') ||
        label.contains('日') ||
        label.contains('韩')) {
      return const Color(0xFFE85D8A);
    }
    return const Color(0xFF2BB673);
  }

  @override
  Widget build(BuildContext context) {
    final totalH = HomeImmersiveHeader.heightOf(context);
    final movies = widget.movies;
    final page = _effectivePage.clamp(0, movies.isEmpty ? 0 : movies.length - 1);
    final current =
        movies.isEmpty ? null : movies[page.clamp(0, movies.length - 1)];

    return SizedBox(
      height: totalH,
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _swipeBanner,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 仅在需要时自己画图；固定海报模式不要放任何底色/PageView（会盖住下层图并透白）
            if (widget.showBackdrop) ...[
              const ColoredBox(color: Color(0xFF1C1C1E)),
              if (current != null)
                Positioned.fill(child: _BannerSlide(movie: current))
              else
                const Positioned.fill(child: _BannerSkeleton()),
            ],

            if (current != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 120,
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
                  onFilterTap: widget.onFilterTap,
                ),
              ),

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
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _BannerPageIndicator(
                          count: movies.length,
                          index: page,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 首页固定顶栏：搜索 + 历史/公告 + 分类 Tab
/// [lightProgress] 0=沉浸透明，1=白底顶栏（滚动驱动过渡）
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
    this.onFilterTap,
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
  final VoidCallback? onFilterTap;
  final int inboxBadge;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final t = lightProgress.clamp(0.0, 1.0);
    final h = top + HomeImmersiveHeader.chromeBodyH;
    final dark = AppPalette.isDark(context);
    final solid = AppPalette.page(context);
    final bg = Color.lerp(Colors.transparent, solid, t)!;
    final scrimOpacity = (1.0 - t).clamp(0.0, 1.0);
    final blurSigma = 16.0 * (1.0 - t);
    final barLift = 6.0 * t;

    final searchFill = Color.lerp(
      Colors.black.withValues(alpha: 0.38),
      dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F3F5),
      t,
    )!;
    final searchFg = Color.lerp(
      Colors.white.withValues(alpha: 0.78),
      dark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93),
      t,
    )!;
    final iconBtnFg = Color.lerp(
      Colors.white,
      dark ? AppColors.textDark : const Color(0xFF1C1C1E),
      t,
    )!;
    final iconShadow = (1.0 - t).clamp(0.0, 1.0);

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
          // 白底 + 阴影随滚动渐入，形成顶栏「浮起」感
          DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              boxShadow: t < 0.04
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08 * t),
                        blurRadius: 14 * t,
                        offset: Offset(0, barLift * 0.35),
                      ),
                    ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: top + 4),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: TourTarget(
                  id: 'tour_search',
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      children: [
                        // 左侧品牌字标（持续日照扫光）
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: BrandSunlightText(
                            text: '哇TV',
                            style: TextStyle(
                              fontFamily: 'ZCOOLKuaiLe',
                              fontSize: 22,
                              height: 1,
                              color: Color.lerp(
                                Colors.white,
                                AppColors.brand,
                                t,
                              ),
                              shadows: t > 0.5
                                  ? null
                                  : const [
                                      Shadow(
                                        color: Color(0x66000000),
                                        blurRadius: 8,
                                      ),
                                    ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Transform.translate(
                            offset: Offset(0, (1 - t) * 1.5),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(17),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: blurSigma < 0.5 ? 0.01 : blurSigma,
                                  sigmaY: blurSigma < 0.5 ? 0.01 : blurSigma,
                                ),
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.only(left: 12),
                                  decoration: BoxDecoration(
                                    color: searchFill,
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: onSearchTap,
                                        behavior: HitTestBehavior.opaque,
                                        child: Icon(
                                          CupertinoIcons.search,
                                          size: 15,
                                          color: searchFg,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: onSearchTap,
                                          behavior: HitTestBehavior.opaque,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: _HotSearchHintTicker(
                                              hints: searchHints,
                                              color: searchFg,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // 搜索框内右侧：筛选 → 独立片库页
                                      GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          onFilterTap?.call();
                                        },
                                        behavior: HitTestBehavior.opaque,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            0,
                                            10,
                                            0,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 1,
                                                height: 14,
                                                margin: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                color: searchFg.withValues(
                                                  alpha: 0.35,
                                                ),
                                              ),
                                              Icon(
                                                CupertinoIcons.slider_horizontal_3,
                                                size: 15,
                                                color: searchFg,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                '筛选',
                                                style: TextStyle(
                                                  fontFamily: 'AppSans',
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: searchFg,
                                                  height: 1,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                            ],
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
                        _ChromeIconButton(
                          icon: Icons.history_rounded,
                          fg: iconBtnFg,
                          shadowStrength: iconShadow,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onHistoryTap?.call();
                          },
                        ),
                        const SizedBox(width: 4),
                        _ChromeIconButton(
                          icon: Icons.notifications_rounded,
                          fg: iconBtnFg,
                          shadowStrength: iconShadow,
                          badge: inboxBadge,
                          ringWhenBadged: true,
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
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 2),
                    child: _OverlayTabs(
                      tabs: tabs,
                      index: tabIndex,
                      lightProgress: t,
                      onChanged: onTabChanged,
                    ),
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
    final url = has
        ? (movies[i].bannerUrl ?? movies[i].coverUrl)?.trim() ?? ''
        : '';

    return SizedBox(
      height: h,
      width: double.infinity,
      child: ColoredBox(
        color: const Color(0xFF1C1C1E),
        child: url.isEmpty
            ? const _BannerSkeleton()
            : Image.network(
                url,
                key: ValueKey(url),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const _BannerSkeleton(),
              ),
      ),
    );
  }
}

/// 轮播空态 / 加载：暗底骨架扫光 + 融球
class _BannerSkeleton extends StatelessWidget {
  const _BannerSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color(0xFF2C2C2E)),
        Positioned.fill(
          child: FigmaSkeletonPulse(
            child: ColoredBox(color: Color(0xFF3A3A3C)),
          ),
        ),
        Center(
          child: FigmaMetaballLoader(
            size: 88,
            color: FigmaSkeletonColors.blobOnDark,
            softColor: FigmaSkeletonColors.blobOnDarkSoft,
          ),
        ),
      ],
    );
  }
}

/// 轮播角标：TOP n · 热播榜 + 地区/类型
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

/// 轮播进度：分段条 + 当前段加长高亮，切换更顺
class _BannerPageIndicator extends StatelessWidget {
  const _BannerPageIndicator({
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final n = count.clamp(1, 12);
    final i = index.clamp(0, n - 1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var k = 0; k < n; k++) ...[
            if (k > 0) const SizedBox(width: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: k == i ? 16 : 6,
              height: 3.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: k == i
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.38),
                boxShadow: k == i
                    ? [
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.55),
                          blurRadius: 6,
                          spreadRadius: 0.2,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BannerSlide extends StatelessWidget {
  const _BannerSlide({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    return _CoverBackdrop(coverUrl: movie.bannerUrl ?? movie.coverUrl);
  }
}

/// 海报背景：等比 cover 铺满，不拉伸
class HomeCoverBackdrop extends StatelessWidget {
  const HomeCoverBackdrop({super.key, this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl?.trim() ?? '';
    if (url.isEmpty) return const _BannerSkeleton();
    return ColoredBox(
      color: const Color(0xFF1C1C1E),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _BannerSkeleton(),
      ),
    );
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

class _ChromeIconButton extends StatefulWidget {
  const _ChromeIconButton({
    required this.icon,
    required this.onTap,
    required this.fg,
    this.badge = 0,
    this.shadowStrength = 1,
    this.ringWhenBadged = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color fg;
  final int badge;
  final double shadowStrength;
  /// 有未读角标时左右摇铃
  final bool ringWhenBadged;

  @override
  State<_ChromeIconButton> createState() => _ChromeIconButtonState();
}

class _ChromeIconButtonState extends State<_ChromeIconButton>
    with SingleTickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _ring;

  bool get _shouldRing => widget.ringWhenBadged && widget.badge > 0;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _syncRing();
  }

  @override
  void didUpdateWidget(covariant _ChromeIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.badge != widget.badge ||
        oldWidget.ringWhenBadged != widget.ringWhenBadged) {
      _syncRing();
    }
  }

  void _syncRing() {
    if (_shouldRing) {
      if (!_ring.isAnimating) _ring.repeat();
    } else {
      _ring
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  /// 前段快速左右摆动，后段停顿，循环像铃铛
  double _ringAngle(double t) {
    if (t > 0.42) return 0;
    final local = t / 0.42;
    final swings = local * math.pi * 5;
    final amp = (1.0 - local) * 0.32; // ≈18°
    return math.sin(swings) * amp;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shadowStrength.clamp(0.0, 1.0);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.88 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: 36,
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _ring,
                builder: (context, child) {
                  final angle = _shouldRing ? _ringAngle(_ring.value) : 0.0;
                  return Transform.rotate(
                    angle: angle,
                    alignment: const Alignment(0, -0.85),
                    child: child,
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      widget.icon,
                      size: 25,
                      weight: 700,
                      color: widget.fg.withValues(alpha: 0.35),
                      shadows: s < 0.05
                          ? null
                          : [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.4 * s),
                                blurRadius: 10 * s,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                    Icon(
                      widget.icon,
                      size: 24,
                      weight: 700,
                      color: widget.fg,
                    ),
                  ],
                ),
              ),
              if (widget.badge > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.badge > 99 ? '99+' : '${widget.badge}',
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
    final raw = <String>[];
    final seen = <String>{};
    for (final h in widget.hints) {
      final t = h.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      raw.add(t);
    }
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
    final i = _index % pool.length;
    final text = pool[i];

    // 固定高度 + 左对齐 Stack，避免长短文案切换时先居中再跳回左边
    return SizedBox(
      height: 18,
      width: double.infinity,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              fit: StackFit.expand,
              children: [
                ...previousChildren,
                ?currentChild,
              ],
            );
          },
          transitionBuilder: (child, anim) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.85),
              end: Offset.zero,
            ).animate(anim);
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: slide,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
              ),
            );
          },
          child: Text(
            text,
            key: ValueKey('hint-$i'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              height: 1.2,
              color: widget.color,
              decoration: TextDecoration.none,
            ),
          ),
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

  static String? _badgeFor(String tab) => switch (tab) {
        '推荐' => 'HOT',
        '短剧' => '新',
        '综艺' => '热',
        '动漫' => 'HOT',
        _ => null,
      };

  static Color _badgeColor(String badge) => switch (badge) {
        'HOT' => const Color(0xFFFF4D4F),
        '热' => const Color(0xFFFF7A1A),
        '新' => AppColors.brand,
        _ => const Color(0xFFFF4D4F),
      };

  @override
  Widget build(BuildContext context) {
    final t = lightProgress.clamp(0.0, 1.0);
    final dark = AppPalette.isDark(context);
    final solidInk = dark ? AppColors.textDark : const Color(0xFF1A1A1A);
    final solidMuted = dark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93);
    final activeColor = Color.lerp(Colors.white, solidInk, t)!;
    final idleColor = Color.lerp(
      Colors.white.withValues(alpha: 0.88),
      solidMuted,
      t,
    )!;
    final indicator = Color.lerp(Colors.white, AppColors.brand, t)!;
    final shadowAlpha = (1.0 - t).clamp(0.0, 1.0);

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        physics: const BouncingScrollPhysics(),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final active = i == index;
          final label = tabs[i];
          final badge = _badgeFor(label);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 角标飘在文字外，不撑宽布局，染色条才能相对文字居中
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: active ? 16 : 14,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w600,
                        color: active ? activeColor : idleColor,
                        height: 1.1,
                        decoration: TextDecoration.none,
                        shadows: shadowAlpha < 0.05
                            ? null
                            : [
                                Shadow(
                                  color: Color.fromRGBO(
                                    0,
                                    0,
                                    0,
                                    0.8 * shadowAlpha,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                      ),
                    ),
                    if (badge != null)
                      Positioned(
                        top: -8,
                        right: -14,
                        child: _TabHotBadge(
                          label: badge,
                          color: _badgeColor(badge),
                        ),
                      ),
                  ],
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
                const SizedBox(height: 6),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TabHotBadge extends StatelessWidget {
  const _TabHotBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 8,
          fontWeight: FontWeight.w800,
          height: 1,
          color: Colors.white,
          letterSpacing: 0.2,
          decoration: TextDecoration.none,
        ),
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
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppPalette.text(context),
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
    final dark = AppPalette.isDark(context);
    final bg = selected
        ? AppColors.brand
        : outlined
            ? (dark ? const Color(0xFF2C2C2E) : Colors.white)
            : (dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F3F5));
    final fg = selected
        ? Colors.white
        : (dark ? const Color(0xFFD1D1D6) : const Color(0xFF555555));

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
                Expanded(
                  child: Text(
                    '扩展筛选',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.text(context),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: AppPalette.textHint(context),
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
                    ? (AppPalette.isDark(context)
                        ? Colors.white
                        : const Color(0xFF1A1A1A))
                    : AppPalette.softFill(context),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                labels[i],
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? (AppPalette.isDark(context)
                          ? const Color(0xFF1A1A1A)
                          : Colors.white)
                      : AppPalette.textSecondary(context),
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
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: AppPalette.text(context),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
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
              ),
              MovieWatchMoreButton(movie: movie),
            ],
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
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: AppPalette.text(context),
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
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.text(context),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
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
                        ),
                        MovieWatchMoreButton(movie: movie),
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
