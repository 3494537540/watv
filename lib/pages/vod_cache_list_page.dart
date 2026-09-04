import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cache_storage_info.dart';
import '../services/local_play_store.dart';
import '../services/maccms_api.dart';
import '../services/vod_cache_store.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import 'vod_cache_album_page.dart';
import 'vod_downloading_page.dart';
import '../widgets/app_page_route.dart';

/// 我的下载：正在下载 + 合集列表（对齐参考图）
class VodCacheListPage extends StatefulWidget {
  const VodCacheListPage({super.key});

  @override
  State<VodCacheListPage> createState() => _VodCacheListPageState();
}

String _fmtBytes(int n) {
  if (n <= 0) return '0B';
  const u = ['B', 'KB', 'MB', 'GB'];
  var v = n.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = (v >= 10 || i == 0) ? 0 : 1;
  final unit = u[i] == 'MB' ? 'M' : u[i];
  return '${v.toStringAsFixed(digits)}$unit';
}

String _fmtSpeed(double bps) {
  if (bps <= 0) return '连接中…';
  final mb = bps / (1024 * 1024);
  if (mb >= 0.1) return '${mb.toStringAsFixed(1)}MB/s';
  final kb = bps / 1024;
  if (kb >= 1) return '${kb.toStringAsFixed(0)}KB/s';
  return '${bps.toStringAsFixed(0)}B/s';
}

