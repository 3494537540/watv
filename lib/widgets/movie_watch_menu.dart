import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../services/movie_watch_store.dart';
import '../theme/app_colors.dart';
import 'dialogx/dialogx.dart';

/// 片名/简介旁竖三点：贴着锚点弹出观影状态小菜单
class MovieWatchMoreButton extends StatelessWidget {
  const MovieWatchMoreButton({
    super.key,
    required this.movie,
    this.color = const Color(0xFFB0B0B5),
  });

  final Movie movie;
  final Color color;

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.sizeOf(context);

    final current = await MovieWatchStore.get(movie.id);
    if (!context.mounted) return;

    // 菜单贴着按钮右下，偏右对齐，避免出屏
    const menuW = 132.0;
    final left = (origin.dx + size.width - menuW).clamp(8.0, screen.width - menuW - 8);
    final top = origin.dy + size.height + 2;

    final picked = await showGeneralDialog<MovieWatchStatus>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, a1, a2) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuW,
              child: FadeTransition(
                opacity: CurvedAnimation(parent: a1, curve: Curves.easeOutCubic),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(
                    CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
                  ),
                  alignment: Alignment.topRight,
                  child: Material(
                    color: Colors.transparent,
                    child: _WatchTipCard(
                      current: current,
                      onPick: (s) => Navigator.of(ctx).pop(s),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (picked == null || !context.mounted) return;
    final next = current == picked ? MovieWatchStatus.none : picked;
    await MovieWatchStore.set(
      movie.id,
      next,
      name: movie.title,
      pic: movie.coverUrl ?? '',
    );
    if (next == MovieWatchStatus.none) {
      DialogX.showSuccess('已取消「${picked.label}」');
    } else {
      DialogX.showSuccess('已标记为「${next.label}」');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            CupertinoIcons.ellipsis_vertical,
            size: 15,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _WatchTipCard extends StatelessWidget {
  const _WatchTipCard({
    required this.current,
    required this.onPick,
  });

  final MovieWatchStatus current;
  final ValueChanged<MovieWatchStatus> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in MovieWatchStatusX.selectable)
            _WatchTipRow(
              label: s.label,
              selected: current == s,
              onTap: () => onPick(s),
            ),
        ],
      ),
    );
  }
}

class _WatchTipRow extends StatelessWidget {
  const _WatchTipRow({
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
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.brand : Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (selected)
              Icon(
                CupertinoIcons.checkmark_alt,
                size: 14,
                color: AppColors.brand,
              ),
          ],
        ),
      ),
    );
  }
}
