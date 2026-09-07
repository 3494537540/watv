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
      // 秒开向：起播后也尽快攒够前方缓冲，减少二次卡顿
      PlayerPlayMode.smooth => const PlaybackProfile(
          backBufferMs: 180000,
          holdEnterAheadMs: 3500,
          holdResumeAheadMs: 10000,
          warmSegmentCount: 4,
        ),
      PlayerPlayMode.standard => const PlaybackProfile(
          backBufferMs: 140000,
          holdEnterAheadMs: 2800,
          holdResumeAheadMs: 8000,
          warmSegmentCount: 3,
        ),
      PlayerPlayMode.high => const PlaybackProfile(
          backBufferMs: 90000,
          holdEnterAheadMs: 2200,
          holdResumeAheadMs: 5500,
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
