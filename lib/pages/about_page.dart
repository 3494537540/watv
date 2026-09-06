import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../services/app_security.dart';
import '../theme/app_colors.dart';
import '../widgets/app_page_route.dart';
import 'legal_doc_page.dart';

/// 关于哇TV
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _avatar = 'assets/images/developer/stewie_avatar.png';
  static const _qr = 'assets/images/developer/stewie_douyin_qr.png';

  @override
  Widget build(BuildContext context) {
    final page = AppPalette.page(context);
    final text = AppPalette.text(context);
    final hint = AppPalette.textHint(context);
    final secondary = AppPalette.textSecondary(context);
    final surface = AppPalette.surface(context);
    final line = AppPalette.line(context);

    return CupertinoPageScaffold(
      backgroundColor: page,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: surface,
        border: Border(bottom: BorderSide(color: line, width: 0.5)),
        middle: Text(
          '关于哇TV',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    '哇TV',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '版本 ${ApiConfig.appVersionName}（${ApiConfig.appVersionCode}）',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: hint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _Block(
              title: '软件简介',
              body:
                  '哇TV 是一款面向影视内容的移动端点播应用，支持浏览、搜索、收藏、播放历史、片单分类与缓存等能力，'
                  '帮助你更轻松地发现和追完喜欢的影视作品。',
              text: text,
              secondary: secondary,
              surface: surface,
            ),
            const SizedBox(height: 12),
            _DeveloperCard(
              avatarAsset: _avatar,
              name: 'stewie',
              subtitle: '点按查看抖音二维码',
              text: text,
              secondary: secondary,
              hint: hint,
              surface: surface,
              onTap: () => _showDouyinQr(context),
            ),
            const SizedBox(height: 12),
            _TechStackCard(
              text: text,
              secondary: secondary,
              surface: surface,
              line: line,
            ),
            const SizedBox(height: 12),
            _Block(
              title: '声明',
              body:
                  '本应用仅作为影视内容聚合与播放体验客户端。'
                  '内容来源于配置的资源站，请遵守当地法律法规与资源站使用条款。',
              text: text,
              secondary: secondary,
              surface: surface,
            ),
            const SizedBox(height: 12),
            Material(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      '用户协议',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: hint,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        AppPageRoute<void>(
                          builder: (_) => const LegalDocPage(
                            kind: LegalDocKind.userAgreement,
                          ),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, color: line),
                  ListTile(
                    title: Text(
                      '隐私政策',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: hint,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        AppPageRoute<void>(
                          builder: (_) => const LegalDocPage(
                            kind: LegalDocKind.privacyPolicy,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '© 哇TV · Made with Flutter',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 12,
                color: hint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDouyinQr(BuildContext context) {
    HapticFeedback.selectionClick();
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final text = AppPalette.text(ctx);
        final hint = AppPalette.textHint(ctx);
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              decoration: BoxDecoration(
                color: AppPalette.surface(ctx),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '@stewie',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '抖音号 93880217302',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 12,
                      color: hint,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      _qr,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '打开抖音扫一扫加我',
                    style: TextStyle(
                      fontFamily: 'AppSans',
                      fontSize: 13,
                      color: hint,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      '关闭',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand,
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

class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({
    required this.avatarAsset,
    required this.name,
    required this.subtitle,
    required this.text,
    required this.secondary,
    required this.hint,
    required this.surface,
    required this.onTap,
  });

  final String avatarAsset;
  final String name;
  final String subtitle;
  final Color text;
  final Color secondary;
  final Color hint;
  final Color surface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '开发者',
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      avatarAsset,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 56,
                        height: 56,
                        color: AppColors.brand.withValues(alpha: 0.2),
                        alignment: Alignment.center,
                        child: Text(
                          'S',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            color: hint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: secondary.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.title,
    required this.body,
    required this.text,
    required this.secondary,
    required this.surface,
  });

  final String title;
  final String body;
  final Color text;
  final Color secondary;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w500,
                color: text.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TechStackCard extends StatelessWidget {
  const _TechStackCard({
    required this.text,
    required this.secondary,
    required this.surface,
    required this.line,
  });

  final Color text;
  final Color secondary;
  final Color surface;
  final Color line;

  static const _items = <({String title, String desc})>[
    (
      title: '客户端',
      desc: 'Flutter / Dart，一套代码覆盖 Android、iOS、H5',
    ),
    (
      title: '界面',
      desc: 'Material 与 Cupertino 组件混排，跟随系统观感',
    ),
    (
      title: '播放',
      desc: 'video_player 等媒体能力，支持缓存与投屏',
    ),
    (
      title: '数据',
      desc: '站点开放接口与扩展面板，远程配置与更新',
    ),
    (
      title: '本地',
      desc: 'SharedPreferences、路径与缓存存储',
    ),
    (
      title: '安全',
      desc: '',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final security = AppSecurity.instance.securitySummary;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '开发技术',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: text,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Divider(height: 1, thickness: 0.5, color: line),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        _items[i].title,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _items[i].desc.isEmpty ? security : _items[i].desc,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: text.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
