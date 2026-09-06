import 'package:flutter/cupertino.dart';

/// 单集可播地址
class MoviePlayEpisode {
  const MoviePlayEpisode({
    required this.name,
    required this.url,
  });

  final String name;
  final String url;
}

/// 一条播放线路
class MoviePlaySource {
  const MoviePlaySource({
    required this.name,
    required this.episodes,
  });

  final String name;
  final List<MoviePlayEpisode> episodes;
}

/// 影视条目（支持 CMS 封面 URL，无图时回退纯色 + 图标）
class Movie {
  const Movie({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.year,
    required this.score,
    required this.genres,
    required this.coverColor,
    required this.tagline,
    required this.synopsis,
    this.icon = CupertinoIcons.film,
    this.episodes = const [],
    this.playEpisodes = const [],
    this.playSourceNames = const [],
    this.playSources = const [],
    this.cast = const [],
    this.durationMinutes,
    this.coverUrl,
    this.remarks = '',
    this.slideUrl,
    this.director = '',
    this.area = '',
    this.lang = '',
    this.durationText = '',
    this.totalEpisodes = 0,
    this.pubdate = '',
    this.writer = '',
    this.subTitle = '',
    this.doubanId = '',
    this.scoreCount = 0,
    this.typeId = 0,
    this.nameEn = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final int year;
  final double score;
  /// 评分人数（CMS vod_score_num）
  final int scoreCount;
  final List<String> genres;
  final Color coverColor;
  final String tagline;
  final String synopsis;
  final IconData icon;
  final List<String> episodes;
  final List<MoviePlayEpisode> playEpisodes;
  final List<String> playSourceNames;
  final List<MoviePlaySource> playSources;
  final List<MovieCast> cast;
  final int? durationMinutes;
  final String? coverUrl;
  final String remarks;
  final String? slideUrl;
  final String director;
  final String area;
  final String lang;
  final String durationText;
  final int totalEpisodes;
  final String pubdate;
  final String writer;
  final String subTitle;
  /// 豆瓣条目 ID（用于拉取演员真人头像）
  final String doubanId;
  /// CMS 分类 ID（同类型推荐）
  final int typeId;
  /// CMS vod_en（英文/拼音检索）
  final String nameEn;

  String? get bannerUrl {
    final s = slideUrl?.trim();
    if (s != null && s.isNotEmpty) return s;
    return coverUrl;
  }

  List<String> get episodeLabels {
    if (playEpisodes.isNotEmpty) {
      return [for (final e in playEpisodes) e.name];
    }
    return episodes;
  }

  bool get isSeries => episodeLabels.length > 1 || totalEpisodes > 1;

  String get scoreLabel => score.toStringAsFixed(1);

  /// 十分制 → 五星（支持半星）
  double get starRating => (score / 2).clamp(0.0, 5.0);

  String? get cornerBadge {
    final r = remarks.trim();
    const keys = <String>[
      '独家',
      '免费',
      '会员',
      '热播',
      '热门',
      '抢先',
      'VIP',
      '预告',
      '限免',
    ];
    for (final k in keys) {
      if (r.toUpperCase().contains(k.toUpperCase())) {
        return k == 'VIP' ? '会员' : k;
      }
    }
    if (score >= 8.5) return '高分';
    if (r.contains('更新')) return '更新';
    if (r.contains('完结') || r.contains('全集')) return '完结';
    if (r.isNotEmpty && r.length <= 4 && !r.contains('集')) return r;
    return null;
  }

  String? playUrlAt(int index, {int sourceIndex = 0}) {
    final list = episodesOf(sourceIndex);
    if (list.isEmpty) return null;
    final i = index.clamp(0, list.length - 1);
    final url = list[i].url.trim();
    return url.isEmpty ? null : url;
  }

  List<MoviePlayEpisode> episodesOf(int sourceIndex) {
    if (playSources.isEmpty) return playEpisodes;
    return playSources[sourceIndex.clamp(0, playSources.length - 1)].episodes;
  }

  Movie copyWith({
    String? id,
    String? title,
    String? subtitle,
    int? year,
    double? score,
    int? scoreCount,
    List<String>? genres,
    Color? coverColor,
    String? tagline,
    String? synopsis,
    IconData? icon,
    List<String>? episodes,
    List<MoviePlayEpisode>? playEpisodes,
    List<String>? playSourceNames,
    List<MoviePlaySource>? playSources,
    List<MovieCast>? cast,
    int? durationMinutes,
    String? coverUrl,
    String? remarks,
    String? slideUrl,
    String? director,
    String? area,
    String? lang,
    String? durationText,
    int? totalEpisodes,
    String? pubdate,
    String? writer,
    String? subTitle,
    String? doubanId,
    int? typeId,
    String? nameEn,
  }) {
    return Movie(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      year: year ?? this.year,
      score: score ?? this.score,
      scoreCount: scoreCount ?? this.scoreCount,
      genres: genres ?? this.genres,
      coverColor: coverColor ?? this.coverColor,
      tagline: tagline ?? this.tagline,
      synopsis: synopsis ?? this.synopsis,
      icon: icon ?? this.icon,
      episodes: episodes ?? this.episodes,
      playEpisodes: playEpisodes ?? this.playEpisodes,
      playSourceNames: playSourceNames ?? this.playSourceNames,
      playSources: playSources ?? this.playSources,
      cast: cast ?? this.cast,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      coverUrl: coverUrl ?? this.coverUrl,
      remarks: remarks ?? this.remarks,
      slideUrl: slideUrl ?? this.slideUrl,
      director: director ?? this.director,
      area: area ?? this.area,
      lang: lang ?? this.lang,
      durationText: durationText ?? this.durationText,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      pubdate: pubdate ?? this.pubdate,
      writer: writer ?? this.writer,
      subTitle: subTitle ?? this.subTitle,
      doubanId: doubanId ?? this.doubanId,
      typeId: typeId ?? this.typeId,
      nameEn: nameEn ?? this.nameEn,
    );
  }
}

class MovieCast {
  const MovieCast({
    required this.name,
    required this.role,
    this.color = const Color(0xFF8E8E93),
    this.avatarUrl,
  });

  final String name;
  final String role;
  final Color color;
  final String? avatarUrl;

  MovieCast copyWith({
    String? name,
    String? role,
    Color? color,
    String? avatarUrl,
  }) {
    return MovieCast(
      name: name ?? this.name,
      role: role ?? this.role,
      color: color ?? this.color,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

/// CMS 站内评论
class MovieComment {
  const MovieComment({
    required this.id,
    required this.userName,
    required this.content,
    this.timeText = '',
    this.timeMs = 0,
    this.avatarUrl,
    this.up = 0,
    this.down = 0,
    this.replyCount = 0,
    this.vodId = '',
    this.vodName = '',
    this.vodPic = '',
  });

  final String id;
  final String userName;
  final String content;
  final String timeText;
  final int timeMs;
  final String? avatarUrl;
  final int up;
  final int down;
  final int replyCount;
  final String vodId;
  final String vodName;
  final String vodPic;

  MovieComment copyWith({
    int? up,
    int? down,
    int? replyCount,
    String? vodId,
    String? vodName,
    String? vodPic,
  }) {
    return MovieComment(
      id: id,
      userName: userName,
      content: content,
      timeText: timeText,
      timeMs: timeMs,
      avatarUrl: avatarUrl,
      up: up ?? this.up,
      down: down ?? this.down,
      replyCount: replyCount ?? this.replyCount,
      vodId: vodId ?? this.vodId,
      vodName: vodName ?? this.vodName,
      vodPic: vodPic ?? this.vodPic,
    );
  }
}

class MovieSection {
  const MovieSection({
    required this.title,
    required this.movies,
  });

  final String title;
  final List<Movie> movies;
}
