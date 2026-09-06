import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'player_settings_store.dart';

/// HLS 清晰度档位
enum VodQualityTier {
  auto,
  q4k,
  q1080,
  q720,
  q480,
  q360,
}

extension VodQualityTierX on VodQualityTier {
  String get label => switch (this) {
        VodQualityTier.auto => '自动',
        VodQualityTier.q4k => '4K',
        VodQualityTier.q1080 => '1080P',
        VodQualityTier.q720 => '720P',
        VodQualityTier.q480 => '480P',
        VodQualityTier.q360 => '360P',
      };

  /// 目标高度下限（自动档不使用）
  int get minHeight => switch (this) {
        VodQualityTier.auto => 0,
        VodQualityTier.q4k => 2160,
        VodQualityTier.q1080 => 1080,
        VodQualityTier.q720 => 720,
        VodQualityTier.q480 => 480,
        VodQualityTier.q360 => 360,
      };
}

/// 一条 HLS / 直链清晰度
class VodHlsVariant {
  const VodHlsVariant({
    required this.url,
    required this.bandwidth,
    required this.width,
    required this.height,
    this.name = '',
  });

  final String url;
  final int bandwidth;
  final int width;
  final int height;
  final String name;

  VodQualityTier get tier {
    if (height >= 2160 || (height == 0 && bandwidth >= 12000000)) {
      return VodQualityTier.q4k;
    }
    if (height >= 1080 || (height == 0 && bandwidth >= 4500000)) {
      return VodQualityTier.q1080;
    }
    if (height >= 720 || (height == 0 && bandwidth >= 1800000)) {
      return VodQualityTier.q720;
    }
    if (height >= 480 || (height == 0 && bandwidth >= 800000)) {
      return VodQualityTier.q480;
    }
    return VodQualityTier.q360;
  }

  String get label {
    if (name.trim().isNotEmpty) return name.trim();
    final t = tier.label;
    if (height > 0 && width > 0) return '$t · ${width}x$height';
    if (bandwidth > 0) {
      final mb = bandwidth / 1000000;
      return '$t · ${mb >= 10 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1)}Mbps';
    }
    return t;
  }

  String get shortLabel => tier.label;
}

/// 解析结果：可选手动档 + 默认播放地址
class VodResolvedStream {
  const VodResolvedStream({
    required this.playUrl,
    this.variants = const [],
    this.selected,
    this.masterUrl,
  });

  final String playUrl;
  final List<VodHlsVariant> variants;
  final VodHlsVariant? selected;
  final String? masterUrl;

  bool get hasQualityChoices => variants.length > 1;
}

/// CMS 片源播放：请求头 + HLS 多清晰度
class VodPlayback {
  VodPlayback._();

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static Map<String, String> get httpHeaders => {
        'User-Agent': userAgent,
        'Referer': '${ApiConfig.macCmsBase}/',
      };

  static const playbackRates = <double>[0.75, 1.0, 1.25, 1.5, 2.0];

