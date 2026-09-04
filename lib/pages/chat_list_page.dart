import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../services/chat_list_cache.dart';
import '../services/douyin_api.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import 'account_manage_page.dart';
import 'chat_messages_page.dart';
import 'spark_renew_page.dart';
import '../widgets/app_page_route.dart';

/// 抖音私信会话列表
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key, this.accountId});

  final int? accountId;

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _api = DouyinApi();
  List<DouyinAccount> _accounts = [];
  DouyinAccount? _account;
  List<DouyinChatConversation> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await _api.myList();
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _accounts = [];
          _account = null;
          _list = [];
          _loading = false;
          _error = '请先绑定抖音账号';
        });
        return;
      }
      DouyinAccount? selected;
      if (widget.accountId != null) {
        for (final a in accounts) {
          if (a.id == widget.accountId) {
            selected = a;
            break;
          }
        }
      }
      selected ??= accounts.first;

      // 先用缓存秒开，再后台刷新
      final cached = ChatListCache.get(selected.id);
      setState(() {
        _accounts = accounts;
        _account = selected;
        if (cached != null && cached.isNotEmpty) {
          _list = cached;
          _loading = false;
        }
      });
      await _loadChats(showSpinner: cached == null || cached.isEmpty);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  Future<void> _loadChats({bool showSpinner = true}) async {
    final acc = _account;
    if (acc == null) return;
    if (!mounted) return;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _api.myChats(
        accountId: acc.id,
        limit: 60,
        fast: true,
      );
      if (!mounted) return;
      ChatListCache.set(acc.id, list);
      setState(() {
        _list = list;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_list.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_list.isEmpty) _error = '拉取失败';
      });
    }
  }

  Future<void> _pickAccount() async {
    if (_accounts.length <= 1) return;
    HapticFeedback.selectionClick();
    final picked = await showCupertinoModalPopup<DouyinAccount>(
      context: context,
      builder: (ctx) => _AccountPickerSheet(accounts: _accounts),
    );
    if (picked == null || !mounted) return;
    setState(() => _account = picked);
    await _loadChats();
  }

  Future<void> _openChat(DouyinChatConversation c) async {
    final acc = _account;
    if (acc == null) return;
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => ChatMessagesPage(
          accountId: acc.id,
          conversation: c,
          selfAvatarUrl: acc.avatarUrl,
        ),
      ),
    );
  }

  String _formatTime(DouyinChatConversation c) {
    final ms = resolveTimeMs(timeMs: c.timeMs, time: c.time);
    return formatConversationTime(ms);
  }

  @override
  Widget build(BuildContext context) {
    final acc = _account;
    final title = acc == null
        ? '消息'
        : (acc.nickname.isNotEmpty ? acc.nickname : '消息');

    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        middle: GestureDetector(
          onTap: _accounts.length > 1 ? _pickAccount : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (acc != null) ...[
                ClipOval(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: acc.avatarUrl.isNotEmpty
                        ? Image.network(
                            acc.avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Color(0xFFD1D1D6),
                            ),
                          )
                        : const ColoredBox(color: Color(0xFFD1D1D6)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_accounts.length > 1) ...[
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_down, size: 14),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _account == null
                  ? null
                  : () async {
                      HapticFeedback.selectionClick();
                      await Navigator.of(context).push(
                        AppPageRoute<void>(
                          builder: (_) => SparkRenewPage(
                            accountId: _account!.id,
                          ),
                        ),
                      );
                    },
              child: const Icon(CupertinoIcons.flame, size: 22),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _loading ? null : _loadChats,
              child: const Icon(CupertinoIcons.refresh, size: 22),
            ),
          ],
        ),
      ),
      child: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(height: 12),
            Text(
              '正在拉取私信…',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null && _list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 15,
                  color: Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 12),
              if (_error!.contains('绑定'))
                CupertinoButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      AppPageRoute<void>(
                        builder: (_) => const AccountManagePage(),
                      ),
                    );
                  },
                  child: const Text('去绑定账号'),
                )
              else
                CupertinoButton(
                  onPressed: _bootstrap,
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return const Center(
        child: Text(
          '暂无私信会话',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 15,
            color: Color(0xFF8E8E93),
          ),
        ),
      );
    }
    return Stack(
      children: [
        CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _loadChats),
            SliverList.separated(
              itemCount: _list.length,
              separatorBuilder: (_, __) => const Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 76,
                color: Color(0xFFE5E5EA),
              ),
              itemBuilder: (context, i) {
                final c = _list[i];
                return _ChatTile(
                  conversation: c,
                  timeText: _formatTime(c),
                  onTap: () => _openChat(c),
                );
              },
            ),
          ],
        ),
        if (_loading)
          const Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: CupertinoActivityIndicator()),
          ),
      ],
    );
  }
}

class _AccountPickerSheet extends StatelessWidget {
  const _AccountPickerSheet({required this.accounts});

  final List<DouyinAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.fromLTRB(10, 0, 10, 8 + bottom),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                '选择抖音账号',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ),
            for (var i = 0; i < accounts.length; i++) ...[
              if (i > 0)
                const Divider(height: 0.5, thickness: 0.5, color: Color(0xFFC6C6C8)),
              _AccountPickRow(
                account: accounts[i],
                onTap: () => Navigator.pop(context, accounts[i]),
              ),
            ],
            SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 20,
                    color: AppColors.iosBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountPickRow extends StatelessWidget {
  const _AccountPickRow({required this.account, required this.onTap});

  final DouyinAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 40,
                height: 40,
                child: account.avatarUrl.isNotEmpty
                    ? Image.network(
                        account.avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFD1D1D6),
                          child: Icon(
                            CupertinoIcons.person_fill,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const ColoredBox(
                        color: Color(0xFFD1D1D6),
                        child: Icon(
                          CupertinoIcons.person_fill,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.nickname.isNotEmpty
                        ? account.nickname
                        : account.douyinUid,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (account.uniqueId.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '抖音号 ${account.uniqueId}',
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: Color(0xFFC7C7CC),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.conversation,
    required this.timeText,
    required this.onTap,
  });

  final DouyinChatConversation conversation;
  final String timeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: conversation.avatarUrl.isNotEmpty
                    ? Image.network(
                        conversation.avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFD1D1D6),
                          child: Icon(
                            CupertinoIcons.person_fill,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const ColoredBox(
                        color: Color(0xFFD1D1D6),
                        child: Icon(
                          CupertinoIcons.person_fill,
                          color: Colors.white,
                        ),
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
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                conversation.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'AppSans',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                            if (conversation.spark) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                CupertinoIcons.flame_fill,
                                size: 14,
                                color: Color(0xFFFF9500),
                              ),
                              if (conversation.sparkDays > 0)
                                Text(
                                  '${conversation.sparkDays}',
                                  style: const TextStyle(
                                    fontFamily: 'AppSans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF9500),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (timeText.isNotEmpty)
                        Text(
                          timeText,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (conversation.lastThumbUrl.isNotEmpty &&
                          conversation.lastKind != 'profile' &&
                          conversation.lastKind != 'card' &&
                          (conversation.lastKind == 'image' ||
                              conversation.lastKind == 'sticker' ||
                              conversation.lastKind == 'emoji' ||
                              conversation.lastKind == 'video')) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            conversation.lastThumbUrl,
                            width: 22,
                            height: 22,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          conversation.lastMessage.isNotEmpty
                              ? conversation.lastMessage
                              : '暂无消息',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 14,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 14,
              color: Color(0xFFC7C7CC),
            ),
          ],
        ),
      ),
    );
  }
}
