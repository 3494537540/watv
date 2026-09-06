import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS：唤起系统 AirPlay 视频路由（优先视频设备，非音箱音频面板）
abstract final class IosAirPlay {
  static const _channel = MethodChannel('watv/cast');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 弹出 AirPlay 视频路由选择器（Apple TV 等），优先视频设备
  static Future<bool> showVideoPicker() async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('showAirPlayVideoPicker');
      return ok == true;
    } catch (e) {
      debugPrint('[airplay] showVideoPicker fail: $e');
      // 兼容旧原生实现
      try {
        final ok = await _channel.invokeMethod<bool>('showAirPlayPicker');
        return ok == true;
      } catch (e2) {
        debugPrint('[airplay] showPicker fail: $e2');
        return false;
      }
    }
  }

  @Deprecated('Use showVideoPicker')
  static Future<bool> showPicker() => showVideoPicker();
}
