import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/movie_models.dart';
import '../../player/player_danmaku_prefs.dart';
import '../../player/player_skip_store.dart';
import '../../player/vod_playback.dart';

import '../../theme/app_colors.dart';
/// 选集面板：竖屏底部小卡片；横屏右侧窄抽屉
Future<void> showPlayerEpisodeSheet({
  required BuildContext context,
  required List<MoviePlayEpisode> episodes,
  required int selected,
  required ValueChanged<int> onSelect,
}) {
  final size = MediaQuery.sizeOf(context);
  final landscape = size.width > size.height;

  if (landscape) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭选集',
      barrierColor: const Color(0x66000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, _) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: const Color(0xF2161618),
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
            child: SizedBox(
              width: (size.width * 0.34).clamp(200.0, 280.0),
              height: size.height,
              child: _EpisodeGrid(
                episodes: episodes,
                selected: selected,
                onSelect: onSelect,
                dark: true,
                crossAxisCount: 4,
                compact: true,
              ),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _EpisodeGrid(
            episodes: episodes,
            selected: selected,
            onSelect: onSelect,
            dark: false,
            crossAxisCount: 5,
            compact: false,
          ),
        ),
      );
    },
  );
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.episodes,
    required this.selected,
    required this.onSelect,
    required this.dark,
    required this.crossAxisCount,
    required this.compact,
  });

  final List<MoviePlayEpisode> episodes;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool dark;
  final int crossAxisCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brand;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 0, compact ? 12 : 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '选集',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: compact ? 15 : 17,
                fontWeight: FontWeight.w800,
                color: dark ? Colors.white : const Color(0xFF181818),
              ),
            ),
          ),
          if (compact)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                CupertinoIcons.xmark,
                color: Colors.white70,
                size: 18,
              ),
            ),
        ],
      ),
    );

    final grid = GridView.builder(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 0,
        0,
        compact ? 10 : 0,
        compact ? 12 : 0,
      ),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: compact ? 6 : 10,
        crossAxisSpacing: compact ? 6 : 10,
        childAspectRatio: compact ? 1.35 : 1.1,
      ),
      itemCount: episodes.length,
      itemBuilder: (_, i) {
        final on = i == selected;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.pop(context);
            onSelect(i);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? (on
                      ? accent.withValues(alpha: 0.22)
                      : const Color(0xFF2A2A2E))
                  : const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(6),
              border: on ? Border.all(color: accent, width: 1.2) : null,
            ),
            child: Center(
              child: Text(
                episodes[i].name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: on
                      ? accent
                      : (dark
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF6B6B6B)),
                ),
              ),
            ),
          ),
        );
      },
    );

    // 横屏侧栏：固定高度用 Expanded；竖屏底栏：内容自适应
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(child: grid),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.45,
          child: grid,
        ),
      ],
    );
  }
}

/// 线路切换面板
Future<void> showPlayerSourceSheet({
  required BuildContext context,
  required List<String> names,
  required int selected,
  required ValueChanged<int> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '播放线路',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '点哪条播哪条；卡顿或模糊可换一条试试',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  color: Color(0xFF888888),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: names.length,
                itemBuilder: (_, i) {
                  final raw = names[i].trim();
                  final title = raw.isEmpty ? '线路${i + 1}' : raw;
                  final on = i == selected;
                  return ListTile(
                    title: Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                        color: on ? const Color(0xFF111111) : const Color(0xFF333333),
                      ),
                    ),
                    subtitle: Text(
                      '线路 ${i + 1}',
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFF999999),
                      ),
                    ),
                    trailing: on
                        ? const Icon(CupertinoIcons.check_mark, size: 18)
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(ctx);
                      onSelect(i);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 更多菜单（倍速 / 片头片尾 / 线路 / 选集等）
