import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, kReleaseMode;

/// 后端 API 配置。
///
/// 打包目标：
/// - **APK / IPA**：直连 [productionMacCms]（无 CORS）
/// - **H5 调试**：本机 `tool/cms_dev_proxy.dart`（127.0.0.1:8791）
/// - **H5 正式包**：走线上 `cms_cors_proxy.php`（需上传该文件）
class ApiConfig {
  ApiConfig._();

  static const String _envBase = String.fromEnvironment('API_BASE');
  static const String _envSite = String.fromEnvironment('SITE_ROOT');

  /// 线上 MacCMS 根（APK / IPA / 正式 H5）
  static const String productionMacCms = 'https://154.12.29.28';

  static String get baseUrl {
    if (_envBase.isNotEmpty) return _envBase;
    // 真机不再使用模拟器回环地址；与 CMS 同域下的 admin 接口（若无则相关页会失败）
    if (kIsWeb && kDebugMode) return 'http://127.0.0.1/admin/api.php';
    return '$productionMacCms/admin/api.php';
  }

  /// 站点根，用于 `api.php`（扫码/网页 Cookie）
  static String get siteRoot {
    if (_envSite.isNotEmpty) return _envSite.replaceAll(RegExp(r'/+$'), '');
    final admin = baseUrl;
    final i = admin.indexOf('/admin/');
    if (i >= 0) return admin.substring(0, i);
    return admin.replaceAll(RegExp(r'/admin/api\.php.*'), '');
  }

  /// 苹果 CMS / 哇TV 开放资源根地址（provide 接口）
  static const String _envMacCms = String.fromEnvironment('MACCMS_BASE');

  /// 运行时自定义 CMS（设置页），优先于编译期与默认值
  static String? _runtimeMacCms;

