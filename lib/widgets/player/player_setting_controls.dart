import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

/// 播放器设置用开关（冰蓝强调，避免橙色）
class PlayerSettingSwitch extends StatelessWidget {
  const PlayerSettingSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.darkSurface = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool darkSurface;

  static Color get _accent => AppColors.brand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: value
              ? _accent
              : (darkSurface ? const Color(0xFF3A3A40) : const Color(0xFFE5E5EA)),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放器设置用滑条
class PlayerSettingSlider extends StatelessWidget {
  const PlayerSettingSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.label,
    this.darkSurface = false,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double> onChanged;
  final bool darkSurface;

  static Color get _accent => AppColors.brand;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: _accent,
        inactiveTrackColor:
            darkSurface ? const Color(0xFF3A3A40) : const Color(0xFFE8E8ED),
        thumbColor: Colors.white,
        overlayColor: _accent.withValues(alpha: 0.12),
        thumbShape: const _MangoThumbShape(),
        trackShape: const RoundedRectSliderTrackShape(),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        valueIndicatorColor: _accent,
        valueIndicatorTextStyle: const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
    );
  }
}

class _MangoThumbShape extends SliderComponentShape {
  const _MangoThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(18, 18);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(center, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..color = AppColors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }
}

/// 设置行：标题 + 自定义开关
class PlayerSettingSwitchRow extends StatelessWidget {
  const PlayerSettingSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.dark = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.white : const Color(0xFF181818),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 11,
                      color: dark
                          ? const Color(0xFFAAAAAA)
                          : const Color(0xFF888888),
                    ),
                  ),
                ],
              ],
            ),
          ),
          PlayerSettingSwitch(
            value: value,
            onChanged: onChanged,
            darkSurface: dark,
          ),
        ],
      ),
    );
  }
}
