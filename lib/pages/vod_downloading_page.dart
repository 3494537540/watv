import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/vod_cache_store.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';

String _fmtSpeed(double bps) {
  if (bps <= 0) return '连接中…';
  final mb = bps / (1024 * 1024);
  if (mb >= 0.1) return '${mb.toStringAsFixed(1)}MB/s';
  final kb = bps / 1024;
  if (kb >= 1) return '${kb.toStringAsFixed(0)}KB/s';
  return '${bps.toStringAsFixed(0)}B/s';
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

/// 正在下载列表：暂停 / 继续 / 删除 / 全部暂停
class VodDownloadingPage extends StatefulWidget {
  const VodDownloadingPage({super.key});

  @override
  State<VodDownloadingPage> createState() => _VodDownloadingPageState();
}

class _VodDownloadingPageState extends State<VodDownloadingPage> {
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF8A8F98);
  static const _accent = Color(0xFF1ECAD3);

  List<VodCacheItem> _items = const [];
  StreamSubscription<List<VodCacheItem>>? _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = VodCacheStore.instance.stream.listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() {
    final list = VodCacheStore.instance.items
        .where(
          (e) =>
              e.isActive ||
              e.isPaused ||
              e.status == VodCacheStatus.failed,
        )
        .toList();
    if (!mounted) return;
    setState(() => _items = list);
  }

  Future<void> _toggle(VodCacheItem e) async {
    HapticFeedback.selectionClick();
    if (e.isActive) {
      await VodCacheStore.instance.pause(e.id);
    } else {
      await VodCacheStore.instance.resume(e.id);
    }
  }

  Future<void> _pauseAll() async {
    HapticFeedback.selectionClick();
    await VodCacheStore.instance.pauseAllActive();
    DialogX.showSuccess('已全部暂停');
  }

  Future<void> _delete(VodCacheItem e) async {
    HapticFeedback.selectionClick();
    final ok = await DialogX.confirm(
      context: context,
      title: '删除任务',
      message: '确定删除「${e.title} ${e.episodeLabel}」的下载？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok == true) {
      await VodCacheStore.instance.remove(e.id);
      DialogX.showSuccess('已删除');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _items.where((e) => e.isActive).length;
    final bottom = MediaQuery.paddingOf(context).bottom;

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
          '正在下载',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        centerTitle: true,
        actions: [
          if (active > 0)
            TextButton(
              onPressed: () => unawaited(_pauseAll()),
              child: const Text(
                '全部暂停',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 15,
                  color: _ink,
                ),
              ),
            ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text(
                '暂无下载任务',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 14,
                  color: _muted,
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final e = _items[i];
                final paused =
                    e.isPaused || e.status == VodCacheStatus.failed;
                final progress = e.progress.clamp(0.0, 1.0);
                final cover = e.coverUrl.trim();
                return Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 112,
                        height: 63,
                        child: cover.isEmpty
                            ? Container(
                                color: const Color(0xFFF0F0F3),
                                child: const Icon(
                                  Icons.movie_outlined,
                                  color: Color(0xFFB0B0B8),
                                ),
                              )
                            : CmsCoverImage(
                                url: cover,
                                vodId: e.vodId,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.title}(${e.episodeLabel})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: e.status == VodCacheStatus.queued
                                  ? null
                                  : (progress <= 0 ? null : progress),
                              minHeight: 3,
                              backgroundColor: const Color(0xFFE5E5EA),
                              color: _accent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            paused
                                ? (e.status == VodCacheStatus.failed
                                    ? '下载失败'
                                    : '已暂停 · ${_fmtBytes(e.bytes)}')
                                : e.status == VodCacheStatus.queued
                                    ? '排队中'
                                    : '${_fmtSpeed(e.speedBps)} · ${(progress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: paused ? '继续' : '暂停',
                      onPressed: () => unawaited(_toggle(e)),
                      icon: Icon(
                        paused
                            ? CupertinoIcons.play_fill
                            : CupertinoIcons.pause_fill,
                        color: _ink,
                        size: 22,
                      ),
                    ),
                    IconButton(
                      tooltip: '删除',
                      onPressed: () => unawaited(_delete(e)),
                      icon: const Icon(
                        CupertinoIcons.trash,
                        color: Color(0xFFFF3B30),
                        size: 20,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
