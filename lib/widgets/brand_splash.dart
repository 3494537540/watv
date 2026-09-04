import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 品牌开屏：白底 + 圆角卡通「哇」+ 青色「哇TV」
class BrandSplashView extends StatelessWidget {
  const BrandSplashView({super.key});

  static const _stack = 'assets/images/splash_brand_stack.png';

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final markW = (w * 0.42).clamp(168.0, 220.0);

    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Image.asset(
          _stack,
          width: markW,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => _FallbackMark(width: markW),
        ),
      ),
    );
  }
}

class _FallbackMark extends StatelessWidget {
  const _FallbackMark({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final iconSide = width * 0.88;
    final radius = iconSide * 0.28;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.asset(
              'assets/images/splash_wa_plate.png',
              width: iconSide,
              height: iconSide,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: iconSide,
                height: iconSide,
                color: Colors.white,
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/images/app_icon_wa_cartoon.png',
                  width: iconSide,
                  height: iconSide,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: iconSide * 0.18),
        Image.asset(
          'assets/images/splash_wordmark.png',
          height: (iconSide * 0.22).clamp(28.0, 40.0),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Text(
            '哇TV',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: (iconSide * 0.28).clamp(26.0, 36.0),
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: AppColors.brand,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// 兼容旧引用
class BrandSplashGate extends StatelessWidget {
  const BrandSplashGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