  /// 本机路径 / file://（缓存播放）
  static bool isLocalMediaPath(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return false;
    if (u.startsWith('file:')) return true;
    if (u.contains('://')) return false;
    if (u.startsWith('/')) return true;
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(u)) return true;
    return false;
  }

  static String rateLabel(double rate) {
    if (rate == rate.roundToDouble()) {
      return '${rate.toInt().toString()}x';
    }
    return '${rate}x';
  }

  /// 兼容旧调用：按偏好解析可播地址
  static Future<String> resolvePlayableUrl(String raw) async {
    final r = await resolveStream(raw);
    return r.playUrl;
  }

  /// 解析 master / 直链，给出全部档位并按偏好选中
  static Future<VodResolvedStream> resolveStream(
    String raw, {
    VodQualityTier? prefer,
    PlayerPlayMode? playMode,
  }) async {
    final url = raw.trim();
    if (url.isEmpty) {
      return const VodResolvedStream(playUrl: '');
    }
    // 本地缓存文件：禁止再走 HTTP 拉清单
    if (isLocalMediaPath(url)) {
      return VodResolvedStream(playUrl: url);
    }
    final tier = prefer ?? await VodQualityStore.load();
    final mode = playMode ?? PlayerSettingsStore.cached.playMode;
    final lower = url.toLowerCase();
    final maybeHls = lower.contains('.m3u8') || lower.contains('m3u8?');
    if (!maybeHls) {
      return VodResolvedStream(playUrl: url);
    }

    try {
      final res = await http
          .get(Uri.parse(url), headers: httpHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return VodResolvedStream(playUrl: url);
      }
      final body = res.body;
      if (!body.contains('#EXT-X-STREAM-INF')) {
        return VodResolvedStream(playUrl: url, masterUrl: url);
      }
      final variants = parseMasterPlaylist(body, url);
      if (variants.isEmpty) {
        return VodResolvedStream(playUrl: url, masterUrl: url);
      }
      final picked = pickVariant(variants, tier, playMode: mode);
      return VodResolvedStream(
        playUrl: picked?.url ?? variants.last.url,
        variants: variants,
        selected: picked,
        masterUrl: url,
      );
    } catch (_) {
      return VodResolvedStream(playUrl: url);
    }
  }

  static List<VodHlsVariant> parseMasterPlaylist(
    String master,
    String masterUrl,
  ) {
    final out = <VodHlsVariant>[];
    final seen = <String>{};
    final lines = master.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
      final bw = int.tryParse(bwMatch?.group(1) ?? '') ?? 0;
      final w = int.tryParse(resMatch?.group(1) ?? '') ?? 0;
      final h = int.tryParse(resMatch?.group(2) ?? '') ?? 0;
      final name = nameMatch?.group(1)?.trim() ?? '';
      String? next;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty) continue;
        if (t.startsWith('#')) break;
        next = t;
        break;
      }
      if (next == null) continue;
      final resolved = _resolveUrl(masterUrl, next);
      if (!seen.add(resolved)) continue;
      out.add(
        VodHlsVariant(
          url: resolved,
          bandwidth: bw,
          width: w,
          height: h,
          name: name,
        ),
      );
    }
    // 低 → 高
    out.sort((a, b) {
      final h = a.height.compareTo(b.height);
      if (h != 0) return h;
      return a.bandwidth.compareTo(b.bandwidth);
    });
    return out;
  }

  /// 按偏好选档；自动档受播放模式影响（流畅偏 480，标准偏 720，高画质偏 1080）
  static VodHlsVariant? pickVariant(
    List<VodHlsVariant> variants,
    VodQualityTier prefer, {
    PlayerPlayMode playMode = PlayerPlayMode.standard,
  }) {
    if (variants.isEmpty) return null;
    if (prefer == VodQualityTier.auto) {
      final order = switch (playMode) {
        PlayerPlayMode.smooth => const [
            VodQualityTier.q480,
            VodQualityTier.q720,
            VodQualityTier.q360,
            VodQualityTier.q1080,
          ],
        PlayerPlayMode.standard => const [
            VodQualityTier.q720,
            VodQualityTier.q1080,
            VodQualityTier.q480,
          ],
        PlayerPlayMode.high => const [
            VodQualityTier.q1080,
            VodQualityTier.q4k,
            VodQualityTier.q720,
            VodQualityTier.q480,
          ],
      };
      for (final tier in order) {
        for (final v in variants) {
          if (v.tier == tier) return v;
        }
      }
      if (playMode == PlayerPlayMode.high) return variants.last;
      if (playMode == PlayerPlayMode.smooth) {
        return variants.length >= 2 ? variants[1] : variants.first;
      }
      if (variants.length >= 3) {
        return variants[variants.length ~/ 2];
      }
      return variants.first;
    }
    // 精确档：找 >= 目标高度的最低档；没有则找最接近的
    final want = prefer.minHeight;
    VodHlsVariant? exact;
    VodHlsVariant? above;
    VodHlsVariant? below;
    for (final v in variants) {
      if (v.tier == prefer) exact = v;
      if (v.height >= want) {
        if (above == null || v.height < above.height) above = v;
      } else {
        if (below == null || v.height > below.height) below = v;
      }
    }
    return exact ?? above ?? below ?? variants.last;
  }

  static String _resolveUrl(String base, String ref) {
    final t = ref.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return Uri.parse(base).resolve(t).toString();
  }
}

/// 用户清晰度偏好（全局）
class VodQualityStore {
  VodQualityStore._();

  static const _key = 'vod_quality_tier_v1';
  static VodQualityTier _cache = VodQualityTier.auto;

  static VodQualityTier get cached => _cache;

  static Future<VodQualityTier> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? VodQualityTier.auto.name;
    _cache = VodQualityTier.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => VodQualityTier.auto,
    );
    return _cache;
  }

  static Future<void> save(VodQualityTier tier) async {
    _cache = tier;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, tier.name);
  }
}
