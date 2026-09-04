import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/app_security.dart';
import '../services/local_play_store.dart';
import '../services/maccms_api.dart';
import 'figma_loading.dart';

/// CMS 封面：带内存缓存，横滑回收后不再闪骨架重拉
class CmsCoverImage extends StatefulWidget {
  const CmsCoverImage({
    super.key,
    required this.url,
    this.vodId,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });

  final String? url;
  final String? vodId;
  final BoxFit fit;
  final Alignment alignment;

  /// 已解码字节缓存（按最终请求 URL）
  static final LinkedHashMap<String, Uint8List> _mem =
      LinkedHashMap<String, Uint8List>();
  static const _memMax = 96;

  static Uint8List? cacheGet(String url) => _mem[url];

  static void cachePut(String url, Uint8List bytes) {
    if (url.isEmpty || bytes.isEmpty) return;
    _mem.remove(url);
    _mem[url] = bytes;
    while (_mem.length > _memMax) {
      _mem.remove(_mem.keys.first);
    }
  }

  static Map<String, String> headersFor(String resolvedUrl) {
    final uri = Uri.tryParse(resolvedUrl);
    final host = uri?.host ?? '';
    final isProxy = resolvedUrl.contains('api=img_proxy');
    final referer = isProxy
        ? '${ApiConfig.macCmsBase}/'
        : (host.isEmpty
            ? '${ApiConfig.macCmsBase}/'
            : '${uri!.scheme}://$host/');
    return {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Referer': referer,
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }

  static Map<String, String> get headers => headersFor(ApiConfig.macCmsBase);

  static const _proxyHosts = {
    'pic.yayazy.info',
    'yayazy.info',
  };

  static bool needsImgProxy(String absoluteUrl) {
    final host = Uri.tryParse(absoluteUrl)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    final cmsHost =
        Uri.tryParse(ApiConfig.macCmsBase)?.host.toLowerCase() ?? '';
    if (cmsHost.isNotEmpty && (host == cmsHost || host.endsWith('.$cmsHost'))) {
      return false;
    }
    for (final h in _proxyHosts) {
      if (host == h || host.endsWith('.$h')) return true;
    }
    return false;
  }

  static String? resolve(String? raw, {bool preferProxy = true}) {
    final p = (raw ?? '').trim();
    if (p.isEmpty) return null;
    final lower = p.toLowerCase();
    if (lower.contains('nopic') ||
        lower.contains('nopicture') ||
        lower.contains('no_pic') ||
        lower.endsWith('default.png') ||
        lower.endsWith('default.jpg')) {
      return null;
    }
    String absolute;
    if (p.startsWith('//')) {
      absolute = 'https:$p';
    } else if (p.startsWith('http://') || p.startsWith('https://')) {
      absolute = p;
    } else if (p.startsWith('/')) {
      absolute = '${ApiConfig.macCmsBase}$p';
    } else {
      absolute = '${ApiConfig.macCmsBase}/$p';
    }
    if (preferProxy && needsImgProxy(absolute)) {
      return ApiConfig.huihuoImgProxyUrl(absolute);
    }
    return absolute;
  }

  static String? resolveDirect(String? raw) =>
      resolve(raw, preferProxy: false);

  @override
  State<CmsCoverImage> createState() => _CmsCoverImageState();
}

class _CmsCoverImageState extends State<CmsCoverImage>
    with AutomaticKeepAliveClientMixin {
  String? _url;
  Uint8List? _bytes;
  bool _imageReady = false;
  bool _detailTried = false;
  bool _proxyTried = false;
  Object? _loadToken;

  bool get _showSkeleton => _bytes == null && !_imageReady;

  @override
  bool get wantKeepAlive => _bytes != null || _imageReady;

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _hydrateFromCache();
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant CmsCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.vodId != widget.vodId) {
      _url = widget.url;
      _bytes = null;
      _imageReady = false;
      _detailTried = false;
      _proxyTried = false;
      _hydrateFromCache();
      unawaited(_bootstrap());
    }
  }

  void _hydrateFromCache() {
    final resolved = CmsCoverImage.resolve(_url);
    if (resolved == null) return;
    final hit = CmsCoverImage.cacheGet(resolved);
    if (hit != null) {
      _bytes = hit;
      _imageReady = true;
    }
  }

  Future<void> _bootstrap() async {
    final resolved = CmsCoverImage.resolve(_url);
    if (resolved != null) {
      final hit = CmsCoverImage.cacheGet(resolved);
      if (hit != null) {
        if (!mounted) return;
        setState(() {
          _bytes = hit;
          _imageReady = true;
        });
        updateKeepAlive();
        return;
      }
      if (mounted) setState(() {});
      final ok = await _loadBytes(resolved);
      if (ok || !mounted) return;
    }
    final direct = CmsCoverImage.resolveDirect(_url);
    if (direct != null &&
        !_proxyTried &&
        !CmsCoverImage.needsImgProxy(direct)) {
      _proxyTried = true;
      final viaProxy = ApiConfig.huihuoImgProxyUrl(direct);
      final cached = CmsCoverImage.cacheGet(viaProxy);
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          _bytes = cached;
          _imageReady = true;
        });
        updateKeepAlive();
        return;
      }
      final ok = await _loadBytes(viaProxy);
      if (ok || !mounted) return;
    }
    await _refetchDetail();
  }

  Future<void> _refetchDetail() async {
    final id = (widget.vodId ?? '').trim();
    if (id.isEmpty || _detailTried) return;
    _detailTried = true;
    try {
      final m = await MacCmsApi()
          .fetchDetail(id)
          .timeout(const Duration(seconds: 12));
      final raw = (m.coverUrl ?? m.slideUrl ?? '').trim();
      final resolved = CmsCoverImage.resolve(raw);
      if (resolved == null) return;
      final hit = CmsCoverImage.cacheGet(resolved);
      if (hit != null) {
        if (!mounted) return;
        setState(() {
          _url = raw;
          _bytes = hit;
          _imageReady = true;
        });
        updateKeepAlive();
        unawaited(LocalPlayStore.updatePic(vodId: id, pic: raw));
        return;
      }
      if (!mounted) return;
      setState(() {
        _url = raw;
        _bytes = null;
        _imageReady = false;
      });
      unawaited(LocalPlayStore.updatePic(vodId: id, pic: raw));
      final ok = await _loadBytes(resolved);
      if (ok || !mounted) return;
      final direct = CmsCoverImage.resolveDirect(raw);
      if (direct != null && !CmsCoverImage.needsImgProxy(direct)) {
        await _loadBytes(ApiConfig.huihuoImgProxyUrl(direct));
      }
    } catch (_) {}
  }

  Future<bool> _loadBytes(String resolved) async {
    if (kIsWeb) return false;
    final cached = CmsCoverImage.cacheGet(resolved);
    if (cached != null) {
      if (!mounted) return true;
      setState(() {
        _bytes = cached;
        _imageReady = true;
      });
      updateKeepAlive();
      return true;
    }
    final token = Object();
    _loadToken = token;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      AppSecurity.instance.hardenClient(client);
      try {
        final req = await client.getUrl(Uri.parse(resolved));
        CmsCoverImage.headersFor(resolved).forEach(req.headers.set);
        final res = await req.close().timeout(const Duration(seconds: 18));
        if (res.statusCode < 200 || res.statusCode >= 300) return false;
        final data = await consolidateHttpClientResponseBytes(res);
        if (data.isEmpty || data.length < 32) return false;
        final head = String.fromCharCodes(data.take(24));
        if (head.contains('fetch failed') || head.contains('bad url')) {
          return false;
        }
        CmsCoverImage.cachePut(resolved, data);
        if (!mounted || _loadToken != token) return false;
        setState(() {
          _bytes = data;
          _imageReady = true;
        });
        updateKeepAlive();
        return true;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final resolved = CmsCoverImage.resolve(_url);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showSkeleton)
          const Positioned.fill(
            child: FigmaSkeletonPulse(
              child: FigmaCoverPlaceholder(iconSize: 28),
            ),
          ),
        if (_bytes != null)
          Image.memory(
            _bytes!,
            fit: widget.fit,
            alignment: widget.alignment,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        else if (resolved != null)
          Image.network(
            resolved,
            key: ValueKey(resolved),
            fit: widget.fit,
            alignment: widget.alignment,
            headers: CmsCoverImage.headersFor(resolved),
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            cacheWidth: 360,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                if (!_imageReady) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _bytes == null) {
                      setState(() => _imageReady = true);
                      updateKeepAlive();
                    }
                  });
                }
                return child;
              }
              return const SizedBox.shrink();
            },
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}
