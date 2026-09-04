import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/movie_models.dart';
import '../services/cms_app_config.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/player/mango_inline_player.dart';
import '../widgets/app_page_route.dart';

/// BT / 磁力链接：走后台配置的解析接口，成功后直链播放
class BtPlayPage extends StatefulWidget {
  const BtPlayPage({super.key});

  @override
  State<BtPlayPage> createState() => _BtPlayPageState();
}

class _BtPlayPageState extends State<BtPlayPage> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _looksMagnetOrTorrent(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('magnet:?') ||
        t.endsWith('.torrent') ||
        t.contains('magnet:?xt=urn:btih:');
  }

  Future<void> _play() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      DialogX.showWarning('请粘贴磁力链接或种子地址');
      return;
    }
    if (!_looksMagnetOrTorrent(raw) &&
        !(raw.startsWith('http://') || raw.startsWith('https://'))) {
      DialogX.showWarning('仅支持 magnet / .torrent / http 种子地址');
      return;
    }

    setState(() => _busy = true);
    try {
      final api = CmsAppConfigStore.instance.config.torrentParseApi.trim();
      String? playUrl;
      String title = 'BT 播放';

      if (api.isNotEmpty) {
        final uri = Uri.parse(api).replace(
          queryParameters: {
            ...Uri.parse(api).queryParameters,
            'url': raw,
          },
        );
        final res = await http
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 25));
        final body = utf8.decode(res.bodyBytes).trim();
        if (body.startsWith('{')) {
          final j = jsonDecode(body);
          if (j is Map) {
            playUrl = '${j['url'] ?? j['play_url'] ?? j['data'] ?? ''}'.trim();
            if (playUrl.isEmpty && j['data'] is Map) {
              playUrl = '${(j['data'] as Map)['url'] ?? ''}'.trim();
            }
            final n = '${j['name'] ?? j['title'] ?? ''}'.trim();
            if (n.isNotEmpty) title = n;
          }
        } else if (body.startsWith('http')) {
          playUrl = body.split('\n').first.trim();
        }
      }

      // 若本身已是可播直链（少见）
      if ((playUrl == null || playUrl.isEmpty) &&
          (raw.contains('.m3u8') || raw.contains('.mp4'))) {
        playUrl = raw;
      }

      if (playUrl == null ||
          playUrl.isEmpty ||
          !(playUrl.startsWith('http://') || playUrl.startsWith('https://'))) {
        if (!mounted) return;
        await showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('暂无法直接播放'),
            content: Text(
              api.isEmpty
                  ? '请在后台 app_config.json 配置 torrent_parse_api（磁力→m3u8/mp4 解析地址），或使用站内已转码资源。'
                  : '解析接口未返回可播地址，请检查后台解析服务。',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
              CupertinoDialogAction(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: raw));
                  if (ctx.mounted) Navigator.pop(ctx);
                  DialogX.showSuccess('已复制链接');
                },
                child: const Text('复制链接'),
              ),
            ],
          ),
        );
        return;
      }

      if (!mounted) return;
      HapticFeedback.selectionClick();
      final movie = Movie(
        id: 'bt_${playUrl.hashCode}',
        title: title,
        subtitle: 'BT',
        year: 0,
        score: 0,
        genres: const ['BT'],
        coverColor: const Color(0xFF1ECAD3),
        tagline: raw,
        synopsis: raw,
        playEpisodes: [MoviePlayEpisode(name: '正片', url: playUrl)],
        playSourceNames: const ['BT'],
        playSources: [
          MoviePlaySource(
            name: 'BT',
            episodes: [MoviePlayEpisode(name: '正片', url: playUrl)],
          ),
        ],
      );
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => _BtPlayerScaffold(movie: movie, url: playUrl!),
        ),
      );
    } catch (e) {
      DialogX.showWarning('解析失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          'BT / 磁力播放',
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
          Text(
            '粘贴 magnet 或 .torrent 地址。需在后台 app_config.json 配置 torrent_parse_api，将磁力解析为可播 m3u8/mp4。',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: Color(0xFF8E8E93),
              height: 1.45,
            ),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            minLines: 4,
            maxLines: 8,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              labelText: '磁力 / 种子链接',
              alignLabelWithHint: true,
              labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
              hintText: 'magnet:?xt=urn:btih:...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _play,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: _busy
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                      '解析并播放',
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

class _BtPlayerScaffold extends StatelessWidget {
  const _BtPlayerScaffold({required this.movie, required this.url});

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
