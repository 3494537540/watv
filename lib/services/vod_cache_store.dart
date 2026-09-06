import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player/vod_playback.dart';
import 'local_notification_service.dart';

enum VodCacheStatus { idle, queued, downloading, paused, done, failed }

class VodCacheItem {
  const VodCacheItem({
    required this.id,
    required this.vodId,
    required this.title,
    required this.episodeIndex,
    required this.episodeLabel,
    required this.url,
    this.sourceIndex = 0,
    this.coverUrl = '',
    this.localPath = '',
    this.status = VodCacheStatus.idle,
    this.progress = 0,
    this.bytes = 0,
    this.totalBytes = 0,
    this.speedBps = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String vodId;
  final String title;
  final int episodeIndex;
  final String episodeLabel;
  final String url;
  final int sourceIndex;
  final String coverUrl;
  final String localPath;
  final VodCacheStatus status;
  final double progress;
  final int bytes;
  final int totalBytes;
  /// 瞬时下载速度（字节/秒），仅下载中有效
  final double speedBps;
  final int updatedAt;

  bool get isDone => status == VodCacheStatus.done && localPath.isNotEmpty;
  bool get isActive =>
      status == VodCacheStatus.queued || status == VodCacheStatus.downloading;
  bool get isPaused => status == VodCacheStatus.paused;

  Map<String, dynamic> toJson() => {
        'id': id,
        'vod_id': vodId,
        'title': title,
        'episode_index': episodeIndex,
        'episode_label': episodeLabel,
        'url': url,
        'source_index': sourceIndex,
        'cover_url': coverUrl,
        'local_path': localPath,
        'status': status.name,
        'progress': progress,
        'bytes': bytes,
        'total_bytes': totalBytes,
        'updated_at': updatedAt,
      };

  factory VodCacheItem.fromJson(Map<String, dynamic> json) {
    final st = '${json['status'] ?? ''}';
    return VodCacheItem(
      id: '${json['id'] ?? ''}',
      vodId: '${json['vod_id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      episodeIndex: (json['episode_index'] as num?)?.toInt() ?? 0,
      episodeLabel: '${json['episode_label'] ?? ''}',
      url: '${json['url'] ?? ''}',
      sourceIndex: (json['source_index'] as num?)?.toInt() ?? 0,
      coverUrl: '${json['cover_url'] ?? ''}',
      localPath: '${json['local_path'] ?? ''}',
      status: VodCacheStatus.values.firstWhere(
        (e) => e.name == st,
        orElse: () => VodCacheStatus.idle,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  VodCacheItem copyWith({
    String? coverUrl,
    String? localPath,
    VodCacheStatus? status,
    double? progress,
    int? bytes,
    int? totalBytes,
    double? speedBps,
    int? updatedAt,
    bool clearSpeed = false,
  }) {
    return VodCacheItem(
      id: id,
      vodId: vodId,
      title: title,
      episodeIndex: episodeIndex,
      episodeLabel: episodeLabel,
      url: url,
      sourceIndex: sourceIndex,
      coverUrl: coverUrl ?? this.coverUrl,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytes: bytes ?? this.bytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBps: clearSpeed ? 0 : (speedBps ?? this.speedBps),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String makeId(String vodId, int episodeIndex, int sourceIndex) =>
      '${vodId}_${sourceIndex}_$episodeIndex';
}

class _CacheJob {
  const _CacheJob({
    required this.vodId,
    required this.title,
    required this.episodeIndex,
    required this.episodeLabel,
    required this.sourceIndex,
    required this.url,
    this.coverUrl = '',
  });

  final String vodId;
  final String title;
  final int episodeIndex;
  final String episodeLabel;
  final int sourceIndex;
  final String url;
  final String coverUrl;

  String get id =>
      VodCacheItem.makeId(vodId, episodeIndex, sourceIndex);
}

/// 本机缓存下载（支持 MP4 / HLS 分段，排队多集）
class VodCacheStore {
  VodCacheStore._();
  static final instance = VodCacheStore._();

  static const _key = 'vod_cache_items_v1';
  final _ctrl = StreamController<List<VodCacheItem>>.broadcast();
  List<VodCacheItem> _items = const [];
  final List<_CacheJob> _queue = [];
  http.Client? _client;
  bool _pumping = false;
  bool _loaded = false;
  String? _cancelId;
  String? _currentId;
  bool _pauseInsteadOfFail = false;
  DateTime? _speedSampleAt;
  int _speedSampleBytes = 0;
  double _speedBps = 0;

  Stream<List<VodCacheItem>> get stream => _ctrl.stream;
  List<VodCacheItem> get items => List.unmodifiable(_items);
  bool get isBusy => _pumping || _queue.isNotEmpty;

  int get activeCount => _items.where((e) => e.isActive).length;

  int activeCountFor(String vodId) =>
      _items.where((e) => e.vodId == vodId && e.isActive).length;

  int get usedBytes => _items.fold<int>(0, (s, e) => s + (e.bytes > 0 ? e.bytes : 0));

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _items = [
        for (final e in list)
          if (e is Map) VodCacheItem.fromJson(Map<String, dynamic>.from(e)),
      ];
      for (final e in _items) {
        if (e.status == VodCacheStatus.downloading ||
            e.status == VodCacheStatus.queued) {
          _upsert(e.copyWith(status: VodCacheStatus.queued, progress: 0));
          _queue.add(
            _CacheJob(
              vodId: e.vodId,
              title: e.title,
              episodeIndex: e.episodeIndex,
              episodeLabel: e.episodeLabel,
              sourceIndex: e.sourceIndex,
              url: e.url,
              coverUrl: e.coverUrl,
            ),
          );
        }
      }
      _ctrl.add(_items);
      unawaited(_pump());
    } catch (_) {}
  }

  Future<void> _persist({bool emit = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final e in _items) e.toJson()]),
    );
    if (emit) _ctrl.add(List.unmodifiable(_items));
  }

  void _emit() => _ctrl.add(List.unmodifiable(_items));

  VodCacheItem? find({
    required String vodId,
    required int episodeIndex,
    required int sourceIndex,
  }) {
    final id = VodCacheItem.makeId(vodId, episodeIndex, sourceIndex);
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 同一集任意线路已缓存完成则返回（优先 [preferSourceIndex]）
  VodCacheItem? findDoneEpisode({
    required String vodId,
    required int episodeIndex,
    int? preferSourceIndex,
  }) {
    VodCacheItem? fallback;
    for (final e in _items) {
      if (e.vodId != vodId || e.episodeIndex != episodeIndex) continue;
      if (!e.isDone || e.localPath.isEmpty) continue;
      if (!File(e.localPath).existsSync()) continue;
      if (preferSourceIndex != null && e.sourceIndex == preferSourceIndex) {
        return e;
      }
      fallback ??= e;
    }
    return fallback;
  }

  /// 已完成且本地文件仍在时返回本地路径，否则 null
  Future<String?> localPlayPath({
    required String vodId,
    required int episodeIndex,
    required int sourceIndex,
  }) async {
    await ensureLoaded();
    final e = findDoneEpisode(
      vodId: vodId,
      episodeIndex: episodeIndex,
      preferSourceIndex: sourceIndex,
    );
    return e?.localPath;
  }

  /// 打开本地 m3u8 前：把仍指向远程的 KEY/MAP 拉到同目录，避免 iOS 离线卡死
  Future<String> prepareLocalMediaPath(String rawPath) async {
    var path = rawPath.trim();
    if (path.startsWith('file:')) {
      path = Uri.parse(path).toFilePath();
    }
    final lower = path.toLowerCase();
    if (!lower.endsWith('.m3u8')) return path;
    final file = File(path);
    if (!await file.exists()) return path;
    String body;
    try {
      body = await file.readAsString();
    } catch (_) {
      return path;
    }
    if (!body.contains('http://') && !body.contains('https://')) {
      return path;
    }
    final dir = file.parent;
    final lines = body.split('\n');
    final out = StringBuffer();
    var changed = false;
    for (final raw in lines) {
      final trimmed = raw.trim();
      final upper = trimmed.toUpperCase();
      if (upper.startsWith('#EXT-X-KEY:') || upper.startsWith('#EXT-X-MAP:')) {
        final name =
            upper.startsWith('#EXT-X-MAP:') ? 'init.mp4' : 'key.key';
        final next = await _localizeHlsAttrUriLine(
          trimmed,
          // 用假基址解析绝对 URL；相对 URI 保持不动
          'https://local.invalid/',
          dir,
          fileName: name,
        );
        if (next != trimmed) changed = true;
        out.writeln(next);
      } else {
        out.writeln(raw);
      }
    }
    if (changed) {
      try {
        await file.writeAsString(out.toString());
      } catch (_) {}
    }
    return path;
  }

  Future<VodCacheItem> enqueueAndDownload({
    required String vodId,
    required String title,
    required int episodeIndex,
    required String episodeLabel,
    required int sourceIndex,
    required String url,
    String coverUrl = '',
    void Function(double progress)? onProgress,
  }) async {
    await enqueueMany(
      jobs: [
        (
          vodId: vodId,
          title: title,
          episodeIndex: episodeIndex,
          episodeLabel: episodeLabel,
          sourceIndex: sourceIndex,
          url: url,
          coverUrl: coverUrl,
        ),
      ],
    );
    return find(
          vodId: vodId,
          episodeIndex: episodeIndex,
          sourceIndex: sourceIndex,
        ) ??
        VodCacheItem(
          id: VodCacheItem.makeId(vodId, episodeIndex, sourceIndex),
          vodId: vodId,
          title: title,
          episodeIndex: episodeIndex,
          episodeLabel: episodeLabel,
          url: url,
          sourceIndex: sourceIndex,
          coverUrl: coverUrl,
        );
  }

  Future<int> enqueueMany({
    required List<
            ({
              String vodId,
              String title,
              int episodeIndex,
              String episodeLabel,
              int sourceIndex,
              String url,
              String coverUrl,
            })>
        jobs,
  }) async {
    await ensureLoaded();
    var added = 0;
    for (final j in jobs) {
      final url = j.url.trim();
      if (url.isEmpty) continue;
      final existing = find(
        vodId: j.vodId,
        episodeIndex: j.episodeIndex,
        sourceIndex: j.sourceIndex,
      );
      if (existing != null &&
          existing.isDone &&
          await File(existing.localPath).exists()) {
        continue;
      }
      if (existing != null && existing.isActive) continue;

      final id = VodCacheItem.makeId(
        j.vodId,
        j.episodeIndex,
        j.sourceIndex,
      );
      final cover = j.coverUrl.trim().isNotEmpty
          ? j.coverUrl.trim()
          : (existing?.coverUrl ?? '');
      final item = VodCacheItem(
        id: id,
        vodId: j.vodId,
        title: j.title,
        episodeIndex: j.episodeIndex,
        episodeLabel: j.episodeLabel,
        url: url,
        sourceIndex: j.sourceIndex,
        coverUrl: cover,
        status: VodCacheStatus.queued,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _upsert(item);
      _queue.add(
        _CacheJob(
          vodId: j.vodId,
          title: j.title,
          episodeIndex: j.episodeIndex,
          episodeLabel: j.episodeLabel,
          sourceIndex: j.sourceIndex,
          url: url,
          coverUrl: cover,
        ),
      );
      added++;
    }
    await _persist();
    unawaited(_pump());
    return added;
  }

  VodCacheItem? _byId(String id) {
    for (final e in _items) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> retry(String id) async {
    await ensureLoaded();
    final item = _byId(id);
    if (item == null) return;
    if (item.isActive) return;
    final url = item.url.trim();
    if (url.isEmpty) return;
    _upsert(
      item.copyWith(
        status: VodCacheStatus.queued,
        progress: 0,
        bytes: 0,
        totalBytes: 0,
        localPath: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _queue.add(
      _CacheJob(
        vodId: item.vodId,
        title: item.title,
        episodeIndex: item.episodeIndex,
        episodeLabel: item.episodeLabel,
        sourceIndex: item.sourceIndex,
        url: url,
        coverUrl: item.coverUrl,
      ),
    );
    await _persist();
    unawaited(_pump());
  }

  Future<void> setCoverForVod(String vodId, String coverUrl) async {
    final cover = coverUrl.trim();
    if (cover.isEmpty) return;
    await ensureLoaded();
    var changed = false;
    for (final e in _items) {
      if (e.vodId == vodId && e.coverUrl.trim().isEmpty) {
        _upsert(e.copyWith(coverUrl: cover));
        changed = true;
      }
    }
    if (changed) await _persist();
  }

  Future<void> cancel(String id) async {
    await ensureLoaded();
    _queue.removeWhere((j) => j.id == id);
    if (_currentId == id) {
      _pauseInsteadOfFail = false;
      _cancelId = id;
      try {
        _client?.close();
      } catch (_) {}
      _client = null;
    }
    final item = _byId(id);
    if (item != null && item.isActive) {
      _upsert(
        item.copyWith(
          status: VodCacheStatus.failed,
          clearSpeed: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _persist();
    }
  }

  /// 暂停下载（保留进度，可继续）
  Future<void> pause(String id) async {
    await ensureLoaded();
    _queue.removeWhere((j) => j.id == id);
    final item = _byId(id);
    if (item == null) return;
    if (_currentId == id) {
      _pauseInsteadOfFail = true;
      _cancelId = id;
      try {
        _client?.close();
      } catch (_) {}
      _client = null;
    }
    if (item.isActive || item.isPaused) {
      _upsert(
        item.copyWith(
          status: VodCacheStatus.paused,
          clearSpeed: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _persist();
    }
  }

  Future<void> pauseAllActive() async {
    await ensureLoaded();
    final ids = [
      for (final e in _items)
        if (e.isActive) e.id,
    ];
    for (final id in ids) {
      await pause(id);
    }
  }

  Future<void> resume(String id) async {
    await ensureLoaded();
    final item = _byId(id);
    if (item == null) return;
    if (item.status != VodCacheStatus.paused &&
        item.status != VodCacheStatus.failed) {
      return;
    }
    final url = item.url.trim();
    if (url.isEmpty) return;
    _upsert(
      item.copyWith(
        status: VodCacheStatus.queued,
        clearSpeed: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _queue.add(
      _CacheJob(
        vodId: item.vodId,
        title: item.title,
        episodeIndex: item.episodeIndex,
        episodeLabel: item.episodeLabel,
        sourceIndex: item.sourceIndex,
        url: url,
        coverUrl: item.coverUrl,
      ),
    );
    await _persist();
    unawaited(_pump());
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    await cancel(id);
    final item = _byId(id);
    if (item != null && item.localPath.isNotEmpty) {
      try {
        final f = File(item.localPath);
        if (await f.exists()) await f.delete();
        final parent = f.parent;
        if (parent.path.contains(id) && await parent.exists()) {
          await parent.delete(recursive: true);
        }
      } catch (_) {}
    }
    _items = [for (final e in _items) if (e.id != id) e];
    await _persist();
  }

  Future<void> removeMany(Iterable<String> ids) async {
    for (final id in ids.toList()) {
      await remove(id);
    }
  }

  Future<void> removeByVodId(String vodId) async {
    await ensureLoaded();
    final ids = [
      for (final e in _items)
        if (e.vodId == vodId) e.id,
    ];
    await removeMany(ids);
  }

  Future<void> clearDone() async {
    await ensureLoaded();
    final done = _items.where((e) => e.isDone).toList();
    for (final e in done) {
      await remove(e.id);
    }
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        try {
          await _downloadOne(job);
        } catch (_) {}
      }
    } finally {
      _pumping = false;
      _emit();
    }
  }

  bool get _cancelledCurrent =>
      _cancelId != null && _cancelId == _currentId;

  void _resetSpeed() {
    _speedSampleAt = null;
    _speedSampleBytes = 0;
    _speedBps = 0;
  }

  double _noteSpeed(int bytes) {
    final now = DateTime.now();
    final at = _speedSampleAt;
    if (at == null) {
      _speedSampleAt = now;
      _speedSampleBytes = bytes;
      return _speedBps;
    }
    final dt = now.difference(at).inMilliseconds;
    if (dt >= 400) {
      final delta = bytes - _speedSampleBytes;
      if (delta >= 0) {
        _speedBps = delta * 1000 / dt;
      }
      _speedSampleAt = now;
      _speedSampleBytes = bytes;
    }
    return _speedBps;
  }

  Future<VodCacheItem> _downloadOne(_CacheJob job) async {
    final id = job.id;
    _currentId = id;
    _cancelId = null;
    _resetSpeed();

    var item = find(
          vodId: job.vodId,
          episodeIndex: job.episodeIndex,
          sourceIndex: job.sourceIndex,
        ) ??
        VodCacheItem(
          id: id,
          vodId: job.vodId,
          title: job.title,
          episodeIndex: job.episodeIndex,
          episodeLabel: job.episodeLabel,
          url: job.url,
          sourceIndex: job.sourceIndex,
          coverUrl: job.coverUrl,
        );

    if (item.isDone && await File(item.localPath).exists()) {
      _currentId = null;
      return item;
    }

    final keepProgress = item.progress > 0.01 || item.bytes > 1024;
    item = item.copyWith(
      coverUrl: item.coverUrl.isNotEmpty ? item.coverUrl : job.coverUrl,
      status: VodCacheStatus.downloading,
      // 暂停续传时保留进度展示
      progress: keepProgress ? item.progress : 0,
      bytes: keepProgress ? item.bytes : 0,
      totalBytes: keepProgress ? item.totalBytes : 0,
      speedBps: 0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _upsert(item);
    await _persist();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheRoot = Directory('${dir.path}/vod_cache');
      if (!await cacheRoot.exists()) {
        await cacheRoot.create(recursive: true);
      }

      final lower = job.url.toLowerCase();
      final isHls = lower.contains('.m3u8') || lower.contains('m3u8?');

      late final String outPath;
      void onProg(double p, int bytes, int total) {
        if (_cancelledCurrent) return;
        final speed = _noteSpeed(bytes);
        item = item.copyWith(
          progress: p,
          bytes: bytes,
          totalBytes: total,
          speedBps: speed,
        );
        _upsert(item);
        _emit();
      }

      if (isHls) {
        final work = Directory('${cacheRoot.path}/$id');
        if (!await work.exists()) {
          await work.create(recursive: true);
        }
        outPath = await _downloadHls(job.url, work, onProgress: onProg);
      } else {
        final ext = lower.contains('.mp4')
            ? 'mp4'
            : (lower.contains('.mkv')
                ? 'mkv'
                : (lower.contains('.flv') ? 'flv' : 'bin'));
        final file = File('${cacheRoot.path}/$id.$ext');
        outPath = await _downloadBinary(job.url, file, onProgress: onProg);
      }

      if (_cancelledCurrent) {
        throw const _CacheCancelled();
      }

      item = item.copyWith(
        status: VodCacheStatus.done,
        progress: 1,
        speedBps: 0,
        localPath: outPath,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _upsert(item);
      await _persist();
      unawaited(
        LocalNotificationService.showDownloadDone(
          cacheId: item.id,
          title: item.title,
          episodeLabel: item.episodeLabel,
        ),
      );
      return item;
    } on _CacheCancelled {
      final paused = _pauseInsteadOfFail;
      _pauseInsteadOfFail = false;
      item = item.copyWith(
        status: paused ? VodCacheStatus.paused : VodCacheStatus.failed,
        clearSpeed: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _upsert(item);
      await _persist();
      return item;
    } catch (_) {
      final paused = _pauseInsteadOfFail && _cancelledCurrent;
      _pauseInsteadOfFail = false;
      item = item.copyWith(
        status: paused ? VodCacheStatus.paused : VodCacheStatus.failed,
        clearSpeed: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      _upsert(item);
      await _persist();
      if (paused) return item;
      rethrow;
    } finally {
      _currentId = null;
      _resetSpeed();
      try {
        _client?.close();
      } catch (_) {}
      _client = null;
    }
  }

  Future<String> _downloadBinary(
    String url,
    File file, {
    required void Function(double progress, int bytes, int total) onProgress,
  }) async {
    _client?.close();
    _client = http.Client();
    final req = http.Request('GET', Uri.parse(url));
    req.headers.addAll(VodPlayback.httpHeaders);
    final res = await _client!.send(req).timeout(const Duration(seconds: 45));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('下载失败 HTTP ${res.statusCode}');
    }
    final total = res.contentLength ?? 0;
    var received = 0;
    var lastEmit = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in res.stream) {
        if (_cancelledCurrent) throw const _CacheCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (received - lastEmit >= 128 * 1024 ||
            (total > 0 && received >= total)) {
          lastEmit = received;
          final p = total > 0
              ? (received / total).clamp(0.0, 0.99)
              : (0.05 + (received / (received + 8 * 1024 * 1024)).clamp(0.0, 0.9));
          onProgress(p, received, total);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (_cancelledCurrent) throw const _CacheCancelled();
    onProgress(1, received, total > 0 ? total : received);
    return file.path;
  }

  Future<String> _downloadHls(
    String url,
    Directory workDir, {
    required void Function(double progress, int bytes, int total) onProgress,
  }) async {
    _client?.close();
    _client = http.Client();

    var playlistUrl = url;
    var playlist = await _getText(playlistUrl);
    if (playlist.contains('#EXT-X-STREAM-INF')) {
      // 下载优先选中等码率，显著快于最高清
      final variant = _pickDownloadVariant(playlist, playlistUrl);
      if (variant == null || variant.isEmpty) {
        throw const HttpException('无法解析 HLS 清晰度列表');
      }
      playlistUrl = variant;
      playlist = await _getText(playlistUrl);
    }

    final lines = playlist.split('\n');
    final segmentUrls = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      segmentUrls.add(_resolveUrl(playlistUrl, line));
    }
    if (segmentUrls.isEmpty) {
      final f = File('${workDir.path}/index.m3u8');
      await f.writeAsString(playlist);
      onProgress(1, playlist.length, playlist.length);
      return f.path;
    }

    final names = <String>[
      for (var i = 0; i < segmentUrls.length; i++)
        'seg_${i.toString().padLeft(5, '0')}.ts',
    ];

    var received = 0;
    var doneCount = 0;
    final totalEst = segmentUrls.length;
    const concurrency = 8;
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancelledCurrent) throw const _CacheCancelled();
        final i = next++;
        if (i >= segmentUrls.length) return;
        final segFile = File('${workDir.path}/${names[i]}');
        int bytes;
        if (await segFile.exists() && await segFile.length() > 0) {
          bytes = await segFile.length();
        } else {
          bytes = await _downloadToFile(segmentUrls[i], segFile);
        }
        received += bytes;
        doneCount++;
        final p = (doneCount / totalEst).clamp(0.0, 0.99);
        onProgress(p, received, 0);
      }
    }

    try {
      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    } catch (_) {
      if (_cancelledCurrent) throw const _CacheCancelled();
      rethrow;
    }

    final rewritten = StringBuffer();
    var segIndex = 0;
    for (final raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        rewritten.writeln(line);
        continue;
      }
      if (trimmed.startsWith('#')) {
        final upper = trimmed.toUpperCase();
        // 密钥 / init map 本地化，避免离线或弱网时 HLS 一直转圈
        if (upper.startsWith('#EXT-X-KEY:')) {
          rewritten.writeln(
            await _localizeHlsAttrUriLine(
              trimmed,
              playlistUrl,
              workDir,
              fileName: 'key.key',
            ),
          );
        } else if (upper.startsWith('#EXT-X-MAP:')) {
          rewritten.writeln(
            await _localizeHlsAttrUriLine(
              trimmed,
              playlistUrl,
              workDir,
              fileName: 'init.mp4',
            ),
          );
        } else {
          rewritten.writeln(line);
        }
        continue;
      }
      rewritten.writeln(names[segIndex]);
      segIndex++;
    }

    final index = File('${workDir.path}/index.m3u8');
    await index.writeAsString(rewritten.toString());
    onProgress(1, received, received);
    return index.path;
  }

  Future<String> _localizeHlsAttrUriLine(
    String line,
    String playlistUrl,
    Directory workDir, {
    required String fileName,
  }) async {
    final m = RegExp(
      r'URI="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(line);
    final raw = m?.group(1)?.trim() ?? '';
    if (raw.isEmpty) return line;
    // 已是相对本地名
    if (!raw.contains('://') && !raw.startsWith('/')) {
      return line;
    }
    try {
      final abs = _resolveUrl(playlistUrl, raw);
      final out = File('${workDir.path}/$fileName');
      if (!await out.exists() || await out.length() == 0) {
        await _downloadToFile(abs, out);
      }
      return line.replaceFirstMapped(
        RegExp(r'URI="[^"]+"', caseSensitive: false),
        (_) => 'URI="$fileName"',
      );
    } catch (_) {
      return line;
    }
  }

  Future<String> _getText(String url) async {
    final req = http.Request('GET', Uri.parse(url));
    req.headers.addAll(VodPlayback.httpHeaders);
    final res = await _client!.send(req).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('拉取播放列表失败 HTTP ${res.statusCode}');
    }
    return utf8.decode(await res.stream.toBytes());
  }

  Future<int> _downloadToFile(String url, File file) async {
    _client ??= http.Client();
    final req = http.Request('GET', Uri.parse(url));
    req.headers.addAll(VodPlayback.httpHeaders);
    final res = await _client!.send(req).timeout(const Duration(seconds: 60));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('分片下载失败 HTTP ${res.statusCode}');
    }
    var n = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in res.stream) {
        if (_cancelledCurrent) throw const _CacheCancelled();
        sink.add(chunk);
        n += chunk.length;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return n;
  }

  String? _pickDownloadVariant(String master, String masterUrl) {
    final variants = <({int bw, String url})>[];
    final lines = master.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final bw = int.tryParse(bwMatch?.group(1) ?? '') ?? 0;
      String? next;
      for (var j = i + 1; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.isEmpty) continue;
        if (t.startsWith('#')) break;
        next = t;
        break;
      }
      if (next == null) continue;
      variants.add((bw: bw, url: _resolveUrl(masterUrl, next)));
    }
    if (variants.isEmpty) return null;
    variants.sort((a, b) => a.bw.compareTo(b.bw));
    // 优先 ~1080P：1.5M–5M；否则取较高中位档，避免缓存回放太糊
    for (final v in variants.reversed) {
      if (v.bw >= 1500000 && v.bw <= 5000000) return v.url;
    }
    for (final v in variants) {
      if (v.bw >= 800000 && v.bw <= 2500000) return v.url;
    }
    return variants[variants.length ~/ 2].url;
  }

  String _resolveUrl(String base, String ref) {
    final t = ref.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    final b = Uri.parse(base);
    return b.resolve(t).toString();
  }

  void _upsert(VodCacheItem item) {
    final i = _items.indexWhere((e) => e.id == item.id);
    if (i < 0) {
      _items = [item, ..._items];
    } else {
      final next = [..._items];
      next[i] = item;
      _items = next;
    }
  }
}

class _CacheCancelled implements Exception {
  const _CacheCancelled();
}
