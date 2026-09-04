import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../services/douyin_api.dart';
import '../state/auth_controller.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/douyin_media_image.dart';
import 'account_manage_page.dart';
import 'chat_list_page.dart';
import 'chat_messages_page.dart';
import 'cloud_disk_play_page.dart';
import 'cms_articles_page.dart';
import 'bt_play_page.dart';
import 'live_tv_page.dart';
import 'spark_renew_page.dart';
import 'sports_page.dart';
import 'vertical_short_feed_page.dart';
import '../config/api_config.dart';
import '../services/cms_app_config.dart';
import '../widgets/app_page_route.dart';

/// 功能页：账号数据仪表盘 + 作品 / 消息 / 互动预览
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _api = DouyinApi();

  List<DouyinAccount> _accounts = [];
  DouyinAccount? _account;
  int _totalFavorited = 0;

  List<DouyinWorkItem> _works = [];
  List<DouyinChatConversation> _chats = [];
  List<DouyinNoticeItem> _notices = [];

  bool _bootLoading = true;
  bool _detailLoading = false;
  bool _chatsLoading = false;
  bool _noticesLoading = false;

  String? _error;
  String? _worksError;
  String? _chatsError;
  String? _noticesError;

  @override
  void initState() {
    super.initState();
    AuthController.instance.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    AuthController.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (!AuthController.instance.isLoggedIn) {
      setState(() {
        _accounts = [];
        _account = null;
        _works = [];
        _chats = [];
        _notices = [];
        _totalFavorited = 0;
        _bootLoading = false;
        _error = null;
      });
      return;
    }
    _bootstrap();
  }

  Future<bool> _ensureLogin() async {
    if (AuthController.instance.isLoggedIn) return true;
    final ok = await showAuthSheet(context);
    if (ok != true) {
      if (mounted) DialogX.showWarning('请先登录后再使用');
      return false;
    }
    return AuthController.instance.isLoggedIn;
  }

  Future<void> _bootstrap({bool force = false}) async {
    if (!AuthController.instance.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _bootLoading = false;
        _accounts = [];
        _account = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _bootLoading = true;
      _error = null;
    });

    try {
      // Phase 1：本地库列表，秒开展示账号与缓存数据
      final accounts = await _api.myList();
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _accounts = [];
          _account = null;
          _works = [];
          _chats = [];
          _notices = [];
          _bootLoading = false;
          _error = '请先绑定抖音账号';
        });
        return;
      }

      DouyinAccount? found;
      final currentId = _account?.id;
      if (currentId != null) {
        for (final a in accounts) {
          if (a.id == currentId) {
            found = a;
            break;
          }
        }
      }
      final selected = found ?? accounts.first;

      setState(() {
        _accounts = accounts;
        _account = selected;
        _bootLoading = false;
      });

      await _loadSections(selected);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _bootLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bootLoading = false;
        _error = '加载失败，请下拉重试';
      });
    }
  }

  Future<void> _loadSections(DouyinAccount account) async {
    if (!mounted) return;
    setState(() {
      _detailLoading = true;
      _chatsLoading = true;
      _noticesLoading = true;
      _worksError = null;
      _chatsError = null;
      _noticesError = null;
    });

    // Phase 2：概览+作品 与 互动通知并行；私信单独拉预览（最慢，不阻塞其它块）
    final detailFuture = _api.myGet(accountId: account.id, worksCount: 16);
    final noticesFuture = _api.myNotices(accountId: account.id, count: 5);
    final chatsFuture = _api.myChats(accountId: account.id, limit: 8, fast: true);

    detailFuture.then((detail) {
      if (!mounted || _account?.id != account.id) return;
      setState(() {
        _account = detail.account;
        _works = detail.works;
        if (detail.totalFavorited > 0) {
          _totalFavorited = detail.totalFavorited;
        }
        _detailLoading = false;
        if (detail.liveError.isNotEmpty && detail.works.isEmpty) {
          _worksError = detail.liveError;
        }
      });
      final idx = _accounts.indexWhere((a) => a.id == detail.account.id);
      if (idx >= 0) {
        _accounts[idx] = detail.account;
      }
    }).catchError((e) {
      if (!mounted || _account?.id != account.id) return;
      setState(() {
        _detailLoading = false;
        _worksError = e is ApiException ? e.message : '作品加载失败';
      });
    });

    noticesFuture.then((list) {
      if (!mounted || _account?.id != account.id) return;
      setState(() {
        _notices = list.take(5).toList();
        _noticesLoading = false;
      });
    }).catchError((e) {
      if (!mounted || _account?.id != account.id) return;
      setState(() {
        _noticesLoading = false;
        _noticesError = e is ApiException ? e.message : '互动加载失败';
      });
    });

    chatsFuture.then((list) {
      if (!mounted || _account?.id != account.id) return;
      setState(() {
        _chats = list.take(5).toList();
        _chatsLoading = false;
      });
    }).catchError((e) {
      if (!mounted || _account?.id != account.id) return;
      setState(() {
        _chatsLoading = false;
        _chatsError = e is ApiException ? e.message : '消息加载失败';
      });
    });
  }

  Future<void> _switchAccount(DouyinAccount account) async {
    if (_account?.id == account.id) return;
    HapticFeedback.selectionClick();
    setState(() {
      _account = account;
      _works = [];
      _chats = [];
      _notices = [];
      _totalFavorited = 0;
    });
    await _loadSections(account);
  }

  Future<void> _openMessages() async {
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    final id = _account?.id;
    await Navigator.of(context, rootNavigator: true).push(
      AppPageRoute<void>(
        builder: (_) => ChatListPage(accountId: id),
      ),
    );
  }

  Future<void> _openSpark() async {
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    final id = _account?.id;
    await Navigator.of(context, rootNavigator: true).push(
      AppPageRoute<void>(
        builder: (_) => SparkRenewPage(accountId: id),
      ),
    );
  }

  Future<void> _openAccounts() async {
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      AppPageRoute<void>(builder: (_) => const AccountManagePage()),
    );
    if (mounted) await _bootstrap(force: true);
  }

  Future<void> _openChat(DouyinChatConversation c) async {
    final acc = _account;
    if (acc == null) return;
    await Navigator.of(context, rootNavigator: true).push(
      AppPageRoute<void>(
        builder: (_) => ChatMessagesPage(
          accountId: acc.id,
          conversation: c,
          selfAvatarUrl: acc.avatarUrl,
        ),
      ),
    );
  }

  Future<void> _pickAccount() async {
    if (_accounts.length <= 1) {
      await _openAccounts();
      return;
    }
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('切换抖音账号'),
        actions: [
          for (final a in _accounts)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _switchAccount(a);
              },
              child: Text(
                a.nickname +
                    (a.id == _account?.id ? '（当前）' : ''),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final loggedIn = AuthController.instance.isLoggedIn;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: () => _bootstrap(force: true)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top + 12, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '功能',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '短剧 · 解说 · 云盘 · 文章',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 15,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ),
                ),
                if (loggedIn)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _bootstrap(force: true),
                    child: Icon(CupertinoIcons.refresh, size: 22, color: AppColors.iosBlue),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _CmsFeatureHub(
              onShortDrama: () {
                Navigator.of(context, rootNavigator: true).push(
                  AppPageRoute<void>(
                    builder: (_) => const VerticalShortFeedPage(
                      title: '短剧',
                      typeId: ApiConfig.macCmsShortDramaTypeId,
                    ),
                  ),
                );
              },
              onCommentary: () {
                Navigator.of(context, rootNavigator: true).push(
                  AppPageRoute<void>(
                    builder: (_) => const VerticalShortFeedPage(
                      title: '影视解说',
                      typeId: ApiConfig.macCmsCommentaryTypeId,
                    ),
                  ),
                );
              },
              onCloud: () {
                Navigator.of(context, rootNavigator: true).push(
                  AppPageRoute<void>(
                    builder: (_) => const CloudDiskPlayPage(),
                  ),
                );
              },
              onArticles: () {
                Navigator.of(context, rootNavigator: true).push(
                  AppPageRoute<void>(
                    builder: (_) => const CmsArticlesPage(),
                  ),
                );
              },
              onBt: () {
                Navigator.of(context, rootNavigator: true).push(
                  AppPageRoute<void>(
                    builder: (_) => const BtPlayPage(),
                  ),
                );
              },
              onLive: () {
                Navigator.of(context, rootNavigator: true).push(
                  AppPageRoute<void>(
                    builder: (_) => const LiveTvPage(),
                  ),
                );
              },
              onSports: () {
                Navigator.of(context, rootNavigator: true).push(
                  AppPageRoute<void>(
                    builder: (_) => const SportsPage(),
                  ),
                );
              },
            ),
          ),
        ),
        if (!loggedIn)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: _EmptyState(
                title: '登录后查看抖音账号数据',
                action: '去登录',
                onTap: () async {
                  await showAuthSheet(context);
                },
              ),
            ),
          )
        else if (_bootLoading && _account == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CupertinoActivityIndicator()),
            ),
          )
        else if (_error != null && _account == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: _EmptyState(
                title: _error!,
                action: _error!.contains('绑定') ? '去绑定' : '重试',
                onTap: () async {
                  if (_error!.contains('绑定')) {
                    await _openAccounts();
                  } else {
                    await _bootstrap(force: true);
                  }
                },
              ),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _AccountHeader(
                account: _account!,
                accountCount: _accounts.length,
                onSwitch: _pickAccount,
                onManage: _openAccounts,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _StatsRow(
                followers: _account!.followersCount,
                followings: _account!.followingsCount,
                aweme: _account!.awemeCount,
                favorited: _totalFavorited,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _QuickActions(
                onMessages: _openMessages,
                onSpark: _openSpark,
                onAccounts: _openAccounts,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionBlock(
              title: '作品',
              trailing: '',
              onMore: null,
              child: _WorksPreview(
                loading: _detailLoading && _works.isEmpty,
                error: _worksError,
                works: _works,
                onRetry: () {
                  final a = _account;
                  if (a != null) _loadSections(a);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionBlock(
              title: '消息',
              trailing: '全部',
              onMore: _openMessages,
              child: _ChatsPreview(
                loading: _chatsLoading && _chats.isEmpty,
                error: _chatsError,
                chats: _chats,
                onTap: _openChat,
                onRetry: () {
                  final a = _account;
                  if (a != null) _loadSections(a);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionBlock(
              title: '互动',
              trailing: '预览',
              onMore: null,
              child: _NoticesPreview(
                loading: _noticesLoading && _notices.isEmpty,
                error: _noticesError,
                notices: _notices,
                onRetry: () {
                  final a = _account;
                  if (a != null) _loadSections(a);
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ],
    );
  }
}

class _CmsFeatureHub extends StatelessWidget {
  const _CmsFeatureHub({
    required this.onShortDrama,
    required this.onCommentary,
    required this.onCloud,
    required this.onArticles,
    required this.onBt,
    required this.onLive,
    required this.onSports,
  });

  final VoidCallback onShortDrama;
  final VoidCallback onCommentary;
  final VoidCallback onCloud;
  final VoidCallback onArticles;
  final VoidCallback onBt;
  final VoidCallback onLive;
  final VoidCallback onSports;

  static const _gray = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final nav = CmsAppConfigStore.instance.config.nav;
    final items = <(IconData, String, VoidCallback)>[];
    void add(String action, IconData icon, String label, VoidCallback cb) {
      items.add((icon, label, cb));
    }

    if (nav.isEmpty) {
      add('short_drama', CupertinoIcons.play_rectangle, '短剧', onShortDrama);
      add('commentary', CupertinoIcons.mic, '解说', onCommentary);
      add('cloud', CupertinoIcons.link, '云盘', onCloud);
      add('bt', CupertinoIcons.arrow_down_doc, 'BT', onBt);
      add('art', CupertinoIcons.doc_text, '文章', onArticles);
      add('live', CupertinoIcons.tv, '直播', onLive);
      add('sports', CupertinoIcons.sportscourt, '体育', onSports);
    } else {
      for (final n in nav) {
        final a = n.action.toLowerCase();
        final cb = switch (a) {
          'short_drama' || 'short' => onShortDrama,
          'commentary' || '解说' => onCommentary,
          'cloud' => onCloud,
          'bt' || 'torrent' || 'magnet' => onBt,
          'art' || 'article' || 'articles' => onArticles,
          'live' || 'live_import' => onLive,
          'sports' => onSports,
          _ => null,
        };
        if (cb == null) continue;
        final icon = switch (a) {
          'short_drama' || 'short' => CupertinoIcons.play_rectangle,
          'commentary' => CupertinoIcons.mic,
          'cloud' => CupertinoIcons.link,
          'bt' || 'torrent' || 'magnet' => CupertinoIcons.arrow_down_doc,
          'art' || 'article' || 'articles' => CupertinoIcons.doc_text,
          'live' || 'live_import' => CupertinoIcons.tv,
          'sports' => CupertinoIcons.sportscourt,
          _ => CupertinoIcons.circle,
        };
        items.add((icon, n.title, cb));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '影视功能',
          textAlign: TextAlign.left,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF181818),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final it in items)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 32 - 30) / 4,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    it.$3();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8E8EC)),
                    ),
                    child: Column(
                      children: [
                        Icon(it.$1, size: 22, color: _gray),
                        const SizedBox(height: 6),
                        Text(
                          it.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _gray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _fmtCount(int n) {
  if (n >= 100000000) {
    return '${(n / 100000000).toStringAsFixed(1)}亿';
  }
  if (n >= 10000) {
    final v = n / 10000;
    return v >= 100 ? '${v.toStringAsFixed(0)}万' : '${v.toStringAsFixed(1)}万';
  }
  return '$n';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EAEF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F2FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(CupertinoIcons.person_crop_circle, size: 28, color: AppColors.iosBlue),
              ),
              SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A3A3C),
                  height: 1.35,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '登录后可同步任务与账号数据',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  color: Color(0xFF8E8E93),
                ),
              ),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.iosBlue,
                    side: BorderSide(color: AppColors.iosBlue, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    action,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.account,
    required this.accountCount,
    required this.onSwitch,
    required this.onManage,
  });

  final DouyinAccount account;
  final int accountCount;
  final VoidCallback onSwitch;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSwitch,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: account.avatarUrl.isNotEmpty
                  ? DouyinMediaImage(
                      url: account.avatarUrl,
                      width: 56,
                      height: 56,
                      fallbackLabel: '头',
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFFE5E5EA),
                      child: const Icon(
                        CupertinoIcons.person_fill,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    account.uniqueId.isNotEmpty
                        ? '@${account.uniqueId}'
                        : 'UID ${account.douyinUid}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                  if (account.description.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      account.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFFAEAEB2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                Icon(
                  accountCount > 1
                      ? CupertinoIcons.arrow_2_squarepath
                      : CupertinoIcons.chevron_forward,
                  size: 18,
                  color: const Color(0xFFC7C7CC),
                ),
                SizedBox(height: 8),
                GestureDetector(
                  onTap: onManage,
                  child: Text(
                    '管理',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: AppColors.iosBlue,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.followers,
    required this.followings,
    required this.aweme,
    required this.favorited,
  });

  final int followers;
  final int followings;
  final int aweme;
  final int favorited;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('粉丝', followers),
      ('关注', followings),
      ('作品', aweme),
      ('获赞', favorited),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 28, color: const Color(0xFFE5E5EA)),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _fmtCount(items[i].$2),
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].$1,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onMessages,
    required this.onSpark,
    required this.onAccounts,
  });

  final VoidCallback onMessages;
  final VoidCallback onSpark;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (CupertinoIcons.chat_bubble_2_fill, '消息', onMessages),
      (CupertinoIcons.flame_fill, '续火花', onSpark),
      (CupertinoIcons.person_2_fill, '账号', onAccounts),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                actions[i].$3();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(actions[i].$1, size: 22, color: AppColors.iosBlue),
                    const SizedBox(height: 6),
                    Text(
                      actions[i].$2,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.trailing,
    required this.child,
    this.onMore,
  });

  final String title;
  final String trailing;
  final Widget child;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              if (onMore != null)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onMore!();
                  },
                  child: Row(
                    children: [
                      Text(
                        trailing,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 14,
                          color: AppColors.iosBlue,
                        ),
                      ),
                      Icon(CupertinoIcons.chevron_forward, size: 14, color: AppColors.iosBlue),
                    ],
                  ),
                )
              else if (trailing.isNotEmpty)
                Text(
                  trailing,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFFAEAEB2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _WorksPreview extends StatefulWidget {
  const _WorksPreview({
    required this.loading,
    required this.error,
    required this.works,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<DouyinWorkItem> works;
  final VoidCallback onRetry;

  @override
  State<_WorksPreview> createState() => _WorksPreviewState();
}

enum _WorksFilter { all, public, private }

class _WorksPreviewState extends State<_WorksPreview> {
  _WorksFilter _filter = _WorksFilter.all;

  List<DouyinWorkItem> get _filtered {
    switch (_filter) {
      case _WorksFilter.all:
        return widget.works;
      case _WorksFilter.public:
        return widget.works.where((w) => !w.isPrivate).toList();
      case _WorksFilter.private:
        return widget.works.where((w) => w.isPrivate).toList();
    }
  }

  int get _publicCount => widget.works.where((w) => !w.isPrivate).length;
  int get _privateCount => widget.works.where((w) => w.isPrivate).length;

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (widget.error != null && widget.works.isEmpty) {
      return _SectionError(message: widget.error!, onRetry: widget.onRetry);
    }
    if (widget.works.isEmpty) {
      return const _SectionHint('暂无作品');
    }

    final list = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _WorksFilterChip(
              label: '全部',
              count: widget.works.length,
              selected: _filter == _WorksFilter.all,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filter = _WorksFilter.all);
              },
            ),
            const SizedBox(width: 8),
            _WorksFilterChip(
              label: '公开',
              count: _publicCount,
              selected: _filter == _WorksFilter.public,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filter = _WorksFilter.public);
              },
            ),
            const SizedBox(width: 8),
            _WorksFilterChip(
              label: '私密',
              count: _privateCount,
              selected: _filter == _WorksFilter.private,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filter = _WorksFilter.private);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          _SectionHint(
            _filter == _WorksFilter.private ? '暂无私密作品' : '暂无公开作品',
          )
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final w = list[i];
                return SizedBox(
                  width: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DouyinMediaImage(
                            url: w.cover,
                            fit: BoxFit.cover,
                            fallbackLabel: '作品',
                          ),
                          if (w.isPrivate)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '私密',
                                  style: TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Text(
                              '♥ ${_fmtCount(w.diggCount)}',
                              style: const TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 11,
                                color: Colors.white,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black54),
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
            ),
          ),
      ],
    );
  }
}

