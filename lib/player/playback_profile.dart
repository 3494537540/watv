import 'player_settings_store.dart';

/// 由「流畅 / 标准 / 高画质」推导出的播放策略参数
class PlaybackProfile {
  const PlaybackProfile({
    required this.backBufferMs,
    required this.holdEnterAheadMs,
    required this.holdResumeAheadMs,
    required this.warmSegmentCount,
  });

  /// Exo / AVPlayer 回退缓冲
  final int backBufferMs;

  /// 前方缓冲低于该值时进入「攒缓冲」
  final int holdEnterAheadMs;

  /// 攒到该值再继续播
  final int holdResumeAheadMs;

  /// 边播边缓：预热分片数量
  final int warmSegmentCount;

  static PlaybackProfile of(PlayerSettingsPrefs prefs) {
    final base = switch (prefs.playMode) {
      PlayerPlayMode.smooth => const PlaybackProfile(
          backBufferMs: 150000,
          holdEnterAheadMs: 4000,
          holdResumeAheadMs: 9000,
          warmSegmentCount: 4,
        ),
      PlayerPlayMode.standard => const PlaybackProfile(
          backBufferMs: 110000,
          holdEnterAheadMs: 3000,
          holdResumeAheadMs: 7000,
          warmSegmentCount: 3,
        ),
      PlayerPlayMode.high => const PlaybackProfile(
          backBufferMs: 70000,
          holdEnterAheadMs: 2200,
          holdResumeAheadMs: 4500,
          warmSegmentCount: 2,
        ),
    };
    if (!prefs.streamCacheEnabled) {
      return PlaybackProfile(
        backBufferMs: base.backBufferMs,
        holdEnterAheadMs: base.holdEnterAheadMs,
        holdResumeAheadMs: base.holdResumeAheadMs,
        warmSegmentCount: 0,
      );
    }
    // 预热开启：轻量前方分片（真正吃缓存要靠播放器自己）
    return PlaybackProfile(
      backBufferMs: base.backBufferMs,
      holdEnterAheadMs: base.holdEnterAheadMs,
      holdResumeAheadMs: base.holdResumeAheadMs,
      warmSegmentCount: base.warmSegmentCount.clamp(1, 3),
    );
  }
}
