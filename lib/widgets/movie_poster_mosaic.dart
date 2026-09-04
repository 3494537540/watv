import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import 'cms_cover_image.dart';

/// 倾斜影视海报拼贴背景（登录页等）
class MoviePosterMosaic extends StatefulWidget {
  const MoviePosterMosaic({
    super.key,
    this.dim = 0.62,
    this.angle = -0.42,
  });

  final double dim;
  final double angle;

  @override
  State<MoviePosterMosaic> createState() => _MoviePosterMosaicState();
}

class _MoviePosterMosaicState extends State<MoviePosterMosaic> {
  List<String> _urls = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final list = await MacCmsApi().fetchHotMovies(limit: 24);
      final urls = <String>[
        for (final m in list)
          if ((m.coverUrl ?? '').trim().isNotEmpty) m.coverUrl!.trim(),
      ];
      if (!mounted || urls.isEmpty) return;
      setState(() => _urls = urls);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = math.max(size.width, size.height) * 1.6;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF0B0B0C)),
          Center(
            child: Transform.rotate(
              angle: widget.angle,
              child: SizedBox(
                width: side,
                height: side,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: 48,
                  itemBuilder: (context, i) {
                    final url =
                        _urls.isEmpty ? null : _urls[i % _urls.length];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: url == null
                          ? ColoredBox(
                              color: Color.lerp(
                                const Color(0xFF1C1C1E),
                                AppColors.brand,
                                (i % 7) * 0.035,
                              )!,
                              child: const Icon(
                                Icons.movie_outlined,
                                color: Color(0x33FFFFFF),
                                size: 26,
                              ),
                            )
                          : CmsCoverImage(url: url, fit: BoxFit.cover),
                    );
                  },
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: widget.dim * 0.72),
                  Colors.black.withValues(alpha: widget.dim),
                  Colors.black.withValues(
                    alpha: math.min(0.92, widget.dim + 0.22),
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

/// 三张叠放海报（单页）
class FavPosterStack extends StatelessWidget {
  const FavPosterStack({
    super.key,
    this.urls = const [],
    this.width = 220,
    this.height = 180,
  });

  final List<String> urls;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget card(double angle, Alignment align, String? url, double w) {
      return Transform.rotate(
        angle: angle,
        alignment: align,
        child: Container(
          width: w,
          height: w * 1.35,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white, width: 5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: url == null || url.isEmpty
                ? const ColoredBox(
                    color: Color(0xFFE8E9ED),
                    child: Icon(
                      Icons.movie_filter_outlined,
                      size: 40,
                      color: Color(0xFFB0B3BB),
                    ),
                  )
                : CmsCoverImage(url: url, fit: BoxFit.cover),
          ),
        ),
      );
    }

    final a = urls.isNotEmpty ? urls[0] : null;
    final b = urls.length > 1 ? urls[1] : a;
    final c = urls.length > 2 ? urls[2] : a;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 8,
            child: card(-0.22, Alignment.centerRight, b, 92),
          ),
          Positioned(
            right: 8,
            child: card(0.22, Alignment.centerLeft, c, 92),
          ),
          card(0, Alignment.center, a, 108),
        ],
      ),
    );
  }
}

/// 兼容旧引用
typedef FavEmptyPosterStack = FavPosterStack;

/// 收藏叠放海报轮播（可左右切换）
class FavCollectionCarousel extends StatefulWidget {
  const FavCollectionCarousel({
    super.key,
    required this.pages,
    this.title = '从收藏开始',
    this.subtitle = '把喜欢的影视收进来，随时继续追',
    this.ctaLabel = '去发现好片',
    this.onCta,
    this.showCta = true,
    this.height = 360,
    this.compact = false,
  });

  /// 每一页 1～3 张封面 URL
  final List<List<String>> pages;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback? onCta;
  final bool showCta;
  final double height;
  final bool compact;

  @override
  State<FavCollectionCarousel> createState() => _FavCollectionCarouselState();
}

class _FavCollectionCarouselState extends State<FavCollectionCarousel> {
  late final PageController _ctrl;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController(viewportFraction: 1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<List<String>> get _pages {
    if (widget.pages.isNotEmpty) return widget.pages;
    return const [<String>[]];
  }

  void _go(int delta) {
    final n = _pages.length;
    if (n <= 1) return;
    final next = (_index + delta).clamp(0, n - 1);
    _ctrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final text = AppPalette.text(context);
    final secondary = AppPalette.textSecondary(context);
    final canSwipe = pages.length > 1;

    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PageView.builder(
                  controller: _ctrl,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) {
                    return Center(
                      child: FavPosterStack(
                        urls: pages[i],
                        width: widget.compact ? 200 : 230,
                        height: widget.compact ? 160 : 188,
                      ),
                    );
                  },
                ),
                if (canSwipe) ...[
                  Positioned(
                    left: 42,
                    child: _NavCircle(
                      icon: Icons.chevron_left,
                      onTap: _index > 0 ? () => _go(-1) : null,
                    ),
                  ),
                  Positioned(
                    right: 42,
                    child: _NavCircle(
                      icon: Icons.chevron_right,
                      onTap: _index < pages.length - 1 ? () => _go(1) : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 4),
          ],
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: widget.compact ? 18 : 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: text,
            ),
          ),
          SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: widget.compact ? 13 : 14,
                height: 1.4,
                color: secondary,
              ),
            ),
          ),
          if (widget.showCta && widget.onCta != null) ...[
            SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.onCta,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(
                      vertical: widget.compact ? 12 : 14,
                    ),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(widget.ctaLabel),
                ),
              ),
            ),
          ],
          if (canSwipe) ...[
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  Container(
                    width: i == _index ? 14 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.brand
                          : AppColors.brand.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _NavCircle extends StatelessWidget {
  const _NavCircle({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.28 : 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// 把封面列表切成每页最多 3 张
List<List<String>> favCarouselPages(List<String> urls, {int perPage = 3}) {
  final clean = [
    for (final u in urls)
      if (u.trim().isNotEmpty) u.trim(),
  ];
  if (clean.isEmpty) return const [<String>[]];
  final pages = <List<String>>[];
  for (var i = 0; i < clean.length; i += perPage) {
    final end = (i + perPage).clamp(0, clean.length);
    pages.add(clean.sublist(i, end));
  }
  return pages;
}
