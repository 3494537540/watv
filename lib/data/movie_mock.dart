import 'package:flutter/cupertino.dart';

import '../models/movie_models.dart';
import '../widgets/ios_carousel.dart';

/// 本地影视假数据（无外网图）
abstract final class MovieMock {
  static const List<Movie> all = [
    Movie(
      id: 'm1',
      title: '夜色旅人',
      subtitle: '都市悬疑',
      year: 2025,
      score: 8.6,
      genres: ['悬疑', '剧情'],
      coverColor: Color(0xFF1C3A5F),
      tagline: '在无人认领的夜晚，真相自行抵达。',
      synopsis:
          '记者林晓意外收到一盘无人署名的录音带，内容指向十年前的冷案。随着调查深入，她发现城市灯火之下藏着一整张沉默的关系网。',
      icon: CupertinoIcons.moon_stars_fill,
      durationMinutes: 118,
      cast: [
        MovieCast(name: '陈予', role: '林晓', color: Color(0xFF5B7C99)),
        MovieCast(name: '周启', role: '顾衡', color: Color(0xFF6B5B95)),
        MovieCast(name: '沈岚', role: '苏晴', color: Color(0xFF8B6B5B)),
      ],
    ),
    Movie(
      id: 'm2',
      title: '夏日回声',
      subtitle: '青春爱情',
      year: 2024,
      score: 8.1,
      genres: ['爱情', '青春'],
      coverColor: Color(0xFFE07A3D),
      tagline: '那些没说出口的话，终于被海风听见。',
      synopsis:
          '回乡过夏的阿夏与旧友阿南重逢，两人沿着旧日足迹重新走一遍海岸线，试图拼回被时间打散的记忆。',
      icon: CupertinoIcons.sun_max_fill,
      durationMinutes: 102,
      cast: [
        MovieCast(name: '许安', role: '阿夏', color: Color(0xFFD97757)),
        MovieCast(name: '林舟', role: '阿南', color: Color(0xFF4A90A4)),
      ],
    ),
    Movie(
      id: 'm3',
      title: '星港',
      subtitle: '科幻冒险',
      year: 2025,
      score: 9.0,
      genres: ['科幻', '冒险'],
      coverColor: Color(0xFF2D1B4E),
      tagline: '最后一艘船，驶向未知的港湾。',
      synopsis:
          '当地球轨道站即将废弃，领航员方澈必须带领幸存者穿越风暴带，寻找传说中的「星港」。',
      icon: CupertinoIcons.rocket_fill,
      durationMinutes: 136,
      cast: [
        MovieCast(name: '韩川', role: '方澈', color: Color(0xFF5C4A8A)),
        MovieCast(name: '叶宁', role: '艾拉', color: Color(0xFF3D6B8A)),
        MovieCast(name: '莫白', role: '老李', color: Color(0xFF6A6A6A)),
      ],
    ),
    Movie(
      id: 'm4',
      title: '厨房里的战争',
      subtitle: '喜剧',
      year: 2023,
      score: 7.8,
      genres: ['喜剧', '家庭'],
      coverColor: Color(0xFFC45C26),
      tagline: '一顿年夜饭，决定谁说了算。',
      synopsis:
          '三代同堂的厨房因一道红烧肉爆发「主权争夺战」，笑料与温情一并上桌。',
      icon: CupertinoIcons.flame_fill,
      durationMinutes: 98,
      cast: [
        MovieCast(name: '老金', role: '金爸', color: Color(0xFFB85C38)),
        MovieCast(name: '方圆', role: '金妈', color: Color(0xFF8B5A2B)),
      ],
    ),
    Movie(
      id: 'm5',
      title: '雾城二十四小时',
      subtitle: '犯罪动作',
      year: 2025,
      score: 8.4,
      genres: ['动作', '犯罪'],
      coverColor: Color(0xFF2C2C2E),
      tagline: '倒计时开始，城市失去能见度。',
      synopsis:
          '大雾封锁全城，卧底警察必须在二十四小时内阻止一场跨境交易，同时保护唯一证人。',
      icon: CupertinoIcons.shield_lefthalf_fill,
      durationMinutes: 124,
      cast: [
        MovieCast(name: '赵野', role: '陈默', color: Color(0xFF4A4A4C)),
        MovieCast(name: '顾青', role: '证人', color: Color(0xFF6B7B8A)),
      ],
    ),
    Movie(
      id: 's1',
      title: '长夜灯塔',
      subtitle: '年代剧',
      year: 2025,
      score: 8.9,
      genres: ['剧情', '年代'],
      coverColor: Color(0xFF8B4513),
      tagline: '灯塔守夜人，照亮整条海岸。',
      synopsis:
          '以灯塔为轴，讲述三代守塔人与渔村的命运交织，跨越半个世纪的坚守与告别。',
      icon: CupertinoIcons.lightbulb_fill,
      episodes: [
        '第1集 初到',
        '第2集 风暴',
        '第3集 来信',
        '第4集 灯火',
        '第5集 潮声',
        '第6集 归航',
        '第7集 守望',
        '第8集 长夜',
      ],
      cast: [
        MovieCast(name: '唐砚', role: '老周', color: Color(0xFF7A5C3A)),
        MovieCast(name: '白露', role: '阿妹', color: Color(0xFF9A6B4A)),
      ],
    ),
    Movie(
      id: 's2',
      title: '算法恋人',
      subtitle: '都市剧',
      year: 2024,
      score: 7.9,
      genres: ['爱情', '科幻'],
      coverColor: Color(0xFF007AFF),
      tagline: '匹配度 99%，但心跳不在公式里。',
      synopsis:
          '情感匹配 App 的产品经理误把自己写入实验组，与算法推荐的对象展开一场关于「真实」的辩论。',
      icon: CupertinoIcons.heart_fill,
      episodes: [
        '第1集 匹配',
        '第2集 误触',
        '第3集 盲测',
        '第4集 偏差',
        '第5集 人工',
        '第6集 心跳',
      ],
      cast: [
        MovieCast(name: '江夏', role: '顾言', color: Color(0xFF3A7BD5)),
        MovieCast(name: '程意', role: '林夏', color: Color(0xFFE85D75)),
      ],
    ),
    Movie(
      id: 'm6',
      title: '白纸之上',
      subtitle: '文艺片',
      year: 2022,
      score: 8.7,
      genres: ['文艺', '剧情'],
      coverColor: Color(0xFF5C6B73),
      tagline: '空白不是结束，是尚未写下的一页。',
      synopsis:
          '失语的插画家在边境小镇遇见一位只会画画的孩子，两人用图画重建彼此的世界。',
      icon: CupertinoIcons.paintbrush_fill,
      durationMinutes: 110,
      cast: [
        MovieCast(name: '纪川', role: '画家', color: Color(0xFF5A6A72)),
        MovieCast(name: '小满', role: '孩子', color: Color(0xFF8A9A7A)),
      ],
    ),
    Movie(
      id: 'm7',
      title: '极北列车',
      subtitle: '公路冒险',
      year: 2025,
      score: 8.2,
      genres: ['冒险', '剧情'],
      coverColor: Color(0xFF1A4A6B),
      tagline: '终点站不在地图上。',
      synopsis:
          '一列开往极北的列车突然偏离轨道，乘客们必须在冰原上决定：等待救援，还是继续向前。',
      icon: CupertinoIcons.tram_fill,
      durationMinutes: 129,
      cast: [
        MovieCast(name: '陆琛', role: '列车长', color: Color(0xFF2A5A7A)),
        MovieCast(name: '安然', role: '医生', color: Color(0xFF6A8A9A)),
      ],
    ),
    Movie(
      id: 's3',
      title: '事务所',
      subtitle: '律政剧',
      year: 2024,
      score: 8.5,
      genres: ['律政', '悬疑'],
      coverColor: Color(0xFF3D3D3D),
      tagline: '每一份卷宗，都是一场未结束的辩论。',
      synopsis:
          '新晋律师入职传奇事务所，在一桩看似无胜算的案件中，发现前辈留下的暗线。',
      icon: CupertinoIcons.briefcase_fill,
      episodes: [
        '第1集 入职',
        '第2集 卷宗',
        '第3集 证人',
        '第4集 反转',
        '第5集 暗线',
        '第6集 庭审',
        '第7集 真相',
        '第8集 交接',
        '第9集 余波',
        '第10集 新案',
      ],
      cast: [
        MovieCast(name: '谢言', role: '新人', color: Color(0xFF4A4A4A)),
        MovieCast(name: '裴宁', role: '合伙人', color: Color(0xFF6B5B4B)),
      ],
    ),
    Movie(
      id: 'm8',
      title: '雨季短片集',
      subtitle: '短片精选',
      year: 2025,
      score: 8.0,
      genres: ['短片', '合集'],
      coverColor: Color(0xFF4A6670),
      tagline: '六十分钟，六个雨天的故事。',
      synopsis: '六位导演各自讲述一场雨里发生的小事件，拼成一部关于等待的合集。',
      icon: CupertinoIcons.cloud_rain_fill,
      durationMinutes: 60,
      cast: [
        MovieCast(name: '多位', role: '导演联名', color: Color(0xFF5A7078)),
      ],
    ),
    Movie(
      id: 'm9',
      title: '回声峡谷',
      subtitle: '奇幻',
      year: 2023,
      score: 7.6,
      genres: ['奇幻', '冒险'],
      coverColor: Color(0xFF5B3A6E),
      tagline: '喊出名字的人，会被山谷记住。',
      synopsis:
          '少年为寻找失踪的姐姐，进入据说能回应心愿的峡谷，却发现每个回声都要付出代价。',
      icon: CupertinoIcons.wind,
      durationMinutes: 115,
      cast: [
        MovieCast(name: '阿岩', role: '少年', color: Color(0xFF6B4A7E)),
        MovieCast(name: '青禾', role: '向导', color: Color(0xFF4A7A6A)),
      ],
    ),
  ];

