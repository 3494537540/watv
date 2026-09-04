import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../theme/app_colors.dart';
import 'movie_poster_card.dart';

/// 分区标题 + 横向海报列表
class MovieSectionRow extends StatelessWidget {
  const MovieSectionRow({
    super.key,
    required this.section,
    this.onMovieTap,
    this.onSeeAll,
  });

  final MovieSection section;
  final ValueChanged<Movie>? onMovieTap;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: AppColors.text,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSeeAll?.call();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '全部',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.iosBlue,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          CupertinoIcons.chevron_forward,
                          size: 14,
                          color: AppColors.iosBlue,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 118 * 1.42 + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: section.movies.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final m = section.movies[i];
              return MoviePosterCard(
                movie: m,
                onTap: () => onMovieTap?.call(m),
              );
            },
          ),
        ),
      ],
    );
  }
}
