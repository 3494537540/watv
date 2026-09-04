import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../theme/app_colors.dart';
import 'media_placeholder.dart';

/// 竖版海报卡（优先展示 CMS 封面）
class MoviePosterCard extends StatelessWidget {
  const MoviePosterCard({
    super.key,
    required this.movie,
    this.width = 118,
    this.onTap,
  });

  final Movie movie;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = movie.coverUrl?.trim() ?? '';
    final sub = movie.remarks.trim().isNotEmpty
        ? movie.remarks.trim()
        : '${movie.year} · ${movie.subtitle}';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedH = constraints.maxHeight.isFinite &&
                constraints.maxHeight < double.infinity;
            final poster = DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.posterPlaceholder,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url.isNotEmpty)
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const MediaPlaceholder(
                          kind: MediaPlaceholderKind.film,
                          radius: 10,
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          // 浅色底 + 淡入，避免骨架结束仍长时间空白
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: movie.coverColor),
                              Opacity(
                                opacity: progress.expectedTotalBytes != null
                                    ? (progress.cumulativeBytesLoaded /
                                            progress.expectedTotalBytes!)
                                        .clamp(0.15, 1.0)
                                    : 0.35,
                                child: child,
                              ),
                            ],
                          );
                        },
                      )
                    else
                      const MediaPlaceholder(
                        kind: MediaPlaceholderKind.film,
                        radius: 10,
                      ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 36,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0x66000000),
                              Color(0x00000000),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (movie.score > 0)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xE6000000),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            movie.scoreLabel,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFFCC00),
                              height: 1.1,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    if (movie.remarks.isNotEmpty)
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: Text(
                          movie.remarks,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );

            final texts = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    color: AppColors.text,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    height: 1.15,
                    color: AppColors.textHint,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            );

            // Grid 等有限高场景：海报吃剩余高度，避免 BOTTOM OVERFLOW
            if (hasBoundedH) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: poster),
                  const SizedBox(height: 6),
                  texts,
                ],
              );
            }

            final posterH = width * 1.42;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: width, height: posterH, child: poster),
                const SizedBox(height: 6),
                texts,
              ],
            );
          },
        ),
      ),
    );
  }
}