  static Movie? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  static List<Movie> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return all.where((m) {
      final hay = [
        m.title,
        m.subtitle,
        m.tagline,
        ...m.genres,
        ...m.cast.map((c) => c.name),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  /// 首页轮播精选（映射到 IosCarousel）
  static List<IosCarouselItem> get banners => [
        IosCarouselItem(
          eyebrow: '今日精选',
          title: all[2].title,
          subtitle: all[2].tagline,
          background: all[2].coverColor,
          icon: all[2].icon,
        ),
        IosCarouselItem(
          eyebrow: '热播剧集',
          title: all[5].title,
          subtitle: all[5].tagline,
          background: all[5].coverColor,
          icon: all[5].icon,
        ),
        IosCarouselItem(
          eyebrow: '高分推荐',
          title: all[0].title,
          subtitle: all[0].tagline,
          background: all[0].coverColor,
          icon: all[0].icon,
        ),
        IosCarouselItem(
          eyebrow: '新片速递',
          title: all[4].title,
          subtitle: all[4].tagline,
          background: all[4].coverColor,
          icon: all[4].icon,
        ),
      ];

  /// 轮播下标对应的影片
  static Movie bannerMovie(int index) {
    const ids = ['m3', 's1', 'm1', 'm5'];
    final id = ids[index.clamp(0, ids.length - 1)];
    return byId(id)!;
  }

  static List<MovieSection> get sections => [
        MovieSection(
          title: '热播榜',
          movies: [all[5], all[2], all[0], all[9], all[4]],
        ),
        MovieSection(
          title: '新片上映',
          movies: [all[0], all[2], all[4], all[6], all[10]],
        ),
        MovieSection(
          title: '高分精选',
          movies: [all[2], all[5], all[7], all[0], all[9]],
        ),
        MovieSection(
          title: '热门剧集',
          movies: [all[5], all[6], all[9]],
        ),
        MovieSection(
          title: '轻松一刻',
          movies: [all[3], all[1], all[10], all[11]],
        ),
      ];
}
