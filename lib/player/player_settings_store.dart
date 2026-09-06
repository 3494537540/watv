import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 画面填充方式
enum PlayerAspectMode {
  /// 完整显示，可能有黑边
  fit,
  /// 铺满裁剪
  cover,
  /// 拉伸填满
  fill,
  /// 强制 16:9
  ratio16x9,
  /// 强制 4:3
  ratio4x3,
}

extension PlayerAspectModeX on PlayerAspectMode {
  String get label => switch (this) {
        PlayerAspectMode.fit => '适应',
        PlayerAspectMode.cover => '裁剪铺满',
        PlayerAspectMode.fill => '拉伸',
        PlayerAspectMode.ratio16x9 => '16:9',
        PlayerAspectMode.ratio4x3 => '4:3',
      };
}

/// 流畅度策略：影响自动清晰度、缓冲与边播边缓力度
enum PlayerPlayMode {
  /// 优先流畅，偏中低清晰度 + 更大缓冲
  smooth,
  /// 均衡
  standard,
  /// 尽量高清
  high,
}

extension PlayerPlayModeX on PlayerPlayMode {
  String get label => switch (this) {
        PlayerPlayMode.smooth => '流畅',
        PlayerPlayMode.standard => '标准',
        PlayerPlayMode.high => '高画质',
      };

  String get hint => switch (this) {
        PlayerPlayMode.smooth => '更稳更省流，自动偏中低清晰度',
        PlayerPlayMode.standard => '清晰度与流畅均衡（推荐）',
        PlayerPlayMode.high => '尽量高清，弱网可能更易卡顿',
      };
}

/// 播放内核
enum PlayerKernel {
  /// Android ExoPlayer / iOS AVPlayer（video_player）
  exo,
  /// libmpv 硬解
  mpv,
  /// IJK 风格兼容（libmpv 软解，奇葩封装更稳）
  ijk,
  /// 阿里云风格兼容（libmpv + 更大缓冲）
  ali,
}

extension PlayerKernelX on PlayerKernel {
  String get label => switch (this) {
        PlayerKernel.exo => '系统(Exo)',
        PlayerKernel.mpv => 'MPV',
        PlayerKernel.ijk => 'IJK兼容',
        PlayerKernel.ali => '阿里兼容',
      };

  String get hint => switch (this) {
        PlayerKernel.exo => '官方推荐，画中画/省电最好',
        PlayerKernel.mpv => 'libmpv 硬解，兼容性更强',
        PlayerKernel.ijk => '软解兼容层，卡顿片源可试',
        PlayerKernel.ali => '大缓冲策略，弱网可试',
      };

  bool get isMediaKit =>
      this == PlayerKernel.mpv ||
      this == PlayerKernel.ijk ||
      this == PlayerKernel.ali;
}

/// 自研画质增强档位
enum PlayerEnhanceLevel {
  off,
  mild,
  standard,
  vivid,
}

extension PlayerEnhanceLevelX on PlayerEnhanceLevel {
  String get label => switch (this) {
        PlayerEnhanceLevel.off => '关闭',
        PlayerEnhanceLevel.mild => '轻度',
        PlayerEnhanceLevel.standard => '标准',
        PlayerEnhanceLevel.vivid => '鲜明',
      };

  String get hint => switch (this) {
        PlayerEnhanceLevel.off => '原始画面',
        PlayerEnhanceLevel.mild => '轻微提亮与清晰感',
        PlayerEnhanceLevel.standard => '对比度与色彩增强',
        PlayerEnhanceLevel.vivid => '更强锐利与饱和（略费电）',
      };
}

/// 播放器综合偏好（全局）
class PlayerSettingsPrefs {
  const PlayerSettingsPrefs({
    this.aspect = PlayerAspectMode.fit,
    this.holdBoostEnabled = true,
    this.holdBoostRate = 2.0,
    this.autoPlayNext = true,
    this.loopSingle = false,
    this.mirrorX = false,
    this.mirrorY = false,
    this.gestureEnabled = true,
    this.showNetSpeed = true,
    this.keepScreenOn = true,
    this.doubleTapSeek = true,
    this.chromeAutoHideSec = 4,
    this.autoSourceFailover = false,
    this.playMode = PlayerPlayMode.high,
    this.streamCacheEnabled = true,
    this.enhanceLevel = PlayerEnhanceLevel.vivid,
    this.kernel = PlayerKernel.exo,
  });

  final PlayerAspectMode aspect;
  final bool holdBoostEnabled;
  final double holdBoostRate;
  final bool autoPlayNext;
  final bool loopSingle;
  final bool mirrorX;
  final bool mirrorY;
  final bool gestureEnabled;
  final bool showNetSpeed;
  final bool keepScreenOn;
  final bool doubleTapSeek;
  final int chromeAutoHideSec;
  /// 卡顿/失败时自动切换播放线路（默认关）
  final bool autoSourceFailover;
  /// 流畅 / 标准 / 高画质
  final PlayerPlayMode playMode;
  /// 迅速模式：边播边缓（分片预热 + 更大缓冲）
  final bool streamCacheEnabled;
  /// 自研画质增强
  final PlayerEnhanceLevel enhanceLevel;
  /// 播放内核
  final PlayerKernel kernel;

