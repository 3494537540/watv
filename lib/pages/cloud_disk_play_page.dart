import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie_models.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/player/mango_inline_player.dart';
import '../widgets/app_page_route.dart';

/// 粘贴云盘 / 直链视频地址后播放（m3u8 / mp4 等）
class CloudDiskPlayPage extends StatefulWidget {
  const CloudDiskPlayPage({super.key});

  @override
  State<CloudDiskPlayPage> createState() => _CloudDiskPlayPageState();
}

class _CloudDiskPlayPageState extends State<CloudDiskPlayPage> {
  final _urlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _play() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      DialogX.showWarning('请输入有效的 http/https 视频链接');
      return;
    }
    final title = _titleCtrl.text.trim().isEmpty
        ? '云盘视频'
        : _titleCtrl.text.trim();
    final movie = Movie(
      id: 'cloud_${url.hashCode}',
      title: title,
      subtitle: '外链播放',
      year: 0,
      score: 0,
      genres: const ['云盘'],
      coverColor: const Color(0xFF1ECAD3),
      tagline: url,
      synopsis: '通过直链播放的云盘视频',
      playEpisodes: [MoviePlayEpisode(name: '正片', url: url)],
      playSourceNames: const ['直链'],
      playSources: [
        MoviePlaySource(
          name: '直链',
          episodes: [MoviePlayEpisode(name: '正片', url: url)],
        ),
      ],
    );
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _CloudPlayerScaffold(movie: movie, url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF181818),
        title: const Text(
          '链接云盘视频',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          const Text(
            '支持直链 m3u8 / mp4 等地址。网盘分享页需先解析为可播直链。',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: Color(0xFF8E8E93),
              height: 1.4,
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              labelText: '标题（可选）',
              labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            textAlign: TextAlign.left,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: '视频链接',
              alignLabelWithHint: true,
              labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
              hintText: 'https://.../*.m3u8 或 *.mp4',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _play,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                '播放',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudPlayerScaffold extends StatelessWidget {
  const _CloudPlayerScaffold({required this.movie, required this.url});

  final Movie movie;
  final String url;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: MangoInlinePlayer(
        url: url,
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
        immersiveTop: true,
        episodes: movie.playEpisodes,
        selectedEpisode: 0,
        sourceNames: movie.playSourceNames,
        sourceIndex: 0,
        vodId: movie.id,
        danmakuTitle: movie.title,
        topOverlay: Padding(
          padding: EdgeInsets.fromLTRB(8, top + 4, 8, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  movie.title,
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
    );
  }
}
