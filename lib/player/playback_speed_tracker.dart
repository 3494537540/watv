import 'dart:math' as math;

import 'package:video_player/video_player.dart';

/// 根据缓冲进度估算下载速率；加载期间文案会持续变化
class PlaybackSpeedTracker {
  Duration _lastEnd = Duration.zero;
  DateTime? _lastAt;
  double _emaBps = 0;
  double _displayBps = 0;
  String? _cachedLabel;
  double _cachedLabelBps = 0;
  bool _loading = false;
  DateTime? _loadingSince;
  int _tickFrame = 0;

  static const _bytesPerVideoSecond = 2.8 * 1024 * 1024 / 8;

  void reset() {
    _lastEnd = Duration.zero;
    _lastAt = null;
    _emaBps = 0;
    _displayBps = 0;
    _cachedLabel = null;
    _cachedLabelBps = 0;
    _loading = false;
    _loadingSince = null;
    _tickFrame = 0;
  }

  /// 只清计量，保留 loading 态（拖动松手后重新计量用）
  void resetMetrics() {
    _lastEnd = Duration.zero;
    _lastAt = null;
    _emaBps = 0;
    _displayBps = 0;
    _cachedLabel = null;
    _cachedLabelBps = 0;
    _tickFrame = 0;
    if (_loading) {
      _loadingSince = DateTime.now();
    }
  }

  void setLoading(bool loading) {
    if (loading && !_loading) {
      _loadingSince = DateTime.now();
      _displayBps = 0;
      _cachedLabel = null;
    }
    _loading = loading;
    if (!loading) {
      _loadingSince = null;
      _tickFrame = 0;
    }
  }

  void tick(List<DurationRange> buffered, {bool isBuffering = false}) {
    _tickFrame++;
    if (_loading || isBuffering) {
      // 先刷新合成速率，避免界面数字卡住
      _pulseSynthetic();
    }

    if (buffered.isEmpty) return;

    var end = Duration.zero;
    for (final r in buffered) {
      if (r.end > end) end = r.end;
    }
    final now = DateTime.now();
    if (_lastAt != null && end > _lastEnd) {
      final dt = now.difference(_lastAt!).inMilliseconds / 1000.0;
      if (dt >= 0.2) {
        final gainedSec = (end - _lastEnd).inMilliseconds / 1000.0;
        if (gainedSec > 0) {
          final bps = gainedSec * _bytesPerVideoSecond / dt;
          _emaBps = _emaBps <= 0 ? bps : _emaBps * 0.75 + bps * 0.25;
          _displayBps = _displayBps <= 0
              ? _emaBps
              : _displayBps * 0.7 + _emaBps * 0.3;
          _cachedLabel = null;
        }
        _lastEnd = end;
        _lastAt = now;
        return;
      }
    }
    if (_lastAt == null || end > _lastEnd) {
      _lastEnd = end;
      _lastAt = now;
    }
  }

  void _pulseSynthetic() {
    final since = _loadingSince ?? DateTime.now();
    final sec = nowMs(since);
    final wobble =
        math.sin(sec * 2.8) * 90 + math.sin(sec * 1.3 + 1.1) * 55;
    final base = 260 + sec * 140;
    final kb = (base + wobble).clamp(140.0, 3200.0);
    // 合成值只在真实速率很低时覆盖，有真实缓冲增速则保留
    if (_emaBps < 40 * 1024) {
      _displayBps = kb * 1024;
      if (_tickFrame % 2 == 0) _cachedLabel = null;
    }
  }

  double nowMs(DateTime since) =>
      DateTime.now().difference(since).inMilliseconds / 1000.0;

  String? get label {
    final bps = _displayBps;
    if (bps <= 64) return null;

    if (_cachedLabel != null && _cachedLabelBps > 0) {
      final rel = (bps - _cachedLabelBps).abs() / _cachedLabelBps;
      // 加载中更频繁换文案，避免一直停在同一个数
      final threshold = _loading ? 0.012 : 0.04;
      if (rel < threshold) return _cachedLabel;
    }

    final text = bps >= 1024 * 1024
        ? '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s'
        : '${(bps / 1024).toStringAsFixed(0)} KB/s';
    _cachedLabel = text;
    _cachedLabelBps = bps;
    return text;
  }

  String get displayLabel {
    // 加载 HUD 定时刷新时也会读这里，主动脉冲避免数字卡住
    if (_loading) {
      _tickFrame++;
      _pulseSynthetic();
    }
    final real = label;
    if (real != null) return real;
    if (!_loading) return '— KB/s';
    return '${(180 + (_tickFrame % 40)).toString()} KB/s';
  }
}
