import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../figma_loading.dart';
import '../../theme/app_colors.dart';

/// 全局 Navigator，供 DialogX 无 context 弹出。
final GlobalKey<NavigatorState> dialogXNavigatorKey =
    GlobalKey<NavigatorState>();

enum DialogXTipType { success, warning, error, info, neutral }

class DialogXTipAction {
  const DialogXTipAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
}

/// Wait：白底居中加载卡；Tip：白底圆角轻提示；Confirm：白底竖排按钮。
class DialogX {
  DialogX._();

  static OverlayEntry? _waitEntry;
  static _WaitHostState? _waitHost;
  static OverlayEntry? _tipEntry;
  static _GlassTipQueueState? _tipQueue;
  static OverlayEntry? _mailToast;
  static Timer? _mailTimer;

  static OverlayState? get _overlay =>
      dialogXNavigatorKey.currentState?.overlay;

  static int _waitGen = 0;

  static void showWait([String message = '请稍候']) {
    HapticFeedback.lightImpact();
    final gen = ++_waitGen;
    _ensureWaitHostThen((host) {
      // 若在 host 就绪前已被 dismiss / 新 showWait，则丢弃本次
      if (gen != _waitGen) return;
      host.show(message);
    });
  }

  static void dismiss() {
    _waitGen++;
    _waitHost?.hide();
    _removeWaitSoon();
    _tipQueue?.clearAll();
  }
  static void showSuccess(
    String message, {
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    HapticFeedback.lightImpact();
    _pushToast(
      message: message,
      type: DialogXTipType.success,
      duration: duration,
    );
  }

  static void showWarning(
    String message, {
    Duration duration = const Duration(milliseconds: 3000),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    HapticFeedback.mediumImpact();
    _pushToast(
      message: message,
      type: DialogXTipType.warning,
      duration: duration,
      action: (actionLabel != null && onAction != null)
          ? DialogXTipAction(label: actionLabel, onPressed: onAction)
          : null,
    );
  }

  static void showError(
    String message, {
    Duration duration = const Duration(milliseconds: 3200),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    HapticFeedback.heavyImpact();
    _pushToast(
      message: message,
      type: DialogXTipType.error,
      duration: duration,
      action: (actionLabel != null && onAction != null)
          ? DialogXTipAction(label: actionLabel, onPressed: onAction)
          : null,
    );
  }

  /// 图二风格：白底圆角卡 + 竖排胶囊按钮。返回点了主操作（第一颗色按钮）。
  static Future<bool> confirm({
    BuildContext? context,
    required String title,
    String? message,
    String confirmLabel = '确定',
    String cancelLabel = '取消',
    String? secondaryLabel,
    bool destructive = false,
  }) async {
    BuildContext? ctx;
    if (context != null && context.mounted) {
      ctx = context;
    }
    ctx ??= dialogXNavigatorKey.currentContext;
    ctx ??= dialogXNavigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) {
      debugPrint('DialogX.confirm: no navigator context');
      return false;
    }
    HapticFeedback.lightImpact();
    final result = await showGeneralDialog<String>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: const Color(0x66000000),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (c, a1, a2) {
        return _MiuiConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          secondaryLabel: secondaryLabel,
          destructive: destructive,
        );
      },
      transitionBuilder: (c, anim, _, child) {
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(t),
            child: child,
          ),
        );
      },
    );
    return result == 'confirm';
  }

  /// MIUI 底部对话框：贴底大圆角白卡，可自定义中间区域。
  /// 返回 `action` / `cancel` / null（点遮罩）。
  static Future<String?> bottom({
    BuildContext? context,
    required String title,
    String? message,
    Widget? body,
    String closeLabel = '取消',
    String? actionLabel,
    bool destructive = false,
  }) async {
    final nav = dialogXNavigatorKey.currentState;
    final ctx = context ?? nav?.context;
    if (ctx == null) return null;
    HapticFeedback.lightImpact();
    return showGeneralDialog<String>(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: const Color(0x66000000),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (c, a1, a2) {
        return _MiuiBottomDialog(
          title: title,
          message: message,
          body: body,
          closeLabel: closeLabel,
          actionLabel: actionLabel,
          destructive: destructive,
        );
      },
      transitionBuilder: (c, anim, _, child) {
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: t,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(t),
            child: child,
          ),
        );
      },
    );
  }

  static void showMailSent({
    String message = '邮件已发送',
    VoidCallback? onUndo,
    Duration duration = const Duration(seconds: 4),
  }) {
    HapticFeedback.lightImpact();
    _mailToast?.remove();
    _mailTimer?.cancel();
    final overlay = _overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final top = MediaQuery.paddingOf(context).top;
        return Positioned(
          top: top + 12,
          left: 16,
          right: 16,
          child: Material(
            type: MaterialType.transparency,
            child: _MailSentToast(
              message: message,
              onUndo: () {
                onUndo?.call();
                _removeMail(entry);
              },
            ),
          ),
        );
      },
    );
    _mailToast = entry;
    overlay.insert(entry);
    _mailTimer = Timer(duration, () => _removeMail(entry));
  }

  static void _removeMail(OverlayEntry entry) {
    if (!identical(_mailToast, entry)) return;
    entry.remove();
    _mailToast = null;
    _mailTimer?.cancel();
    _mailTimer = null;
  }

  static void _pushToast({
    required String message,
    required DialogXTipType type,
    required Duration duration,
    DialogXTipAction? action,
  }) {
    _waitGen++;
    _waitHost?.hide();
    _removeWaitSoon();

    final overlay = _overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_overlay == null) return;
        _pushToast(
          message: message,
          type: type,
          duration: duration,
          action: action,
        );
      });
      return;
    }

    if (_tipQueue != null && _tipEntry != null) {
      _tipQueue!.push(
        message: message,
        type: type,
        duration: duration,
        action: action,
      );
      return;
    }

    _tipEntry?.remove();
    _tipEntry = OverlayEntry(
      builder: (context) => _GlassTipQueue(
        onReady: (s) {
          _tipQueue = s;
          s.push(
            message: message,
            type: type,
            duration: duration,
            action: action,
          );
        },
        onEmpty: () {
          _tipEntry?.remove();
          _tipEntry = null;
          _tipQueue = null;
        },
      ),
    );
    overlay.insert(_tipEntry!);
  }

  static void _ensureWaitHostThen(void Function(_WaitHostState host) action) {
    final overlay = _overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_overlay == null) return;
        _ensureWaitHostThen(action);
      });
      return;
    }
    if (_waitHost != null && _waitEntry != null) {
      action(_waitHost!);
      return;
    }
    _waitEntry?.remove();
    _waitEntry = OverlayEntry(
      builder: (context) => _WaitHost(
        onReady: (s) {
          _waitHost = s;
          action(s);
        },
      ),
    );
    overlay.insert(_waitEntry!);
  }

  static void _removeWaitSoon() {
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (_waitHost?.visible == true) return;
      _waitEntry?.remove();
      _waitEntry = null;
      _waitHost = null;
    });
  }
}

