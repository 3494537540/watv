import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../theme/app_colors.dart';

/// 产品导览锚点注册表（首次进入高亮真实控件）
class TourRegistry {
  TourRegistry._();
  static final Map<String, GlobalKey> _keys = {};

  static GlobalKey keyOf(String id) =>
      _keys.putIfAbsent(id, GlobalKey.new);

  static Rect? rectOf(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }
}

/// 包一层即可成为导览目标
class TourTarget extends StatelessWidget {
  const TourTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: TourRegistry.keyOf(id), child: child);
  }
}

class ProductTourStep {
  const ProductTourStep({
    required this.targetId,
    required this.title,
    required this.body,
    this.preferBelow = true,
  });

  final String targetId;
  final String title;
  final String body;
  final bool preferBelow;
}

/// 首次进入：遮罩高亮 + 气泡步骤（非整页翻页）
class AppOnboardingGate extends StatefulWidget {
  const AppOnboardingGate({super.key, required this.child});

  final Widget child;

  static const prefsKey = 'watv_product_tour_done_v3';

  /// 设置里点「重新导览」时递增，触发当前 Gate 立刻重开
  static final ValueNotifier<int> restartTick = ValueNotifier(0);

  static Future<bool> isDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(prefsKey) ?? false;
  }

  static Future<void> markDone() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefsKey, true);
  }

  /// 清除完成标记并立刻重开导览（若 Gate 已在树上）
  static Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(prefsKey);
    restartTick.value++;
  }

  @override
  State<AppOnboardingGate> createState() => _AppOnboardingGateState();
}

class _AppOnboardingGateState extends State<AppOnboardingGate> {
  bool _showTour = false;

  static const steps = <ProductTourStep>[
    ProductTourStep(
      targetId: 'tour_search',
      title: '搜索影片',
      body: '输入片名或演员即可搜索；橙色「热榜」可看当下热门。',
      preferBelow: true,
    ),
    ProductTourStep(
      targetId: 'tour_tabs',
      title: '频道分类',
      body: '左右滑动切换推荐、电影、剧集、综艺、动漫等频道。',
      preferBelow: true,
    ),
    ProductTourStep(
      targetId: 'tour_quick',
      title: '快捷功能',
      body: '片库筛选、榜单、会员与福利入口都在这里。',
      preferBelow: true,
    ),
    ProductTourStep(
      targetId: 'tour_feed',
      title: '发现好片',
      body: '下滑浏览热门海报，点一下就能进详情播放。',
      preferBelow: false,
    ),
    ProductTourStep(
      targetId: 'tour_nav',
      title: '底部导航',
      body: '首页 · 片库 · 资讯 · 我的，随时切换。',
      preferBelow: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    AppOnboardingGate.restartTick.addListener(_onRestartRequested);
    unawaited(_maybeStart());
  }

  @override
  void dispose() {
    AppOnboardingGate.restartTick.removeListener(_onRestartRequested);
    super.dispose();
  }

  void _onRestartRequested() {
    if (!mounted) return;
    // MainShell 同步听 restartTick 会先切回首页；这里等锚点就绪再盖引导
    unawaited(_startTourAfterHomeReady());
  }

  Future<void> _startTourAfterHomeReady() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final search = TourRegistry.rectOf('tour_search');
      final nav = TourRegistry.rectOf('tour_nav');
      if ((search != null && search.width > 8) ||
          (nav != null && nav.width > 8)) {
        break;
      }
    }
    if (!mounted) return;
    setState(() => _showTour = true);
  }

  Future<void> _maybeStart() async {
    final done = await AppOnboardingGate.isDone();
    if (done || !mounted) return;
    // 等首页锚点挂上：最多约 2.4s，避免「引导消失」
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      final search = TourRegistry.rectOf('tour_search');
      final nav = TourRegistry.rectOf('tour_nav');
      if ((search != null && search.width > 8) ||
          (nav != null && nav.width > 8)) {
        break;
      }
    }
    if (!mounted) return;
    setState(() => _showTour = true);
  }

  Future<void> _finish() async {
    await AppOnboardingGate.markDone();
    if (mounted) setState(() => _showTour = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showTour)
          ProductTourOverlay(
            steps: steps,
            onFinished: () => unawaited(_finish()),
          ),
      ],
    );
  }
}

