import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie_models.dart';
import '../../player/source_latency.dart';
import '../../state/theme_controller.dart';
import '../../theme/app_colors.dart';
import '../cms_cover_image.dart';
import '../figma_loading.dart';
import '../media_placeholder.dart';

/// 详情页小品牌标：卡通「哇」圆角裁剪，避免四角黑边
class _WaBrandMark extends StatelessWidget {
  const _WaBrandMark({this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/images/app_icon_wa_cartoon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => ColoredBox(
          color: AppColors.brand,
          child: Center(
            child: Text(
              '哇',
              style: TextStyle(
                fontFamily: 'ZCOOLKuaiLe',
                fontSize: size * 0.62,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 芒果 TV 播放页下方样式常量（跟随明暗主题）
abstract final class MangoWatchStyle {
  static const hPad = 16.0;
  static Color get accent => AppColors.mango;

  static bool get _dark => ThemeController.instance.isDark;

  static Color get titleColor =>
      _dark ? AppColors.textDark : const Color(0xFF111111);
  static Color get bodyColor =>
      _dark ? const Color(0xFFD8D8D8) : const Color(0xFF333333);
  static Color get tabOffColor =>
      _dark ? const Color(0xFFAEAEB2) : const Color(0xFF444444);
  static Color get metaColor =>
      _dark ? const Color(0xFF8E8E93) : const Color(0xFF777777);
  static Color get linkColor =>
      _dark ? const Color(0xFF8E8E93) : const Color(0xFF777777);
  static Color get iconColor =>
      _dark ? const Color(0xFFC7C7CC) : const Color(0xFF555555);
  static Color get chipBgOn =>
      _dark ? const Color(0xFF3A3A3C) : const Color(0xFFEEEEEE);
  static Color get chipBgOff =>
      _dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F2);
  static Color get chipText =>
      _dark ? const Color(0xFFD1D1D6) : const Color(0xFF555555);

  static const titleSize = 19.0;
  static const metaSize = 12.0;
  static const tabSize = 16.0;
  static const badgeSize = 9.0;
  static const sectionSize = 16.0;
  static const linkSize = 13.0;
  static const chipLabelSize = 15.0;

  static const chipSize = 48.0;
  static const chipGap = 8.0;
  /// 偏圆角（接近芒果方块）
  static const chipRadius = 14.0;

  static const gapTitleMeta = 8.0;
  static const gapMetaTabs = 24.0;
  static const gapTabsSection = 24.0;
  static const gapSectionChips = 12.0;
}

TextStyle _titleStyle({required double size, required FontWeight w, Color? c}) {
  return TextStyle(
    fontFamily: 'AppSans',
    fontSize: size,
    fontWeight: w,
    color: c ?? MangoWatchStyle.titleColor,
    height: 1.2,
  );
}

/// 播放页：片名（右 chevron）+ 来源行
class MangoWatchHeader extends StatelessWidget {
  const MangoWatchHeader({
    super.key,
    required this.title,
    required this.sourceLine,
    this.onTitleTap,
    this.onSynopsisTap,
  });

  final String title;
  final String sourceLine;
  final VoidCallback? onTitleTap;
  /// 片名旁「简介」入口
  final VoidCallback? onSynopsisTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onTitleTap ?? onSynopsisTap,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(
                    size: MangoWatchStyle.titleSize,
                    w: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (onSynopsisTap != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSynopsisTap!();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F3F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '简介',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF555555),
                          height: 1,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 11,
                        color: Color(0xFF888888),
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              const Icon(
                CupertinoIcons.arrowtriangle_down_fill,
                size: 11,
                color: Color(0xFF888888),
              ),
          ],
        ),
        SizedBox(height: MangoWatchStyle.gapTitleMeta),
        Builder(
          builder: (context) {
            var suffix = '';
            final raw = sourceLine.trim();
            if (raw.contains('·')) {
              suffix = raw.split('·').skip(1).join('·').trim();
            } else if (raw.isNotEmpty && raw != '哇TV') {
              suffix = raw;
            }
            return Row(
              children: [
                const _WaBrandMark(size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '哇TV',
                          style: TextStyle(
                            fontFamily: 'ZCOOLKuaiLe',
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF555555),
                            height: 1.15,
                          ),
                        ),
                        if (suffix.isNotEmpty)
                          TextSpan(
                            text: ' · $suffix',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: MangoWatchStyle.metaSize,
                              fontWeight: FontWeight.w400,
                              color: MangoWatchStyle.metaColor,
                              height: 1.2,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Tab：视频 | 评论 + 收藏/投屏/缓存/分享
class MangoWatchTabs extends StatelessWidget {
  const MangoWatchTabs({
    super.key,
    required this.index,
    required this.commentCount,
    required this.onChanged,
    this.onFavorite,
    this.onCast,
    this.onShare,
    this.onCache,
    this.favored = false,
    this.downloadingCount = 0,
    this.cacheIconKey,
  });

  final int index;
  final int commentCount;
  final ValueChanged<int> onChanged;
  final VoidCallback? onFavorite;
  final VoidCallback? onCast;
  final VoidCallback? onShare;
  final VoidCallback? onCache;
  final bool favored;
  final int downloadingCount;
  final GlobalKey? cacheIconKey;

  static String _countText(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }

  Widget _tabLabel({
    required String label,
    required bool on,
    int? badge,
  }) {
    final style = TextStyle(
      fontFamily: 'AppSans',
      fontSize: MangoWatchStyle.tabSize,
      fontWeight: on ? FontWeight.w700 : FontWeight.w600,
      color: on ? MangoWatchStyle.accent : MangoWatchStyle.tabOffColor,
      height: 1.15,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: style),
        if (badge != null && badge > 0)
          Padding(
            padding: const EdgeInsets.only(left: 1, top: 0),
            child: Transform.translate(
              offset: const Offset(0, -3),
              child: Text(
                _countText(badge),
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: MangoWatchStyle.badgeSize,
                  fontWeight: FontWeight.w600,
                  color: MangoWatchStyle.accent,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, int i, {int? badge}) {
      final on = index == i;
      return GestureDetector(
        onTap: () => onChanged(i),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tabLabel(label: label, on: on, badge: badge),
              SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: on ? 16 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: MangoWatchStyle.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        tab('视频', 0),
        tab('评论', 1, badge: commentCount),
        const Spacer(),
        if (onFavorite != null)
          _ActionIconButton(
            icon: Icons.favorite_border_rounded,
            activeIcon: Icons.favorite_rounded,
            active: favored,
            activeColor: MangoWatchStyle.accent,
            onTap: onFavorite!,
          ),
        if (onCast != null)
          _ActionIconButton(
            icon: Icons.cast_rounded,
            onTap: onCast!,
          ),
        if (onCache != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _CacheDownloadButton(
              key: cacheIconKey,
              downloadingCount: downloadingCount,
              onTap: onCache!,
            ),
          ),
        if (onShare != null)
          _ActionIconButton(
            icon: Icons.ios_share_rounded,
            onTap: onShare!,
          ),
      ],
    );
  }
}

/// 详情顶栏操作图标：统一尺寸/线宽/颜色
class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.onTap,
    this.activeIcon,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final IconData? activeIcon;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;

  static const _ink = Color(0xFF444444);
  static const _box = 40.0;
  static const _glyph = 22.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _box,
        height: _box,
        child: Icon(
          active ? (activeIcon ?? icon) : icon,
          size: _glyph,
          color: active ? (activeColor ?? _ink) : _ink,
        ),
      ),
    );
  }
}

/// 下载中：纯图标（无底色）+ 主题色角标 + 箭头下落；空闲：灰线框图标
class _CacheDownloadButton extends StatefulWidget {
  const _CacheDownloadButton({
    super.key,
    required this.downloadingCount,
    required this.onTap,
  });

  final int downloadingCount;
  final VoidCallback onTap;

  @override
  State<_CacheDownloadButton> createState() => _CacheDownloadButtonState();
}

class _CacheDownloadButtonState extends State<_CacheDownloadButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant _CacheDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadingCount != widget.downloadingCount) _sync();
  }

  void _sync() {
    if (widget.downloadingCount > 0) {
      if (!_anim.isAnimating) _anim.repeat();
    } else {
      _anim
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.downloadingCount > 0;
    final accent = AppColors.brand;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 40,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final bob =
                active ? (0.5 - (_anim.value - 0.5).abs()) * 5.0 : 0.0;
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  offset: Offset(0, bob),
                  child: Icon(
                    Icons.download_rounded,
                    size: 22,
                    color: active ? accent : const Color(0xFF444444),
                  ),
                ),
                if (active)
                  Positioned(
                    top: 4,
                    right: 2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 14),
                      height: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        widget.downloadingCount > 9
                            ? '9+'
                            : '${widget.downloadingCount}',
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 选集方块（选中时底部等化波动效）
class MangoEpisodeChip extends StatefulWidget {
  const MangoEpisodeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.size = MangoWatchStyle.chipSize,
    this.width,
    this.expand = false,
    this.cornerBadge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double size;
  final double? width;
  final bool expand;
  final String? cornerBadge;

  static bool isVipLabel(String name) {
    final u = name.toUpperCase();
    return u.contains('VIP') || name.contains('会员');
  }

  static Color badgeColor(String badge) {
    final u = badge.toUpperCase();
    if (u == 'VIP' || badge == '会员') return const Color(0xFFE0B13A);
    if (badge == '新') return MangoWatchStyle.accent;
    if (badge == '预') return const Color(0xFF5B8DEF);
    return const Color(0xFF999999);
  }

  @override
  State<MangoEpisodeChip> createState() => _MangoEpisodeChipState();
}

class _MangoEpisodeChipState extends State<MangoEpisodeChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.selected) _wave.repeat();
  }

  @override
  void didUpdateWidget(covariant MangoEpisodeChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    // 只启停，不重建 Controller（SingleTicker 不能多次 createTicker）
    if (widget.selected) {
      _wave.repeat();
    } else {
      _wave
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget chip({required double w, required double h}) {
      final badge = widget.cornerBadge?.trim();
      final on = widget.selected;

      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // 选中也不换底、不描边，仅数字与波形染色
                  color: MangoWatchStyle.chipBgOff,
                  borderRadius:
                      BorderRadius.circular(MangoWatchStyle.chipRadius),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: h >= 44
                            ? MangoWatchStyle.chipLabelSize
                            : 13,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on
                            ? MangoWatchStyle.accent
                            : MangoWatchStyle.chipText,
                      ),
                    ),
                    if (on) ...[
                      SizedBox(height: 4),
                      SizedBox(
                        height: 10,
                        width: 18,
                        child: AnimatedBuilder(
                          animation: _wave,
                          builder: (context, _) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(3, (i) {
                                final t = (_wave.value + i * 0.28) % 1.0;
                                final wave =
                                    0.35 + 0.65 * (0.5 + 0.5 *
                                        math.sin(t * math.pi * 2));
                                return Container(
                                  width: 3,
                                  height: 10 * wave,
                                  decoration: BoxDecoration(
                                    color: MangoWatchStyle.accent,
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (badge != null && badge.isNotEmpty)
              Positioned(
                top: -4,
                right: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: MangoEpisodeChip.badgeColor(badge),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: widget.expand
          ? LayoutBuilder(
              builder: (context, c) {
                final side = (c.maxWidth.isFinite && c.maxHeight.isFinite)
                    ? (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight)
                    : MangoWatchStyle.chipSize;
                final s = side.isFinite ? side : MangoWatchStyle.chipSize;
                return Center(child: chip(w: s, h: s));
              },
            )
          : chip(w: widget.width ?? widget.size, h: widget.size),
    );
  }
}

/// 横滑线路骨架（占位）
class MangoSourceSkeleton extends StatelessWidget {
  const MangoSourceSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '播放线路',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: MangoWatchStyle.sectionSize,
              fontWeight: FontWeight.w700,
              color: MangoWatchStyle.titleColor,
            ),
          ),
          const SizedBox(height: 10),
          FigmaSkeletonPulse(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, _) => const FigmaSkeletonBone(
                  width: 108,
                  height: 34,
                  radius: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 选集横滑骨架
class MangoEpisodeSkeleton extends StatelessWidget {
  const MangoEpisodeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选集',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: MangoWatchStyle.sectionSize,
              fontWeight: FontWeight.w700,
              color: MangoWatchStyle.titleColor,
            ),
          ),
          const SizedBox(height: 10),
          FigmaSkeletonPulse(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 6,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, _) => const FigmaSkeletonBone(
                  width: 56,
                  height: 40,
                  radius: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 同类型推荐横滑骨架
class MangoRelatedSkeleton extends StatelessWidget {
  const MangoRelatedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaSkeletonPulse(
      child: SizedBox(
        height: 148,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) {
            return SizedBox(
              width: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: const AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ColoredBox(color: FigmaSkeletonColors.bone),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const FigmaSkeletonBone(width: 120, height: 12, radius: 4),
                  const SizedBox(height: 6),
                  const FigmaSkeletonBone(width: 72, height: 10, radius: 4),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 横滑线路（进入即自动测速；单行名+延迟）
class MangoSourceRow extends StatefulWidget {
  const MangoSourceRow({
    super.key,
    required this.names,
    required this.selected,
    required this.onSelect,
    this.probeUrls = const [],
  });

  final List<String> names;
  final int selected;
  final ValueChanged<int> onSelect;
  /// 与 names 一一对应的探测地址（通常取该线路当前集 URL）
  final List<String> probeUrls;

  @override
  State<MangoSourceRow> createState() => _MangoSourceRowState();
}

class _MangoSourceRowState extends State<MangoSourceRow> {
  final Map<int, int?> _latency = {};
  bool _probing = false;
  int _probeGen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_runProbe());
  }

  @override
  void didUpdateWidget(covariant MangoSourceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当探测地址真变了才重测；切换选中线路不重测、不清空结果
    if (oldWidget.probeUrls.join('|') != widget.probeUrls.join('|') ||
        oldWidget.names.join('|') != widget.names.join('|')) {
      unawaited(_runProbe(force: true));
    }
  }

  Future<void> _runProbe({bool force = false}) async {
    if (_probing && !force) return;
    if (widget.names.length <= 1) return;
    if (!widget.probeUrls.any((u) => u.trim().isNotEmpty)) return;
    final gen = ++_probeGen;
    setState(() => _probing = true);
    final urls = List<String>.from(widget.probeUrls);
    final n = widget.names.length;
    // 限流并发：同时狂拉容易把弱 CDN 测成「失败」
    const concurrency = 2;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= n) return;
        if (!mounted || gen != _probeGen) return;
        final url = i < urls.length ? urls[i] : '';
        final bps =
            url.trim().isEmpty ? null : await SourceLatency.probe(url);
        if (!mounted || gen != _probeGen) return;
        setState(() => _latency[i] = bps);
      }
    }

    await Future.wait([
      for (var w = 0; w < concurrency; w++) worker(),
    ]);
    if (!mounted || gen != _probeGen) return;
    setState(() => _probing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.names.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  '播放线路',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: MangoWatchStyle.sectionSize,
                    fontWeight: FontWeight.w700,
                    color: MangoWatchStyle.titleColor,
                  ),
                ),
                if (_probing) ...[
                  const SizedBox(width: 8),
                  const Text(
                    '测速中',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.names.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final on = i == widget.selected;
                final raw = widget.names[i].trim();
                final label = raw.isEmpty ? '线路${i + 1}' : raw;
                final hasLat = _latency.containsKey(i);
                final bps = hasLat ? _latency[i] : null;
                final tone = hasLat ? SourceLatency.tone(bps) : null;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onSelect(i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? AppColors.brand.withValues(alpha: 0.12)
                          : MangoWatchStyle.chipBgOff,
                      borderRadius: BorderRadius.circular(18),
                      border: on
                          ? Border.all(color: AppColors.brand, width: 1.2)
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tone != null) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: Color(tone.argb),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ] else if (_probing) ...[
                          SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.4,
                              color: AppColors.brand.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                            color: on
                                ? MangoWatchStyle.titleColor
                                : MangoWatchStyle.chipText,
                            height: 1,
                          ),
                        ),
                        if (hasLat) ...[
                          const SizedBox(width: 6),
                          Text(
                            SourceLatency.label(bps),
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(tone!.argb),
                              height: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 横滑选集
class MangoEpisodeRow extends StatelessWidget {
  const MangoEpisodeRow({
    super.key,
    required this.episodes,
    required this.selected,
    required this.onSelect,
    this.onShowAll,
    this.markVipFromIndex,
    this.intro,
  });

  final List<MoviePlayEpisode> episodes;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback? onShowAll;
  final int? markVipFromIndex;
  /// 正片旁短介绍（如备注两字：完结/更新）
  final String? intro;

  static String chipLabel(String name, int index, {int total = 0}) {
    final t = name.trim();

    // 单集（电影）：统一显示「正片」，除非本来就是花絮/预告等短名
    if (total == 1) {
      if (t.isEmpty) return '正片';
      final lower = t.toLowerCase();
      if (RegExp(r'^(第?\s*\d+\s*集?|正片|高清|超清|蓝光|抢先|hd|4k|1080p|720p)$',
              caseSensitive: false)
          .hasMatch(t)) {
        return '正片';
      }
      if (t.contains('花絮') ||
          t.contains('预告') ||
          t.contains('彩蛋') ||
          lower.contains('preview') ||
          lower.contains('trailer')) {
        return t.length <= 4 ? t : '正片';
      }
      if (t.length <= 4 && !RegExp(r'^\d+$').hasMatch(t)) return t;
      return '正片';
    }

    if (t.isEmpty) return '${index + 1}';

    // 标准「第N集」/「N集」：必须整段匹配集数，避免把「集」字拆出来
    final ep = RegExp(r'第\s*(\d+)\s*集').firstMatch(t) ??
        RegExp(r'^(\d+)\s*集$').firstMatch(t);
    if (ep != null) {
      final n = int.tryParse(ep.group(1)!);
      if (n != null) {
        // 「第3集 花絮」→ 花絮；纯「第3集」→ 3
        final rest = t
            .replaceFirst(RegExp(r'第?\s*\d+\s*集'), '')
            .replaceAll(RegExp(r'^[\s·\-_:：]+'), '')
            .trim();
        if (rest.isNotEmpty &&
            rest.length <= 4 &&
            !RegExp(r'\d').hasMatch(rest) &&
            rest != '集') {
          return rest;
        }
        return '$n';
      }
    }

    if (RegExp(r'^\d+$').hasMatch(t)) {
      return '${int.parse(t)}';
    }

    // 纯短名：花絮 / 预告 / 上集 …
    if (t.length <= 4 && t != '集') return t;

    final any = RegExp(r'(\d+)').firstMatch(t);
    if (any != null) {
      final n = int.tryParse(any.group(1)!);
      if (n != null) return '$n';
    }
    return '${index + 1}';
  }

  static double _chipWidthFor(String label) {
    if (label.length <= 2) return MangoWatchStyle.chipSize;
    return MangoWatchStyle.chipSize + (label.length - 2) * 10.0;
  }

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) return const SizedBox.shrink();
    final tip = intro?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '正片',
              style: _titleStyle(
                size: MangoWatchStyle.sectionSize,
                w: FontWeight.w700,
              ),
            ),
            if (tip != null && tip.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tip,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF888888),
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (onShowAll != null)
              GestureDetector(
                onTap: onShowAll,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '全部',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: MangoWatchStyle.linkSize,
                          fontWeight: FontWeight.w400,
                          color: MangoWatchStyle.linkColor,
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 12,
                        color: MangoWatchStyle.linkColor,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: MangoWatchStyle.gapSectionChips),
        SizedBox(
          height: MangoWatchStyle.chipSize + 10,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 6, right: 6),
            physics: const BouncingScrollPhysics(),
            itemCount: episodes.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: MangoWatchStyle.chipGap),
            itemBuilder: (context, i) {
              final ep = episodes[i];
              final label = chipLabel(ep.name, i, total: episodes.length);
              String? badge;
              if (MangoEpisodeChip.isVipLabel(ep.name) ||
                  (markVipFromIndex != null && i >= markVipFromIndex!)) {
                badge = 'VIP';
              } else if (i == episodes.length - 1 && episodes.length > 1) {
                badge = '新';
              } else if (ep.name.contains('预告') ||
                  ep.name.toUpperCase().contains('PREVIEW')) {
                badge = '预';
              }
              return MangoEpisodeChip(
                label: label,
                selected: i == selected,
                cornerBadge: badge,
                width: _chipWidthFor(label),
                onTap: () => onSelect(i),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 同类型推荐：横向卡片
class MangoWatchHotspots extends StatelessWidget {
  const MangoWatchHotspots({
    super.key,
    required this.items,
    this.onTap,
    this.title = '同类型剧集',
    this.loading = false,
  });

  final List<Movie> items;
  final ValueChanged<Movie>? onTap;
  final String title;
  final bool loading;

  static String? _tagOf(Movie m) {
    final b = m.cornerBadge;
    if (b != null && b.isNotEmpty) return b;
    final r = m.remarks.trim();
    if (r.isNotEmpty && r.length <= 6) return r;
    return null;
  }

  static String _durationLabel(Movie m, int index) {
    final d = m.durationText.trim();
    if (d.isNotEmpty) return d;
    if (m.durationMinutes != null && m.durationMinutes! > 0) {
      final min = m.durationMinutes!;
      if (min >= 60) {
        return '${min ~/ 60}小时${min % 60 > 0 ? '${min % 60}分' : ''}';
      }
      return '$min分钟';
    }
    if (m.totalEpisodes > 1) return '全${m.totalEpisodes}集';
    final fake = 44 + (index * 17) % 50;
    return '00:${fake.toString().padLeft(2, '0')}';
  }

  static String _subLine(Movie m) {
    final parts = <String>[
      if (m.year > 0) '${m.year}',
      if (m.area.trim().isNotEmpty) m.area.trim(),
      if (m.genres.isNotEmpty) m.genres.first,
    ];
    if (parts.isEmpty && m.remarks.trim().isNotEmpty) {
      return m.remarks.trim();
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Row(
            children: [
              Text(
                title,
                style: _titleStyle(
                  size: MangoWatchStyle.sectionSize,
                  w: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                Text(
                  '共${items.length}部',
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 12,
                    color: Color(0xFFAAAAAA),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (loading && items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: MangoRelatedSkeleton(),
          )
        else if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 88,
              child: Center(
                child: Text(
                  '暂无推荐',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFF999999),
                  ),
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final m = items[i];
                final cover = m.coverUrl?.trim() ?? '';
                final tag = _tagOf(m);
                final score = m.score > 0 ? m.scoreLabel : null;
                final sub = _subLine(m);

                return GestureDetector(
                  onTap: () => onTap?.call(m),
                  child: SizedBox(
                    width: 168,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (cover.isNotEmpty)
                                  CmsCoverImage(
                                    url: cover,
                                    vodId: m.id,
                                    fit: BoxFit.cover,
                                  )
                                else
                                  const MediaPlaceholder(),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Color(0x88000000),
                                      ],
                                      stops: [0.5, 1],
                                    ),
                                  ),
                                ),
                                if (tag != null)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (tag.contains('热') ||
                                                tag.contains('VIP') ||
                                                tag.contains('会员'))
                                            ? MangoWatchStyle.accent
                                            : Colors.black
                                                .withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        tag,
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
                                if (score != null)
                                  Positioned(
                                    left: 6,
                                    bottom: 6,
                                    child: Text(
                                      score,
                                      style: const TextStyle(
                                        fontFamily: 'AppSans',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFFFB020),
                                        height: 1,
                                        shadows: [
                                          Shadow(
                                            color: Color(0x88000000),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Text(
                                    _durationLabel(m, i),
                                    style: const TextStyle(
                                      fontFamily: 'AppSans',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      height: 1.1,
                                      shadows: [
                                        Shadow(
                                          color: Color(0x88000000),
                                          blurRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF222222),
                            height: 1.25,
                          ),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF999999),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 底部品牌条：哇TV · www.watv.fun
class MangoWatchBrandFooter extends StatelessWidget {
  const MangoWatchBrandFooter({super.key});

  @override
  Widget build(BuildContext context) {
    const gray = Color(0xFFB0B0B0);
    Widget dot() => Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: gray.withValues(alpha: 0.7), width: 1),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 36, 16, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          dot(),
          const SizedBox(width: 14),
          const Text(
            '哇TV',
            style: TextStyle(
              fontFamily: 'ZCOOLKuaiLe',
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: gray,
              letterSpacing: 0.5,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '·',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                color: gray,
              ),
            ),
          ),
          const Text(
            'www.watv.fun',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: gray,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 14),
          dot(),
        ],
      ),
    );
  }
}

/// 播放器下方：完整剧集网格（内嵌展开，非弹窗；过多时按批切换）
class MangoEpisodeAllPanel extends StatefulWidget {
  const MangoEpisodeAllPanel({
    super.key,
    required this.episodes,
    required this.selectedEpisode,
    required this.onSelect,
    required this.onClose,
    this.intro,
    this.markVipFromIndex,
    this.bottomInset = 0,
    this.batchSize = 50,
  });

  final List<MoviePlayEpisode> episodes;
  final int selectedEpisode;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;
  final String? intro;
  final int? markVipFromIndex;
  final double bottomInset;
  final int batchSize;

  @override
  State<MangoEpisodeAllPanel> createState() => _MangoEpisodeAllPanelState();
}

class _MangoEpisodeAllPanelState extends State<MangoEpisodeAllPanel> {
  late int _batch;

  @override
  void initState() {
    super.initState();
    _batch = _batchOf(widget.selectedEpisode);
  }

  @override
  void didUpdateWidget(covariant MangoEpisodeAllPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedEpisode != widget.selectedEpisode ||
        oldWidget.episodes.length != widget.episodes.length) {
      final next = _batchOf(widget.selectedEpisode);
      if (next != _batch) setState(() => _batch = next);
    }
  }

  int _batchOf(int index) {
    if (widget.episodes.isEmpty) return 0;
    final i = index.clamp(0, widget.episodes.length - 1);
    return i ~/ widget.batchSize;
  }

  int get _start => _batch * widget.batchSize;
  int get _end {
    final e = _start + widget.batchSize;
    return e > widget.episodes.length ? widget.episodes.length : e;
  }

  @override
  Widget build(BuildContext context) {
    final tip = widget.intro?.trim() ?? '';
    final showBatches = widget.episodes.length > widget.batchSize;
    final count = _end - _start;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MangoWatchStyle.hPad,
              12,
              8,
              0,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '选集',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF181818),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: '收起',
                  icon: const Icon(
                    CupertinoIcons.xmark,
                    size: 20,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          if (tip.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MangoWatchStyle.hPad,
                0,
                MangoWatchStyle.hPad,
                6,
              ),
              child: Text(
                tip,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFF999999),
                ),
              ),
            ),
          if (showBatches)
            MangoEpisodeBatchBar(
              total: widget.episodes.length,
              batchSize: widget.batchSize,
              batchIndex: _batch,
              onChanged: (i) => setState(() => _batch = i),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(
                MangoWatchStyle.hPad,
                4,
                MangoWatchStyle.hPad,
                10,
              ),
              child: Text(
                '分集',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF666666),
                ),
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                MangoWatchStyle.hPad,
                0,
                MangoWatchStyle.hPad,
                16 + widget.bottomInset,
              ),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
              ),
              itemCount: count,
              itemBuilder: (_, local) {
                final i = _start + local;
                final ep = widget.episodes[i];
                String? badge;
                if (MangoEpisodeChip.isVipLabel(ep.name) ||
                    (widget.markVipFromIndex != null &&
                        i >= widget.markVipFromIndex!)) {
                  badge = 'VIP';
                } else if (ep.name.contains('预') ||
                    ep.name.toLowerCase().contains('preview')) {
                  badge = '预';
                } else if (i == widget.episodes.length - 1 &&
                    widget.episodes.length > 1) {
                  badge = '新';
                }
                return MangoEpisodeChip(
                  label: MangoEpisodeRow.chipLabel(
                    ep.name,
                    i,
                    total: widget.episodes.length,
                  ),
                  selected: i == widget.selectedEpisode,
                  expand: true,
                  cornerBadge: badge,
                  onTap: () => widget.onSelect(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 集数分批切换条：1-50 / 51-100 …
class MangoEpisodeBatchBar extends StatelessWidget {
  const MangoEpisodeBatchBar({
    super.key,
    required this.total,
    required this.batchSize,
    required this.batchIndex,
    required this.onChanged,
  });

  final int total;
  final int batchSize;
  final int batchIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final batches = (total + batchSize - 1) ~/ batchSize;
    if (batches <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          MangoWatchStyle.hPad,
          4,
          MangoWatchStyle.hPad,
          8,
        ),
        itemCount: batches,
        separatorBuilder: (_, _) => SizedBox(width: 8),
        itemBuilder: (context, i) {
          final start = i * batchSize + 1;
          final end = ((i + 1) * batchSize).clamp(1, total);
          final on = i == batchIndex;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? MangoWatchStyle.accent.withValues(alpha: 0.14)
                    : const Color(0xFFF3F3F5),
                borderRadius: BorderRadius.circular(16),
                border: on
                    ? Border.all(color: MangoWatchStyle.accent, width: 1)
                    : null,
              ),
              child: Text(
                '$start-$end',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? MangoWatchStyle.accent : const Color(0xFF666666),
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

/// 播放器下方：下载选集（可多选）
class MangoDownloadPickPanel extends StatefulWidget {
  const MangoDownloadPickPanel({
    super.key,
    required this.episodes,
    required this.selectedEpisode,
    required this.onClose,
    required this.onSubmit,
    this.onOpenCacheList,
    this.doneIndexes = const {},
    this.markVipFromIndex,
    this.bottomInset = 0,
  });

  final List<MoviePlayEpisode> episodes;
  final int selectedEpisode;
  final VoidCallback onClose;
  final ValueChanged<List<int>> onSubmit;
  final VoidCallback? onOpenCacheList;
  final Set<int> doneIndexes;
  final int? markVipFromIndex;
  final double bottomInset;

  @override
  State<MangoDownloadPickPanel> createState() => _MangoDownloadPickPanelState();
}

class _MangoDownloadPickPanelState extends State<MangoDownloadPickPanel> {
  late Set<int> _picked;

  @override
  void initState() {
    super.initState();
    _picked = {
      if (widget.selectedEpisode >= 0 &&
          widget.selectedEpisode < widget.episodes.length &&
          !widget.doneIndexes.contains(widget.selectedEpisode))
        widget.selectedEpisode,
    };
  }

  void _toggle(int i) {
    if (widget.doneIndexes.contains(i)) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_picked.contains(i)) {
        _picked = {..._picked}..remove(i);
      } else {
        _picked = {..._picked, i};
      }
    });
  }

  void _toggleAll() {
    HapticFeedback.selectionClick();
    final available = [
      for (var i = 0; i < widget.episodes.length; i++)
        if (!widget.doneIndexes.contains(i)) i,
    ];
    setState(() {
      if (_picked.length >= available.length) {
        _picked = {};
      } else {
        _picked = {...available};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.episodes.length - widget.doneIndexes.length;
    final allOn = available > 0 && _picked.length >= available;

    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MangoWatchStyle.hPad,
              12,
              8,
              0,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '缓存剧集',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF181818),
                    ),
                  ),
                ),
                if (widget.onOpenCacheList != null)
                  TextButton(
                    onPressed: widget.onOpenCacheList,
                    child: Text(
                      '缓存列表',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: available > 0 ? _toggleAll : null,
                  child: Text(
                    allOn ? '取消全选' : '全选',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MangoWatchStyle.accent,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(
                    CupertinoIcons.xmark,
                    size: 20,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              MangoWatchStyle.hPad,
              0,
              MangoWatchStyle.hPad,
              10,
            ),
            child: Text(
              '可多选，已缓存的集不可再选',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                color: Color(0xFF999999),
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                MangoWatchStyle.hPad,
                0,
                MangoWatchStyle.hPad,
                12,
              ),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
              ),
              itemCount: widget.episodes.length,
              itemBuilder: (_, i) {
                final ep = widget.episodes[i];
                final done = widget.doneIndexes.contains(i);
                final on = _picked.contains(i);
                String? badge;
                if (done) {
                  badge = '已存';
                } else if (MangoEpisodeChip.isVipLabel(ep.name) ||
                    (widget.markVipFromIndex != null &&
                        i >= widget.markVipFromIndex!)) {
                  badge = 'VIP';
                }
                return Opacity(
                  opacity: done ? 0.45 : 1,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      MangoEpisodeChip(
                        label: MangoEpisodeRow.chipLabel(
                          ep.name,
                          i,
                          total: widget.episodes.length,
                        ),
                        selected: on,
                        expand: true,
                        cornerBadge: badge,
                        onTap: () => _toggle(i),
                      ),
                      if (on)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            size: 16,
                            color: MangoWatchStyle.accent,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              MangoWatchStyle.hPad,
              4,
              MangoWatchStyle.hPad,
              12 + widget.bottomInset,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _picked.isEmpty
                        ? '请选择要缓存的剧集'
                        : '已选 ${_picked.length} 集',
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: Color(0xFF888888),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _picked.isEmpty
                      ? null
                      : () => widget.onSubmit(_picked.toList()..sort()),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _picked.isEmpty ? 0.45 : 1,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _picked.isEmpty
                                ? const Color(0xFFE8E8E8)
                                : AppColors.brand,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.download_rounded,
                            size: 24,
                            color: _picked.isEmpty
                                ? const Color(0xFF999999)
                                : Colors.white,
                          ),
                        ),
                        if (_picked.isNotEmpty)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 18),
                              height: 18,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.brand,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '${_picked.length}',
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
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

/// 播放页下方信息区（统一边距）
class MangoWatchPanel extends StatelessWidget {
  const MangoWatchPanel({
    super.key,
    required this.title,
    required this.sourceLine,
    required this.tabIndex,
    required this.commentCount,
    required this.onTabChanged,
    required this.episodes,
    required this.selectedEpisode,
    required this.onEpisodeSelect,
    required this.relatedMovies,
    this.onTitleTap,
    this.onSynopsisTap,
    this.onShowAllEpisodes,
    this.onFavorite,
    this.onCast,
    this.onShare,
    this.onCache,
    this.favored = false,
    this.downloadingCount = 0,
    this.cacheIconKey,
    this.onRelatedTap,
    this.commentPanel,
    this.markVipFromIndex,
    this.episodeIntro,
    this.relatedLoading = false,
    this.relatedTitle = '同类型剧集',
    this.hideChrome = false,
    this.sourceNames = const [],
    this.sourceIndex = 0,
    this.onSourceSelect,
    this.sourceProbeUrls = const [],
    this.shellLoading = false,
  });

  final String title;
  final String sourceLine;
  final int tabIndex;
  final int commentCount;
  final ValueChanged<int> onTabChanged;
  final List<MoviePlayEpisode> episodes;
  final int selectedEpisode;
  final ValueChanged<int> onEpisodeSelect;
  final List<Movie> relatedMovies;
  final VoidCallback? onTitleTap;
  final VoidCallback? onSynopsisTap;
  final VoidCallback? onShowAllEpisodes;
  final VoidCallback? onFavorite;
  final VoidCallback? onCast;
  final VoidCallback? onShare;
  final VoidCallback? onCache;
  final bool favored;
  final int downloadingCount;
  final GlobalKey? cacheIconKey;
  final ValueChanged<Movie>? onRelatedTap;
  final Widget? commentPanel;
  final int? markVipFromIndex;
  final String? episodeIntro;
  final bool relatedLoading;
  final String relatedTitle;
  final bool hideChrome;
  final List<String> sourceNames;
  final int sourceIndex;
  final ValueChanged<int>? onSourceSelect;
  final List<String> sourceProbeUrls;
  /// 详情未到：线路/选集用骨架占位
  final bool shellLoading;

  @override
  Widget build(BuildContext context) {
    final isComment = tabIndex == 1 && commentPanel != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isComment ? 10 : MangoWatchStyle.hPad,
        hideChrome ? (isComment ? 2 : 10) : (isComment ? 6 : 14),
        isComment ? 10 : MangoWatchStyle.hPad,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hideChrome) ...[
            MangoWatchHeader(
              title: title,
              sourceLine: sourceLine,
              onTitleTap: onTitleTap,
              onSynopsisTap: onSynopsisTap,
            ),
            const SizedBox(height: MangoWatchStyle.gapMetaTabs),
            MangoWatchTabs(
              index: tabIndex,
              commentCount: commentCount,
              onChanged: onTabChanged,
              onFavorite: onFavorite,
              onCast: onCast,
              onShare: onShare,
              onCache: onCache,
              favored: favored,
              downloadingCount: downloadingCount,
              cacheIconKey: cacheIconKey,
            ),
          ],
          if (tabIndex == 0) ...[
            if (!hideChrome)
              const SizedBox(height: MangoWatchStyle.gapTabsSection)
            else
              const SizedBox(height: 4),
            if (shellLoading && sourceNames.length <= 1)
              const MangoSourceSkeleton()
            else if (sourceNames.length > 1 && onSourceSelect != null)
              MangoSourceRow(
                names: sourceNames,
                selected: sourceIndex,
                onSelect: onSourceSelect!,
                probeUrls: sourceProbeUrls,
              ),
            if (shellLoading && episodes.isEmpty)
              const MangoEpisodeSkeleton()
            else if (episodes.isNotEmpty)
              MangoEpisodeRow(
                episodes: episodes,
                selected: selectedEpisode,
                onSelect: onEpisodeSelect,
                onShowAll:
                    episodes.length > 1 ? onShowAllEpisodes : null,
                markVipFromIndex: markVipFromIndex,
                intro: episodeIntro,
              ),
            MangoWatchHotspots(
              items: relatedMovies,
              onTap: onRelatedTap,
              title: relatedTitle,
              loading: relatedLoading || (shellLoading && relatedMovies.isEmpty),
            ),
            const MangoWatchBrandFooter(),
          ] else if (commentPanel != null) ...[
            const SizedBox(height: 4),
            commentPanel!,
          ],
        ],
      ),
    );
  }
}
