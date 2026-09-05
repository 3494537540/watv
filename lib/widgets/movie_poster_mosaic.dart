import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// 收藏叠放卡片数据
class FavStackItem {
  const FavStackItem({
    required this.id,
    required this.name,
    this.pic = '',
  });

  final String id;
  final String name;
  final String pic;
}

/// 1～3 张叠放海报：可展开扇出，点某一张跳转播放
class FavPosterStack extends StatefulWidget {
  const FavPosterStack({
    super.key,
    this.items = const [],
    this.urls = const [],
    this.onOpen,
    this.width = 260,
    this.height = 210,
    this.interactive = true,
  });

  /// 优先使用；空时回退 [urls]（仅展示）
  final List<FavStackItem> items;
  final List<String> urls;
  final ValueChanged<FavStackItem>? onOpen;
  final double width;
  final double height;
  final bool interactive;

  @override
  State<FavPosterStack> createState() => _FavPosterStackState();
}

class _FavPosterStackState extends State<FavPosterStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expand;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _expand = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _t = CurvedAnimation(parent: _expand, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  List<FavStackItem> get _items {
    if (widget.items.isNotEmpty) {
      return widget.items.take(3).toList(growable: false);
    }
    return [
      for (final u in widget.urls.take(3))
        if (u.trim().isNotEmpty)
          FavStackItem(id: '', name: '', pic: u.trim()),
    ];
  }

  bool get _canExpand => _items.length > 1 && widget.interactive;

  bool get _expanded => _expand.value > 0.5;

  Future<void> _toggleExpand() async {
    if (!_canExpand) return;
    HapticFeedback.selectionClick();
    if (_expand.isCompleted || _expand.value > 0.5) {
      await _expand.reverse();
    } else {
      await _expand.forward();
    }
  }

  Future<void> _collapse() async {
    if (_expand.value == 0) return;
    await _expand.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: _posterCard(
          url: null,
          w: 112,
          onTap: null,
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value.clamp(0.0, 1.2);
          final n = items.length;
          // 绘制顺序：后层先画，前层最后（索引大 = 越靠前）
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_expanded) unawaited(_collapse());
            },
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // 绘制顺序：侧卡先画，正面最后盖上
                for (final slot in _paintOrder(n))
                  _buildLayeredCard(
                    slot: slot,
                    count: n,
                    item: items[_itemIndexForSlot(slot, n)],
                    itemIndex: _itemIndexForSlot(slot, n),
                    t: t,
                  ),
                if (_canExpand && !_expanded)
                  Positioned(
                    bottom: 0,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: (1.0 - t).clamp(0.0, 1.0) * 0.85,
                        child: Text(
                          '点侧卡展开 · 点中间播放',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 11,
                            color: AppPalette.textHint(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_canExpand && _expanded)
                  Positioned(
                    bottom: 0,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: t.clamp(0.0, 1.0) * 0.85,
                        child: Text(
                          '点海报播放 · 点空白收起',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 11,
                            color: AppPalette.textHint(context),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 视觉槽位：0=左后 1=右后 2=正面（或双卡时 0左 1右前）
  List<int> _paintOrder(int count) {
    if (count <= 1) return const [2];
    if (count == 2) return const [0, 1];
    return const [0, 1, 2];
  }

  /// 数据下标：第 1 部永远正面；第 2/3 部在两侧
  int _itemIndexForSlot(int slot, int count) {
    if (count == 1) return 0;
    if (count == 2) {
      // slot 0 左后 = items[1]，slot 1 右前 = items[0]
      return slot == 0 ? 1 : 0;
    }
    // slot 0 左 = items[1]，slot 1 右 = items[2]，slot 2 中 = items[0]
    return switch (slot) {
      0 => 1,
      1 => 2,
      _ => 0,
    };
  }

  Widget _buildLayeredCard({
    required int slot,
    required int count,
    required FavStackItem item,
    required int itemIndex,
    required double t,
  }) {
    final layout = _layoutForSlot(slot, count, t);
    final cardW = layout.w;

    return Transform.translate(
      offset: Offset(layout.dx, layout.dy),
      child: Transform.rotate(
        angle: layout.rot,
        child: Transform.scale(
          scale: layout.scale,
          child: _posterCard(
            url: item.pic,
            w: cardW,
            onTap: () => _onCardTap(itemIndex),
          ),
        ),
      ),
    );
  }

  void _onCardTap(int itemIndex) {
    final items = _items;
    if (itemIndex < 0 || itemIndex >= items.length) return;
    final item = items[itemIndex];
    final canPlay = widget.onOpen != null && item.id.trim().isNotEmpty;

    if (!_canExpand) {
      if (canPlay) {
        HapticFeedback.mediumImpact();
        widget.onOpen!(item);
      }
      return;
    }

    // 收起态：点正面（第 1 部）直接播放；点侧卡展开
    if (!_expanded) {
      if (itemIndex == 0 && canPlay) {
        HapticFeedback.mediumImpact();
        widget.onOpen!(item);
        return;
      }
      unawaited(_toggleExpand());
      return;
    }

    if (canPlay) {
      HapticFeedback.mediumImpact();
      widget.onOpen!(item);
      unawaited(_collapse());
    } else {
      unawaited(_collapse());
    }
  }

  /// slot: 0 左 / 1 右 / 2 中前
  _CardLayout _layoutForSlot(int slot, int count, double t) {
    if (count == 1) {
      return const _CardLayout(dx: 0, dy: -6, rot: 0, scale: 1, w: 118);
    }

    if (count == 2) {
      final collapsed = slot == 0
          ? const _CardLayout(dx: -34, dy: 8, rot: -0.18, scale: 0.92, w: 100)
          : const _CardLayout(dx: 28, dy: -2, rot: 0.12, scale: 1.0, w: 112);
      final expanded = slot == 0
          ? const _CardLayout(dx: -78, dy: 0, rot: -0.04, scale: 1.0, w: 108)
          : const _CardLayout(dx: 78, dy: 0, rot: 0.04, scale: 1.0, w: 108);
      return _CardLayout.lerp(collapsed, expanded, t);
    }

    final collapsed = switch (slot) {
      0 => const _CardLayout(dx: -42, dy: 10, rot: -0.22, scale: 0.88, w: 96),
      1 => const _CardLayout(dx: 42, dy: 10, rot: 0.22, scale: 0.88, w: 96),
      _ => const _CardLayout(dx: 0, dy: -4, rot: 0, scale: 1.0, w: 112),
    };
    final expanded = switch (slot) {
      0 => const _CardLayout(dx: -108, dy: 2, rot: -0.05, scale: 0.98, w: 104),
      1 => const _CardLayout(dx: 108, dy: 2, rot: 0.05, scale: 0.98, w: 104),
      _ => const _CardLayout(dx: 0, dy: -8, rot: 0, scale: 1.06, w: 116),
    };
    return _CardLayout.lerp(collapsed, expanded, t);
  }

  Widget _posterCard({
    required String? url,
    required double w,
    required VoidCallback? onTap,
  }) {
    final h = w * 1.38;
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
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
      ),
    );
  }
}

class _CardLayout {
  const _CardLayout({
    required this.dx,
    required this.dy,
    required this.rot,
    required this.scale,
    required this.w,
  });

  final double dx;
  final double dy;
  final double rot;
  final double scale;
  final double w;

  static _CardLayout lerp(_CardLayout a, _CardLayout b, double t) {
    final x = t.clamp(0.0, 1.0);
    return _CardLayout(
      dx: a.dx + (b.dx - a.dx) * x,
      dy: a.dy + (b.dy - a.dy) * x,
      rot: a.rot + (b.rot - a.rot) * x,
      scale: a.scale + (b.scale - a.scale) * x,
      w: a.w + (b.w - a.w) * x,
    );
  }
}

/// 兼容旧引用
typedef FavEmptyPosterStack = FavPosterStack;

/// 收藏叠放海报轮播（可左右切换 / 展开 / 点播）
class FavCollectionCarousel extends StatefulWidget {
  const FavCollectionCarousel({
    super.key,
    this.items = const [],
    this.pages,
    this.decorCovers = const [],
    this.onOpen,
    this.title = '从收藏开始',
    this.subtitle = '把喜欢的影视收进来，随时继续追',
    this.ctaLabel = '去发现好片',
    this.onCta,
    this.showCta = true,
    this.height = 360,
    this.compact = false,
  });

  /// 真实收藏（优先）
  final List<FavStackItem> items;
  /// 旧 API：每页 URL 列表；[items] 为空时使用
  final List<List<String>>? pages;
  final List<String> decorCovers;
  final ValueChanged<FavStackItem>? onOpen;
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

  List<List<FavStackItem>> get _pages {
    final real = [
      for (final e in widget.items)
        if (e.pic.trim().isNotEmpty || e.id.trim().isNotEmpty) e,
    ];
    if (real.isNotEmpty) return favCarouselItemPages(real);

    final legacy = widget.pages;
    if (legacy != null && legacy.isNotEmpty) {
      return [
        for (final page in legacy)
          [
            for (final u in page)
              if (u.trim().isNotEmpty)
                FavStackItem(id: '', name: '', pic: u.trim()),
          ],
      ];
    }

    final decor = [
      for (final u in widget.decorCovers)
        if (u.trim().isNotEmpty)
          FavStackItem(id: '', name: '', pic: u.trim()),
    ];
    if (decor.isEmpty) return const [<FavStackItem>[]];
    return favCarouselItemPages(decor);
  }

  void _go(int delta) {
    final n = _pages.length;
    if (n <= 1) return;
    final next = (_index + delta).clamp(0, n - 1);
    _ctrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final text = AppPalette.text(context);
    final secondary = AppPalette.textSecondary(context);
    final canSwipe = pages.length > 1;
    final interactive = widget.onOpen != null && widget.items.isNotEmpty;

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
                        items: pages[i],
                        onOpen: interactive ? widget.onOpen : null,
                        interactive: interactive,
                        width: widget.compact ? 240 : 280,
                        height: widget.compact ? 188 : 220,
                      ),
                    );
                  },
                ),
                if (canSwipe) ...[
                  Positioned(
                    left: 8,
                    child: _NavCircle(
                      icon: Icons.chevron_left,
                      onTap: _index > 0 ? () => _go(-1) : null,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    child: _NavCircle(
                      icon: Icons.chevron_right,
                      onTap: _index < pages.length - 1 ? () => _go(1) : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: widget.compact ? 4 : 8),
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
          const SizedBox(height: 6),
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
            const SizedBox(height: 14),
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
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

/// 把封面列表切成每页最多 3 张（旧 API）
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

/// 收藏条目分页（每页最多 3 部，不足不补假封面）
List<List<FavStackItem>> favCarouselItemPages(
  List<FavStackItem> items, {
  int perPage = 3,
}) {
  if (items.isEmpty) return const [<FavStackItem>[]];
  final pages = <List<FavStackItem>>[];
  for (var i = 0; i < items.length; i += perPage) {
    final end = (i + perPage).clamp(0, items.length);
    pages.add(items.sublist(i, end));
  }
  return pages;
}
