import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 跳过片头片尾偏好
class PlayerSkipPrefs {
  const PlayerSkipPrefs({
    this.enabled = false,
    this.introSeconds = 90,
    this.outroSeconds = 90,
  });

  final bool enabled;
  final int introSeconds;
  final int outroSeconds;

  PlayerSkipPrefs copyWith({
    bool? enabled,
    int? introSeconds,
    int? outroSeconds,
  }) {
    return PlayerSkipPrefs(
      enabled: enabled ?? this.enabled,
      introSeconds: introSeconds ?? this.introSeconds,
      outroSeconds: outroSeconds ?? this.outroSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'intro_seconds': introSeconds,
        'outro_seconds': outroSeconds,
      };

  factory PlayerSkipPrefs.fromJson(Map<String, dynamic> json) {
    return PlayerSkipPrefs(
      enabled: json['enabled'] == true,
      introSeconds: (json['intro_seconds'] as num?)?.toInt().clamp(0, 600) ?? 90,
      outroSeconds: (json['outro_seconds'] as num?)?.toInt().clamp(0, 600) ?? 90,
    );
  }
}

class PlayerSkipStore {
  PlayerSkipStore._();

  static const _key = 'player_skip_prefs_v1';
  static PlayerSkipPrefs _cache = const PlayerSkipPrefs();

  static PlayerSkipPrefs get cached => _cache;

  static Future<PlayerSkipPrefs> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return _cache;
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        _cache = PlayerSkipPrefs.fromJson(Map<String, dynamic>.from(json));
      }
    } catch (_) {}
    return _cache;
  }

  static Future<void> save(PlayerSkipPrefs prefs) async {
    _cache = prefs;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(prefs.toJson()));
  }
}