Future<void> showPlayerMoreSheet({
  required BuildContext context,
  required List<PlayerMoreAction> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '播放设置',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final a in actions)
              ListTile(
                leading: Icon(
                  a.icon,
                  color: a.highlight ? AppColors.brand : const Color(0xFF555555),
                ),
                title: Text(
                  a.title,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: a.subtitle != null
                    ? Text(
                        a.subtitle!,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          color: a.highlight
                              ? AppColors.brand
                              : const Color(0xFF999999),
                        ),
                      )
                    : null,
                trailing: const Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: Color(0xFFCCCCCC),
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(ctx);
                  a.onTap();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

class PlayerMoreAction {
  const PlayerMoreAction({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.highlight = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
}

/// 倍速面板
Future<double?> showPlayerSpeedSheet(
  BuildContext context,
  double current,
) {
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '播放倍速',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final rate in VodPlayback.playbackRates)
              ListTile(
                title: Text(
                  VodPlayback.rateLabel(rate),
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontWeight:
                        rate == current ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                trailing: rate == current
                    ? const Icon(CupertinoIcons.check_mark, size: 18)
                    : null,
                onTap: () => Navigator.pop(ctx, rate),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 跳过片头片尾设置
Future<void> showPlayerSkipSheet(BuildContext context) async {
  var prefs = await PlayerSkipStore.load();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '跳过片头片尾',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '自动跳过',
                      style: TextStyle(fontFamily: 'AppSans', fontSize: 15),
                    ),
                    subtitle: Text(
                      '开播跳过片头，临近片尾自动下一集',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFF999999),
                      ),
                    ),
                    value: prefs.enabled,
                    activeTrackColor: AppColors.brand,
                    onChanged: (v) {
                      setModalState(() => prefs = prefs.copyWith(enabled: v));
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '片头时长',
                      style: TextStyle(fontFamily: 'AppSans', fontSize: 14),
                    ),
                    subtitle: Slider(
                      value: prefs.introSeconds.toDouble(),
                      min: 0,
                      max: 300,
                      divisions: 30,
                      label: '${prefs.introSeconds}秒',
                      activeColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(introSeconds: v.round()),
                        );
                      },
                    ),
                    trailing: Text(
                      '${prefs.introSeconds}s',
                      style: const TextStyle(fontFamily: 'AppSans'),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '片尾时长',
                      style: TextStyle(fontFamily: 'AppSans', fontSize: 14),
                    ),
                    subtitle: Slider(
                      value: prefs.outroSeconds.toDouble(),
                      min: 0,
                      max: 300,
                      divisions: 30,
                      label: '${prefs.outroSeconds}秒',
                      activeColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(outroSeconds: v.round()),
                        );
                      },
                    ),
                    trailing: Text(
                      '${prefs.outroSeconds}s',
                      style: const TextStyle(fontFamily: 'AppSans'),
                    ),
                  ),
                  SizedBox(height: 8),
                  FilledButton(
                    onPressed: () async {
                      await PlayerSkipStore.save(prefs);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                    ),
                    child: const Text(
                      '保存',
                      style: TextStyle(fontFamily: 'AppSans'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 弹幕显示设置
Future<DanmakuDisplayPrefs?> showPlayerDanmakuSettingsSheet(
  BuildContext context,
) async {
  var prefs = await PlayerDanmakuPrefs.load();
  if (!context.mounted) return null;

  return showModalBottomSheet<DanmakuDisplayPrefs>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Widget sectionTitle(String t) => Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(
                  t,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF888888),
                  ),
                ),
              );

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '弹幕设置',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '显示弹幕',
                        style: TextStyle(fontFamily: 'AppSans', fontSize: 15),
                      ),
                      value: prefs.enabled,
                      activeTrackColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(enabled: v),
                        );
                      },
                    ),
                    sectionTitle('显示区域'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final a in DanmakuArea.values)
                          ChoiceChip(
                            label: Text(
                              switch (a) {
                                DanmakuArea.top => '上方',
                                DanmakuArea.full => '全屏',
                                DanmakuArea.bottom => '下方',
                              },
                              style: const TextStyle(fontFamily: 'AppSans'),
                            ),
                            selected: prefs.area == a,
                            selectedColor: AppColors.brand.withValues(alpha: 0.25),
                            onSelected: (_) {
                              setModalState(
                                () => prefs = prefs.copyWith(area: a),
                              );
                            },
                          ),
                      ],
                    ),
                    sectionTitle('字体大小  ${prefs.fontSize.round()}'),
                    Slider(
                      value: prefs.fontSize,
                      min: 12,
                      max: 26,
                      divisions: 14,
                      label: '${prefs.fontSize.round()}',
                      activeColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(fontSize: v),
                        );
                      },
                    ),
                    sectionTitle(
                      '不透明度  ${(prefs.opacity * 100).round()}%',
                    ),
                    Slider(
                      value: prefs.opacity,
                      min: 0.2,
                      max: 1,
                      divisions: 16,
                      activeColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(opacity: v),
                        );
                      },
                    ),
                    sectionTitle(
                      '滚动速度  ${prefs.speed.toStringAsFixed(1)}x',
                    ),
                    Slider(
                      value: prefs.speed,
                      min: 0.5,
                      max: 2,
                      divisions: 15,
                      activeColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(speed: v),
                        );
                      },
                    ),
                    sectionTitle(
                      '弹幕密度  ${prefs.density.toStringAsFixed(1)}x',
                    ),
                    Slider(
                      value: prefs.density,
                      min: 0.4,
                      max: 1.5,
                      divisions: 11,
                      activeColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(density: v),
                        );
                      },
                    ),
                    sectionTitle(
                      '时间轴校准  ${prefs.timeOffsetSec >= 0 ? '+' : ''}'
                      '${prefs.timeOffsetSec.toStringAsFixed(1)}s',
                    ),
                    Text(
                      '弹幕比画面早出现就往右调（延后）；比画面晚出现就往左调',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 11,
                        color: Color(0xFF999999),
                      ),
                    ),
                    Slider(
                      value: prefs.timeOffsetSec,
                      min: -15,
                      max: 15,
                      divisions: 60,
                      activeColor: AppColors.brand,
                      onChanged: (v) {
                        setModalState(
                          () => prefs = prefs.copyWith(timeOffsetSec: v),
                        );
                      },
                    ),
                    SizedBox(height: 8),
                    FilledButton(
                      onPressed: () async {
                        await PlayerDanmakuPrefs.save(prefs);
                        if (ctx.mounted) Navigator.pop(ctx, prefs);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                      ),
                      child: const Text(
                        '保存',
                        style: TextStyle(fontFamily: 'AppSans'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// 发送弹幕结果
class DanmakuDraft {
  const DanmakuDraft({required this.text, required this.color});
  final String text;
  final int color;
}

/// 发送弹幕：横屏右侧侧栏；竖屏底部面板（避开键盘溢出）
Future<DanmakuDraft?> showSendDanmakuSheet(
  BuildContext context, {
  required double timeSec,
}) {
  final size = MediaQuery.sizeOf(context);
  final landscape = size.width > size.height;

  if (landscape) {
    return showGeneralDialog<DanmakuDraft>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭发弹幕',
      barrierColor: const Color(0x66000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim, _) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: const Color(0xF2161618),
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(12)),
            child: SizedBox(
              width: (size.width * 0.42).clamp(260.0, 360.0),
              height: size.height,
              child: _SendDanmakuForm(
                timeSec: timeSec,
                dark: true,
              ),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<DanmakuDraft>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: _SendDanmakuForm(timeSec: timeSec, dark: false),
        ),
      );
    },
  );
}