class ProductTourOverlay extends StatefulWidget {
  const ProductTourOverlay({
    super.key,
    required this.steps,
    required this.onFinished,
  });

  final List<ProductTourStep> steps;
  final VoidCallback onFinished;

  @override
  State<ProductTourOverlay> createState() => _ProductTourOverlayState();
}

class _ProductTourOverlayState extends State<ProductTourOverlay>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  Rect? _hole;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final step = widget.steps[_index];
    final ctx = TourRegistry.keyOf(step.targetId).currentContext;
    if (ctx != null) {
      // 把目标滚进可视区（快捷入口 / 列表可能在 Banner 下方）
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          alignment: 0.35,
          curve: Curves.easeOutCubic,
        ).then((_) {
          if (!mounted) return;
          _applyHole(step.targetId);
        }),
      );
      return;
    }
    _applyHole(step.targetId);
  }

  void _applyHole(String targetId) {
    if (!mounted) return;
    var rect = TourRegistry.rectOf(targetId);
    if (rect == null || rect.width < 8 || rect.height < 8) {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        rect = TourRegistry.rectOf(targetId);
        setState(() => _hole = _inflate(rect));
      });
      setState(() => _hole = null);
      return;
    }
    setState(() => _hole = _inflate(rect));
  }

  Rect? _inflate(Rect? r) {
    if (r == null) return null;
    return r.inflate(8).intersect(
          Offset.zero & MediaQuery.sizeOf(context),
        );
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_index >= widget.steps.length - 1) {
      widget.onFinished();
      return;
    }
    setState(() {
      _index += 1;
      _hole = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _skip() {
    HapticFeedback.selectionClick();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    final pad = MediaQuery.paddingOf(context);
    final hole = _hole;
    final total = widget.steps.length;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return CustomPaint(
                painter: _TourMaskPainter(
                  hole: hole,
                  glow: 0.35 + _pulse.value * 0.25,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const SizedBox.expand(),
            ),
          ),
          if (hole != null)
            Positioned(
              left: hole.left,
              top: hole.top,
              width: hole.width,
              height: hole.height,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final p = _pulse.value;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.14 + p * 0.06),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55 + p * 0.25),
                          width: 1.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          // 说明卡跟随高亮洞口：优先洞下方，空间不够则洞上方，再兜底贴底
          Builder(
            builder: (context) {
              final bubble = _TourBubble(
                step: _index + 1,
                total: total,
                title: step.title,
                body: step.body,
                isLast: _index >= total - 1,
                onSkip: _skip,
                onNext: _next,
              );
              if (hole == null) {
                return Positioned(
                  left: 16,
                  right: 16,
                  bottom: pad.bottom + 16,
                  child: bubble,
                );
              }
              final size = MediaQuery.sizeOf(context);
              const gap = 14.0;
              const estH = 210.0;
              final spaceBelow = size.height - hole.bottom - pad.bottom - 16;
              final preferBelow = spaceBelow >= estH + gap;
              double top;
              if (preferBelow) {
                top = hole.bottom + gap;
              } else {
                top = hole.top - estH - gap;
                if (top < pad.top + 12) {
                  top = (pad.top + 12).clamp(0.0, size.height);
                }
              }
              final maxTop = size.height - pad.bottom - estH - 8;
              if (top > maxTop) top = maxTop;
              return Positioned(
                left: 16,
                right: 16,
                top: top,
                child: bubble,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TourBubble extends StatelessWidget {
  const _TourBubble({
    required this.step,
    required this.total,
    required this.title,
    required this.body,
    required this.isLast,
    required this.onSkip,
    required this.onNext,
  });

  final int step;
  final int total;
  final String title;
  final String body;
  final bool isLast;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '步骤 $step / $total',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i + 1 == step ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i + 1 == step
                          ? AppColors.brand
                          : AppColors.brand.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: onSkip,
                  child: const Text(
                    '跳过',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isLast ? '完成' : '下一步',
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TourMaskPainter extends CustomPainter {
  _TourMaskPainter({required this.hole, required this.glow});

  final Rect? hole;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      final r = RRect.fromRectAndRadius(hole!, const Radius.circular(14));
      overlay.addRRect(r);
      overlay.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
      overlay,
      Paint()..color = Color.fromRGBO(10, 12, 16, 0.55 + glow * 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _TourMaskPainter old) =>
      old.hole != hole || old.glow != glow;
}
