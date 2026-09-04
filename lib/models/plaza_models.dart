class PlazaAuthor {
  const PlazaAuthor({
    this.id = 0,
    this.username = '',
    this.nickname = '',
    this.avatar = '',
  });

  final int id;
  final String username;
  final String nickname;
  final String avatar;

  String get displayName {
    final n = nickname.trim();
    if (n.isNotEmpty) return n;
    final u = username.trim();
    if (u.isNotEmpty) return u;
    return '用户';
  }

  factory PlazaAuthor.fromJson(Map<String, dynamic> json) {
    return PlazaAuthor(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: '${json['username'] ?? ''}',
      nickname: '${json['nickname'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
    );
  }
}

class PlazaPost {
  const PlazaPost({
    required this.id,
    required this.userId,
    required this.content,
    this.images = const [],
    this.cover = '',
    this.status = 1,
    this.statusLabel = '',
    this.rejectReason = '',
    this.likeCount = 0,
    this.liked = false,
    this.isMine = false,
    this.author = const PlazaAuthor(),
    this.createdAt = '',
    this.createdMs = 0,
  });

  final int id;
  final int userId;
  final String content;
  final List<String> images;
  final String cover;
  final int status; // 0待审 1通过 2拒绝 3删除
  final String statusLabel;
  final String rejectReason;
  final int likeCount;
  final bool liked;
  final bool isMine;
  final PlazaAuthor author;
  final String createdAt;
  final int createdMs;

  String get displayCover {
    if (cover.isNotEmpty) return cover;
    if (images.isNotEmpty) return images.first;
    return '';
  }

  bool get isPending => status == 0;
  bool get isApproved => status == 1;
  bool get isRejected => status == 2;

  PlazaPost copyWith({
    int? likeCount,
    bool? liked,
    int? status,
    String? statusLabel,
    String? rejectReason,
  }) {
    return PlazaPost(
      id: id,
      userId: userId,
      content: content,
      images: images,
      cover: cover,
      status: status ?? this.status,
      statusLabel: statusLabel ?? this.statusLabel,
      rejectReason: rejectReason ?? this.rejectReason,
      likeCount: likeCount ?? this.likeCount,
      liked: liked ?? this.liked,
      isMine: isMine,
      author: author,
      createdAt: createdAt,
      createdMs: createdMs,
    );
  }

  factory PlazaPost.fromJson(Map<String, dynamic> json) {
    final imgs = <String>[];
    final raw = json['images'];
    if (raw is List) {
      for (final u in raw) {
        final s = '$u'.trim();
        if (s.isNotEmpty) imgs.add(s);
      }
    }
    final authorRaw = json['author'];
    return PlazaPost(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      content: '${json['content'] ?? ''}',
      images: imgs,
      cover: '${json['cover'] ?? ''}',
      status: (json['status'] as num?)?.toInt() ?? 0,
      statusLabel: '${json['status_label'] ?? ''}',
      rejectReason: '${json['reject_reason'] ?? ''}',
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      liked: json['liked'] == true || json['liked'] == 1,
      isMine: json['is_mine'] == true || json['is_mine'] == 1,
      author: authorRaw is Map
          ? PlazaAuthor.fromJson(Map<String, dynamic>.from(authorRaw))
          : const PlazaAuthor(),
      createdAt: '${json['created_at'] ?? ''}',
      createdMs: (json['created_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlazaListResult {
  const PlazaListResult({
    this.list = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
  });

  final List<PlazaPost> list;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => list.length + (page - 1) * pageSize < total;
}

class PlazaStats {
  const PlazaStats({
    this.pending = 0,
    this.approved = 0,
    this.rejected = 0,
  });

  final int pending;
  final int approved;
  final int rejected;

  factory PlazaStats.fromJson(Map<String, dynamic> json) {
    return PlazaStats(
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      approved: (json['approved'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
    );
  }
}
