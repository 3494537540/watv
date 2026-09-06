import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/theme_controller.dart';
import '../theme/app_colors.dart';
import 'figma_loading.dart';

typedef AnchoredChoice = ({
  String label,
  String? subtitle,
  bool selected,
  VoidCallback onPick,
  Widget? leading,
});

/// 外观/动效：底部弹窗（贴底、左右下无大留白）
Future<void> showAnchoredChoiceMenu(
  BuildContext anchor, {
  required List<AnchoredChoice> Function() buildOptions,
  Widget? Function(BuildContext context)? previewBuilder,
  bool applyAndClose = true,
  double menuWidth = 300, // 兼容旧参数，底部弹窗忽略
}) {
  return showChoiceBottomSheet(
    anchor,
    buildOptions: buildOptions,
    previewBuilder: previewBuilder,
    applyAndClose: applyAndClose,
  );
}

Future<void> showChoiceBottomSheet(
  BuildContext context, {
  required List<AnchoredChoice> Function() buildOptions,
  Widget? Function(BuildContext context)? previewBuilder,
  bool applyAndClose = true,
}) async {
  HapticFeedback.selectionClick();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (ctx) {
      return _ChoiceBottomSheet(
        buildOptions: buildOptions,
        previewBuilder: previewBuilder,
        applyAndClose: applyAndClose,
      );
    },
  );
}

class _ChoiceBottomSheet extends StatefulWidget {
  const _ChoiceBottomSheet({
    required this.buildOptions,
    required this.applyAndClose,
    this.previewBuilder,
  });

  final List<AnchoredChoice> Function() buildOptions;
  final Widget? Function(BuildContext context)? previewBuilder;
  final bool applyAndClose;

  @override
  State<_ChoiceBottomSheet> createState() => _ChoiceBottomSheetState();
}

class _ChoiceBottomSheetState extends State<_ChoiceBottomSheet> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onTheme);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onTheme);
    super.dispose();
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    final page = dark ? const Color(0xFF1C1C1E) : Colors.white;
    final text = dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E);
    final hint = dark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
    final line = dark ? const Color(0x14FFFFFF) : const Color(0x12000000);
    final soft = dark ? const Color(0xFF2C2C2E) : const Color(0xFFF4F5F7);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final options = widget.buildOptions();
    final preview = widget.previewBuilder?.call(context);

    return Material(
      color: page,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // 贴底：仅保留安全区，左右紧凑
        padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: hint.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              preview,
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.52,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < options.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 14,
                            endIndent: 14,
                            color: line,
                          ),
                        _ChoiceRow(
                          option: options[i],
                          text: text,
                          hint: hint,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            options[i].onPick();
                            if (widget.applyAndClose) {
                              Navigator.of(context).maybePop();
                            } else {
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.option,
    required this.text,
    required this.hint,
    required this.onTap,
  });

  final AnchoredChoice option;
  final Color text;
  final Color hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedBg = option.selected
        ? AppColors.brand.withValues(alpha: 0.10)
        : Colors.transparent;

    return Material(
      color: selectedBg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              if (option.leading != null) ...[
                SizedBox(
                  width: 40,
                  height: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.surface(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: option.leading,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: text,
                      ),
                    ),
                    if (option.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        option.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: hint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (option.selected)
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                )
              else
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hint.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MotionPreviewPane extends StatefulWidget {
  const MotionPreviewPane({
    super.key,
    required this.enabled,
    required this.transition,
    required this.speed,
    this.compact = false,
  });

  final bool enabled;
  final AppPageTransition transition;
  final AppMotionSpeed speed;
  final bool compact;

  @override
  State<MotionPreviewPane> createState() => _MotionPreviewPaneState();
}

class _MotionPreviewPaneState extends State<MotionPreviewPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
    _replay();
  }

  @override
  void didUpdateWidget(covariant MotionPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transition != widget.transition ||
        oldWidget.speed != widget.speed ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.compact != widget.compact) {
      _replay();
    }
  }

  void _replay() {
    final ms = widget.enabled
        ? (420 * widget.speed.factor).round().clamp(180, 700)
        : 1;
    _c.duration = Duration(milliseconds: ms);
    if (widget.compact && widget.enabled) {
      _c.repeat(reverse: true);
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final soft = AppPalette.softFill(context);
    if (widget.compact) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_c.value);
              return _buildAnimated(t, child!);
            },
            child: Container(
              width: 28,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Text(
          '预览 · ${widget.enabled ? widget.transition.label : '已关闭'}',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppPalette.textHint(context),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(_c.value);
                  return _buildAnimated(t, child!);
                },
                child: Container(
                  width: 88,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '哇TV',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimated(double t, Widget child) {
    if (!widget.enabled || widget.transition == AppPageTransition.none) {
      return child;
    }
    switch (widget.transition) {
      case AppPageTransition.fade:
        return Opacity(opacity: t.clamp(0.0, 1.0), child: child);
      case AppPageTransition.zoom:
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.82 + 0.18 * t, child: child),
        );
      case AppPageTransition.slideUp:
        return Transform.translate(
          offset: Offset(0, 28 * (1 - t)),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        );
      case AppPageTransition.slide:
      case AppPageTransition.cupertino:
        return Transform.translate(
          offset: Offset(36 * (1 - t), 0),
          child: Opacity(
            opacity: (0.4 + 0.6 * t).clamp(0.0, 1.0),
            child: child,
          ),
        );
      case AppPageTransition.none:
        return child;
    }
  }
}

class LoadingPreviewPane extends StatelessWidget {
  const LoadingPreviewPane({super.key});

  @override
  Widget build(BuildContext context) {
    final soft = AppPalette.softFill(context);
    return Column(
      children: [
        Text(
          '预览',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppPalette.textHint(context),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          height: 84,
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: ListenableBuilder(
            listenable: ThemeController.instance,
            builder: (_, _) => AppLoadingIndicator(
              size: 48,
              color: AppColors.brand,
              style: ThemeController.instance.loadingStyle,
            ),
          ),
        ),
      ],
    );
  }
}
