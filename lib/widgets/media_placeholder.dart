import 'package:flutter/material.dart';

import 'figma_loading.dart';

/// 封面/海报未加载或失败时的占位图
enum MediaPlaceholderKind {
  /// 影视海报（竖图）
  film,
  /// 横图 / 通用
  image,
}

class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({
    super.key,
    this.kind = MediaPlaceholderKind.film,
    this.radius = 0,
  });

  final MediaPlaceholderKind kind;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final iconSize = kind == MediaPlaceholderKind.film ? 36.0 : 40.0;
    return FigmaCoverPlaceholder(iconSize: iconSize, radius: radius);
  }
}

/// 加载中：骨架呼吸 + 山峰占位
class MediaLoadingPlaceholder extends StatelessWidget {
  const MediaLoadingPlaceholder({
    super.key,
    this.kind = MediaPlaceholderKind.film,
    this.radius = 0,
  });

  final MediaPlaceholderKind kind;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return FigmaSkeletonPulse(
      child: MediaPlaceholder(kind: kind, radius: radius),
    );
  }
}