  static void applyRuntimeMacCmsOverride(String? url) {
    final t = (url ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    _runtimeMacCms = t.isEmpty ? null : t;
  }

  /// 正式 H5 用线上 PHP 代理；可用 `--dart-define=CMS_WEB_PROXY=true/false` 强制开关
  static bool get useCmsWebProxy {
    const flag = String.fromEnvironment('CMS_WEB_PROXY');
    if (flag == '1' || flag == 'true') return true;
    if (flag == '0' || flag == 'false') return false;
    return kIsWeb && kReleaseMode;
  }

  /// APK/IPA → 线上；Web 调试 → 本机代理；Web 正式 → 线上
  /// 设置页自定义地址优先
  static String get macCmsBase {
    final runtime = _runtimeMacCms;
    if (runtime != null && runtime.isNotEmpty) return runtime;
    if (_envMacCms.isNotEmpty) {
      return _envMacCms.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb && kDebugMode) return 'http://127.0.0.1:8791';
    return productionMacCms;
  }

  /// 正式 H5 provide 代理（上传 scripts/maccms-tools/cms_cors_proxy.php）
  static String get cmsWebProxyBase =>
      '$productionMacCms/maccms-tools/cms_cors_proxy.php';

  static String get macCmsVodProvide => useCmsWebProxy
      ? cmsWebProxyBase
      : '$macCmsBase/api.php/provide/vod/';

  /// 苹果 CMS 文章开放接口
  static String get macCmsArtProvide => useCmsWebProxy
      ? cmsWebProxyBase
      : '$macCmsBase/api.php/provide/art/';

  /// 第三方弹幕库（默认 [danmu.zxz.ee](https://danmu.zxz.ee/)）
  /// 编译期：`--dart-define=DANMAKU_API=https://danmu.zxz.ee`
  static const String _envDanmaku = String.fromEnvironment('DANMAKU_API');

  static String get danmakuApi {
    if (_envDanmaku.isNotEmpty) {
      return _envDanmaku.replaceAll(RegExp(r'/+$'), '');
    }
    return 'https://danmu.zxz.ee';
  }

  /// 站点「电影」周热门排行页（与网页一致）
  static String get macCmsMovieWeekHotUrl => macCmsWeekHotUrl(1);

  /// 站点「电视剧」周热门排行页
  static String get macCmsTvWeekHotUrl => macCmsWeekHotUrl(2);

  /// 分类周热门：1电影 2电视剧 3综艺 4动漫
  static String macCmsWeekHotUrl(int typeId) =>
      '$macCmsBase/index.php/vod/show/id/$typeId/by/hits_week.html';

  /// 站点总排行（label/rank）
  static String get macCmsRankUrl =>
      '$macCmsBase/index.php/label/rank.html';

  /// 首页 Tab → CMS 一级分类 ID；推荐=null 表示电影+剧混合
  static const Map<String, int?> macCmsHomeTabTypeIds = {
    '推荐': null,
    '电影': 1,
    '电视剧': 2,
    '综艺': 3,
    '动漫': 4,
    '短剧': macCmsShortDramaTypeId,
  };

  /// 热门「电影」子分类（本站一级 t=1 为空，需展开）
  static const List<int> macCmsMovieTypeIds = [
    6, 7, 8, 9, 10, 11, 12, // 动作喜剧爱情科幻恐怖剧情战争
    31, 32, 33, 34, 35, 36, 37, 38, 39, // 惊悚家庭古装历史悬疑犯罪灾难记录短片
  ];

  /// 热门「电视剧」子分类
  static const List<int> macCmsTvTypeIds = [
    13, 14, 15, 16, 24, 45, 46, 51, // 国产/台/韩/欧美/日/港/海外/连续剧
  ];

  /// 综艺子分类：大陆 / 日韩 / 港台 / 欧美
  static const List<int> macCmsVarietyTypeIds = [40, 41, 42, 43];

  /// 动漫子分类：国漫 / 日韩 / 美漫 / 港台 / 动漫电影（排除里番）
  static const List<int> macCmsAnimeTypeIds = [25, 26, 27, 28, 29];

  /// 一级分类 → 可拉详情的子分类（一级 t=1/2/3/4 接口常返回空）
  static List<int> macCmsChildTypeIds(int typeId) {
    return switch (typeId) {
      1 => macCmsMovieTypeIds,
      2 => macCmsTvTypeIds,
      3 => macCmsVarietyTypeIds,
      4 => macCmsAnimeTypeIds,
      _ => [typeId],
    };
  }

  /// 轮播排除（短剧、成人、里番、泰剧等）— 仅首页 Banner
  static const Set<int> macCmsBannerExcludeTypeIds = {44, 20, 30, 47};

  /// 搜索排除（成人、里番）；短剧要进搜索，不放这里
  static const Set<int> macCmsSearchExcludeTypeIds = {20, 30};

  /// 短剧一级分类
  static const int macCmsShortDramaTypeId = 44;

  /// 体育一级分类
  static const int macCmsSportsTypeId = 48;

  /// 体育赛事（录像/集锦等）
  static const int macCmsSportsEventTypeId = 84;

  /// 影视解说
  static const int macCmsCommentaryTypeId = 95;

  /// App 远程配置（策划栏 / 底栏 / 直播源）
  static String get macCmsAppConfigUrl =>
      '$macCmsBase/static/app/app_config.json';

  /// 哇TV 扩展面板（通知 / 更新 / 远程配置）
  /// 与后台 `huihuo_panel.php` 公开 `?api=` 对齐（服务端文件名保持兼容）。
  static String get huihuoPanelBase =>
      '$macCmsBase/maccms-tools/huihuo_panel.php';

  static String get huihuoPanelNotifyUrl =>
      '$huihuoPanelBase?api=notify_list';

  /// 静态通知兜底（面板发布时同步写入）
  static String get huihuoNotifyStaticUrl =>
      '$macCmsBase/static/app/notify_list.json';

  static String get huihuoPanelUpdateUrl =>
      '$huihuoPanelBase?api=app_update';

  static String get huihuoPanelAppConfigUrl =>
      '$huihuoPanelBase?api=app_config';

  static String get huihuoPanelReportUrl =>
      '$huihuoPanelBase?api=update_report';

  static String get huihuoPanelRedeemUrl =>
      '$huihuoPanelBase?api=redeem';

  /// 按影片过滤的评论列表（DB 直查；可带片名，避免 id 不一致）
  static String huihuoPanelCommentListUrl({
    String rid = '',
    String name = '',
    int mid = 1,
    int page = 1,
  }) {
    final q = <String>[
      'api=comment_list',
      'mid=$mid',
      'page=$page',
      if (rid.trim().isNotEmpty) 'rid=${Uri.encodeQueryComponent(rid.trim())}',
      if (name.trim().isNotEmpty)
        'name=${Uri.encodeQueryComponent(name.trim())}',
    ];
    return '$huihuoPanelBase?${q.join('&')}';
  }

  /// 封面反代（部分采集 CDN 客户端直连会被重置）
  static String huihuoImgProxyUrl(String absoluteImageUrl) =>
      '$huihuoPanelBase?api=img_proxy&u=${Uri.encodeComponent(absoluteImageUrl)}';

  /// 与 pubspec.yaml `version: name+code` 的 build number 对齐；发版时两边一起改。
  static const int appVersionCode = 1;
  static const String appVersionName = '1.0.0';

  /// 默认直播源 m3u（可在后台替换）
  static String get macCmsLiveM3uUrl => '$macCmsBase/static/app/live.m3u';

  /// 网址/直播 website 开放接口
  static String get macCmsWebsiteProvide => useCmsWebProxy
      ? cmsWebProxyBase
      : '$macCmsBase/api.php/provide/website/';

  /// 搜索顶栏默认频道（CMS 一级；短剧必含）
  static const List<MacCmsSearchChannel> macCmsSearchChannelDefaults = [
    MacCmsSearchChannel(name: '全部', typeId: null),
    MacCmsSearchChannel(name: '电影', typeId: 1),
    MacCmsSearchChannel(name: '电视剧', typeId: 2),
    MacCmsSearchChannel(name: '综艺', typeId: 3),
    MacCmsSearchChannel(name: '动漫', typeId: 4),
    MacCmsSearchChannel(name: '短剧', typeId: macCmsShortDramaTypeId),
  ];

  /// 搜索顶栏不展示的一级分类
  static const Set<int> macCmsSearchTabExcludeTypeIds = {5, 20};

  /// 顶栏默认：全部 + 地区（题材等放进扩展筛选）
  static List<MacCmsGenreTag> macCmsQuickFiltersFor(String tab) {
    final tid = macCmsHomeTabTypeIds[tab];
    final all = MacCmsGenreTag(
      label: '全部',
      mode: MacCmsGenreMode.weekHot,
      typeId: tid,
    );
    return switch (tab) {
      // 电影 CMS 无地区子类，顶栏只留全部；类型在筛选里
      '电影' => [all],
      '电视剧' => [all, ..._tvRegionTags],
      '综艺' => [all, ..._varietyRegionTags],
      '动漫' => [all, ..._animeRegionQuickTags],
      '短剧' => [all],
      // 推荐：默认地区剧
      _ => [all, ..._tvRegionTags],
    };
  }

  /// 扩展筛选：最新 / 题材类型等（非顶栏地区）
  static List<MacCmsFilterGroup> macCmsSheetFilterGroupsFor(String tab) {
    final tid = macCmsHomeTabTypeIds[tab];
    final latest = MacCmsGenreTag(
      label: '最新',
      mode: MacCmsGenreMode.latest,
      typeId: tid,
    );
    final hot = MacCmsGenreTag(
      label: '最热',
      mode: MacCmsGenreMode.weekHot,
      typeId: tid,
    );
    return switch (tab) {
      '电影' => [
          MacCmsFilterGroup(title: '排序', tags: [hot, latest]),
          const MacCmsFilterGroup(title: '类型', tags: _movieGenreTags),
        ],
      '电视剧' => [
          MacCmsFilterGroup(title: '排序', tags: [hot, latest]),
          const MacCmsFilterGroup(title: '地区', tags: _tvRegionTags),
          const MacCmsFilterGroup(title: '更多', tags: _tvExtraTags),
        ],
      '综艺' => [
          MacCmsFilterGroup(title: '排序', tags: [hot, latest]),
          const MacCmsFilterGroup(title: '地区', tags: _varietyRegionTags),
        ],
      '动漫' => [
          MacCmsFilterGroup(title: '排序', tags: [hot, latest]),
          const MacCmsFilterGroup(title: '类型', tags: _animeAllTags),
        ],
      '短剧' => [
          MacCmsFilterGroup(title: '排序', tags: [hot, latest]),
        ],
      _ => [
          MacCmsFilterGroup(title: '排序', tags: [hot, latest]),
          const MacCmsFilterGroup(title: '电影', tags: _movieGenreTags),
          const MacCmsFilterGroup(title: '剧集', tags: _tvRegionTags),
          const MacCmsFilterGroup(title: '综艺', tags: _varietyRegionTags),
          const MacCmsFilterGroup(title: '动漫', tags: _animeAllTags),
        ],
    };
  }

  /// 片库筛选页：与站点 /vod/show 一致（分类 / 地区 / 年代）
  static MacCmsLibraryFilters macCmsLibraryFiltersFor(String tab) {
    return switch (tab) {
      '电影' => _libraryMovie,
      '电视剧' => _libraryTv,
      '综艺' => _libraryVariety,
      '动漫' => _libraryAnime,
      _ => _libraryAll,
    };
  }

  /// @Deprecated 旧片库组；请用 [macCmsLibraryFiltersFor]
  static List<MacCmsFilterGroup> macCmsLibraryFilterGroupsFor(String tab) {
    final f = macCmsLibraryFiltersFor(tab);
    return [
      MacCmsFilterGroup(
        title: '分类',
        tags: [
          for (final c in f.classes)
            MacCmsGenreTag(
              label: c.label,
              mode: c.typeId == null
                  ? MacCmsGenreMode.latest
                  : MacCmsGenreMode.byType,
              typeId: c.typeId ?? f.channelTypeId,
            ),
        ],
      ),
    ];
  }

  static const _libraryMovie = MacCmsLibraryFilters(
    channelTypeId: 1,
    classes: [
      MacCmsClassOption(label: '全部'),
      MacCmsClassOption(label: '惊悚', typeId: 31),
      MacCmsClassOption(label: '动作', typeId: 6),
      MacCmsClassOption(label: '喜剧', typeId: 7),
      MacCmsClassOption(label: '爱情', typeId: 8),
      MacCmsClassOption(label: '科幻', typeId: 9),
      MacCmsClassOption(label: '恐怖', typeId: 10),
      MacCmsClassOption(label: '剧情', typeId: 11),
      MacCmsClassOption(label: '战争', typeId: 12),
    ],
    areas: [
      '全部', '大陆', '香港', '台湾', '美国', '法国', '英国', '日本',
      '韩国', '德国', '泰国', '印度', '意大利', '西班牙', '加拿大', '其他',
    ],
    years: [
      '全部', '2018', '2017', '2016', '2015', '2014', '2013', '2012', '2011', '2010',
    ],
  );

  static const _libraryTv = MacCmsLibraryFilters(
    channelTypeId: 2,
    classes: [
      MacCmsClassOption(label: '全部'),
      MacCmsClassOption(label: '国产剧', typeId: 13),
      MacCmsClassOption(label: '台湾剧', typeId: 14),
      MacCmsClassOption(label: '韩剧', typeId: 15),
      MacCmsClassOption(label: '欧美剧', typeId: 16),
    ],
    areas: [
      '全部', '内地', '韩国', '香港', '台湾', '日本', '美国', '泰国', '英国', '新加坡', '其他',
    ],
    years: [
      '全部', '2018', '2017', '2016', '2015', '2014', '2013', '2012', '2011', '2010',
      '2009', '2008', '2006', '2005', '2004',
    ],
  );

  static const _libraryVariety = MacCmsLibraryFilters(
    channelTypeId: 3,
    classes: [
      MacCmsClassOption(label: '全部'),
      MacCmsClassOption(label: '大陆', typeId: 40),
      MacCmsClassOption(label: '日韩', typeId: 41),
      MacCmsClassOption(label: '港台', typeId: 42),
      MacCmsClassOption(label: '欧美', typeId: 43),
    ],
    areas: ['全部', '内地', '港台', '日韩', '欧美'],
    years: [
      '全部', '2018', '2017', '2016', '2015', '2014', '2013', '2012', '2011', '2010',
      '2009', '2008', '2007', '2006', '2005', '2004',
    ],
  );

  static const _libraryAnime = MacCmsLibraryFilters(
    channelTypeId: 4,
    classes: [
      MacCmsClassOption(label: '全部'),
      MacCmsClassOption(label: '国漫', typeId: 25),
      MacCmsClassOption(label: '日韩', typeId: 26),
      MacCmsClassOption(label: '美漫', typeId: 27),
      MacCmsClassOption(label: '港台', typeId: 28),
      MacCmsClassOption(label: '动漫电影', typeId: 29),
    ],
    areas: ['全部', '国产', '日本', '欧美', '其他'],
    years: [
      '全部', '2018', '2017', '2016', '2015', '2014', '2013', '2012', '2011', '2010',
      '2009', '2008', '2007', '2006', '2005', '2004',
    ],
  );

  /// 「全部」频道：电影地区/年代 + 合并主流分类
  static const _libraryAll = MacCmsLibraryFilters(
    channelTypeId: null,
    classes: [
      MacCmsClassOption(label: '全部'),
      MacCmsClassOption(label: '惊悚', typeId: 31),
      MacCmsClassOption(label: '动作', typeId: 6),
      MacCmsClassOption(label: '喜剧', typeId: 7),
      MacCmsClassOption(label: '爱情', typeId: 8),
      MacCmsClassOption(label: '科幻', typeId: 9),
      MacCmsClassOption(label: '恐怖', typeId: 10),
      MacCmsClassOption(label: '剧情', typeId: 11),
      MacCmsClassOption(label: '战争', typeId: 12),
      MacCmsClassOption(label: '国产剧', typeId: 13),
      MacCmsClassOption(label: '韩剧', typeId: 15),
      MacCmsClassOption(label: '欧美剧', typeId: 16),
      MacCmsClassOption(label: '国漫', typeId: 25),
      MacCmsClassOption(label: '日韩动漫', typeId: 26),
    ],
    areas: [
      '全部', '大陆', '内地', '香港', '台湾', '美国', '日本', '韩国', '英国', '泰国', '其他',
    ],
    years: [
      '全部', '2018', '2017', '2016', '2015', '2014', '2013', '2012', '2011', '2010',
    ],
  );

  /// 电视剧地区（顶栏）
  static const List<MacCmsGenreTag> _tvRegionTags = [
    MacCmsGenreTag(label: '国产', mode: MacCmsGenreMode.byType, typeId: 13),
    MacCmsGenreTag(label: '台剧', mode: MacCmsGenreMode.byType, typeId: 14),
    MacCmsGenreTag(label: '韩剧', mode: MacCmsGenreMode.byType, typeId: 15),
    MacCmsGenreTag(label: '美剧', mode: MacCmsGenreMode.byType, typeId: 16),
    MacCmsGenreTag(label: '日剧', mode: MacCmsGenreMode.byType, typeId: 24),
    MacCmsGenreTag(label: '港剧', mode: MacCmsGenreMode.byType, typeId: 45),
    MacCmsGenreTag(label: '海外', mode: MacCmsGenreMode.byType, typeId: 46),
  ];

  static const List<MacCmsGenreTag> _tvExtraTags = [
    MacCmsGenreTag(label: '连续剧', mode: MacCmsGenreMode.byType, typeId: 51),
  ];

  static const List<MacCmsGenreTag> _varietyRegionTags = [
    MacCmsGenreTag(label: '大陆', mode: MacCmsGenreMode.byType, typeId: 40),
    MacCmsGenreTag(label: '日韩', mode: MacCmsGenreMode.byType, typeId: 41),
    MacCmsGenreTag(label: '港台', mode: MacCmsGenreMode.byType, typeId: 42),
    MacCmsGenreTag(label: '欧美', mode: MacCmsGenreMode.byType, typeId: 43),
  ];

  static const List<MacCmsGenreTag> _animeRegionQuickTags = [
    MacCmsGenreTag(label: '国漫', mode: MacCmsGenreMode.byType, typeId: 25),
    MacCmsGenreTag(label: '日韩', mode: MacCmsGenreMode.byType, typeId: 26),
    MacCmsGenreTag(label: '美漫', mode: MacCmsGenreMode.byType, typeId: 27),
  ];

  static const List<MacCmsGenreTag> _animeExtraTags = [
    MacCmsGenreTag(label: '港台', mode: MacCmsGenreMode.byType, typeId: 28),
    MacCmsGenreTag(label: '动漫电影', mode: MacCmsGenreMode.byType, typeId: 29),
  ];

  static const List<MacCmsGenreTag> _animeAllTags = [
    ..._animeRegionQuickTags,
    ..._animeExtraTags,
  ];

  static const List<MacCmsGenreTag> _movieGenreTags = [
    MacCmsGenreTag(label: '动作', mode: MacCmsGenreMode.byType, typeId: 6),
    MacCmsGenreTag(label: '喜剧', mode: MacCmsGenreMode.byType, typeId: 7),
    MacCmsGenreTag(label: '爱情', mode: MacCmsGenreMode.byType, typeId: 8),
    MacCmsGenreTag(label: '科幻', mode: MacCmsGenreMode.byType, typeId: 9),
    MacCmsGenreTag(label: '恐怖', mode: MacCmsGenreMode.byType, typeId: 10),
    MacCmsGenreTag(label: '剧情', mode: MacCmsGenreMode.byType, typeId: 11),
    MacCmsGenreTag(label: '战争', mode: MacCmsGenreMode.byType, typeId: 12),
    MacCmsGenreTag(label: '惊悚', mode: MacCmsGenreMode.byType, typeId: 31),
    MacCmsGenreTag(label: '家庭', mode: MacCmsGenreMode.byType, typeId: 32),
    MacCmsGenreTag(label: '古装', mode: MacCmsGenreMode.byType, typeId: 33),
    MacCmsGenreTag(label: '历史', mode: MacCmsGenreMode.byType, typeId: 34),
    MacCmsGenreTag(label: '悬疑', mode: MacCmsGenreMode.byType, typeId: 35),
    MacCmsGenreTag(label: '犯罪', mode: MacCmsGenreMode.byType, typeId: 36),
    MacCmsGenreTag(label: '灾难', mode: MacCmsGenreMode.byType, typeId: 37),
    MacCmsGenreTag(label: '记录', mode: MacCmsGenreMode.byType, typeId: 38),
    MacCmsGenreTag(label: '短片', mode: MacCmsGenreMode.byType, typeId: 39),
  ];

  /// 兼容旧调用：顶栏筛选项
  static List<MacCmsGenreTag> macCmsGenreTagsFor(String tab) =>
      macCmsQuickFiltersFor(tab);

  static String get cookieApi => '$siteRoot/api.php';

  static String get imMediaBase => '$siteRoot/im_media.php';

  /// 解密后的本地缓存图
  static String imMediaUrl(String file) {
    if (file.isEmpty) return '';
    return '$imMediaBase?f=${Uri.encodeQueryComponent(file)}';
  }

  static const String client = 'app';

  /// 抖音创作者登录页（网页绑定 WebView）
  static const String douyinWebLoginUrl =
      'https://sso.douyin.com/?service=https%3A%2F%2Fcreator.douyin.com&aid=2906';
}

enum MacCmsGenreMode { latest, weekHot, byType }

/// 搜索顶栏频道（对接 CMS 一级分类）
class MacCmsSearchChannel {
  const MacCmsSearchChannel({required this.name, this.typeId});

