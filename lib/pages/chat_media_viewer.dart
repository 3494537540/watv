import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../services/app_permission.dart';
import '../services/douyin_api.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/douyin_media_image.dart';
import '../widgets/app_page_route.dart';

bool looksLikeDirectVideoUrl(String url) {
  final u = url.toLowerCase();
  if (u.isEmpty || u.startsWith('data:')) return false;
  if (u.contains('douyin.com/video/') || u.contains('iesdouyin.com')) {
    return false;
  }
  if (u.startsWith('snssdk') || u.startsWith('aweme://')) return false;
  return u.contains('.mp4') ||
      u.contains('.m3u8') ||
      u.contains('mime_type=video') ||
      u.contains('/video/tos/') ||
      u.contains('playwm') ||
      u.contains('play_addr');
}

String _fmtDur(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final h = d.inHours;
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

/// 聊天媒体详情：全黑底、完整播放控件、图集预览可选保存
class ChatMediaViewerPage extends StatefulWidget {
  const ChatMediaViewerPage({
    super.key,
    required this.message,
    required this.accountId,
  });

  final DouyinChatMessage message;
  final int accountId;

  @override
  State<ChatMediaViewerPage> createState() => _ChatMediaViewerPageState();
}

class _ChatMediaViewerPageState extends State<ChatMediaViewerPage> {
  final _api = DouyinApi();
  final _pageCtrl = PageController();
  VideoPlayerController? _player;

  bool _resolving = false;
  bool _playerReady = false;
  bool _saving = false;
  bool _dragging = false;
  String? _resolveError;
  String _playUrl = '';
  String _cover = '';
  List<String> _images = [];
  bool _preferGallery = false;
  final Set<int> _selected = {};
  int _galleryIndex = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  DouyinChatMessage get m => widget.message;

  bool get _isGallery =>
      _preferGallery ||
      _images.length > 1 ||
      (_images.isNotEmpty && _playUrl.isEmpty);

  bool get _isVideo =>
      !_isGallery &&
      (m.kind == 'video' ||
          looksLikeDirectVideoUrl(m.mediaUrl) ||
          _playUrl.isNotEmpty ||
          m.awemeId.isNotEmpty ||
          m.link.contains('/video/'));

  String get _title {
    if (m.title.isNotEmpty) return m.title;
    final t = m.text.replaceFirst(RegExp(r'^\[.+?\]\s*'), '').trim();
    if (t.isNotEmpty) return t;
    if (_isGallery) return '图集';
    return m.kind == 'video' ? '视频' : '媒体详情';
  }

  String get _webLink {
    final id = m.awemeId.isNotEmpty ? m.awemeId : extractAwemeId(m.link);
    return normalizeDouyinWebLink(m.link, id);
  }

  @override
  void initState() {
    super.initState();
    _cover = m.coverUrl.isNotEmpty
        ? m.coverUrl
        : (m.thumbUrl.isNotEmpty ? m.thumbUrl : m.mediaUrl);
    // 单图消息直接作为图集一项
    if (m.kind == 'image' &&
        (m.displayImageUrl.isNotEmpty || m.mediaFile.isNotEmpty)) {
      if (m.displayImageUrl.isNotEmpty) {
        _images = [m.displayImageUrl];
        _preferGallery = true;
        _selected.add(0);
      }
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final needResolve = m.awemeId.isNotEmpty ||
        m.link.contains('/video/') ||
        m.kind == 'video' ||
        m.kind == 'card';
    if (needResolve) {
      await _resolveMedia();
    } else if (looksLikeDirectVideoUrl(m.mediaUrl)) {
      await _initPlayer(m.mediaUrl);
    }
  }

  Future<void> _resolveMedia() async {
    setState(() {
      _resolving = true;
      _resolveError = null;
    });
    try {
      if (looksLikeDirectVideoUrl(m.mediaUrl)) {
        await _initPlayer(m.mediaUrl);
        if (_playerReady) return;
      }
      final play = await _api.awemePlay(
        accountId: widget.accountId,
        awemeId: m.awemeId,
        link: m.link.isNotEmpty ? m.link : _webLink,
      );
      if (!mounted) return;
      if (play.cover.isNotEmpty) _cover = play.cover;
      if (play.desc.isNotEmpty && m.title.isEmpty) {
        // keep title from message; desc shown via subtitle area if needed
      }
      if (play.images.isNotEmpty) {
        setState(() {
          _images = play.images;
          _preferGallery = play.isGallery || play.playUrl.isEmpty;
          _selected
            ..clear()
            ..addAll(List.generate(_images.length, (i) => i));
          _resolving = false;
        });
        // 图集优先展示，不强制播视频
        if (play.isGallery || play.playUrl.isEmpty) return;
      }
      if (play.playUrl.isEmpty) {
        setState(() {
          _resolving = false;
          if (_images.isEmpty) {
            _resolveError = '未能解析到媒体地址';
          }
        });
        return;
      }
      _playUrl = play.playUrl;
      await _initPlayer(play.playUrl);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolveError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolveError = '媒体加载失败';
      });
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _initPlayer(String url) async {
    try {
      await _player?.dispose();
      final c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: const {
          'Referer': 'https://www.douyin.com/',
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        },
      );
      _player = c;
      c.addListener(_onPlayerTick);
      await c.initialize();
      if (!mounted) return;
      setState(() {
        _playerReady = true;
        _playUrl = url;
        _duration = c.value.duration;
        _position = c.value.position;
        _resolveError = null;
      });
      await c.setLooping(true);
      await c.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _playerReady = false;
        _resolveError = '播放器初始化失败';
      });
    }
  }

  void _onPlayerTick() {
    final p = _player;
    if (!mounted || p == null || _dragging) return;
    setState(() {
      _position = p.value.position;
      _duration = p.value.duration;
    });
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayerTick);
    _player?.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<bool> _ensureSavePermission() async {
    return AppPermission.requestWithRationale(
      AppPermissionKind.saveMedia,
      context: context,
      title: '需要保存到相册',
      message: '保存图片或视频到相册，方便你离线查看与分享。',
    );
  }

  Future<List<int>> _downloadBytes(String url) async {
    final res = await http
        .get(
          Uri.parse(url),
          headers: const {
            'Referer': 'https://www.douyin.com/',
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15',
          },
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final allowed = await _ensureSavePermission();
      if (!allowed) {
        DialogX.showWarning('请允许访问相册后再保存');
        return;
      }

      if (_isGallery) {
        final indexes = _selected.toList()..sort();
        if (indexes.isEmpty) {
          DialogX.showWarning('请先选择要保存的图片');
          return;
        }
        var ok = 0;
        for (final i in indexes) {
          if (i < 0 || i >= _images.length) continue;
          final url = _images[i];
          try {
            if (url.startsWith('data:')) {
              await Gal.putImageBytes(
                Uint8List.fromList(base64Decode(url.split(',').last)),
              );
            } else {
              await Gal.putImageBytes(
                Uint8List.fromList(await _downloadBytes(url)),
              );
            }
            ok++;
          } catch (_) {}
        }
        if (ok > 0) {
          DialogX.showSuccess('已保存 $ok 张图片到相册');
        } else {
          DialogX.showError('保存失败');
        }
        return;
      }

      if (_playUrl.isEmpty && _isVideo) {
        await _resolveMedia();
      }
      if (_playUrl.isNotEmpty && looksLikeDirectVideoUrl(_playUrl)) {
        final bytes = await _downloadBytes(_playUrl);
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/watv_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await file.writeAsBytes(bytes, flush: true);
        await Gal.putVideo(file.path);
        DialogX.showSuccess('视频已保存到相册');
        return;
      }

      final imageUrl = _cover.isNotEmpty
          ? _cover
          : (_images.isNotEmpty ? _images.first : m.displayImageUrl);
      if (imageUrl.isEmpty) {
        DialogX.showWarning('没有可保存的媒体');
        return;
      }
      if (imageUrl.startsWith('data:')) {
        await Gal.putImageBytes(
          Uint8List.fromList(base64Decode(imageUrl.split(',').last)),
        );
      } else {
        await Gal.putImageBytes(
          Uint8List.fromList(await _downloadBytes(imageUrl)),
        );
      }
      DialogX.showSuccess(_isVideo ? '未能下载视频，已保存封面' : '已保存到相册');
    } catch (_) {
      DialogX.showError('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openDetailWeb() {
    final link = _webLink;
    if (link.isEmpty) {
      DialogX.showWarning('暂无详情链接');
      return;
    }
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _DarkWebPage(title: '详情', url: link),
      ),
    );
  }

  void _togglePlay() {
    final p = _player;
    if (p == null || !_playerReady) {
      _resolveMedia();
      return;
    }
    if (p.value.isPlaying) {
      p.pause();
    } else {
      p.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarColor: Colors.black,
      ),
      child: Material(
        color: Colors.black,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Icon(
                        CupertinoIcons.back,
                        color: Color(0xFF0A84FF),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const Icon(
                              CupertinoIcons.arrow_down_to_line,
                              color: Colors.white,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _buildStage()),
            if (_playerReady && _player != null && !_isGallery)
              _buildVideoControls(),
            if (_isGallery) _buildGalleryBar(),
            _buildInfo(),
            _buildActions(),
            SizedBox(height: bottom > 0 ? bottom : 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    if (_isGallery) {
      return PageView.builder(
        controller: _pageCtrl,
        itemCount: _images.length,
        onPageChanged: (i) => setState(() => _galleryIndex = i),
        itemBuilder: (context, i) {
          final url = _images[i];
          final selected = _selected.contains(i);
          return Stack(
            fit: StackFit.expand,
            children: [
              DouyinMediaImage(
                url: url,
                fit: BoxFit.contain,
                fallbackLabel: '图${i + 1}',
              ),
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (selected) {
                        _selected.remove(i);
                      } else {
                        _selected.add(i);
                      }
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF0A84FF)
                          : Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70),
                    ),
                    child: Icon(
                      selected
                          ? CupertinoIcons.checkmark
                          : CupertinoIcons.circle,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    if (_playerReady && _player != null) {
      return GestureDetector(
        onTap: _togglePlay,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: _player!.value.aspectRatio == 0
                  ? 9 / 16
                  : _player!.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_player!),
                  if (!(_player!.value.isPlaying))
                    const Icon(
                      CupertinoIcons.play_circle_fill,
                      size: 64,
                      color: Colors.white70,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_cover.isNotEmpty || m.mediaFile.isNotEmpty)
            DouyinMediaImage(
              url: _cover,
              mediaFile: m.mediaFile,
              fit: BoxFit.contain,
              fallbackLabel: '',
            ),
          if (_resolving)
            const Center(
              child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
            )
          else
            Center(
              child: CupertinoButton(
                onPressed: _togglePlay,
                child: const Icon(
                  CupertinoIcons.play_circle_fill,
                  size: 72,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoControls() {
    final maxMs = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final playing = _player?.value.isPlaying ?? false;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(6),
            onPressed: _togglePlay,
            child: Icon(
              playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
              color: Colors.white,
              size: 22,
            ),
          ),
          Text(
            _fmtDur(_position),
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: const Color(0xFF0A84FF),
                inactiveTrackColor: const Color(0xFF3A3A3C),
                thumbColor: Colors.white,
              ),
              child: Slider(
                min: 0,
                max: maxMs,
                value: posMs,
                onChangeStart: (_) => setState(() => _dragging = true),
                onChanged: (v) {
                  setState(() => _position = Duration(milliseconds: v.round()));
                },
                onChangeEnd: (v) async {
                  final p = _player;
                  if (p != null) {
                    await p.seekTo(Duration(milliseconds: v.round()));
                  }
                  if (mounted) setState(() => _dragging = false);
                },
              ),
            ),
          ),
          Text(
            _fmtDur(_duration),
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildGalleryBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Text(
            '${_galleryIndex + 1}/${_images.length}',
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _selected
                  ..clear()
                  ..addAll(List.generate(_images.length, (i) => i));
              });
            },
            child: const Text(
              '全选',
              style: TextStyle(fontSize: 14, color: Color(0xFF0A84FF)),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.only(left: 12),
            onPressed: () => setState(_selected.clear),
            child: const Text(
              '清空',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ),
          Text(
            '已选 ${_selected.length}',
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (m.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              m.subtitle,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                color: Color(0xFFAEAEB2),
              ),
            ),
          ],
          if (_resolveError != null) ...[
            const SizedBox(height: 6),
            Text(
              _resolveError!,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                color: Color(0xFFFF453A),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (!_isGallery) ...[
            Expanded(
              child: _ActionBtn(
                icon: (_player?.value.isPlaying ?? false)
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                label: _resolving
                    ? '解析中'
                    : ((_player?.value.isPlaying ?? false) ? '暂停' : '播放'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _togglePlay();
                },
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: _ActionBtn(
              icon: CupertinoIcons.doc_text,
              label: '详情',
              onTap: () {
                HapticFeedback.selectionClick();
                _openDetailWeb();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionBtn(
              icon: CupertinoIcons.arrow_down_to_line_alt,
              label: _isGallery ? '保存所选' : '保存',
              onTap: () {
                HapticFeedback.selectionClick();
                _save();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkWebPage extends StatelessWidget {
  const _DarkWebPage({required this.title, required this.url});

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: Colors.black,
      ),
      child: Material(
        color: Colors.black,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Icon(
                        CupertinoIcons.back,
                        color: Color(0xFF0A84FF),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  supportZoom: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                ),
                initialUrlRequest: URLRequest(url: WebUri(url)),
                shouldOverrideUrlLoading: (controller, action) async {
                  final u = action.request.url;
                  if (u == null) return NavigationActionPolicy.ALLOW;
                  final s = u.toString();
                  if (s.startsWith('snssdk') ||
                      s.startsWith('aweme://') ||
                      s.startsWith('bytedance')) {
                    final id = extractAwemeId(s);
                    if (id.isNotEmpty) {
                      await controller.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri('https://www.douyin.com/video/$id'),
                        ),
                      );
                    }
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
              ),
            ),
            SizedBox(height: bottom),
          ],
        ),
      ),
    );
  }
}
