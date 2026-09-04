import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../services/douyin_api.dart';
import '../theme/app_colors.dart';
import '../utils/relative_time.dart';
import '../widgets/douyin_emoji_text.dart';
import '../widgets/douyin_media_image.dart';
import 'chat_media_viewer.dart';
import '../widgets/app_page_route.dart';

/// 某个好友会话的聊天记录（最新在底、双方头像右上/左上）
class ChatMessagesPage extends StatefulWidget {
  const ChatMessagesPage({
    super.key,
    required this.accountId,
    required this.conversation,
    this.selfAvatarUrl = '',
  });

  final int accountId;
  final DouyinChatConversation conversation;
  final String selfAvatarUrl;

  @override
  State<ChatMessagesPage> createState() => _ChatMessagesPageState();
}

class _ChatMessagesPageState extends State<ChatMessagesPage> {
  final _api = DouyinApi();
  final _scroll = ScrollController();
  List<DouyinChatMessage> _list = [];
  String _selfAvatar = '';
  String _peerAvatar = '';
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  Timer? _autoRefresh;
  bool _stickToBottom = true;

  @override
  void initState() {
    super.initState();
    _selfAvatar = widget.selfAvatarUrl;
    _peerAvatar = widget.conversation.avatarUrl;
    DouyinEmojiMap.ensureLoaded();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _autoRefresh = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _silentRefresh(),
    );
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _stickToBottom = pos.maxScrollExtent - pos.pixels < 80;
  }

  String _fingerprint(List<DouyinChatMessage> list) {
    if (list.isEmpty) return '0';
    final last = list.last;
    return '${list.length}|${last.timeMs}|${last.text}|${last.kind}|${last.mediaUrl}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _fetchAndApply(jump: true);
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

  Future<void> _silentRefresh() async {
    if (!mounted || _loading || _refreshing) return;
    _refreshing = true;
    try {
      await _fetchAndApply(jump: false);
    } catch (_) {
      // 静默刷新失败不打断阅读
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _fetchAndApply({required bool jump}) async {
    final key = widget.conversation.conversationId.isNotEmpty
        ? widget.conversation.conversationId
        : '${widget.conversation.index}';
    final before = _fingerprint(_list);
    final thread = await _api.myChatMessages(
      accountId: widget.accountId,
      conversation: key,
      shortId: widget.conversation.shortId,
      limit: 200,
    );
    if (!mounted) return;
    final after = _fingerprint(thread.messages);
    final changed = before != after;
    setState(() {
      _list = thread.messages;
      if (thread.selfAvatar.isNotEmpty) _selfAvatar = thread.selfAvatar;
      if (thread.peerAvatar.isNotEmpty) _peerAvatar = thread.peerAvatar;
      _loading = false;
      _error = null;
    });
    if (jump || (changed && _stickToBottom)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
    }
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients || _list.isEmpty) return;
    final max = _scroll.position.maxScrollExtent;
    if (max > 0) {
      _scroll.jumpTo(max);
    }
  }

  void _openLink(String link) {
    if (link.isEmpty) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _LinkPreviewPage(url: link),
      ),
    );
  }

  void _openMedia(DouyinChatMessage m) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => ChatMediaViewerPage(
          message: m,
          accountId: widget.accountId,
        ),
      ),
    );
  }

  bool _showTimeChip(int index) {
    final msg = _list[index];
    final cur = resolveTimeMs(timeMs: msg.timeMs, time: msg.time);
    final older = index > 0
        ? resolveTimeMs(
            timeMs: _list[index - 1].timeMs,
            time: _list[index - 1].time,
          )
        : 0;
    return shouldShowMessageTimeChip(currentMs: cur, olderMs: older);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.conversation.nickname;
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE5E5EA), width: 0.5),
        ),
        middle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (widget.conversation.spark) ...[
              const SizedBox(width: 4),
              const Icon(
                CupertinoIcons.flame_fill,
                size: 14,
                color: Color(0xFFFF9500),
              ),
              if (widget.conversation.sparkDays > 0)
                Text(
                  '${widget.conversation.sparkDays}',
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
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _loading ? null : _load,
          child: _refreshing && !_loading
              ? const CupertinoActivityIndicator(radius: 10)
              : const Icon(CupertinoIcons.refresh, size: 22),
        ),
      ),
      child: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _list.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_error != null && _list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 15,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ),
            CupertinoButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_list.isEmpty) {
      return const Center(
        child: Text(
          '暂无聊天记录',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 15,
            color: Color(0xFF8E8E93),
          ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: ListView.builder(
        controller: _scroll,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
        itemCount: _list.length,
        itemBuilder: (context, index) {
          final m = _list[index];
          final ms = resolveTimeMs(timeMs: m.timeMs, time: m.time);
          final timeLabel = _showTimeChip(index) ? formatMessageTime(ms) : '';
          return Column(
            children: [
              if (timeLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    timeLabel,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
              _Bubble(
                message: m,
                avatarUrl: m.isSelf ? _selfAvatar : _peerAvatar,
                onOpenLink: () => _openLink(m.link),
                onOpenMedia: () => _openMedia(m),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LinkPreviewPage extends StatelessWidget {
  const _LinkPreviewPage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final safe = normalizeDouyinWebLink(url);
    return CupertinoPageScaffold(
      backgroundColor: Colors.white,
      navigationBar: const CupertinoNavigationBar(
        backgroundColor: Colors.white,
        middle: Text('详情', style: TextStyle(fontFamily: 'AppSans')),
      ),
      child: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(safe.isNotEmpty ? safe : url),
          ),
          shouldOverrideUrlLoading: (controller, action) async {
            final u = action.request.url?.toString() ?? '';
            if (u.startsWith('snssdk') ||
                u.startsWith('aweme://') ||
                u.startsWith('bytedance')) {
              final id = extractAwemeId(u);
              if (id.isNotEmpty) {
                await controller.loadUrl(
                  urlRequest: URLRequest(
                    url: WebUri('https://www.douyin.com/video/$id'),
                  ),
                );
              }
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.avatarUrl,
    required this.onOpenLink,
    required this.onOpenMedia,
  });

  final DouyinChatMessage message;
  final String avatarUrl;
  final VoidCallback onOpenLink;
  final VoidCallback onOpenMedia;

  @override
  Widget build(BuildContext context) {
    if (message.kind == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'AppSans',
            fontSize: 12,
            color: Color(0xFF8E8E93),
          ),
        ),
      );
    }

    final self = message.isSelf;
    final maxW = MediaQuery.sizeOf(context).width * 0.68;
    // 头像贴消息顶部：自己右上，对方左上
    final row = Row(
      mainAxisAlignment: self ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!self) ...[
          _Avatar(url: avatarUrl),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: _content(self, maxW),
          ),
        ),
        if (self) ...[
          const SizedBox(width: 8),
          _Avatar(url: avatarUrl),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: row,
    );
  }

  Widget _content(bool self, double maxW) {
    switch (message.kind) {
      case 'image':
      case 'sticker':
      case 'emoji':
        return _imageBubble(self, sticker: message.kind != 'image');
      case 'audio':
        return _audioBubble(self);
      case 'profile':
        return _profileBubble(self, maxW);
      case 'video':
      case 'card':
        return _shareBubble(self, maxW);
      default:
        return _textBubble(self);
    }
  }

  String _formatFans(int n) {
    if (n <= 0) return '';
    if (n >= 10000) {
      final v = n / 10000;
      final s = v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
      return '$s万粉丝';
    }
    return '$n粉丝';
  }

  Widget _textBubble(bool self) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: self ? AppColors.iosBlue : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DouyinEmojiText(
        text: message.text,
        emojiSize: 22,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: 16,
          height: 1.35,
          color: self ? Colors.white : AppColors.text,
        ),
      ),
    );
  }

  Widget _imageBubble(bool self, {required bool sticker}) {
    final url = message.displayImageUrl;
    final file = message.mediaFile;
    final isEmoji = message.kind == 'emoji';
    final w = isEmoji ? 64.0 : (sticker ? 120.0 : 200.0);
    final h = isEmoji ? 64.0 : (sticker ? 120.0 : 220.0);
    if (url.isEmpty && file.isEmpty) {
      if (message.text.contains('[')) return _textBubble(self);
      return _textBubble(self);
    }
    final img = DouyinMediaImage(
      url: url,
      mediaFile: file,
      width: w,
      height: isEmoji || sticker ? w : h,
      fit: BoxFit.contain,
      borderRadius: BorderRadius.circular(isEmoji ? 8 : (sticker ? 12 : 16)),
      fallbackLabel: sticker || isEmoji ? '[表情]' : '[图片]',
    );
    if (isEmoji || sticker) return img;
    return GestureDetector(onTap: onOpenMedia, child: img);
  }

  Widget _profileBubble(bool self, double maxW) {
    final name = message.title.isNotEmpty ? message.title : '用户';
    final fans = _formatFans(message.followers);
    final status = message.followStatus.isNotEmpty ? message.followStatus : '关注';
    final avatar = message.coverUrl.isNotEmpty
        ? message.coverUrl
        : message.mediaUrl;
    return GestureDetector(
      onTap: message.link.isNotEmpty ? onOpenLink : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW.clamp(220, 300)),
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: (avatar.isNotEmpty || message.mediaFile.isNotEmpty)
                    ? DouyinMediaImage(
                        url: avatar,
                        mediaFile: message.mediaFile,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        fallbackLabel: '',
                      )
                    : const ColoredBox(
                        color: Color(0xFFD1D1D6),
                        child: Icon(
                          CupertinoIcons.person_fill,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (fans.isNotEmpty) ...[
                    SizedBox(height: 2),
                    Text(
                      fans,
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
            SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: status == '关注' || status == '回关'
                    ? AppColors.iosBlue
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: status == '关注' || status == '回关'
                      ? Colors.white
                      : const Color(0xFF8E8E93),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _audioBubble(bool self) {
    final sec = message.durationSec > 0 ? message.durationSec : 1;
    final barW = (48.0 + sec * 4).clamp(72.0, 180.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: self ? AppColors.iosBlue : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.waveform,
            size: 18,
            color: self ? Colors.white : AppColors.iosBlue,
          ),
          const SizedBox(width: 8),
          Container(
            width: barW,
            height: 4,
            decoration: BoxDecoration(
              color: self
                  ? Colors.white.withValues(alpha: 0.45)
                  : const Color(0xFFD1D1D6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${message.durationSec > 0 ? message.durationSec : "?"}″',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: self ? Colors.white : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shareBubble(bool self, double maxW) {
    final cover = message.coverUrl.isNotEmpty
        ? message.coverUrl
        : message.displayImageUrl;
    final title = message.title.isNotEmpty
        ? message.title
        : (message.text.isNotEmpty ? message.text.replaceFirst(RegExp(r'^\[.+?\]\s*'), '') : '分享');
    final sub = message.subtitle;
    final showSub = sub.isNotEmpty && sub != title;
    return GestureDetector(
      onTap: onOpenMedia,
      child: Container(
        width: maxW.clamp(160, 240),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover.isNotEmpty || message.mediaFile.isNotEmpty)
              AspectRatio(
                aspectRatio: message.kind == 'card' ? 1 : 3 / 4,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DouyinMediaImage(
                      url: cover,
                      mediaFile: message.mediaFile,
                      fit: BoxFit.cover,
                      fallbackLabel: '[封面]',
                    ),
                    if (message.kind == 'video')
                      const Center(
                        child: Icon(
                          CupertinoIcons.play_circle_fill,
                          size: 44,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (showSub) ...[
                    SizedBox(height: 4),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                  SizedBox(height: 6),
                  Text(
                    message.kind == 'video' ? '点击播放 / 查看详情' : '点击查看',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 11,
                      color: AppColors.iosBlue,
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 34,
        height: 34,
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Color(0xFFD1D1D6),
                  child: Icon(
                    CupertinoIcons.person_fill,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              )
            : const ColoredBox(
                color: Color(0xFFD1D1D6),
                child: Icon(
                  CupertinoIcons.person_fill,
                  size: 18,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