class _VodCacheListPageState extends State<VodCacheListPage> {
  static const _accent = Color(0xFF1ECAD3);
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF8A8F98);

  List<VodCacheItem> _items = const [];
  StreamSubscription<List<VodCacheItem>>? _sub;
  bool _editing = false;
  final Set<String> _selectedVods = {};
  bool _selectDownloading = false;
  int _tab = 0; // 0 视频
  int _usedBytes = 0;
  int? _freeBytes;
  final Set<String> _opening = {};

  @override
  void initState() {
    super.initState();
    _boot();
    _sub = VodCacheStore.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _items = list);
      unawaited(_loadStorage());
      // 新入队任务若无封面，补拉一次
      final miss = list.any((e) => e.coverUrl.trim().isEmpty);
      if (miss) unawaited(_backfillCovers());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await VodCacheStore.instance.ensureLoaded();
    if (!mounted) return;
    setState(() => _items = VodCacheStore.instance.items);
    unawaited(_loadStorage());
    unawaited(_backfillCovers());
  }

  Future<void> _backfillCovers() async {
    final cms = MacCmsApi();
    final need = <String>{};
    for (final a in _albums) {
      if (a.coverUrl.trim().isEmpty) need.add(a.vodId);
    }
    for (final e in _items) {
      if (e.isActive && e.coverUrl.trim().isEmpty) need.add(e.vodId);
    }
    for (final vodId in need) {
      var cover = '';
      try {
        final local = await LocalPlayStore.get(vodId);
        cover = (local?.pic ?? '').trim();
      } catch (_) {}
      if (cover.isEmpty) {
        try {
          final m = await cms.fetchDetail(vodId);
          cover = (m.coverUrl ?? m.slideUrl ?? '').trim();
        } catch (_) {}
      }
      if (cover.isEmpty) continue;
      await VodCacheStore.instance.setCoverForVod(vodId, cover);
    }
  }

  Future<void> _loadStorage() async {
    final info = await CacheStorageInfo.load();
    if (!mounted) return;
    setState(() {
      _usedBytes = info.usedBytes;
      _freeBytes = info.freeBytes;
    });
  }

  List<VodCacheItem> get _active =>
      _items.where((e) => e.isActive).toList(growable: false);

  List<VodCacheItem> get _downloadTasks => _items
      .where(
        (e) =>
            e.isActive ||
            e.isPaused ||
            e.status == VodCacheStatus.failed,
      )
      .toList(growable: false);

  List<_CacheAlbum> get _albums {
    final map = <String, List<VodCacheItem>>{};
    for (final e in _items) {
      if (!e.isDone) continue;
      (map[e.vodId] ??= []).add(e);
    }
    final out = <_CacheAlbum>[];
    for (final entry in map.entries) {
      final eps = [...entry.value]
        ..sort((a, b) => a.episodeIndex.compareTo(b.episodeIndex));
      out.add(_CacheAlbum(vodId: entry.key, episodes: eps));
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  VodCacheItem? get _currentDownloading {
    for (final e in _active) {
      if (e.status == VodCacheStatus.downloading) return e;
    }
    return _active.isEmpty ? null : _active.first;
  }

  void _toggleEdit() {
    HapticFeedback.selectionClick();
    setState(() {
      _editing = !_editing;
      if (!_editing) {
        _selectedVods.clear();
        _selectDownloading = false;
      }
    });
  }

  void _toggleSelectVod(String vodId) {
    setState(() {
      if (_selectedVods.contains(vodId)) {
        _selectedVods.remove(vodId);
      } else {
        _selectedVods.add(vodId);
      }
    });
  }

  void _selectAll() {
    final albums = _albums;
    final hasTasks = _downloadTasks.isNotEmpty;
    setState(() {
      final allSelected = _selectedVods.length == albums.length &&
          (!hasTasks || _selectDownloading);
      if (allSelected && (albums.isNotEmpty || hasTasks)) {
        _selectedVods.clear();
        _selectDownloading = false;
      } else {
        _selectedVods
          ..clear()
          ..addAll(albums.map((e) => e.vodId));
        _selectDownloading = hasTasks;
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedVods.isEmpty && !_selectDownloading) {
      DialogX.showWarning('请先选择要删除的内容');
      return;
    }
    final ok = await DialogX.confirm(
      context: context,
      title: '删除下载',
      message: '确定删除所选内容？本地缓存将一并清除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    if (_selectDownloading) {
      for (final e in _active) {
        await VodCacheStore.instance.remove(e.id);
      }
    }
    for (final id in _selectedVods.toList()) {
      await VodCacheStore.instance.removeByVodId(id);
    }
    if (!mounted) return;
    setState(() {
      _selectedVods.clear();
      _selectDownloading = false;
      _editing = false;
    });
    DialogX.showSuccess('已删除');
  }

  Future<void> _openAlbum(_CacheAlbum album) async {
    if (_editing) {
      _toggleSelectVod(album.vodId);
      return;
    }
    if (_opening.contains(album.vodId)) return;
    setState(() => _opening.add(album.vodId));
    HapticFeedback.selectionClick();
    try {
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => VodCacheAlbumPage(
            vodId: album.vodId,
            title: album.title,
            coverUrl: album.coverUrl,
          ),
        ),
      );
      unawaited(_loadStorage());
    } finally {
      if (mounted) setState(() => _opening.remove(album.vodId));
    }
  }

  String get _storageLine {
    final used = _fmtBytes(_usedBytes);
    final free = _freeBytes;
    if (free != null && free > 0) {
      return '已占用$used，剩余${_fmtBytes(free)}可用';
    }
    return '已占用$used';
  }

  Future<int> _pendingWatchCount(_CacheAlbum album) async {
    final prev = await LocalPlayStore.get(album.vodId);
    if (prev == null) return album.episodes.length;
    var n = 0;
    for (final e in album.episodes) {
      if (e.episodeIndex != prev.episodeIndex) n++;
    }
    // 当前集也算「待观看」若进度很浅
    if (prev.positionMs < 60000) n++;
    return n.clamp(1, album.episodes.length);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final tasks = _downloadTasks;
    final albums = _albums;
    final current = _currentDownloading ??
        (tasks.isNotEmpty ? tasks.first : null);
    final empty = tasks.isEmpty && albums.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actionsPadding: const EdgeInsets.only(right: 12),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.back, color: _ink),
        ),
        title: const Text(
          '我的下载',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: empty && !_editing ? null : _toggleEdit,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _editing ? '取消' : '编辑',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 15,
                color: empty && !_editing ? _muted : _ink,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                _TabPill(
                  label: '视频',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 10),
                _TabPill(
                  label: '小说',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tab == 1
                ? const Center(
                    child: Text(
                      '暂无小说下载',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 14,
                        color: _muted,
                      ),
                    ),
                  )
                : empty
                    ? const Center(
                        child: Text(
                          '暂无下载\n可在影片详情或搜索结果中下载',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 14,
                            height: 1.5,
                            color: _muted,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          if (current != null || tasks.isNotEmpty)
                            _DownloadingRow(
                              editing: _editing,
                              selected: _selectDownloading,
                              count: tasks.length,
                              item: current ?? tasks.first,
                              onSelect: () => setState(
                                () =>
                                    _selectDownloading = !_selectDownloading,
                              ),
                              onTap: () {
                                if (_editing) {
                                  setState(
                                    () => _selectDownloading =
                                        !_selectDownloading,
                                  );
                                  return;
                                }
                                unawaited(
                                  Navigator.of(context).push(
                                    AppPageRoute<void>(
                                      builder: (_) =>
                                          const VodDownloadingPage(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (tasks.isNotEmpty && albums.isNotEmpty)
                            const SizedBox(height: 18),
                          for (final a in albums) ...[
                            FutureBuilder<int>(
                              future: _pendingWatchCount(a),
                              builder: (context, snap) {
                                return _AlbumRow(
                                  album: a,
                                  editing: _editing,
                                  selected: _selectedVods.contains(a.vodId),
                                  pending: snap.data ?? a.episodes.length,
                                  onSelect: () => _toggleSelectVod(a.vodId),
                                  onTap: () => unawaited(_openAlbum(a)),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                          ],
                        ],
                      ),
          ),
          if (!empty || _editing) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, _editing ? 8 : 12 + bottom),
              child: Text(
                _storageLine,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  color: _muted,
                ),
              ),
            ),
          ],
          if (_editing)
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFEBEBEB)),
                ),
              ),
              padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + bottom),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _selectAll,
                      child: const Text(
                        '全选',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 22,
                    color: const Color(0xFFE5E5EA),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () => unawaited(_deleteSelected()),
                      child: const Text(
                        '删除',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CacheAlbum {
  _CacheAlbum({required this.vodId, required this.episodes});

  final String vodId;
  final List<VodCacheItem> episodes;

  String get title => episodes.first.title;
  String get coverUrl {
    for (final e in episodes) {
      if (e.coverUrl.trim().isNotEmpty) return e.coverUrl.trim();
    }
    return '';
  }

  int get totalBytes => episodes.fold<int>(0, (s, e) => s + e.bytes);
  int get updatedAt =>
      episodes.map((e) => e.updatedAt).fold<int>(0, (a, b) => a > b ? a : b);
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1ECAD3).withValues(alpha: 0.16)
              : const Color(0xFFF3F3F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF0E8A92) : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF1ECAD3) : const Color(0xFFCCCCCC),
          width: 1.6,
        ),
        color: selected ? const Color(0xFF1ECAD3) : Colors.transparent,
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _DownloadingRow extends StatelessWidget {
  const _DownloadingRow({
    required this.editing,
    required this.selected,
    required this.count,
    required this.item,
    required this.onSelect,
    required this.onTap,
  });

  final bool editing;
  final bool selected;
  final int count;
  final VodCacheItem item;
  final VoidCallback onSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = item.status == VodCacheStatus.queued
        ? 0.0
        : item.progress.clamp(0.0, 1.0);
    final title = '${item.title}(${item.episodeLabel})';
    final cover = item.coverUrl.trim();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          if (editing) ...[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: onSelect,
                child: _CheckCircle(selected: selected),
              ),
            ),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 128,
              height: 72,
              child: cover.isEmpty
                  ? Container(
                      color: const Color(0xFFF0F0F3),
                      child: const Icon(
                        Icons.download_rounded,
                        size: 28,
                        color: Color(0xFFB0B0B8),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CmsCoverImage(
                          url: cover,
                          vodId: item.vodId,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        ),
                        Container(
                          color: Colors.black.withValues(alpha: 0.18),
                        ),
                        const Center(
                          child: Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '正在下载',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1ECAD3),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress <= 0 ? null : progress,
                    minHeight: 3,
                    backgroundColor: const Color(0xFFE5E5EA),
                    color: const Color(0xFF1ECAD3),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.isPaused
                      ? '已暂停，点击管理'
                      : item.status == VodCacheStatus.queued
                          ? '排队中'
                          : item.status == VodCacheStatus.failed
                              ? '失败，点击重试'
                              : _fmtSpeed(item.speedBps),
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 12,
                    color: Color(0xFF8A8F98),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.editing,
    required this.selected,
    required this.pending,
    required this.onSelect,
    required this.onTap,
  });

  final _CacheAlbum album;
  final bool editing;
  final bool selected;
  final int pending;
  final VoidCallback onSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = album.coverUrl;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          if (editing) ...[
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: onSelect,
                child: _CheckCircle(selected: selected),
              ),
            ),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 128,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover.isEmpty
                      ? Container(
                          color: const Color(0xFFF0F0F3),
                          child: const Icon(
                            Icons.movie_outlined,
                            color: Color(0xFFB0B0B8),
                          ),
                        )
                      : CmsCoverImage(
                          url: cover,
                          vodId: album.vodId,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        ),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.layers,
                            size: 11,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${album.episodes.length}个视频',
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fmtBytes(album.totalBytes),
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          color: Color(0xFF8A8F98),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '$pending个待观看',
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: Color(0xFF8A8F98),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