class _WorksFilterChip extends StatelessWidget {
  const _WorksFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.iosBlue : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF636366),
          ),
        ),
      ),
    );
  }
}

class _ChatsPreview extends StatelessWidget {
  const _ChatsPreview({
    required this.loading,
    required this.error,
    required this.chats,
    required this.onTap,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<DouyinChatConversation> chats;
  final ValueChanged<DouyinChatConversation> onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (error != null && chats.isEmpty) {
      return _SectionError(message: error!, onRetry: onRetry);
    }
    if (chats.isEmpty) {
      return const _SectionHint('暂无私信会话');
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < chats.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 62, color: Color(0xFFE5E5EA)),
            _ChatPreviewRow(
              chat: chats[i],
              onTap: () => onTap(chats[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatPreviewRow extends StatelessWidget {
  const _ChatPreviewRow({required this.chat, required this.onTap});

  final DouyinChatConversation chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: chat.avatarUrl.isNotEmpty
                  ? DouyinMediaImage(
                      url: chat.avatarUrl,
                      width: 40,
                      height: 40,
                      fallbackLabel: '友',
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      color: const Color(0xFFE5E5EA),
                      alignment: Alignment.center,
                      child: const Text('友'),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (chat.time.isNotEmpty)
                        Text(
                          chat.time,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 11,
                            color: Color(0xFFAEAEB2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    chat.lastMessage.isNotEmpty ? chat.lastMessage : '暂无消息',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticesPreview extends StatelessWidget {
  const _NoticesPreview({
    required this.loading,
    required this.error,
    required this.notices,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<DouyinNoticeItem> notices;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (error != null && notices.isEmpty) {
      return _SectionError(message: error!, onRetry: onRetry);
    }
    if (notices.isEmpty) {
      return const _SectionHint('暂无互动通知');
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < notices.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 62, color: Color(0xFFE5E5EA)),
            _NoticePreviewRow(notice: notices[i]),
          ],
        ],
      ),
    );
  }
}

class _NoticePreviewRow extends StatelessWidget {
  const _NoticePreviewRow({required this.notice});

  final DouyinNoticeItem notice;

  @override
  Widget build(BuildContext context) {
    final who = notice.userNickname.isNotEmpty ? notice.userNickname : '用户';
    final label = notice.groupLabel.isNotEmpty ? notice.groupLabel : '互动';
    final body = notice.text.isNotEmpty ? notice.text : label;
    final time = notice.createTime > 0
        ? formatRelativeTime(notice.createTime * 1000)
        : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: notice.userAvatar.isNotEmpty
                ? DouyinMediaImage(
                    url: notice.userAvatar,
                    width: 40,
                    height: 40,
                    fallbackLabel: '互',
                  )
                : Container(
                    width: 40,
                    height: 40,
                    color: const Color(0xFFE5E5EA),
                    alignment: Alignment.center,
                    child: Text(
                      label.characters.first,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$who · $label',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 11,
                          color: Color(0xFFAEAEB2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
          if (notice.awemeCover.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: DouyinMediaImage(
                url: notice.awemeCover,
                width: 36,
                height: 36,
                fallbackLabel: '',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHint extends StatelessWidget {
  const _SectionHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'AppSans',
          fontSize: 14,
          color: Color(0xFF8E8E93),
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: Color(0xFF8E8E93),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.only(top: 4),
            onPressed: onRetry,
            child: const Text('重试', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
