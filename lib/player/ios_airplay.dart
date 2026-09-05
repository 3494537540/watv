import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS：唤起系统 AirPlay / 屏幕镜像面板
abstract final class IosAirPlay {
  static const _channel = MethodChannel('watv/cast');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 弹出系统路由选择器（含 AirPlay 音箱/Apple TV，以及可走镜像的设备）
  static Future<bool> showPicker() async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('showAirPlayPicker');
      return ok == true;
    } catch (e) {
      debugPrint('[airplay] showPicker fail: $e');
      return false;
    }
  }
}
