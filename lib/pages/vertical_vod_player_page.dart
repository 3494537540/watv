import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../services/maccms_api.dart';
import '../widgets/figma_loading.dart';
import '../widgets/player/mango_inline_player.dart';

/// 竖屏点播页（体育等）：无弹幕、保持竖屏壳
class VerticalVodPlayerPage extends StatefulWidget {
  const VerticalVodPlayerPage({super.key, required this.movie});

  final Movie movie;

  @override
  State<VerticalVodPlayerPage> createState() => _VerticalVodPlayerPageState();
}

class _VerticalVodPlayerPageState extends State<VerticalVodPlayerPage> {
  final _api = MacCmsApi();
  Movie? _detail;
  bool _loading = true;
  String? _error;
  int _ep = 0;
  int _source = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    unawaited(_load());
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var m = widget.movie;
      if (m.playSources.isEmpty || m.playUrlAt(0) == null) {
        final d = await _api.fetchVodDetail(m.id);
        if (d != null) m = d;
      }
      if (!mounted) return;
      setState(() {
        _detail = m;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: FigmaMetaballLoader(size: 48)),
      );
    }
    final m = _detail;
    if (m == null || _error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: TextButton(
            onPressed: () => unawaited(_load()),
            child: Text(
              _error ?? '加载失败',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
    final eps = m.episodesOf(_source);
    final url = eps.isEmpty
        ? (m.playUrlAt(0) ?? '')
        : eps[_ep.clamp(0, eps.length - 1)].url;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: url.isEmpty
                ? const Center(
                    child: Text('暂无播放地址',
                        style: TextStyle(color: Colors.white70)),
                  )
                : MangoInlinePlayer(
                    url: url,
                    showBack: true,
                    onBack: () => Navigator.of(context).pop(),
                    immersiveTop: true,
                    enableDanmaku: false,
                    episodes: eps,
                    selectedEpisode: _ep,
                    onEpisodeSelect: (i) => setState(() => _ep = i),
                    sourceNames: [for (final s in m.playSources) s.name],
                    sourceIndex: _source,
                    onSourceSelect: (i) => setState(() {
                      _source = i;
                      _ep = 0;
                    }),
                    vodId: m.id,
                    danmakuTitle: m.title,
                    showEpisodesInMenu: eps.length > 1,
                    topOverlay: Padding(
                      padding: EdgeInsets.fromLTRB(4, top + 2, 8, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(CupertinoIcons.back,
                                color: Colors.white),
                          ),
                          Expanded(
                            child: Text(
                              m.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          Expanded(
            flex: 4,
            child: ColoredBox(
              color: Colors.white,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  Text(
                    m.title,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF181818),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (m.remarks.isNotEmpty) m.remarks,
                      if (m.area.isNotEmpty) m.area,
                      if (m.year > 0) '${m.year}',
                    ].join(' · '),
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                  if (m.synopsis.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      m.synopsis.trim(),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ],
                  if (eps.length > 1) ...[
                    const SizedBox(height: 14),
                    const Text(
                      '选集',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < eps.length; i++)
                          GestureDetector(
                            onTap: () => setState(() => _ep = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: i == _ep
                                    ? const Color(0xFF1ECAD3)
                                    : const Color(0xFFF2F3F5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                eps[i].name,
                                style: TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: i == _ep
                                      ? Colors.white
                                      : const Color(0xFF666666),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
