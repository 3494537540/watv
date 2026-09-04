import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cms_message_store.dart';
import '../services/maccms_user_api.dart';
import '../state/cms_auth_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/auth_sheet.dart';
import '../widgets/cms_cover_image.dart';
import '../widgets/dialogx/dialogx.dart';
import '../widgets/figma_loading.dart';

/// 公告 / 站内通知
class CmsMessagesPage extends StatefulWidget {
  const CmsMessagesPage({super.key});

  @override
  State<CmsMessagesPage> createState() => _CmsMessagesPageState();
}

class _CmsMessagesPageState extends State<CmsMessagesPage> {
  bool _loading = true;
  List<CmsMessageItem> _items = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    CmsMessageStore.instance.addListener(_syncFromStore);
    unawaited(_load());
  }

  @override
  void dispose() {
    CmsMessageStore.instance.removeListener(_syncFromStore);
    super.dispose();
  }

  void _syncFromStore() {
    if (!mounted) return;
    setState(() => _items = CmsMessageStore.instance.items);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = CmsAuthController.instance.user?.userId ?? 0;
      await CmsMessageStore.instance.bootstrap(userId: uid);
      if (mounted && CmsMessageStore.instance.items.isNotEmpty) {
        setState(() {
          _items = CmsMessageStore.instance.items;
          _loading = false;
        });
      }
      final list = await CmsMessageStore.instance.refresh(
        CmsAuthController.instance.api,
        userId: uid,
        allowFallback: !CmsAuthController.instance.isLoggedIn,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        final err = CmsMessageStore.instance.lastFetchError;
        _error = (list.isEmpty && err != null && err.isNotEmpty) ? err : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _items = CmsMessageStore.instance.items;
      });
    }
  }

  Future<void> _markAllRead() async {
    HapticFeedback.mediumImpact();
    await CmsMessageStore.instance.markAllRead();
    if (!mounted) return;
    setState(() => _items = CmsMessageStore.instance.items);
    DialogX.showSuccess('已全部标为已读');
  }

  Future<void> _openItem(CmsMessageItem m) async {
    await CmsMessageStore.instance.markRead(m.id);
    if (!mounted) return;
    setState(() => _items = CmsMessageStore.instance.items);

    final cover = CmsCoverImage.resolve(m.coverUrl);
    final hasLink = m.link.trim().isNotEmpty;
    final buf = StringBuffer();
    if (m.subtitle.trim().isNotEmpty) {
      buf.writeln(m.subtitle.trim());
      buf.writeln();
    }
    buf.write(m.content.isEmpty ? '暂无正文' : m.content);
    if (m.timeText.isNotEmpty) {
      buf.writeln();
      buf.writeln();
      buf.write(m.timeText);
    }

    final result = await DialogX.bottom(
      context: context,
      title: m.title.isEmpty ? '公告' : m.title,
      message: buf.toString().trim(),
      closeLabel: '知道了',
      actionLabel: hasLink ? '复制链接' : null,
      body: cover == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: double.infinity,
                height: 160,
                child: CmsCoverImage(url: cover, fit: BoxFit.cover),
              ),
            ),
    );

    if (result == 'action' && hasLink) {
      await Clipboard.setData(ClipboardData(text: m.link.trim()));
      DialogX.showSuccess('链接已复制');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = CmsAuthController.instance.isLoggedIn;
    final page = AppPalette.page(context);
    final surface = AppPalette.surface(context);
    final text = AppPalette.text(context);
    final line = AppPalette.line(context);
    final unread = _items.where((e) => !e.read).length;

    return Scaffold(
      backgroundColor: page,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: text,
        title: Text(
          '公告',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: text,
          ),
        ),
        actions: [
          if (unread > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton(
                onPressed: _markAllRead,
                child: Text(
                  '全部已读',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand,
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5, color: line),
        ),
      ),
      body: AppPullRefresh(
        color: AppColors.brand,
        onRefresh: _load,
        child: _loading && _items.isEmpty
            ? const Center(child: FigmaMetaballLoader(size: 56))
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  if (!loggedIn)
                    _LoginHint(onTap: () => showAuthSheet(context)),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          color: Color(0xFFB54708),
                        ),
                      ),
                    ),
                  if (unread > 0) ...[
                    _SectionHead(
                      title: '未读',
                      trailing: '$unread',
                      action: '一键已读',
                      onAction: _markAllRead,
                    ),
                    const SizedBox(height: 10),
                    for (final m in _items.where((e) => !e.read))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NoticeCard(
                          item: m,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            unawaited(_openItem(m));
                          },
                        ),
                      ),
                    if (_items.any((e) => e.read)) ...[
                      const SizedBox(height: 6),
                      const _SectionHead(title: '已读'),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (_items.isEmpty)
                    const _EmptyNotices()
                  else
                    for (final m in _items.where((e) => unread == 0 || e.read))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NoticeCard(
                          item: m,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            unawaited(_openItem(m));
                          },
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}

