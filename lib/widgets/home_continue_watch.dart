import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/local_play_store.dart';
import '../theme/app_colors.dart';
import 'cms_cover_image.dart';

/// 首页右下角：上次未看完悬浮小卡（可拖、可叉）
class HomeContinueWatchCard extends StatefulWidget {
  const HomeContinueWatchCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismissed,
    this.bottomInset = 128,
  });

  final LocalPlayItem item;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  /// 需高于悬浮底栏，避免小卡被玻璃导航挡住
  final double bottomInset;

  static Future<LocalPlayItem?> loadUnfinished() async {
    final list = await LocalPlayStore.list(limit: 20);
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString(_dismissKey) ?? '';
    for (final e in list) {
      if (!_isUnfinished(e)) continue;
      final token = '${e.vodId}:${e.playedAt}';
      if (token == dismissed) continue;
      return e;
    }
    return null;
  }

  static Future<void> dismissItem(LocalPlayItem item) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissKey, '${item.vodId}:${item.playedAt}');
  }

  static const _dismissKey = 'home_continue_dismiss_v1';

  static bool _isUnfinished(LocalPlayItem e) {
    if (e.durationMs > 0) {
      return e.progress > 0.01 && e.progress < 0.96 && e.positionMs >= 1500;
    }
    // 无片长：看过一会儿或切过集，都算可续看
    return e.positionMs >= 2000 || e.episodeIndex > 0 || e.progress > 0.01;
  }

  @override
  State<HomeContinueWatchCard> createState() => _HomeContinueWatchCardState();
}

class _HomeContinueWatchCardState extends State<HomeContinueWatchCard> {
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final cardW = 168.0;
    final cardH = 64.0;
    final defaultX = size.width - cardW - 12;
    final defaultY = size.height - widget.bottomInset - cardH - pad.bottom;

    // 小窗/矮屏时上下界可能反转，clamp 会抛 ArgumentError
    double safeClamp(double v, double a, double b) {
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      if (hi <= lo) return lo;
      return v.clamp(lo, hi);
    }

    final ox = safeClamp(_offset?.dx ?? defaultX, 8.0, size.width - cardW - 8);
    final oy = safeClamp(
      _offset?.dy ?? defaultY,
      pad.top + 72,
      size.height - cardH - pad.bottom - 56,
    );

    final item = widget.item;
    final progress = item.durationMs > 0 ? item.progress : 0.35;
    final ep = item.episodeLabel.trim().isNotEmpty
        ? item.episodeLabel.trim()
        : (item.episodeIndex >= 0 ? '第${item.episodeIndex + 1}集' : '继续观看');
    final pct = item.durationMs > 0
        ? '${(item.progress * 100).clamp(1, 99).round()}%'
        : '续看';

    return Positioned(
      left: ox,
      top: oy,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerMove: (e) {
          if (e.down && e.delta != Offset.zero) {
            setState(() {
              _offset = Offset(ox + e.delta.dx, oy + e.delta.dy);
            });
          }
        },
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: Material(
          color: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: cardW,
            height: cardH,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8E8EA)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x28000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 22, 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 36,
                          height: 48,
                          child: ColoredBox(
                            color: const Color(0xFFF0F0F2),
                            child: item.pic.isEmpty
                                ? const Icon(
                                    CupertinoIcons.film,
                                    size: 16,
                                    color: Color(0xFFB0B0B0),
                                  )
                                : CmsCoverImage(
                                    url: item.pic,
                                    vodId: item.vodId,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                                height: 1.15,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '$ep · $pct',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 10,
                                color: Color(0xFF8E8E93),
                                decoration: TextDecoration.none,
                              ),
                            ),
                            SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.05, 1.0),
                                minHeight: 3,
                                backgroundColor: const Color(0xFFECECEC),
                                color: AppColors.brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onDismissed();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 18,
                        color: Color(0xFFC7C7CC),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}