  PlayerSettingsPrefs copyWith({
    PlayerAspectMode? aspect,
    bool? holdBoostEnabled,
    double? holdBoostRate,
    bool? autoPlayNext,
    bool? loopSingle,
    bool? mirrorX,
    bool? mirrorY,
    bool? gestureEnabled,
    bool? showNetSpeed,
    bool? keepScreenOn,
    bool? doubleTapSeek,
    int? chromeAutoHideSec,
    bool? autoSourceFailover,
    PlayerPlayMode? playMode,
    bool? streamCacheEnabled,
    PlayerEnhanceLevel? enhanceLevel,
    PlayerKernel? kernel,
  }) {
    return PlayerSettingsPrefs(
      aspect: aspect ?? this.aspect,
      holdBoostEnabled: holdBoostEnabled ?? this.holdBoostEnabled,
      holdBoostRate: holdBoostRate ?? this.holdBoostRate,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      loopSingle: loopSingle ?? this.loopSingle,
      mirrorX: mirrorX ?? this.mirrorX,
      mirrorY: mirrorY ?? this.mirrorY,
      gestureEnabled: gestureEnabled ?? this.gestureEnabled,
      showNetSpeed: showNetSpeed ?? this.showNetSpeed,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
      chromeAutoHideSec: chromeAutoHideSec ?? this.chromeAutoHideSec,
      autoSourceFailover: autoSourceFailover ?? this.autoSourceFailover,
      playMode: playMode ?? this.playMode,
      streamCacheEnabled: streamCacheEnabled ?? this.streamCacheEnabled,
      enhanceLevel: enhanceLevel ?? this.enhanceLevel,
      kernel: kernel ?? this.kernel,
    );
  }

  Map<String, dynamic> toJson() => {
        'aspect': aspect.name,
        'hold_boost': holdBoostEnabled,
        'hold_rate': holdBoostRate,
        'auto_next': autoPlayNext,
        'loop': loopSingle,
        'mirror_x': mirrorX,
        'mirror_y': mirrorY,
        'gesture': gestureEnabled,
        'net_speed': showNetSpeed,
        'keep_on': keepScreenOn,
        'double_tap': doubleTapSeek,
        'chrome_hide': chromeAutoHideSec,
        'auto_source': autoSourceFailover,
        'play_mode': playMode.name,
        'stream_cache': streamCacheEnabled,
        'enhance': enhanceLevel.name,
        'kernel': kernel.name,
      };

  factory PlayerSettingsPrefs.fromJson(Map<String, dynamic> json) {
    final aspectName = '${json['aspect'] ?? 'fit'}';
    final aspect = PlayerAspectMode.values.firstWhere(
      (e) => e.name == aspectName,
      orElse: () => PlayerAspectMode.fit,
    );
    final modeName = '${json['play_mode'] ?? 'high'}';
    final playMode = PlayerPlayMode.values.firstWhere(
      (e) => e.name == modeName,
      orElse: () => PlayerPlayMode.high,
    );
    final enhanceName = '${json['enhance'] ?? 'vivid'}';
    final enhance = PlayerEnhanceLevel.values.firstWhere(
      (e) => e.name == enhanceName,
      orElse: () => PlayerEnhanceLevel.vivid,
    );
    // 仅保留系统 Exo
    const kernel = PlayerKernel.exo;
    return PlayerSettingsPrefs(
      aspect: aspect,
      holdBoostEnabled: json['hold_boost'] != false,
      holdBoostRate:
          ((json['hold_rate'] as num?)?.toDouble() ?? 2.0).clamp(1.5, 3.0),
      autoPlayNext: json['auto_next'] != false,
      loopSingle: json['loop'] == true,
      mirrorX: json['mirror_x'] == true,
      mirrorY: json['mirror_y'] == true,
      gestureEnabled: json['gesture'] != false,
      showNetSpeed: json['net_speed'] != false,
      keepScreenOn: json['keep_on'] != false,
      doubleTapSeek: json['double_tap'] != false,
      chromeAutoHideSec:
          ((json['chrome_hide'] as num?)?.toInt() ?? 4).clamp(2, 12),
      autoSourceFailover: json['auto_source'] == true,
      playMode: playMode,
      streamCacheEnabled: json['stream_cache'] != false,
      enhanceLevel: enhance,
      kernel: kernel,
    );
  }
}

class PlayerSettingsStore {
  PlayerSettingsStore._();

  static const _key = 'player_settings_prefs_v2';
  static const _legacyKey = 'player_settings_prefs_v1';
  static PlayerSettingsPrefs _cache = const PlayerSettingsPrefs();

  static PlayerSettingsPrefs get cached => _cache;

  static Future<PlayerSettingsPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_key);
    // 旧版可能误开镜像；迁移时强制关掉左右/上下翻转
    if (raw == null || raw.isEmpty) {
      final legacy = prefs.getString(_legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        try {
          final json = jsonDecode(legacy);
          if (json is Map) {
            final migrated = PlayerSettingsPrefs.fromJson(
              Map<String, dynamic>.from(json),
            ).copyWith(mirrorX: false, mirrorY: false);
            await save(migrated);
            await prefs.remove(_legacyKey);
            return _cache;
          }
        } catch (_) {}
      }
      return _cache;
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        _cache = PlayerSettingsPrefs.fromJson(
          Map<String, dynamic>.from(json),
        );
      }
    } catch (_) {}
    return _cache;
  }

  static Future<void> save(PlayerSettingsPrefs prefs) async {
    _cache = prefs;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(prefs.toJson()));
  }
}
