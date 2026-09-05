import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_permission.dart';
import '../services/cms_fav_store.dart';
import '../services/cms_message_store.dart';
import '../services/local_play_store.dart';
import '../services/maccms_api.dart';
import '../services/maccms_user_api.dart';
import '../state/cms_auth_controller.dart';
import '../state/theme_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/figma_loading.dart';
import '../widgets/movie_poster_mosaic.dart';
import 'cms_favs_page.dart';
import 'cms_messages_page.dart';
import 'membership_shop_page.dart';
import 'movie_detail_page.dart';
import 'settings_page.dart';
import 'vod_cache_list_page.dart';
import 'watch_history_page.dart';
import '../widgets/app_page_route.dart';

/// 我的：参考布局（模糊风景顶栏 + 悬浮特权卡 + Tab + 横滑历史）
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  bool _refreshing = false;
  List<CmsUlogItem> _plays = const [];
  List<CmsUlogItem> _favs = const [];
  List<String> _favDecorCovers = const [];
  String? _listError;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    CmsAuthController.instance.addListener(_onAuth);
    CmsMessageStore.instance.addListener(_onMessages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshAll());
      unawaited(CmsMessageStore.instance
          .bootstrap(userId: CmsAuthController.instance.user?.userId ?? 0)
          .then((_) {
        if (mounted) setState(() {});
      }));
    });
  }

  @override
  void dispose() {
    CmsAuthController.instance.removeListener(_onAuth);
    CmsMessageStore.instance.removeListener(_onMessages);
    super.dispose();
  }

  void _onMessages() {
    if (mounted) setState(() {});
  }

  void _onAuth() {
    if (!mounted) return;
    setState(() {});
    _loadLists(showSkeleton: false);
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      unawaited(
        CmsMessageStore.instance
            .refresh(CmsAuthController.instance.api)
            .then((_) {
          if (mounted) setState(() {});
        }),
      );
      if (CmsAuthController.instance.isLoggedIn) {
        try {
          await CmsAuthController.instance.refreshProfile();
        } catch (_) {}
      }
      await _loadLists(showSkeleton: false);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _loadLists({bool showSkeleton = true}) async {
    if (showSkeleton && mounted) setState(() => _loading = true);

    Future<List<CmsUlogItem>> fromLocal() async {
      final local = await LocalPlayStore.list(limit: 30);
      return [
        for (final e in local)
          CmsUlogItem(
            id: e.vodId,
            vodId: e.vodId,
            name: e.name,
            pic: e.pic,
            remarks: e.remarks,
            playedAt: e.playedAt,
            timeText: _formatRelative(e.playedAt),
            episodeLabel: e.episodeLabel,
            episodeNid: e.episodeIndex + 1,
            progress: e.progress,
          ),
      ];
    }

    Future<List<CmsUlogItem>> mergeFavs(List<CmsUlogItem> remote) async {
      if (remote.isNotEmpty) {
        await CmsFavStore.mergeFromRemote([
          for (final e in remote)
            (
              vodId: e.vodId,
              name: e.name,
              pic: e.pic,
              ulogId: e.id,
            ),
        ]);
      }
      final local = await CmsFavStore.list();
      final byRemote = {
        for (final e in remote) CmsFavStore.normId(e.vodId): e,
      };
      final out = <CmsUlogItem>[
        for (final e in local)
          byRemote[e.vodId] ??
              CmsUlogItem(
                id: e.ulogId.isNotEmpty ? e.ulogId : e.vodId,
                vodId: e.vodId,
                name: e.name.isEmpty ? '影片 ${e.vodId}' : e.name,
                pic: e.pic,
                playedAt: e.updatedAt,
              ),
      ];
      final ids = out.map((e) => e.vodId).toSet();
      for (final e in remote) {
        final id = CmsFavStore.normId(e.vodId);
        if (id.isNotEmpty && !ids.contains(id)) out.add(e);
      }
      return out;
    }

    if (_favDecorCovers.isEmpty) {
      unawaited(() async {
        try {
          final hot = await MacCmsApi().fetchHotMovies(limit: 9);
          final urls = <String>[
            for (final m in hot)
              if ((m.coverUrl ?? '').trim().isNotEmpty) m.coverUrl!.trim(),
          ];
          if (!mounted || urls.isEmpty) return;
          setState(() => _favDecorCovers = urls);
        } catch (_) {}
      }());
    }

    if (!CmsAuthController.instance.isLoggedIn) {
      final plays = await fromLocal();
      final favs = await mergeFavs(const []);
      if (!mounted) return;
      setState(() {
        _plays = plays;
        _favs = favs;
        _listError = null;
        _loading = false;
      });
      return;
    }

    final api = CmsAuthController.instance.api;
    try {
      final results = await Future.wait([
        api.fetchUlog(type: 2, limit: 40),
        api.fetchUlog(type: 1, limit: 40),
      ]);
      final playsRaw = results[0];
      final favsRaw = results[1];
      final localPlays = await fromLocal();
      final byLocal = {for (final e in localPlays) e.vodId: e};

      final List<CmsUlogItem> plays;
      if (playsRaw.isEmpty) {
        plays = localPlays;
      } else {
        final cmsIds = playsRaw.map((e) => e.vodId).toSet();
        plays = [
          for (final p in playsRaw)
            () {
              final loc = byLocal[p.vodId];
              final playedAt =
                  (loc?.playedAt ?? 0) > 0 ? loc!.playedAt : p.playedAt;
              final epLabel = (loc?.episodeLabel ?? '').isNotEmpty
                  ? loc!.episodeLabel
                  : p.episodeDisplay;
              return CmsUlogItem(
                id: p.id,
                vodId: p.vodId,
                name: p.name,
                pic: _pickBetterPic(p.pic, loc?.pic ?? ''),
                remarks: p.remarks,
                typeName: p.typeName,
                link: p.link,
                playedAt: playedAt,
                timeText: playedAt > 0
                    ? _formatRelative(playedAt)
                    : (p.timeText.isNotEmpty ? p.timeText : ''),
                episodeLabel: epLabel,
                episodeNid: p.episodeNid > 0
                    ? p.episodeNid
                    : (loc?.episodeNid ?? 0),
                progress: loc?.progress ?? p.progress,
              );
            }(),
          // CMS 尚未同步到的本机记录也保留
          for (final loc in localPlays)
            if (!cmsIds.contains(loc.vodId)) loc,
        ];
        plays.sort((a, b) => b.playedAt.compareTo(a.playedAt));
      }

      final favs = await mergeFavs(favsRaw);
      if (!mounted) return;
      setState(() {
        _plays = plays;
        _favs = favs;
        _listError = null;
        _loading = false;
      });
      _enrichCoversInBackground(plays, forFavs: false);
      _enrichCoversInBackground(favs, forFavs: true);
    } on CmsUserException catch (e) {
      if (!mounted) return;
      final local = await fromLocal();
      final favs = await mergeFavs(const []);
      setState(() {
        _plays = local;
        _favs = favs;
        _listError = e.code == 401 ? '登录已失效，下拉可重试' : e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      final local = await fromLocal();
      final favs = await mergeFavs(const []);
      setState(() {
        _plays = local;
        _favs = favs;
        _listError = local.isEmpty ? '播放记录加载失败' : null;
        _loading = false;
      });
    }
  }

  Future<void> _enrichCoversInBackground(
    List<CmsUlogItem> items, {
    bool forFavs = false,
  }) async {
    final need = items.where(_needsCoverEnrich).take(20).toList();
    if (need.isEmpty) return;
    final cms = MacCmsApi();
    final map = <String, ({String pic, String name})>{};

    Future<void> fetchOne(CmsUlogItem it) async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final m = await cms
              .fetchDetail(it.vodId)
              .timeout(const Duration(seconds: 12));
          final pic = CmsCoverImage.resolve(m.coverUrl) ??
              CmsCoverImage.resolve(m.slideUrl) ??
              '';
          // resolve 返回完整 URL；存原始字段便于 coverUrl 再解析
          final raw = (m.coverUrl ?? m.slideUrl ?? '').trim();
          final name = m.title.trim();
          if (raw.isNotEmpty || pic.isNotEmpty || name.isNotEmpty) {
            map[it.vodId] = (
              pic: raw.isNotEmpty ? raw : pic,
              name: name,
            );
            if (raw.isNotEmpty || pic.isNotEmpty) {
              unawaited(
                LocalPlayStore.updatePic(
                  vodId: it.vodId,
                  pic: raw.isNotEmpty ? raw : pic,
                ),
              );
            }
          }
          return;
        } catch (_) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        }
      }
    }

    await Future.wait([for (final it in need) fetchOne(it)]);
    if (!mounted || map.isEmpty) return;
    setState(() {
      List<CmsUlogItem> patch(List<CmsUlogItem> list) => [
            for (final p in list)
              if (map.containsKey(p.vodId))
                CmsUlogItem(
                  id: p.id,
                  vodId: p.vodId,
                  name: (map[p.vodId]!.name.isNotEmpty &&
                          _looksLikePlaceholderName(p))
                      ? map[p.vodId]!.name
                      : p.name,
                  pic: map[p.vodId]!.pic.isNotEmpty
                      ? map[p.vodId]!.pic
                      : p.pic,
                  remarks: p.remarks,
                  typeName: p.typeName,
                  link: p.link,
                  timeText: p.timeText,
                  playedAt: p.playedAt,
                  episodeLabel: p.episodeLabel,
                  episodeNid: p.episodeNid,
                  progress: p.progress,
                )
              else
                p,
          ];
      if (forFavs) {
        _favs = patch(_favs);
      } else {
        _plays = patch(_plays);
      }
    });
  }

  static bool _needsCoverEnrich(CmsUlogItem e) {
    if (_looksLikePlaceholderName(e)) return true;
    return CmsCoverImage.resolve(e.pic) == null;
  }

  /// 优先可用封面，忽略 nopic / 空串
  static String _pickBetterPic(String a, String b) {
    bool usable(String s) {
      final t = s.trim().toLowerCase();
      if (t.isEmpty) return false;
      if (t.contains('nopic') ||
          t.contains('nopicture') ||
          t.contains('no_pic') ||
          t.endsWith('default.png') ||
          t.endsWith('default.jpg')) {
        return false;
      }
      return true;
    }

    if (usable(a)) return a.trim();
    if (usable(b)) return b.trim();
    return '';
  }

  static bool _looksLikePlaceholderName(CmsUlogItem e) {
    final n = e.name.trim();
    if (n.isEmpty) return true;
    if (n.startsWith('影片')) return true;
    if (n == e.typeName) return true;
    return false;
  }

  static String _formatRelative(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (dt.year == DateTime.now().year) {
      return '${dt.month}月${dt.day}日';
    }
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  Future<void> _openVod(CmsUlogItem item) async {
    final id = item.vodId.trim();
    if (id.isEmpty) return;
    HapticFeedback.selectionClick();
    DialogX.showWait('加载中…');
    try {
      final movie = await MacCmsApi().fetchDetail(id);
      DialogX.dismiss();
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => MovieDetailPage(movie: movie, autoPlay: true),
        ),
      );
      _loadLists(showSkeleton: false);
    } catch (e) {
      DialogX.showError('$e');
    }
  }

  Future<void> _changeAvatar() async {
    if (!CmsAuthController.instance.isLoggedIn) {
      await showAuthSheet(context);
      return;
    }
    HapticFeedback.selectionClick();
    final allowed = await AppPermission.requestWithRationale(
      AppPermissionKind.photos,
      context: context,
      title: '需要访问相册',
      message: '更换头像时需要读取你选择的照片，仅用于设置个人头像。',
    );
    if (!allowed) return;
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 88,
      );
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final uid = CmsAuthController.instance.user?.userId ?? 0;
      final dest = File('${dir.path}/cms_avatar_$uid.jpg');
      await File(x.path).copy(dest.path);
      await CmsAuthController.instance.updateLocalProfile(portrait: dest.path);
      if (!mounted) return;
      setState(() {});
      DialogX.showSuccess('头像已更新');
    } catch (e) {
      DialogX.showError('更换失败：$e');
    }
  }

  void _push(Widget page) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(AppPageRoute<void>(builder: (_) => page));
  }

  void _openSettings() {
    HapticFeedback.selectionClick();
    _push(const SettingsPage());
  }

  void _toggleTheme() {
    HapticFeedback.mediumImpact();
    ThemeController.instance.toggle();
  }


  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final auth = CmsAuthController.instance;
    final bodyBg = AppPalette.page(context);

    return ListenableBuilder(
      listenable: Listenable.merge([auth, ThemeController.instance]),
      builder: (context, _) {
        final user = auth.user;
        final loggedIn = auth.isLoggedIn;
        final dark = ThemeController.instance.isDark;

        return Scaffold(
          backgroundColor: bodyBg,
          body: ColoredBox(
            color: bodyBg,
            child: AppPullRefresh(
              color: AppColors.brand,
              edgeOffset: top,
              onRefresh: _refreshAll,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _HeroBand(
                      topInset: top,
                      loggedIn: loggedIn,
                      user: user,
                      darkMode: dark,
                      flagDays: loggedIn ? (user?.points ?? 0) : 0,
                      onLogin: () => showAuthSheet(context),
                      onToggleTheme: _toggleTheme,
                      onSettings: _openSettings,
                      onMessages: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context)
                            .push(
                          AppPageRoute<void>(
                            builder: (_) => const CmsMessagesPage(),
                          ),
                        )
                            .then((_) {
                          if (mounted) setState(() {});
                        });
                      },
                      messageBadge: CmsMessageStore.instance.unreadCount,
                      onEditAvatar: () => unawaited(_changeAvatar()),
                      onFavs: () async {
                        if (!CmsAuthController.instance.isLoggedIn) {
                          await showAuthSheet(context);
                          if (!CmsAuthController.instance.isLoggedIn) return;
                        }
                        if (!mounted) return;
                        _push(const CmsFavsPage());
                      },
                      onCache: () {
                        HapticFeedback.selectionClick();
                        _push(const VodCacheListPage());
                      },
                      onVip: () {
                        HapticFeedback.selectionClick();
                        _push(const MembershipShopPage());
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: bodyBg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_listError != null)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Text(
                                _listError!,
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 13,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                            child: _ProfileListCard(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      10,
                                      12,
                                      0,
                                    ),
                                    child: _Tabs(
                                      index: _tab,
                                      historyCount: _plays.length,
                                      favCount: _favs.length,
                                      onChanged: (i) =>
                                          setState(() => _tab = i),
                                      onAllHistory: () =>
                                          _push(const WatchHistoryPage()),
                                    ),
                                  ),
                                  if (_loading &&
                                      _plays.isEmpty &&
                                      _tab == 0)
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        12,
                                        12,
                                      ),
                                      child: _HistorySkeleton(),
                                    )
                                  else if (_tab == 0 && _plays.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        36,
                                        16,
                                        28,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '暂无播放记录',
                                          style: TextStyle(
                                            fontFamily: 'AppSans',
                                            fontSize: 14,
                                            color: AppPalette.textHint(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  else if (_tab == 0)
                                    SizedBox(
                                      height: 268,
                                      child: _PlayTimeline(
                                        items: _plays,
                                        onOpen: _openVod,
                                      ),
                                    )
                                  else if (_tab == 1)
                                    _ProfileFavCarousel(
                                      items: _favs,
                                      decorCovers: _favDecorCovers,
                                      loggedIn: loggedIn,
                                      onLogin: () => showAuthSheet(context),
                                      onBrowse: () async {
                                        await Navigator.of(context).push(
                                          AppPageRoute<void>(
                                            builder: (_) =>
                                                const CmsFavsPage(),
                                          ),
                                        );
                                        if (mounted) {
                                          unawaited(
                                            _loadLists(showSkeleton: false),
                                          );
                                        }
                                      },
                                      onOpen: _openVod,
                                    )
                                  else
                                    const SizedBox.shrink(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 140),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


class _HeroBand extends StatelessWidget {
  const _HeroBand({
    required this.topInset,
    required this.loggedIn,
    required this.user,
    required this.darkMode,
    required this.flagDays,
    required this.onLogin,
    required this.onToggleTheme,
    required this.onSettings,
    required this.onMessages,
    required this.messageBadge,
    required this.onEditAvatar,
    required this.onFavs,
    required this.onCache,
    required this.onVip,
  });

  final double topInset;
  final bool loggedIn;
  final CmsUser? user;
  final bool darkMode;
  final int flagDays;
  final VoidCallback onLogin;
  final VoidCallback onToggleTheme;
  final VoidCallback onSettings;
  final VoidCallback onMessages;
  final int messageBadge;
  final VoidCallback onEditAvatar;
  final VoidCallback onFavs;
  final VoidCallback onCache;
  final VoidCallback onVip;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final name = loggedIn ? (u?.displayName ?? '会员') : '未登录';
    final accent = AppColors.brand;
    final ink = AppPalette.text(context);
    final hint = AppPalette.textHint(context);
    final cardBg = AppPalette.isDark(context)
        ? const Color(0xFF2A2A2C)
        : const Color(0xFFF3F4F6);
    final subtitle = loggedIn
        ? '在哇TV Flag 打卡第$flagDays天'
        : '登录后开启打卡与会员权益';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topInset + 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Spacer(),
              _ProfileBellButton(
                badge: messageBadge,
                onPressed: onMessages,
              ),
              _ThemeToggleButton(
                dark: darkMode,
                onPressed: onToggleTheme,
                lightOnDark: false,
              ),
              IconButton(
                onPressed: onSettings,
                icon: Icon(
                  CupertinoIcons.gear_alt_fill,
                  size: 22,
                  color: ink,
                ),
              ),
            ],
          ),
          // 图一：顶栏图标与昵称/头像之间多留间距
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: loggedIn ? null : onLogin,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: ink,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: hint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: loggedIn ? onEditAvatar : onLogin,
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: ClipOval(child: _profileAvatar(u?.avatarUrl)),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _QuickEntryCard(
                  label: '我的收藏',
                  background: cardBg,
                  icon: CupertinoIcons.heart_fill,
                  accent: accent,
                  onTap: onFavs,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _QuickEntryCard(
                  label: '我的缓存',
                  background: cardBg,
                  icon: CupertinoIcons.arrow_down_circle_fill,
                  accent: accent,
                  onTap: onCache,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _VipEntryCard(
            background: cardBg,
            accent: accent,
            expireText: _vipExpireLabel(loggedIn, u),
            onTap: onVip,
          ),
        ],
      ),
    );
  }
}

String _vipExpireLabel(bool loggedIn, CmsUser? user) {
  if (!loggedIn) return '点击开通';
  final raw = (user?.endTime ?? '').trim();
  final group = (user?.groupName ?? '').trim();
  final looksVip = group.contains('VIP') ||
      group.contains('vip') ||
      (group.contains('会员') && !group.contains('游客'));

  if (raw.isEmpty || raw == '0' || raw == '0000-00-00') {
    // 有会员组但无到期字段 → 多为永久；否则就是未开通
    return looksVip ? '永久会员' : '未开通';
  }

  final ts = int.tryParse(raw);
  if (ts != null && ts > 1000000000) {
    final sec = ts > 9999999999 ? ts ~/ 1000 : ts;
    // 常见「永久」占位：远未来或 0 已排除
    if (sec >= 4102444800) return '永久会员'; // >= 2100-01-01
    final dt = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    final now = DateTime.now();
    if (dt.isBefore(now)) return '已过期';
    return '至 ${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  final m = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(raw);
  if (m != null) {
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (y >= 2099) return '永久会员';
    final dt = DateTime(y, mo, d);
    if (dt.isBefore(DateTime.now())) return '已过期';
    return '至 ${y.toString().padLeft(4, '0')}-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  if (raw.contains('永久')) return '永久会员';
  return looksVip ? raw : '未开通';
}

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({
    required this.label,
    required this.background,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color background;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.text(context);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              Icon(icon, size: 30, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _VipEntryCard extends StatelessWidget {
  const _VipEntryCard({
    required this.background,
    required this.accent,
    required this.expireText,
    required this.onTap,
  });

  final Color background;
  final Color accent;
  final String expireText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.text(context);
    final hint = AppPalette.textHint(context);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          child: Row(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '我的',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    TextSpan(
                      text: ' VIP',
                      style: TextStyle(
                        fontFamily: 'ZCOOLKuaiLe',
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        color: accent,
                        letterSpacing: 0.5,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  expireText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: hint,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(CupertinoIcons.ticket_fill, size: 28, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放历史 / 收藏列表外层卡片
class _ProfileListCard extends StatelessWidget {
  const _ProfileListCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2A2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x33000000) : const Color(0x0F000000),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 未读时左右摇铃；暗色角标用品牌青，亮色用红
class _ProfileBellButton extends StatefulWidget {
  const _ProfileBellButton({
    required this.badge,
    required this.onPressed,
  });

  final int badge;
  final VoidCallback onPressed;

  @override
  State<_ProfileBellButton> createState() => _ProfileBellButtonState();
}

class _ProfileBellButtonState extends State<_ProfileBellButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring;

  bool get _shouldRing => widget.badge > 0;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _syncRing();
  }

  @override
  void didUpdateWidget(covariant _ProfileBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.badge != widget.badge) _syncRing();
  }

  void _syncRing() {
    if (_shouldRing) {
      if (!_ring.isAnimating) _ring.repeat();
    } else {
      _ring
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  double _ringAngle(double t) {
    if (t > 0.42) return 0;
    final local = t / 0.42;
    final swings = local * math.pi * 5;
    final amp = (1.0 - local) * 0.32;
    return math.sin(swings) * amp;
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeController.instance.isDark;
    final badgeBg = dark ? AppColors.brand : const Color(0xFFFF3B30);
    final iconColor = AppPalette.text(context);

    return IconButton(
      onPressed: widget.onPressed,
      tooltip: '消息',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _ring,
            builder: (context, child) {
              return Transform.rotate(
                angle: _ringAngle(_ring.value),
                alignment: const Alignment(0, -0.6),
                child: child,
              );
            },
            child: Icon(
              CupertinoIcons.bell_fill,
              size: 24,
              color: iconColor,
            ),
          ),
          if (widget.badge > 0)
            Positioned(
              right: -4,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppPalette.page(context),
                    width: 1.2,
                  ),
                ),
                child: Text(
                  widget.badge > 99 ? '99+' : '${widget.badge}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _profileAvatar(String? url) {
  final u = (url ?? '').trim();
  if (u.isEmpty) return const _AvatarPh();
  if (!u.startsWith('http')) {
    final f = File(u);
    if (f.existsSync()) {
      return Image.file(
        f,
        key: ValueKey('${u}_${f.lastModifiedSync().millisecondsSinceEpoch}'),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _AvatarPh(),
      );
    }
  }
  if (u.startsWith('http')) {
    return Image.network(
      u,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _AvatarPh(),
    );
  }
  return const _AvatarPh();
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.index,
    required this.historyCount,
    required this.favCount,
    required this.onChanged,
    this.onAllHistory,
  });

  final int index;
  final int historyCount;
  final int favCount;
  final ValueChanged<int> onChanged;
  final VoidCallback? onAllHistory;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, int i, int count) {
      final on = index == i;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(i);
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 20, top: 2, bottom: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: on ? 17 : 15,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                      color: on
                          ? AppPalette.text(context)
                          : AppPalette.textHint(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 20,
                    height: 3,
                    decoration: BoxDecoration(
                      color: on ? AppColors.ember : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: EdgeInsets.only(top: on ? 4 : 3),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: AppPalette.textHint(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        item('播放历史', 0, historyCount),
        item('收藏', 1, favCount),
        const Spacer(),
        if (index == 0 && onAllHistory != null)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onAllHistory!();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8, left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '全部历史',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textHint(context),
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: AppPalette.textHint(context),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 横滑播放历史 + 时间轴线（时间 → 圆点连线 → 海报）
class _PlayTimeline extends StatelessWidget {
  const _PlayTimeline({
    required this.items,
    required this.onOpen,
    this.showProgress = true,
  });

  final List<CmsUlogItem> items;
  final ValueChanged<CmsUlogItem> onOpen;
  final bool showProgress;

  static const _itemW = 118.0;
  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    final line = AppPalette.line(context);

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      addAutomaticKeepAlives: true,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        final isFirst = i == 0;
        final isLast = i == items.length - 1;
        final time = it.timeText.isNotEmpty ? it.timeText : '最近';
        final ep = it.episodeDisplay;
        final progress = it.progress.clamp(0.0, 1.0);

        return KeyedSubtree(
          key: ValueKey('ulog_${it.vodId}_${it.pic}_$i'),
          child: GestureDetector(
          onTap: () => onOpen(it),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: _itemW + (isLast ? 0 : _gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _itemW,
                  child: Text(
                    time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 11,
                      fontWeight: isFirst ? FontWeight.w700 : FontWeight.w500,
                      color: isFirst
                          ? AppColors.ember
                          : AppPalette.textHint(context),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                SizedBox(
                  width: _itemW + (isLast ? 0 : _gap),
                  height: 16,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (!isFirst)
                        Positioned(
                          left: 0,
                          width: _itemW / 2,
                          top: 7,
                          child: Container(height: 2, color: line),
                        ),
                      Positioned(
                        left: _itemW / 2,
                        right: isLast ? _itemW / 2 : 0,
                        top: 7,
                        child: Container(height: 2, color: line),
                      ),
                      Positioned(
                        left: _itemW / 2 - 6,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFirst
                                ? AppColors.ember
                                : AppPalette.surface(context),
                            border: Border.all(
                              color: isFirst
                                  ? AppColors.ember
                                  : AppPalette.textHint(context),
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: _itemW,
                  height: 168,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CmsCoverImage(url: it.pic, vodId: it.vodId),
                        if (ep.isNotEmpty)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              color: const Color(0xD9000000),
                              child: Text(
                                ep,
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        // 进度贴在海报底部，避免标题下单独一条突兀进度条
                        if (showProgress && progress > 0.01)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 3,
                              color: Colors.black.withValues(alpha: 0.28),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progress.clamp(0.0, 1.0),
                                child: ColoredBox(
                                  color: AppColors.brand.withValues(alpha: 0.92),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: _itemW,
                  child: Text(
                    it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.text(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

/// 片名右侧环形进度（内显示百分比）
class _PosterProgressRing extends StatelessWidget {
  const _PosterProgressRing({required this.progress});

  final double progress;

  static const _size = 28.0;
  static const _stroke = 2.5;
  static const _track = Color(0xFFE0E0E0);
  static const _fill = Color(0xFF00A1D6);

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final pct = (p * 100).round().clamp(0, 100);
    return SizedBox(
      width: _size,
      height: _size,
      child: CustomPaint(
        painter: _RingPainter(progress: p),
        child: Center(
          child: Text(
            '$pct%',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: pct >= 100 ? 7 : 8,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF333333),
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.shortestSide - _PosterProgressRing._stroke) / 2;
    final track = Paint()
      ..color = _PosterProgressRing._track
      ..style = PaintingStyle.stroke
      ..strokeWidth = _PosterProgressRing._stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = _PosterProgressRing._fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = _PosterProgressRing._stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track);
    if (progress > 0.005) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -1.57079632679, // 从正上方开始
        progress * 6.28318530718,
        false,
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 248,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) {
          return _Pulse(
            child: SizedBox(
              width: 118,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 10,
                    color: FigmaSkeletonColors.bone,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: FigmaSkeletonColors.bone,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 12, color: FigmaSkeletonColors.bone),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThemeToggleButton extends StatefulWidget {
  const _ThemeToggleButton({
    required this.dark,
    required this.onPressed,
    this.lightOnDark = false,
  });
  final bool dark;
  final VoidCallback onPressed;
  final bool lightOnDark;

  @override
  State<_ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends State<_ThemeToggleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: widget.dark ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _ThemeToggleButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dark != widget.dark) {
      if (widget.dark) {
        _c.forward(from: 0);
      } else {
        _c.reverse(from: 1);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.lightOnDark ? Colors.white : AppPalette.text(context);
    return IconButton(
      onPressed: widget.onPressed,
      tooltip: widget.dark ? '切换浅色' : '切换深色',
      icon: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInOutBack.transform(_c.value.clamp(0.0, 1.0));
          final bounce = 1.0 + 0.12 * math.sin(t * math.pi);
          return Transform.scale(
            scale: bounce.clamp(0.88, 1.14),
            child: SizedBox(
              width: 26,
              height: 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: t * 1.1,
                      child: Icon(
                        CupertinoIcons.moon_fill,
                        size: 24,
                        color: color,
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: (t - 1) * 1.1,
                      child: Icon(
                        CupertinoIcons.sun_max_fill,
                        size: 24,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: 0.55 + _c.value * 0.45,
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _AvatarPh extends StatelessWidget {
  const _AvatarPh();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF3A322E),
      child: Icon(
        CupertinoIcons.person_fill,
        size: 30,
        color: Color(0x88FFFFFF),
      ),
    );
  }
}

/// 我的页 · 收藏 Tab：叠放海报（1/2/3 按量，多则轮播）
class _ProfileFavCarousel extends StatelessWidget {
  const _ProfileFavCarousel({
    required this.items,
    required this.decorCovers,
    required this.loggedIn,
    required this.onLogin,
    required this.onBrowse,
    required this.onOpen,
  });

  final List<CmsUlogItem> items;
  final List<String> decorCovers;
  final bool loggedIn;
  final VoidCallback onLogin;
  final VoidCallback onBrowse;
  final ValueChanged<CmsUlogItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final stackItems = [
      for (final e in items)
        FavStackItem(
          id: e.vodId,
          name: e.name,
          pic: e.pic,
        ),
    ];
    final empty = items.isEmpty;

    return FavCollectionCarousel(
      items: stackItems,
      decorCovers: decorCovers,
      onOpen: empty
          ? null
          : (it) {
              for (final e in items) {
                if (e.vodId == it.id) {
                  onOpen(e);
                  return;
                }
              }
            },
      title: empty
          ? (loggedIn ? '从收藏开始' : '登录后开启收藏')
          : '我的收藏',
      subtitle: empty
          ? '把喜欢的影视收进来，随时继续追'
          : (items.length == 1
              ? '点击海报直接播放'
              : items.length <= 3
                  ? '点中间播放 · 点侧卡展开'
                  : '左右滑动换页 · 点中间播放 · 点侧卡展开'),
      ctaLabel: !loggedIn
          ? '去登录'
          : (empty ? '去发现好片' : '查看全部收藏'),
      showCta: true,
      onCta: !loggedIn
          ? onLogin
          : (empty
              ? () {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              : onBrowse),
      height: empty ? 360 : 340,
      compact: false,
    );
  }
}

