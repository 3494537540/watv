import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'vod_cache_store.dart';

/// 缓存占用 / 磁盘剩余
class CacheStorageInfo {
  const CacheStorageInfo({required this.usedBytes, this.freeBytes});

  final int usedBytes;
  final int? freeBytes;

  static Future<CacheStorageInfo> load() async {
    await VodCacheStore.instance.ensureLoaded();
    var used = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cache = Directory('${docs.path}/vod_cache');
      if (await cache.exists()) {
        await for (final e in cache.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              used += await e.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      used = VodCacheStore.instance.usedBytes;
    }
    if (used <= 0) used = VodCacheStore.instance.usedBytes;

    int? free;
    try {
      free = await _probeFreeBytes();
    } catch (_) {}
    return CacheStorageInfo(usedBytes: used, freeBytes: free);
  }

  static Future<int?> _probeFreeBytes() async {
    final docs = await getApplicationDocumentsDirectory();
    if (Platform.isWindows) {
      final drive = docs.path.length >= 2 ? docs.path[0] : 'C';
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '(Get-PSDrive -Name $drive).Free',
        ],
      );
      if (r.exitCode == 0) {
        return int.tryParse('${r.stdout}'.trim().split('\n').last.trim());
      }
      return null;
    }
    // Android / Linux / macOS：df
    final r = await Process.run('df', ['-k', docs.path]);
    if (r.exitCode != 0) return null;
    final lines = '${r.stdout}'.trim().split('\n');
    if (lines.length < 2) return null;
    final parts = lines.last.trim().split(RegExp(r'\s+'));
    // Filesystem 1K-blocks Used Available ...
    if (parts.length < 4) return null;
    final availKb = int.tryParse(parts[3]);
    if (availKb == null) return null;
    return availKb * 1024;
  }
}
