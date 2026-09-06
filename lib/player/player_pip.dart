import 'dart:async';
import 'dart:math' show Rectangle;

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_pip/video_player_pip.dart';
import 'package:video_player_pip/video_player_pip_platform_interface.dart';

import '../widgets/dialogx/dialogx.dart';

/// 系统画中画：Android 用 floating；iOS 用 video_player_pip（需 PlatformView）
abstract final class PlayerPip {
  static final Floating _floating = Floating();

  static StreamSubscription<PiPStatus>? _androidSub;
  static StreamSubscription<bool>? _iosSub;
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);
  static VoidCallback? _onEntered;

  static Floating get floating => _floating;

  static bool get isInPip => inPip.value;

  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 小窗进入后继续播（由播放器注册；勿在此 setState 挪动播放器）
  static void setOnEntered(VoidCallback? cb) => _onEntered = cb;

  static void ensureListening() {
    if (_isAndroid) {
      if (_androidSub != null) return;
      _androidSub = _floating.pipStatusStream.listen((s) {
        final enabled = s == PiPStatus.enabled;
        _setInPip(enabled);
      });
      return;
    }
    if (_isIos) {
      if (_iosSub != null) return;
      // 触发 VideoPlayerPip 单例以挂上 method handler
      VideoPlayerPip.instance;
      _iosSub = VideoPlayerPip.instance.onPipModeChanged.listen(_setInPip);
    }
  }

  static void _setInPip(bool enabled) {
    if (inPip.value == enabled) return;
    inPip.value = enabled;
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        DialogX.dismiss();
        _onEntered?.call();
      });
    }
  }

  static void stopListening() {
    _androidSub?.cancel();
    _androidSub = null;
    _iosSub?.cancel();
    _iosSub = null;
    if (inPip.value) inPip.value = false;
  }

  static Future<bool> get isAvailable async {
    if (kIsWeb) return false;
    if (_isAndroid) {
      try {
        return await _floating.isPipAvailable;
      } catch (_) {
        return false;
      }
    }
    if (_isIos) {
      try {
        return await VideoPlayerPip.isPipSupported();
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// 按 Home 自动进小窗（仅 Android 12+；失败则静默）
  static Future<void> enableAutoOnLeave({Rect? sourceRect}) async {
    if (!_isAndroid) return;
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
      debugPrint('[pip] onLeave enable fail: $e');
    }
  }

  static Future<void> cancelAutoOnLeave() async {
    if (!_isAndroid) return;
    try {
      await _floating.cancelOnLeavePiP();
    } catch (_) {}
    if (!inPip.value) stopListening();
  }

  static Future<void> enter({
    Rational aspect = const Rational.landscape(),
    Rect? sourceRect,
    int? iosPlayerId,
    double videoAspect = 16 / 9,
  }) async {
    if (kIsWeb) {
      DialogX.showWarning('当前环境不支持画中画');
      return;
    }
    ensureListening();
    DialogX.dismiss();

    if (_isAndroid) {
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
        if (status == PiPStatus.enabled) {
          _setInPip(true);
        }
      } catch (e) {
        debugPrint('[pip] android enable fail: $e');
        DialogX.showWarning('无法进入画中画');
      }
      return;
    }

    if (_isIos) {
      final playerId = iosPlayerId;
      if (playerId == null) {
        DialogX.showWarning('当前内核不支持 iOS 画中画，请切换「系统(Exo)」内核');
        return;
      }
      try {
        if (!await VideoPlayerPip.isPipSupported()) {
          DialogX.showWarning('当前设备不支持画中画');
          return;
        }
        final ar = videoAspect <= 0 ? 16 / 9 : videoAspect;
        final w = 320;
        final h = (w / ar).round().clamp(120, 480);
        final ok = await VideoPlayerPipPlatform.instance.enterPipMode(
          playerId,
          width: w,
          height: h,
        );
        if (!ok) {
          DialogX.showWarning('无法进入画中画，请确认在真机且已播放');
          return;
        }
        _setInPip(true);
      } catch (e) {
        debugPrint('[pip] ios enable fail: $e');
        DialogX.showWarning('无法进入画中画');
      }
      return;
    }

    DialogX.showWarning('画中画仅支持 Android / iOS');
  }

  /// Android sourceRectHint 需要物理像素
  static Rectangle<int>? _hint(Rect? r) {
    if (r == null || r.isEmpty) return null;
    final w = r.width.round().clamp(1, 100000);
    final h = r.height.round().clamp(1, 100000);
    return Rectangle<int>(r.left.round(), r.top.round(), w, h);
  }
}