// ─── GlassToast 垂直队列（排开、可多条）────────────────────

class _TipItem {
  _TipItem({
    required this.id,
    required this.message,
    required this.type,
    required this.duration,
    this.action,
  });

  final int id;
  final String message;
  final DialogXTipType type;
  final Duration duration;
  final DialogXTipAction? action;
}

/// 像参考图：多条自上而下排成一列，间距≈胶囊高度，互不挡字。
class _GlassTipQueue extends StatefulWidget {
  const _GlassTipQueue({
    required this.onReady,
    required this.onEmpty,
  });

  final ValueChanged<_GlassTipQueueState> onReady;
  final VoidCallback onEmpty;

  @override
  State<_GlassTipQueue> createState() => _GlassTipQueueState();
}

class _GlassTipQueueState extends State<_GlassTipQueue> {
  final List<_TipItem> _items = [];
  final Map<int, Timer> _timers = {};
  int _seq = 0;

  /// 槽位间距：白底圆角卡高度
  static const slotStep = 60.0;
  static const maxVisible = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onReady(this);
    });
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  void push({
    required String message,
    required DialogXTipType type,
    required Duration duration,
    DialogXTipAction? action,
  }) {
    final id = ++_seq;
    setState(() {
      _items.insert(0, _TipItem(
        id: id,
        message: message,
        type: type,
        duration: duration,
        action: action,
      ));
      while (_items.length > maxVisible) {
        final old = _items.removeLast();
        _timers.remove(old.id)?.cancel();
      }
    });
    _timers[id]?.cancel();
    _timers[id] = Timer(duration, () => unawaited(_requestDismiss(id)));
  }

  Future<void> _requestDismiss(int id) async {
    // 由子项自己播「上弹走」动画后回调 remove
    final key = _itemKeys[id];
    if (key?.currentState != null) {
      await key!.currentState!.flyOut();
    } else {
      _remove(id);
    }
  }

  final Map<int, GlobalKey<_QueuedTipState>> _itemKeys = {};

  GlobalKey<_QueuedTipState> _keyFor(int id) =>
      _itemKeys.putIfAbsent(id, GlobalKey<_QueuedTipState>.new);

  void _remove(int id) {
    _timers.remove(id)?.cancel();
    _itemKeys.remove(id);
    if (!_items.any((e) => e.id == id)) return;
    setState(() => _items.removeWhere((e) => e.id == id));
    if (_items.isEmpty) widget.onEmpty();
  }

  void clearAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _itemKeys.clear();
    setState(() => _items.clear());
    widget.onEmpty();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < _items.length; i++)
            Builder(
              builder: (_) {
                final item = _items[i];
                return _QueuedTip(
                  key: _keyFor(item.id),
                  item: item,
                  index: i,
                  topInset: top,
                  onRemoved: () => _remove(item.id),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _QueuedTip extends StatefulWidget {
  const _QueuedTip({
    super.key,
    required this.item,
    required this.index,
    required this.topInset,
    required this.onRemoved,
  });

  final _TipItem item;
  final int index;
  final double topInset;
  final VoidCallback onRemoved;

  @override
  State<_QueuedTip> createState() => _QueuedTipState();
}

class _QueuedTipState extends State<_QueuedTip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _y =
      AnimationController.unbounded(vsync: this);
  bool _ready = false;
  bool _exiting = false;

  static const _springIn = SpringDescription(
    mass: 0.68,
    stiffness: 340,
    damping: 13,
  );
  static const _springMove = SpringDescription(
    mass: 0.75,
    stiffness: 300,
    damping: 17,
  );
  static const _springOut = SpringDescription(
    mass: 0.8,
    stiffness: 280,
    damping: 18,
  );

  double get _slot =>
      widget.topInset + 10 + widget.index * _GlassTipQueueState.slotStep;

  @override
  void initState() {
    super.initState();
    _y.value = _slot - 130;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _y.animateWith(SpringSimulation(_springIn, _y.value, _slot, 1900));
      _ready = true;
    });
  }

  @override
  void didUpdateWidget(covariant _QueuedTip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready || _exiting) return;
    if (oldWidget.index != widget.index ||
        oldWidget.topInset != widget.topInset) {
      _y.animateWith(SpringSimulation(_springMove, _y.value, _slot, 0));
    }
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> flyOut() async {
    if (_exiting) return;
    _exiting = true;
    await _y.animateWith(
      SpringSimulation(_springOut, _y.value, _y.value - 160, -1400),
    );
    if (mounted) widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _y,
      builder: (context, child) {
        final dy = _y.value - _slot;
        // 入场/出场时淡入淡出
        final opacity = dy < -20
            ? (1.0 + (dy + 20) / 120.0).clamp(0.0, 1.0)
            : 1.0;
        return Positioned(
          top: _y.value,
          left: 28,
          right: 28,
          child: Opacity(
            opacity: opacity,
            child: child,
          ),
        );
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -180) {
                unawaited(flyOut());
              }
            },
            child: _SolidTipCapsule(
              message: widget.item.message,
              type: widget.item.type,
              action: widget.item.action,
            ),
          ),
        ),
      ),
    );
  }
}