  final String name;
  /// null = 全部
  final int? typeId;
}

/// CMS 分类节点（provide/vod class[]）
class MacCmsTypeNode {
  const MacCmsTypeNode({
    required this.typeId,
    required this.typePid,
    required this.typeName,
  });

  final int typeId;
  final int typePid;
  final String typeName;
}

class MacCmsGenreTag {
  const MacCmsGenreTag({
    required this.label,
    required this.mode,
    this.typeId,
  });

  final String label;
  final MacCmsGenreMode mode;
  final int? typeId;

  bool sameAs(MacCmsGenreTag other) =>
      label == other.label && mode == other.mode && typeId == other.typeId;
}

class MacCmsFilterGroup {
  const MacCmsFilterGroup({required this.title, required this.tags});

  final String title;
  final List<MacCmsGenreTag> tags;
}

class MacCmsClassOption {
  const MacCmsClassOption({required this.label, this.typeId});

  final String label;
  final int? typeId;
}

/// 片库三维筛选（对齐站点 show 页返回的分类/地区/年代）
class MacCmsLibraryFilters {
  const MacCmsLibraryFilters({
    required this.channelTypeId,
    required this.classes,
    required this.areas,
    required this.years,
  });

  /// 频道一级 type_id；全部频道为 null
  final int? channelTypeId;
  final List<MacCmsClassOption> classes;
  final List<String> areas;
  final List<String> years;
}

