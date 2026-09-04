import 'dart:async';
import 'dart:math' show Rectangle;

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../widgets/dialogx/dialogx.dart';

/// Android 系统画中画
///
/// 注意：进小窗时禁止改动 VideoPlayer 在树上的位置（会拆 Texture 导致引擎断连）。
abstract final class PlayerPip {
  static final Floating _floating = Floating();

  static StreamSubscription<PiPStatus>? _sub;
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);
  static VoidCallback? _onEntered;

  static Floating get floating => _floating;

  static bool get isInPip => inPip.value;

  /// 小窗进入后继续播（由播放器注册；勿在此 setState 挪动播放器）
  static void setOnEntered(VoidCallback? cb) => _onEntered = cb;

  static void ensureListening() {
    if (_sub != null) return;
    _sub = _floating.pipStatusStream.listen((s) {
      final enabled = s == PiPStatus.enabled;
      if (inPip.value == enabled) return;
      inPip.value = enabled;
      if (enabled) {
        // 延后到帧外，避开 PiP 切换当帧的布局风暴
        WidgetsBinding.instance.addPostFrameCallback((_) {
          DialogX.dismiss();
          _onEntered?.call();
        });
      }
    });
  }

  static void stopListening() {
    _sub?.cancel();
    _sub = null;
    if (inPip.value) inPip.value = false;
  }

  static Future<bool> get isAvailable async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _floating.isPipAvailable;
    } catch (_) {
      return false;
    }
  }

  /// 按 Home 自动进小窗（仅 Android 12+；失败则静默）
  static Future<void> enableAutoOnLeave({Rect? sourceRect}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    ensureListening();
    try {
      if (!await _floating.isPipAvailable) return;
      await _floating.enable(
        OnLeavePiP(
          aspectRatio: const Rational.landscape(),
          sourceRectHint: _hint(sourceRect),
        ),
      );
    } catch (e) {
      // SDK<31 会抛 PlatformException，忽略即可
      debugPrint('[pip] onLeave enable fail: $e');
    }
  }

  static Future<void> cancelAutoOnLeave() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _floating.cancelOnLeavePiP();
    } catch (_) {}
    if (!inPip.value) stopListening();
  }

  static Future<void> enter({
    Rational aspect = const Rational.landscape(),
    Rect? sourceRect,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      DialogX.showWarning('画中画仅支持 Android');
      return;
    }
    ensureListening();
    DialogX.dismiss();
    try {
      if (!await _floating.isPipAvailable) {
        DialogX.showWarning('当前设备不支持画中画');
        return;
      }
      final status = await _floating.enable(
        ImmediatePiP(
          aspectRatio: aspect,
          sourceRectHint: _hint(sourceRect),
        ),
      );
      // ImmediatePiP 成功时可能仍短暂为 disabled，以系统回调为准
      if (status == PiPStatus.enabled) {
        inPip.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _onEntered?.call();
        });
      }
    } catch (e) {
      debugPrint('[pip] enable fail: $e');
      DialogX.showWarning('无法进入画中画');
    }
  }

  /// Android sourceRectHint 需要物理像素
  static Rectangle<int>? _hint(Rect? r) {
    if (r == null || r.isEmpty) return null;
    final w = r.width.round().clamp(1, 100000);
    final h = r.height.round().clamp(1, 100000);
    return Rectangle<int>(r.left.round(), r.top.round(), w, h);
  }
}
