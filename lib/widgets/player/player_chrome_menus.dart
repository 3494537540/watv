import 'dart:async';

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

/// 清晰度：锚点小菜单（有多档才列档位；单档提示换线路）
Future<Object?> showChromeQualityMenu(
  BuildContext anchor, {
  required VodQualityTier prefer,
  required List<VodHlsVariant> variants,
  VodHlsVariant? current,
  List<String> sourceNames = const [],
  int sourceIndex = 0,
}) {
  HapticFeedback.selectionClick();
  final items = <PopupMenuEntry<Object>>[];
  final multi = variants.length > 1;

  if (multi) {
    items.add(
      _item<Object>(
        value: VodQualityTier.auto,
        label: VodQualityTier.auto.label,
        selected: prefer == VodQualityTier.auto,
      ),
    );
    // 标准档位入口（含 1080），再按实际流列一遍，避免只显示当前低档
    const tiers = [
      VodQualityTier.q1080,
      VodQualityTier.q720,
      VodQualityTier.q480,
      VodQualityTier.q360,
    ];
    final seenUrls = <String>{};
    for (final tier in tiers) {
      final match = VodPlayback.pickVariant(variants, tier);
      if (match == null) continue;
      // 该档在片源里确实够高才展示（避免 480 源冒充 1080）
      if (match.height + 40 < tier.minHeight && match.tier != tier) continue;
      if (!seenUrls.add(match.url)) continue;
      items.add(
        _item<Object>(
          value: tier,
          label: tier.label,
          selected: prefer == tier ||
              (prefer != VodQualityTier.auto && current?.url == match.url),
        ),
      );
    }
    for (final v in [...variants].reversed) {
      if (seenUrls.contains(v.url)) continue;
      items.add(
        _item<Object>(
          value: v,
          label: v.label,
          selected: current?.url == v.url && prefer != VodQualityTier.auto,
        ),
      );
    }
  } else {
    final sole = current ?? (variants.isNotEmpty ? variants.first : null);
    final label = sole?.shortLabel ?? '原画';
    items.add(
      _item<Object>(
        value: '_sole',
        label: '$label（当前线路）',
        selected: true,
      ),
    );
    if (sourceNames.length > 1) {
      items.add(const PopupMenuDivider(height: 8));
      for (var i = 0; i < sourceNames.length; i++) {
        final name = sourceNames[i].trim().isEmpty ? '线路${i + 1}' : sourceNames[i];
        items.add(
          _item<Object>(
            value: '_src:$i',
            label: name,
            selected: i == sourceIndex,
          ),
        );
      }
    }
  }

  return showMenu<Object>(
    context: anchor,
    position: _anchorRect(anchor),
    color: _menuBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    items: items,
  );
}

/// 线路：锚点小菜单（与倍速/清晰度同风格）
Future<int?> showChromeSourceMenu(
  BuildContext anchor, {
  required List<String> names,
  required int selected,
  List<String> probeUrls = const [],
}) {
  HapticFeedback.selectionClick();
  if (names.isEmpty) return Future.value(null);
  // probeUrls 留给侧栏测速页；此处保持秒开
  return showMenu<int>(
    context: anchor,
    position: _anchorRect(anchor),
    color: _menuBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    items: [
      for (var i = 0; i < names.length; i++)
        _item<int>(
          value: i,
          label: names[i].trim().isEmpty ? '线路${i + 1}' : names[i].trim(),
          selected: i == selected,
        ),
    ],
  );
}

/// 跳过片头片尾：锚点小菜单
Future<String?> showChromeSkipMenu(
  BuildContext anchor, {
  required bool enabled,
  required int introSec,
  required int outroSec,
}) {
  HapticFeedback.selectionClick();
  return showMenu<String>(
    context: anchor,
    position: _anchorRect(anchor),
    color: _menuBg,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    items: [
      _item(
        value: 'toggle',
        label: enabled ? '跳过：开（点关）' : '跳过：关（点开）',
        selected: enabled,
      ),
      _item(
        value: 'intro',
        label: introSec > 0 ? '将当前位置设为片头（现 ${introSec}s）' : '将当前位置设为片头结束',
        selected: false,
      ),
      _item(
        value: 'outro',
        label: outroSec > 0 ? '将当前位置设为片尾（现 ${outroSec}s）' : '将当前位置设为片尾开始',
        selected: false,
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
