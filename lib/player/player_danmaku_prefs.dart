import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕显示区域
enum DanmakuArea {
  /// 画面上半（默认，避开底部字幕/控件）
  top,
  /// 接近全屏（留底边）
  full,
  /// 画面下半
  bottom,
}

/// 弹幕显示偏好（全局）
class DanmakuDisplayPrefs {
  const DanmakuDisplayPrefs({
    this.enabled = true,
    this.fontSize = 15,
    this.opacity = 1,
    this.area = DanmakuArea.top,
    this.speed = 1,
    this.density = 1,
    this.timeOffsetSec = 0,
  });

  final bool enabled;
  /// 字号 12–28
  final double fontSize;
  /// 不透明度 0.2–1
  final double opacity;
  final DanmakuArea area;
  /// 滚动速度倍率 0.5–2（越大飞得越快）
  final double speed;
  /// 密度 0.4–1.5（越大同屏越多）
  final double density;
  /// 时间轴偏移（秒）：正数弹幕更晚出现，负数更早
  final double timeOffsetSec;

  DanmakuDisplayPrefs copyWith({
    bool? enabled,
    double? fontSize,
    double? opacity,
    DanmakuArea? area,
    double? speed,
    double? density,
    double? timeOffsetSec,
  }) {
    return DanmakuDisplayPrefs(
      enabled: enabled ?? this.enabled,
      fontSize: fontSize ?? this.fontSize,
      opacity: opacity ?? this.opacity,
      area: area ?? this.area,
      speed: speed ?? this.speed,
      density: density ?? this.density,
      timeOffsetSec: timeOffsetSec ?? this.timeOffsetSec,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'font_size': fontSize,
        'opacity': opacity,
        'area': area.name,
        'speed': speed,
        'density': density,
        'time_offset': timeOffsetSec,
      };

  factory DanmakuDisplayPrefs.fromJson(Map<String, dynamic> json) {
    final areaName = '${json['area'] ?? 'top'}';
    final area = DanmakuArea.values.firstWhere(
      (e) => e.name == areaName,
      orElse: () => DanmakuArea.top,
    );
    return DanmakuDisplayPrefs(
      enabled: json['enabled'] != false,
      fontSize: ((json['font_size'] as num?)?.toDouble() ?? 15).clamp(12, 28),
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1).clamp(0.2, 1),
      area: area,
      speed: ((json['speed'] as num?)?.toDouble() ?? 1).clamp(0.5, 2),
      density: ((json['density'] as num?)?.toDouble() ?? 1).clamp(0.4, 1.5),
      timeOffsetSec:
          ((json['time_offset'] as num?)?.toDouble() ?? 0).clamp(-30, 30),
    );
  }

  String get areaLabel => switch (area) {
        DanmakuArea.top => '上方',
        DanmakuArea.full => '全屏',
        DanmakuArea.bottom => '下方',
      };
}

/// 弹幕偏好存取（兼容旧版仅开关）
class PlayerDanmakuPrefs {
  PlayerDanmakuPrefs._();

  static const _key = 'player_danmaku_display_v2';
  static const _legacyEnabledKey = 'player_danmaku_enabled_v1';

  static DanmakuDisplayPrefs _cache = const DanmakuDisplayPrefs();

  static DanmakuDisplayPrefs get cached => _cache;

  static bool get enabled => _cache.enabled;

  static Future<DanmakuDisplayPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          _cache = DanmakuDisplayPrefs.fromJson(
            Map<String, dynamic>.from(json),
          );
          return _cache;
        }
      } catch (_) {}
    }
    // 迁移旧开关
    final legacy = prefs.getBool(_legacyEnabledKey);
    if (legacy != null) {
      _cache = DanmakuDisplayPrefs(enabled: legacy);
      await save(_cache);
    }
    return _cache;
  }

  static Future<void> save(DanmakuDisplayPrefs prefs) async {
    _cache = prefs;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(prefs.toJson()));
  }

  static Future<void> setEnabled(bool enabled) async {
    await save(_cache.copyWith(enabled: enabled));
  }

  /// 兼容旧调用：返回是否开启
  static Future<bool> loadEnabled() async {
    final p = await load();
    return p.enabled;
  }
}
