import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../widgets/player/mango_watch_panel.dart';
import 'movie_detail_page.dart';
import '../widgets/app_page_route.dart';

/// 全屏选集（对齐芒果 6 列网格；间距与播放器芯片一致）
class EpisodeListPage extends StatelessWidget {
  const EpisodeListPage({
    super.key,
    required this.movie,
    this.selectedIndex = 0,
  });

  final Movie movie;
  final int selectedIndex;

  static const _vipFromRatio = 0.35;

  @override
  Widget build(BuildContext context) {
    final eps = movie.playEpisodes.isNotEmpty
        ? movie.playEpisodes
        : [
            for (var i = 0; i < movie.episodeLabels.length; i++)
              MoviePlayEpisode(
                name: movie.episodeLabels[i],
                url: '',
              ),
          ];
    final vipFrom = (eps.length * _vipFromRatio).floor().clamp(0, eps.length);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(CupertinoIcons.back, color: Color(0xFF1A1A1A)),
        ),
        title: Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        centerTitle: true,
      ),
      body: GridView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          MangoWatchStyle.hPad,
          8,
          MangoWatchStyle.hPad,
          32,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          mainAxisSpacing: MangoWatchStyle.chipGap,
          crossAxisSpacing: MangoWatchStyle.chipGap,
          childAspectRatio: 1,
        ),
        itemCount: eps.length,
        itemBuilder: (context, i) {
          final name = eps[i].name;
          String? badge;
          if (MangoEpisodeChip.isVipLabel(name) || i >= vipFrom) {
            badge = 'VIP';
          } else if (i > 0 && i < vipFrom) {
            badge = '限免';
          }
          final label = MangoEpisodeRow.chipLabel(
            name,
            i,
            total: eps.length,
          );
          return MangoEpisodeChip(
            label: label,
            selected: i == selectedIndex,
            expand: true,
            cornerBadge: badge,
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pushReplacement(
                AppPageRoute<void>(
                  builder: (_) => MovieDetailPage(
                    movie: movie,
                    autoPlay: true,
                    initialEpisodeIndex: i,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
