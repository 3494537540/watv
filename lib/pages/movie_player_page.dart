import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../services/local_play_store.dart';
import '../widgets/cast_sheet.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/player/mango_inline_player.dart';
import '../widgets/player/mango_player_chrome.dart';

/// 全屏播放页（横屏，退出时回传当前进度 ms）
class MoviePlayerFullscreenPage extends StatefulWidget {
  const MoviePlayerFullscreenPage({
    super.key,
    required this.movie,
    required this.episodeIndex,
    required this.sourceIndex,
    required this.playUrl,
    this.startPositionMs = 0,
  });

  final Movie movie;
  final int episodeIndex;
  final int sourceIndex;
  final String playUrl;
  final int startPositionMs;

  @override
  State<MoviePlayerFullscreenPage> createState() =>
      _MoviePlayerFullscreenPageState();
}

class _MoviePlayerFullscreenPageState extends State<MoviePlayerFullscreenPage> {
  final _playerKey = GlobalKey<MangoInlinePlayerState>();
  late int _episodeIndex;
  late int _sourceIndex;
  late String _playUrl;
  late int _startMs;
  final Set<int> _failedSources = <int>{};

  @override
  void initState() {
    super.initState();
    _episodeIndex = widget.episodeIndex;
    _sourceIndex = widget.sourceIndex;
    _playUrl = widget.playUrl;
    _startMs = widget.startPositionMs;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _restoreUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exit() {
    final ms = _playerKey.currentState?.positionMs ?? _startMs;
    _restoreUi();
    Navigator.of(context).pop((ms, _episodeIndex));
  }

  @override
  void dispose() {
    _restoreUi();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    unawaited(_playerKey.currentState?.forceStop());
  }

  List<MoviePlayEpisode> get _episodes =>
      widget.movie.episodesOf(_sourceIndex);

  bool get _hasNext => _episodeIndex < _episodes.length - 1;

  String get _episodeLabel {
    final eps = _episodes;
    if (eps.length > 1) {
      return '第${(_episodeIndex + 1).toString().padLeft(2, '0')}集';
    }
    if (_episodeIndex >= 0 && _episodeIndex < eps.length) {
      return eps[_episodeIndex].name;
    }
    return '第${_episodeIndex + 1}集';
  }

  Future<bool> _tryNextPlaySource() async {
    final sources = widget.movie.playSources;
    if (sources.length <= 1) return false;
    _failedSources.add(_sourceIndex);
    final wantName = () {
      final cur = _episodes;
      if (_episodeIndex >= 0 && _episodeIndex < cur.length) {
        return cur[_episodeIndex].name.trim();
      }
      return '';
    }();
    for (var i = 0; i < sources.length; i++) {
      if (_failedSources.contains(i)) continue;
      final eps = sources[i].episodes;
      if (eps.isEmpty) continue;
      var ep = _episodeIndex;
      if (ep < 0 || ep >= eps.length) {
        ep = 0;
        if (wantName.isNotEmpty) {
          final j = eps.indexWhere((e) => e.name.trim() == wantName);
          if (j >= 0) ep = j;
        }
      }
      final u = eps[ep].url.trim();
      if (u.isEmpty) continue;
      setState(() {
        _sourceIndex = i;
        _episodeIndex = ep;
        _playUrl = u;
        _startMs = 0;
      });
      DialogX.showWarning('当前线路异常，已自动切换');
      return true;
    }
    return false;
  }

  void _playNextEpisode() {
    if (!_hasNext) return;
    final next = _episodeIndex + 1;
    final url = widget.movie.playUrlAt(next, sourceIndex: _sourceIndex);
    if (url == null || url.isEmpty) return;
    _failedSources.clear();
    setState(() {
      _episodeIndex = next;
      _playUrl = url;
      _startMs = 0;
    });
  }

  Future<void> _saveProgress(Duration position, Duration duration) async {
    if (duration.inMilliseconds < 1000) return;
    await LocalPlayStore.add(
      vodId: widget.movie.id,
      name: widget.movie.title,
      pic: widget.movie.coverUrl ?? '',
      episodeIndex: _episodeIndex,
      episodeLabel: _episodeLabel,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
    );
  }

  void _onCastTap() {
    unawaited(
      showCastSheet(
        context: context,
        mediaUrl: _playUrl,
        title: widget.movie.title,
        onCastStarted: () {
          unawaited(_playerKey.currentState?.pause());
        },
        onCastStopped: () {
          unawaited(_playerKey.currentState?.play());
        },
      ),
    );
  }

  String _watchTag() {
    if (_episodes.length > 1) return '全${_episodes.length}集';
    final remarks = widget.movie.remarks.trim();
    if (remarks.isNotEmpty) return remarks;
    final sub = widget.movie.subtitle.trim();
    if (sub.isNotEmpty) return sub;
    return '高清';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MangoInlinePlayer(
          key: _playerKey,
          url: _playUrl,
          startPositionMs: _startMs,
          immersiveTop: true,
          episodes: _episodes,
          selectedEpisode: _episodeIndex,
          onEpisodeSelect: (i) {
            final u = widget.movie.playUrlAt(i, sourceIndex: _sourceIndex);
            if (u == null || u.isEmpty) return;
            _failedSources.clear();
            setState(() {
              _episodeIndex = i;
              _playUrl = u;
              _startMs = 0;
            });
          },
          sourceNames: [for (final s in widget.movie.playSources) s.name],
          sourceIndex: _sourceIndex,
          onRequestSourceFailover: _tryNextPlaySource,
          onPrepareRetry: () async {
            _failedSources.clear();
            if (_sourceIndex != 0) {
              final u = widget.movie.playUrlAt(
                _episodeIndex,
                sourceIndex: 0,
              );
              if (u != null && u.isNotEmpty) {
                setState(() {
                  _sourceIndex = 0;
                  _playUrl = u;
                  _startMs = 0;
                });
              }
            }
          },
          onProgress: _saveProgress,
          showNextEpisode: _hasNext,
          onNextEpisode: _hasNext ? _playNextEpisode : null,
          showEpisodesInMenu: true,
          vodId: widget.movie.id,
          danmakuTitle: widget.movie.title,
          danmakuEpisode: _episodeIndex,
          danmakuEpisodeLabel: _episodes.length > 1 ? _episodeLabel : '',
          topOverlay: MangoWatchTopBar(
            topInset: top,
            title: widget.movie.title,
            episodeLabel: _episodes.length > 1 ? _episodeLabel : '',
            tag: _watchTag(),
            onCast: _onCastTap,
            onSettings: () => _playerKey.currentState?.openSettings(),
            onBack: _exit,
          ),
          onCast: _onCastTap,
        ),
      ),
    );
  }
}
