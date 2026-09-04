import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../services/cms_app_config.dart';
import '../services/live_source_store.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/figma_loading.dart';
import '../widgets/player/mango_inline_player.dart';
import '../widgets/app_page_route.dart';

/// 直播：CCTV / 导入源 / CMS 配置源
class LiveTvPage extends StatefulWidget {
  const LiveTvPage({super.key});

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> {
  bool _loading = true;
  String _group = '全部';
  String _query = '';
  List<LiveChannel> _channels = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    setState(() => _loading = true);
    final cfgStore = CmsAppConfigStore.instance;
    await cfgStore.bootstrap();
    await LiveSourceStore.instance.bootstrap();
    await cfgStore.refresh();
    await LiveSourceStore.instance.refreshFromConfig(cfgStore.config);
    if (!mounted) return;
    setState(() {
      _channels = LiveSourceStore.instance.all;
      _loading = false;
    });
  }

  List<LiveChannel> get _filtered {
    final q = _query.trim().toLowerCase();
    return [
      for (final c in _channels)
        if ((_group == '全部' || c.group == _group) &&
            (q.isEmpty ||
                c.name.toLowerCase().contains(q) ||
                c.group.toLowerCase().contains(q)))
          c,
    ];
  }

  Future<void> _importSheet() async {
    final ctrl = TextEditingController();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('导入直播源'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: ctrl,
            maxLines: 8,
            placeholder: '粘贴 M3U 或 name,url 文本',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    await LiveSourceStore.instance.importText(text, group: '导入');
    if (!mounted) return;
    setState(() => _channels = LiveSourceStore.instance.all);
    DialogX.showSuccess('已导入');
  }

  void _open(LiveChannel c) {
    if (c.url.contains('example.invalid')) {
      DialogX.showWarning('请先在「导入」或后台 app_config / live.m3u 配置真实直播源');
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _LivePlayerPage(channel: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final groups = ['全部', ...LiveSourceStore.instance.groups];
    final list = _filtered;

    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: top + 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '直播',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF181818),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_importSheet()),
                  child: const Text(
                    '导入',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      color: Color(0xFF8E8E93),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => unawaited(_boot()),
                  icon: const Icon(
                    CupertinoIcons.refresh,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CupertinoSearchTextField(
              placeholder: '搜索频道 / CCTV',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: groups.length,
              separatorBuilder: (_, _) => SizedBox(width: 8),
              itemBuilder: (context, i) {
                final g = groups[i];
                final on = g == _group;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _group = g);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? AppColors.brand.withValues(alpha: 0.15)
                          : const Color(0xFFF2F3F5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      g,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: on ? AppColors.brand : const Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: _loading
                ? Center(child: FigmaMetaballLoader(size: 48))
                : RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _boot,
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  '暂无直播源\n点右上角导入 M3U，或配置后台 live.m3u',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    color: Color(0xFF8E8E93),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final c = list[i];
                              return GestureDetector(
                                onTap: () => _open(c),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F8FA),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFE8E8EC),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE8EEF0),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          CupertinoIcons.tv,
                                          size: 18,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.left,
                                              style: const TextStyle(
                                                fontFamily: 'AppSans',
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF333333),
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              c.group,
                                              textAlign: TextAlign.left,
                                              style: const TextStyle(
                                                fontFamily: 'AppSans',
                                                fontSize: 12,
                                                color: Color(0xFF8E8E93),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        CupertinoIcons.play_fill,
                                        size: 18,
                                        color: AppColors.brand,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LivePlayerPage extends StatelessWidget {
  const _LivePlayerPage({required this.channel});

  final LiveChannel channel;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: MangoInlinePlayer(
        url: channel.url,
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
        immersiveTop: true,
        enableDanmaku: false,
        vodId: channel.id,
        danmakuTitle: channel.name,
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
                  channel.name,
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

/// 从配置 URL 拉 m3u（供外部调用）
Future<String?> fetchRemoteText(String url) async {
  try {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return utf8.decode(res.bodyBytes);
    }
  } catch (_) {}
  return null;
}
