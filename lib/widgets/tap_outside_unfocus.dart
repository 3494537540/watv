import 'package:flutter/material.dart';

/// 点击已聚焦输入框之外的区域时收起键盘 / 取消焦点。
class TapOutsideUnfocus extends StatelessWidget {
  const TapOutsideUnfocus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null || !focus.hasFocus) return;
        final ctx = focus.context;
        if (ctx == null) {
          focus.unfocus();
          return;
        }
        final box = ctx.findRenderObject();
        if (box is! RenderBox || !box.hasSize) {
          focus.unfocus();
          return;
        }
        final local = box.globalToLocal(event.position);
        final inside = Offset.zero & box.size;
        if (!inside.contains(local)) {
          focus.unfocus();
        }
      },
      child: child,
    );
  }
}