class _SendDanmakuForm extends StatefulWidget {
  const _SendDanmakuForm({
    required this.timeSec,
    required this.dark,
  });

  final double timeSec;
  final bool dark;

  @override
  State<_SendDanmakuForm> createState() => _SendDanmakuFormState();
}

class _SendDanmakuFormState extends State<_SendDanmakuForm> {
  final _ctrl = TextEditingController();
  var _color = 0xFFFFFFFF;

  static const _colors = <int>[
    0xFFFFFFFF,
    0xFFFFD54F,
    0xFF81D4FA,
    0xFFA5D6A7,
    0xFFE57373,
    0xFFFF8A65,
    0xFFCE93D8,
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, DanmakuDraft(text: t, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final ink = dark ? Colors.white : const Color(0xFF181818);
    final muted = dark ? const Color(0xFF8E8E93) : Colors.grey.shade400;
    final fieldFill = dark ? const Color(0xFF2A2A2E) : const Color(0xFFF5F5F7);
    final titleTime = _fmtDanmakuTime(widget.timeSec);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '发送弹幕 · $titleTime',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: dark ? 15 : 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ),
            if (dark)
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  CupertinoIcons.xmark,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
          ],
        ),
        SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 40,
          maxLines: dark ? 3 : 1,
          style: TextStyle(
            fontFamily: 'AppSans',
            color: _color == 0xFFFFFFFF && !dark
                ? const Color(0xFF181818)
                : Color(_color),
            fontWeight: FontWeight.w600,
          ),
          cursorColor: AppColors.brand,
          decoration: InputDecoration(
            hintText: '说点什么…',
            hintStyle: TextStyle(fontFamily: 'AppSans', color: muted),
            counterText: '',
            filled: true,
            fillColor: fieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        SizedBox(height: 12),
        Text(
          '颜色',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _colors)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(c == 0xFFFFFFFF ? 0xFFF2F2F2 : c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c
                          ? AppColors.brand
                          : (dark
                              ? const Color(0xFF3A3A3E)
                              : const Color(0xFFDDDDDD)),
                      width: _color == c ? 2 : 1,
                    ),
                  ),
                  child: c == 0xFFFFFFFF
                      ? Center(
                          child: Text(
                            'A',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: dark
                                  ? const Color(0xFF181818)
                                  : const Color(0xFF181818),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ),
        SizedBox(height: 16),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            minimumSize: const Size.fromHeight(44),
          ),
          child: const Text(
            '发送',
            style: TextStyle(fontFamily: 'AppSans'),
          ),
        ),
      ],
    );

    if (dark) {
      final inset = MediaQuery.viewInsetsOf(context);
      return Padding(
        padding: EdgeInsets.only(bottom: inset.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 16),
          child: body,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: body,
    );
  }
}

String _fmtDanmakuTime(double sec) {
  final d = Duration(milliseconds: (sec * 1000).round());
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
