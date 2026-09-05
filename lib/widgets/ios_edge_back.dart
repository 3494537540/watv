import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 在 [PopScope(canPop: false)] 等场景下，仍保留 iOS 左缘侧滑返回手势。
class IosEdgeBack extends StatefulWidget {
  const IosEdgeBack({
    super.key,
    required this.onBack,
    required this.child,
    this.enabled = true,
    this.edgeWidth = 28,
  });

  final VoidCallback onBack;
  final Widget child;
  final bool enabled;
  final double edgeWidth;

  @override
  State<IosEdgeBack> createState() => _IosEdgeBackState();
}

class _IosEdgeBackState extends State<IosEdgeBack> {
  double _dx = 0;
  bool _tracking = false;

  bool get _iosLike =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  void _maybeBack() {
    if (_dx > 64) {
      widget.onBack();
    }
    _dx = 0;
    _tracking = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_iosLike) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: widget.edgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (d) {
              if (d.globalPosition.dx > widget.edgeWidth + 8) return;
              _tracking = true;
              _dx = 0;
            },
            onHorizontalDragUpdate: (d) {
              if (!_tracking) return;
              if (d.delta.dx > 0) _dx += d.delta.dx;
            },
            onHorizontalDragEnd: (_) => _maybeBack(),
            onHorizontalDragCancel: () {
              _dx = 0;
              _tracking = false;
            },
          ),
        ),
      ],
    );
  }
}

/// 系统返回 / 侧滑统一入口（观看页等拦截 pop 的场景）
class InterceptPopScope extends StatelessWidget {
  const InterceptPopScope({
    super.key,
    required this.onIntercept,
    required this.child,
  });

  final VoidCallback onIntercept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        onIntercept();
      },
      child: IosEdgeBack(
        onBack: onIntercept,
        child: child,
      ),
    );
  }
}
