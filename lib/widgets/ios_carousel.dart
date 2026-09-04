import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 轮播条目（iOS App Store Today 卡风格）
class IosCarouselItem {
  const IosCarouselItem({
    required this.title,
    required this.subtitle,
    required this.background,
    this.eyebrow = '精选',
    this.icon = CupertinoIcons.sparkles,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Color background;
  final IconData icon;
}

/// iOS 风格轮播：分页吸附、侧缘预览、页面指示点、自动播放（手势优先）
class IosCarousel extends StatefulWidget {
  const IosCarousel({
    super.key,
    required this.items,
    this.height = 420,
    this.autoPlay = true,
    this.autoPlayInterval = const Duration(seconds: 4),
    this.onTap,
  });

  final List<IosCarouselItem> items;
  final double height;
  final bool autoPlay;
  final Duration autoPlayInterval;
  final ValueChanged<int>? onTap;

  @override
  State<IosCarousel> createState() => _IosCarouselState();
}

class _IosCarouselState extends State<IosCarousel> {
  late final PageController _controller;
  int _index = 0;
  Timer? _timer;
  bool _userInteracting = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
    _restartAutoPlay();
  }

  @override
  void didUpdateWidget(covariant IosCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.autoPlayInterval != widget.autoPlayInterval ||
        oldWidget.items.length != widget.items.length) {
      _restartAutoPlay();
    }
  }

  void _restartAutoPlay() {
    _timer?.cancel();
    if (!widget.autoPlay || widget.items.length < 2) return;
    _timer = Timer.periodic(widget.autoPlayInterval, (_) {
      if (!mounted || _userInteracting || !_controller.hasClients) return;
      final next = (_index + 1) % widget.items.length;
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

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _userInteracting = true;
              } else if (n is ScrollEndNotification) {
                _userInteracting = false;
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              physics: const BouncingScrollPhysics(
                parent: PageScrollPhysics(),
              ),
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _index = i);
              },
              itemBuilder: (context, i) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    var scale = 1.0;
                    if (_controller.position.haveDimensions) {
                      final page = _controller.page ?? _index.toDouble();
                      final dist = (page - i).abs().clamp(0.0, 1.0);
                      scale = 1.0 - (dist * 0.04);
                    }
                    return Transform.scale(
                      scale: scale,
                      alignment: Alignment.center,
                      child: child,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _CarouselCard(
                      item: widget.items[i],
                      onTap: () => widget.onTap?.call(i),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        _IosPageControl(
          count: widget.items.length,
          index: _index,
          onDotTap: (i) {
            _controller.animateToPage(
              i,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
            );
          },
        ),
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.item, this.onTap});

  final IosCarouselItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: item.background,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 轻纹理：避免纯色死板，但仍是单色体系（无营销渐变）
              Positioned(
                right: -40,
                top: -30,
                child: Icon(
                  item.icon,
                  size: 220,
                  color: const Color(0x22FFFFFF),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.eyebrow.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: Color(0xCCFFFFFF),
                      ),
                    ),
                    const Spacer(),
                    Icon(item.icon, size: 36, color: Colors.white),
                    const SizedBox(height: 12),
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        color: Color(0xE6FFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UIPageControl 风格：当前点略宽
class _IosPageControl extends StatelessWidget {
  const _IosPageControl({
    required this.count,
    required this.index,
    this.onDotTap,
  });

  final int count;
  final int index;
  final ValueChanged<int>? onDotTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onDotTap?.call(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: i == index ? 16 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == index
                      ? AppColors.iosBlue
                      : const Color(0x4D3C3C43),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
