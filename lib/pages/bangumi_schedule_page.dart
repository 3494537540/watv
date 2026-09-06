import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../services/maccms_api.dart';
import '../theme/app_colors.dart';
import '../widgets/app_page_route.dart';
import '../widgets/figma_loading.dart';
import '../widgets/movie_poster_card.dart';
import 'movie_detail_page.dart';

/// 追番表：按周一～周日查看动漫 / 剧集更新
class BangumiSchedulePage extends StatefulWidget {
  const BangumiSchedulePage({super.key});

  @override
  State<BangumiSchedulePage> createState() => _BangumiSchedulePageState();
}

class _BangumiSchedulePageState extends State<BangumiSchedulePage> {
  static const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  final _api = MacCmsApi();
  /// weekday 1..7 → movies
  final Map<int, List<Movie>> _byDay = {};
  bool _loading = true;
  String? _error;
  late int _selectedWeekday;

  @override
  void initState() {
    super.initState();
    _selectedWeekday = DateTime.now().weekday;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final map = await _api.fetchBangumiSchedule();
      if (!mounted) return;
      setState(() {
        _byDay
          ..clear()
          ..addAll(map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<Movie> get _todayList => _byDay[_selectedWeekday] ?? const [];

  Future<void> _open(Movie m) async {
    HapticFeedback.selectionClick();
    Movie ready = m;
    try {
      if (m.playSources.isEmpty && m.playEpisodes.isEmpty) {
        ready = await _api.fetchDetail(m.id);
      }
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => MovieDetailPage(movie: ready),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = AppPalette.page(context);
    final text = AppPalette.text(context);
    final hint = AppPalette.textHint(context);
    final surface = AppPalette.surface(context);
    final line = AppPalette.line(context);
    final today = DateTime.now().weekday;

    return Scaffold(
      backgroundColor: page,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        title: Text(
          '追番表',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w800,
            fontSize: 17,
            color: text,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(CupertinoIcons.refresh, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: surface,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                for (var i = 1; i <= 7; i++) ...[
                  if (i > 1) const SizedBox(width: 6),
                  Expanded(
                    child: _WeekDayChip(
                      label: '周${_weekLabels[i - 1]}',
                      selected: _selectedWeekday == i,
                      isToday: i == today,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedWeekday = i);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: line),
          Expanded(
            child: _loading
                ? const Center(child: FigmaMetaballLoader(size: 48))
                : (_error != null && _todayList.isEmpty)
                    ? Center(
                        child: TextButton(
                          onPressed: () => unawaited(_load()),
                          child: Text(
                            '$_error\n点击重试',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              color: AppColors.brand,
                            ),
                          ),
                        ),
                      )
                    : _todayList.isEmpty
                        ? Center(
                            child: Text(
                              '本周${_weekLabels[_selectedWeekday - 1]}暂无更新',
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 14,
                                color: hint,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.brand,
                            onRefresh: _load,
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.55,
                              ),
                              itemCount: _todayList.length,
                              itemBuilder: (context, i) {
                                final m = _todayList[i];
                                return LayoutBuilder(
                                  builder: (context, c) {
                                    return MoviePosterCard(
                                      movie: m,
                                      width: c.maxWidth,
                                      onTap: () => unawaited(_open(m)),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayChip extends StatelessWidget {
  const _WeekDayChip({
    required this.label,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.brand : AppPalette.page(context);
    final fg = selected ? Colors.white : AppPalette.text(context);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (isToday) ...[
                const SizedBox(height: 2),
                Text(
                  '今',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.brand,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
