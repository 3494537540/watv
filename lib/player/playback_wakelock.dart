import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 播放时保持屏幕常亮（失败时静默忽略，不影响播放）
class PlaybackWakelock {
  PlaybackWakelock._();

  static int _refs = 0;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> acquire() async {
    if (!_supported) return;
    _refs++;
    if (_refs > 1) return;
    try {
      await WakelockPlus.enable();
    } catch (_) {
      _refs = 0;
    }
  }

  static Future<void> release() async {
    if (!_supported) return;
    if (_refs <= 0) return;
    _refs--;
    if (_refs > 0) return;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
