import 'package:flutter/material.dart';

import '../config/api_config.dart';
import 'vertical_short_feed_page.dart';

/// 兼容旧入口：短剧竖滑 Feed
class ShortDramaFeedPage extends StatelessWidget {
  const ShortDramaFeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const VerticalShortFeedPage(
      title: '短剧',
      typeId: ApiConfig.macCmsShortDramaTypeId,
    );
  }
}
