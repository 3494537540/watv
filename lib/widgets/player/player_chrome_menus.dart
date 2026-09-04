import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie_models.dart';
import '../../player/player_settings_store.dart';
import '../../player/vod_playback.dart';

import '../../theme/app_colors.dart';
const _menuBg = Color(0xF21C1C1E);
Color get _menuAccent => AppColors.brand;

RelativeRect _anchorRect(BuildContext anchor) {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(anchor).overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) {
    return const RelativeRect.fromLTRB(16, 16, 16, 16);
  }
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight =
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  // 稍微上移，让菜单盖住按钮上方
  final rect = Rect.fromPoints(
    Offset(topLeft.dx, topLeft.dy - 4),
    bottomRight,
  );
  return RelativeRect.fromRect(rect, Offset.zero & overlay.size);
}

PopupMenuItem<T> _item<T>({
  required T value,
  required String label,
  required bool selected,
}) {
  return PopupMenuItem<T>(
    value: value,
    height: 40,
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? _menuAccent : Colors.white,
            ),
          ),
        ),
        if (selected)
          Icon(CupertinoIcons.check_mark, size: 16, color: _menuAccent),
      ],
    ),
  );
}

/// 倍速：锚点小菜单
Future<double?> showChromeSpeedMenu(
  BuildContext anchor, {
  required double current,
}) {
  HapticFeedback.selectionClick();
  return showMenu<double>(
    context: anchor,
    position: _anchorRect(anchor),
    color: _menuBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    items: [
      for (final rate in VodPlayback.playbackRates)
        _item(
          value: rate,
          label: VodPlayback.rateLabel(rate),
          selected: (rate - current).abs() < 0.01,
        ),
    ],
  );
}

/// 画面比例：锚点小菜单
Future<PlayerAspectMode?> showChromeAspectMenu(
  BuildContext anchor, {
  required PlayerAspectMode current,
}) {
  HapticFeedback.selectionClick();
  return showMenu<PlayerAspectMode>(
    context: anchor,
    position: _anchorRect(anchor),
    color: _menuBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    items: [
      for (final m in PlayerAspectMode.values)
        _item(
          value: m,
          label: m.label,
          selected: m == current,
        ),
    ],
  );
}

/// 选集：锚点小面板（可滚动，不占整屏）
Future<void> showChromeEpisodeMenu({
  required BuildContext anchor,
  required List<MoviePlayEpisode> episodes,
  required int selected,
  required ValueChanged<int> onSelect,
}) async {
  HapticFeedback.selectionClick();
  final box = anchor.findRenderObject() as RenderBox?;
  final overlayBox =
      Navigator.of(anchor).overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlayBox == null) return;

  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final btnSize = box.size;
  final screen = overlayBox.size;
  final menuW = (screen.width * 0.42).clamp(200.0, 280.0);
  final menuH = (screen.height * 0.52).clamp(180.0, 300.0);
  var left = topLeft.dx + btnSize.width - menuW;
  var top = topLeft.dy - menuH - 8;
  if (left < 8) left = 8;
  if (left + menuW > screen.width - 8) left = screen.width - menuW - 8;
  if (top < 8) top = topLeft.dy + btnSize.height + 8;
  if (top + menuH > screen.height - 8) {
    top = (screen.height - menuH - 8).clamp(8.0, screen.height);
  }

  await showGeneralDialog<void>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: '关闭选集',
    barrierColor: const Color(0x55000000),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, anim, _) {
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: menuW,
            height: menuH,
            child: FadeTransition(
              opacity: anim,
              child: Material(
                color: _menuBg,
                elevation: 10,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Text(
                        '选集',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1.35,
                        ),
                        itemCount: episodes.length,
                        itemBuilder: (_, i) {
                          final on = i == selected;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(ctx);
                              onSelect(i);
                            },
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: on
                                    ? _menuAccent.withValues(alpha: 0.22)
                                    : const Color(0xFF2A2A2E),
                                borderRadius: BorderRadius.circular(6),
                                border: on
                                    ? Border.all(color: _menuAccent, width: 1.2)
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  episodes[i].name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: on
                                        ? _menuAccent
                                        : const Color(0xFFCCCCCC),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