/// 纯灰底圆角提示：胶囊形，偏灰底 + 浅字
class _SolidTipCapsule extends StatelessWidget {
  const _SolidTipCapsule({
    required this.message,
    required this.type,
    this.action,
  });

  final String message;
  final DialogXTipType type;
  final DialogXTipAction? action;

  @override
  Widget build(BuildContext context) {
    // 偏灰胶囊：不要拉满宽，圆角要够
    const bg = Color(0xFF6B6B70);
    const fg = Color(0xFFF2F2F7);
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 12, action == null ? 18 : 10, 12),
          child: IntrinsicWidth(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      decoration: TextDecoration.none,
                      height: 1.25,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 6),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    onPressed: action!.onPressed,
                    child: Text(
                      action!.label,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFFFFF),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Wait / Mail ───────────────────────────────────────────

class _WaitHost extends StatefulWidget {
  const _WaitHost({required this.onReady});

  final ValueChanged<_WaitHostState> onReady;

  @override
  State<_WaitHost> createState() => _WaitHostState();
}

class _WaitHostState extends State<_WaitHost> with TickerProviderStateMixin {
  bool visible = false;
  String message = '请稍候';

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.72, end: 1.06)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 70,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.06, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 30,
    ),
  ]).animate(_anim);

  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void show(String msg) {
    setState(() {
      visible = true;
      message = msg;
    });
    _anim.forward(from: 0);
  }

  void hide() {
    _anim.reverse().whenComplete(() {
      if (mounted) setState(() => visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!visible && _anim.isDismissed) {
      return const SizedBox.shrink();
    }

    const barrier = Color(0x73000000);

    return Positioned.fill(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // 保持透明导航栏，让半透明遮罩铺满底部，避免单独改系统栏颜色闪一下
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ModalBarrier(
                  dismissible: false,
                  color: barrier,
                ),
                Center(
                  child: ScaleTransition(
                    scale: _scale,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 140,
                        minHeight: 140,
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 32,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FigmaMetaballLoader(
                              size: 52,
                              color: AppColors.brand,
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                message,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 14,
                                  height: 1.3,
                                  color: Color(0xFF1C1C1E),
                                  decoration: TextDecoration.none,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MailSentToast extends StatefulWidget {
  const _MailSentToast({
    required this.message,
    required this.onUndo,
  });

  final String message;
  final VoidCallback onUndo;

  @override
  State<_MailSentToast> createState() => _MailSentToastState();
}

class _MailSentToastState extends State<_MailSentToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.35),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x28000000),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.envelope,
                  size: 22,
                  color: Color(0xFF1C1C1E),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 15,
                      color: Color(0xFF1C1C1E),
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 0),
                  onPressed: widget.onUndo,
                  child: const Text(
                    '撤回',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 15,
                      color: Color(0xFF007AFF),
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 图二：白底大圆角 + 竖排胶囊按钮（主操作为色底，取消为浅灰）
class _MiuiConfirmDialog extends StatelessWidget {
  const _MiuiConfirmDialog({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    this.message,
    this.secondaryLabel,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final String? secondaryLabel;
  final bool destructive;

  static const _ink = Color(0xFF1C1C1E);
  static const _muted = Color(0xFF8E8E93);
  static const _pillGray = Color(0xFFF2F2F7);
  static const _blue = Color(0xFF007AFF);
  static const _red = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    final primary = destructive ? _red : _blue;
    final screenW = MediaQuery.sizeOf(context).width;
    // 左右各约 20，避免「确认删除」悬空过窄
    final dialogW = (screenW - 40).clamp(280.0, 420.0);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: dialogW,
          child: Container(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    decoration: TextDecoration.none,
                    height: 1.25,
                  ),
                ),
                if (message != null && message!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                      decoration: TextDecoration.none,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _miuiPill(
                  label: confirmLabel,
                  bg: primary,
                  fg: Colors.white,
                  onTap: () => Navigator.of(context).pop('confirm'),
                ),
                if (secondaryLabel != null &&
                    secondaryLabel!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _miuiPill(
                    label: secondaryLabel!,
                    bg: _pillGray,
                    fg: _ink,
                    onTap: () => Navigator.of(context).pop('secondary'),
                  ),
                ],
                const SizedBox(height: 10),
                _miuiPill(
                  label: cancelLabel,
                  bg: _pillGray,
                  fg: _ink,
                  onTap: () => Navigator.of(context).pop('cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// MIUI 底部对话框（贴底大圆角，与参考图一致）
class _MiuiBottomDialog extends StatelessWidget {
  const _MiuiBottomDialog({
    required this.title,
    required this.closeLabel,
    required this.destructive,
    this.message,
    this.body,
    this.actionLabel,
  });

  final String title;
  final String? message;
  final Widget? body;
  final String closeLabel;
  final String? actionLabel;
  final bool destructive;

  static const _ink = Color(0xFF1C1C1E);
  static const _pillGray = Color(0xFFF2F2F7);
  static const _blue = Color(0xFF007AFF);
  static const _red = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final primary = destructive ? _red : _blue;
    final hasAction = actionLabel != null && actionLabel!.trim().isNotEmpty;

    // 贴底全宽：无左右/底部外边距，仅保留顶部圆角 + 安全区 padding
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.fromLTRB(20, 16, 20, 10 + bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  decoration: TextDecoration.none,
                  height: 1.25,
                ),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.36,
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      message!,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: _ink,
                        decoration: TextDecoration.none,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ],
              if (body != null) ...[
                const SizedBox(height: 12),
                body!,
              ],
              const SizedBox(height: 14),
              if (hasAction) ...[
                _miuiPill(
                  label: actionLabel!.trim(),
                  bg: primary,
                  fg: Colors.white,
                  onTap: () => Navigator.of(context).pop('action'),
                ),
                const SizedBox(height: 8),
              ],
              _miuiPill(
                label: closeLabel,
                bg: _pillGray,
                fg: _ink,
                onTap: () => Navigator.of(context).pop('cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _miuiPill({
  required String label,
  required Color bg,
  required Color fg,
  required VoidCallback onTap,
}) {
  return SizedBox(
    height: 48,
    child: Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: fg,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}
