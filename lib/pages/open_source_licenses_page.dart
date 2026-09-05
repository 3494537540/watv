import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class _LibItem {
  const _LibItem({
    required this.name,
    required this.license,
    required this.desc,
    this.usage = '',
  });
  final String name;
  final String license;
  final String desc;
  final String usage;
}

/// 开源协议 / 第三方库说明
class OpenSourceLicensesPage extends StatelessWidget {
  const OpenSourceLicensesPage({super.key});

  static const _libs = <_LibItem>[
    _LibItem(
      name: 'Flutter / Dart SDK',
      license: 'BSD-3-Clause',
      desc: 'Google 开源的跨平台 UI 框架与 Dart 语言运行时，构成哇TV 的主体工程。',
      usage: '页面渲染、手势、动画、平台通道',
    ),
    _LibItem(
      name: 'cupertino_icons',
      license: 'MIT',
      desc: 'Cupertino 风格矢量图标字体，配合 Flutter CupertinoIcons 使用。',
      usage: '设置、导航、播放器等 iOS 风格图标',
    ),
    _LibItem(
      name: 'http',
      license: 'BSD-3-Clause',
      desc: 'Dart 官方维护的 HTTP 客户端，用于 REST / JSON 接口请求。',
      usage: 'CMS 片源、会员、弹幕、面板通知等网络请求',
    ),
    _LibItem(
      name: 'shared_preferences',
      license: 'BSD-3-Clause',
      desc: '跨平台轻量键值持久化（NSUserDefaults / SharedPreferences）。',
      usage: '主题、登录态、通知开关、播放偏好等本地配置',
    ),
    _LibItem(
      name: 'path_provider',
      license: 'BSD-3-Clause',
      desc: '获取应用文档、缓存、临时目录等平台路径。',
      usage: '离线缓存、更新包下载、头像临时文件',
    ),
    _LibItem(
      name: 'video_player',
      license: 'BSD-3-Clause',
      desc: '官方音视频播放插件，底层对接 ExoPlayer / AVPlayer。',
      usage: '影视主播放器、短视频、聊天媒体预览',
    ),
    _LibItem(
      name: 'video_player_pip',
      license: 'MIT',
      desc: '基于 video_player 的 iOS 画中画扩展。',
      usage: 'iOS 系统画中画',
    ),
    _LibItem(
      name: 'floating',
      license: 'Apache-2.0',
      desc: 'Android 画中画 / 悬浮窗能力封装。',
      usage: 'Android 系统画中画',
    ),
    _LibItem(
      name: 'flutter_inappwebview',
      license: 'Apache-2.0',
      desc: '功能完整的应用内 WebView（Cookie、JS Bridge、自定义请求等）。',
      usage: '抖音绑定、聊天链接、图文页内嵌浏览',
    ),
    _LibItem(
      name: 'image_picker',
      license: 'Apache-2.0',
      desc: '调用系统相册 / 相机选取图片或视频。',
      usage: '更换头像、广场发帖配图',
    ),
    _LibItem(
      name: 'permission_handler',
      license: 'MIT',
      desc: '统一申请与查询通知、存储、相册等运行时权限。',
      usage: '通知权限、相册写入等',
    ),
    _LibItem(
      name: 'gal',
      license: 'BSD-3-Clause',
      desc: '将图片 / 视频保存到系统相册的轻量库。',
      usage: '播放器截图、聊天媒体保存',
    ),
    _LibItem(
      name: 'wakelock_plus',
      license: 'BSD-3-Clause',
      desc: '播放时保持屏幕常亮，避免息屏打断观看。',
      usage: '视频播放期间防休眠',
    ),
    _LibItem(
      name: 'connectivity_plus',
      license: 'BSD-3-Clause',
      desc: '监听 Wi‑Fi / 蜂窝 / 无网络等连通性变化。',
      usage: '播放器顶栏网络指示',
    ),
    _LibItem(
      name: 'volume_controller',
      license: 'MIT',
      desc: '读写系统媒体音量。',
      usage: '播放器侧滑调节音量',
    ),
    _LibItem(
      name: 'screen_brightness',
      license: 'MIT',
      desc: '调节应用内或系统屏幕亮度。',
      usage: '播放器侧滑调节亮度',
    ),
    _LibItem(
      name: 'battery_plus',
      license: 'BSD-3-Clause',
      desc: '读取电量百分比与充放电状态。',
      usage: '全屏播放顶栏电量显示',
    ),
    _LibItem(
      name: 'device_info_plus',
      license: 'BSD-3-Clause',
      desc: '读取设备型号、系统版本、Android SDK 等。',
      usage: '权限策略分支、通知渠道兼容',
    ),
    _LibItem(
      name: 'flutter_local_notifications',
      license: 'BSD-3-Clause',
      desc: '本地推送通知（Android Notification / iOS UNUserNotification）。',
      usage: '剧集更新、下载完成、站内公告提醒',
    ),
    _LibItem(
      name: 'crypto',
      license: 'BSD-3-Clause',
      desc: '摘要算法（MD5 / SHA 等）与基础加解密工具。',
      usage: '弹幕接口签名等',
    ),
    _LibItem(
      name: 'lpinyin',
      license: 'BSD-2-Clause',
      desc: '汉字转拼音 / 首字母，便于模糊搜索。',
      usage: '片名搜索拼音匹配',
    ),
    _LibItem(
      name: 'lottie',
      license: 'Apache-2.0 / MIT',
      desc: '播放 After Effects 导出的 Lottie JSON 动画。',
      usage: '加载动画、登录页插画动效',
    ),
    _LibItem(
      name: 'custom_refresh_indicator',
      license: 'MIT',
      desc: '可自定义外观的下拉刷新指示器。',
      usage: '首页等列表下拉刷新',
    ),
    _LibItem(
      name: 'flutter_svg',
      license: 'MIT',
      desc: '在 Flutter 中渲染 SVG 矢量图。',
      usage: '登录 QQ 等品牌矢量图标',
    ),
    _LibItem(
      name: 'liquid_glass_widgets',
      license: '见仓库许可',
      desc: '液态玻璃风格控件与 Tab 栏效果。',
      usage: '底部导航玻璃质感（支持时启用）',
    ),
    _LibItem(
      name: 'airplay_button',
      license: 'MIT',
      desc: 'iOS AirPlay 路由按钮封装。',
      usage: '投屏面板中的 AirPlay 入口',
    ),
  ];

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
          '开源协议',
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Text(
              '哇TV 基于 Flutter 构建，并使用了以下开源库。感谢各位维护者。'
              '下列说明供查阅，具体权利义务以各库官方许可证原文为准。',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                height: 1.5,
                color: secondary,
              ),
            ),
            const SizedBox(height: 14),
            for (final lib in _libs) ...[
              Material(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              lib.name,
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: text,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brand.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              lib.license,
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        lib.desc,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          height: 1.45,
                          color: secondary,
                        ),
                      ),
                      if (lib.usage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '本应用用途：${lib.usage}',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            height: 1.4,
                            color: hint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