Color? _parseAccent(String raw) {
  final s = raw.trim();
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s)) return null;
  return Color(int.parse('FF${s.substring(1)}', radix: 16));
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.title,
    this.trailing,
    this.action,
    this.onAction,
  });

  final String title;
  final String? trailing;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppPalette.textSecondary(context),
            letterSpacing: 0.4,
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              trailing!,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (action != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              action!,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.brand,
              ),
            ),
          ),
      ],
    );
  }
}

class _LoginHint extends StatelessWidget {
  const _LoginHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppPalette.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.line(context)),
          ),
          child: Text(
            '登录后可同步站内信 · 点此登录',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: AppPalette.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNotices extends StatelessWidget {
  const _EmptyNotices();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppPalette.softFill(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.bell,
              size: 32,
              color: AppPalette.textHint(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无公告',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppPalette.text(context),
            ),
          ),
          SizedBox(height: 6),
          Text(
            '后台发布后会出现在这里',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: AppPalette.textHint(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.item, required this.onTap});

  final CmsMessageItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = AppPalette.text(context);
    final secondary = AppPalette.textSecondary(context);
    final hint = AppPalette.textHint(context);
    final surface = AppPalette.surface(context);
    final accent = _parseAccent(item.accent) ?? AppColors.brand;
    final cover = CmsCoverImage.resolve(item.coverUrl);
    final style = item.style.trim().isEmpty ? 'normal' : item.style.trim();
    final important = style == 'important';
    final promo = style == 'promo';
    final preview = item.subtitle.trim().isNotEmpty
        ? item.subtitle.trim()
        : item.content;
    final tag = item.tag.trim().isEmpty ? '公告' : item.tag.trim();
    final title = item.title.isEmpty ? '公告' : item.title;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: cover != null
                ? _CoverCard(
                    cover: cover,
                    tag: tag,
                    title: title,
                    preview: preview,
                    time: item.timeText,
                    hasLink: item.link.trim().isNotEmpty,
                    read: item.read,
                    accent: accent,
                    filledTag: promo || important,
                    hint: hint,
                  )
                : _TextCard(
                    tag: tag,
                    title: title,
                    preview: preview,
                    time: item.timeText,
                    hasLink: item.link.trim().isNotEmpty,
                    read: item.read,
                    accent: accent,
                    filledTag: promo || important,
                    text: text,
                    secondary: secondary,
                    hint: hint,
                  ),
          ),
        ),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.cover,
    required this.tag,
    required this.title,
    required this.preview,
    required this.time,
    required this.hasLink,
    required this.read,
    required this.accent,
    required this.filledTag,
    required this.hint,
  });

  final String cover;
  final String tag;
  final String title;
  final String preview;
  final String time;
  final bool hasLink;
  final bool read;
  final Color accent;
  final bool filledTag;
  final Color hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CmsCoverImage(url: cover, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0, 0.35, 1],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: filledTag
                    ? accent
                    : Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (!read)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '未读',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 18,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Color(0x88000000), blurRadius: 8),
                    ],
                  ),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      time.isEmpty ? '刚刚' : time,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      hasLink ? '查看链接' : '查看详情',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({
    required this.tag,
    required this.title,
    required this.preview,
    required this.time,
    required this.hasLink,
    required this.read,
    required this.accent,
    required this.filledTag,
    required this.text,
    required this.secondary,
    required this.hint,
  });

  final String tag;
  final String title;
  final String preview;
  final String time;
  final bool hasLink;
  final bool read;
  final Color accent;
  final bool filledTag;
  final Color text;
  final Color secondary;
  final Color hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TagChip(label: tag, accent: accent, filled: filledTag),
              const Spacer(),
              if (!read)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 16,
              height: 1.3,
              fontWeight: read ? FontWeight.w600 : FontWeight.w800,
              color: text,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                height: 1.45,
                color: secondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                time.isEmpty ? '刚刚' : time,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  color: hint,
                ),
              ),
              const Spacer(),
              Text(
                hasLink ? '查看链接' : '查看详情',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 13, color: hint),
            ],
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.accent,
    required this.filled,
  });

  final String label;
  final Color accent;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? accent
        : accent.withValues(alpha: 0.14);
    final fg = filled ? Colors.white : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
