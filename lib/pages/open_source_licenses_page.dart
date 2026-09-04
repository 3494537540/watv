import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class _LibItem {
  const _LibItem(this.name, this.license, this.desc);
  final String name;
  final String license;
  final String desc;
}

/// 开源协议 / 第三方库说明
class OpenSourceLicensesPage extends StatelessWidget {
  const OpenSourceLicensesPage({super.key});

  static const _libs = <_LibItem>[
    _LibItem('Flutter / Dart SDK', 'BSD-3-Clause', '跨平台 UI 框架与语言运行时'),
    _LibItem('cupertino_icons', 'MIT', 'iOS 风格图标字体'),
    _LibItem('http', 'BSD-3-Clause', 'HTTP 网络请求'),
    _LibItem('shared_preferences', 'BSD-3-Clause', '本地键值存储'),
    _LibItem('path_provider', 'BSD-3-Clause', '应用目录路径'),
    _LibItem('video_player', 'BSD-3-Clause', '音视频播放'),
    _LibItem('flutter_inappwebview', 'Apache-2.0', '内嵌 WebView'),
    _LibItem('image_picker', 'Apache-2.0', '相册/相机选图'),
    _LibItem('permission_handler', 'MIT', '运行时权限'),
    _LibItem('gal', 'BSD-3-Clause', '保存图片到相册'),
    _LibItem('wakelock_plus', 'BSD-3-Clause', '播放时保持屏幕常亮'),
    _LibItem('connectivity_plus', 'BSD-3-Clause', '网络连通性检测'),
    _LibItem('volume_controller', 'MIT', '系统音量控制'),
    _LibItem('screen_brightness', 'MIT', '屏幕亮度调节'),
    _LibItem('battery_plus', 'BSD-3-Clause', '电量信息'),
    _LibItem('floating', 'Apache-2.0', '画中画 / 悬浮窗相关'),
    _LibItem('crypto', 'BSD-3-Clause', '摘要与加解密工具'),
    _LibItem('lpinyin', 'BSD-2-Clause', '中文拼音处理'),
    _LibItem('lottie', 'Apache-2.0 / MIT', 'Lottie 动画'),
    _LibItem('custom_refresh_indicator', 'MIT', '自定义下拉刷新'),
    _LibItem('liquid_glass_widgets', '见其仓库许可', '液态玻璃风格控件'),
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
              '下列信息供查阅，具体以各库官方许可证为准。',
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 13,
                height: 1.5,
                color: secondary,
              ),
            ),
            SizedBox(height: 14),
            for (final lib in _libs) ...[
              Material(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                      const SizedBox(height: 6),
                      Text(
                        lib.desc,
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          height: 1.4,
                          color: hint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Text(
              '也可在工程目录执行 flutter pub deps 查看完整依赖树。',
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
}
