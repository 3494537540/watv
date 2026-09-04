import '../utils/relative_time.dart';

class DouyinAccount {
  const DouyinAccount({
    required this.id,
    required this.douyinUid,
    required this.nickname,
    this.avatarUrl = '',
    this.uniqueId = '',
    this.description = '',
    this.followersCount = 0,
    this.followingsCount = 0,
    this.awemeCount = 0,
    this.status = 1,
    this.boundAt = '',
    this.lastCheckAt = '',
    this.hasCookie = true,
  });

  final int id;
  final String douyinUid;
  final String nickname;
  final String avatarUrl;
  final String uniqueId;
  final String description;
  final int followersCount;
  final int followingsCount;
  final int awemeCount;
  final int status;
  final String boundAt;
  final String lastCheckAt;
  final bool hasCookie;

  DouyinAccount copyWith({
    String? nickname,
    String? avatarUrl,
    String? uniqueId,
    String? description,
    int? followersCount,
    int? followingsCount,
    int? awemeCount,
    String? lastCheckAt,
    bool? hasCookie,
  }) {
    return DouyinAccount(
      id: id,
      douyinUid: douyinUid,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      uniqueId: uniqueId ?? this.uniqueId,
      description: description ?? this.description,
      followersCount: followersCount ?? this.followersCount,
      followingsCount: followingsCount ?? this.followingsCount,
      awemeCount: awemeCount ?? this.awemeCount,
      status: status,
      boundAt: boundAt,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      hasCookie: hasCookie ?? this.hasCookie,
    );
  }

  factory DouyinAccount.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return DouyinAccount(
      id: asInt(json['id']),
      douyinUid: '${json['douyin_uid'] ?? ''}',
      nickname: '${json['nickname'] ?? '抖音账号'}',
      avatarUrl: '${json['avatar_url'] ?? ''}',
      uniqueId: '${json['unique_id'] ?? ''}',
      description: '${json['description'] ?? ''}',
      followersCount: asInt(json['followers_count']),
      followingsCount: asInt(json['followings_count']),
      awemeCount: asInt(json['aweme_count']),
      status: asInt(json['status'] ?? 1),
      boundAt: '${json['bound_at'] ?? ''}',
      lastCheckAt: '${json['last_check_at'] ?? ''}',
      hasCookie: json['has_cookie'] == true || json['has_cookie'] == 1,
    );
  }
}

class DouyinUserPreview {
  const DouyinUserPreview({
    required this.userId,
    required this.nickname,
    this.secUserId = '',
    this.avatarUrl = '',
    this.uniqueId = '',
    this.followersCount = 0,
    this.followingsCount = 0,
    this.awemeCount = 0,
    this.description = '',
  });

  final String userId;
  final String nickname;
  final String secUserId;
  final String avatarUrl;
  final String uniqueId;
  final int followersCount;
  final int followingsCount;
  final int awemeCount;
  final String description;

  Map<String, dynamic> toBindJson() => {
        'user_id': userId,
        'sec_user_id': secUserId,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'unique_id': uniqueId,
        'followers_count': followersCount,
        'followings_count': followingsCount,
        'aweme_count': awemeCount,
        'description': description,
      };

  factory DouyinUserPreview.fromJson(Map<String, dynamic> json) {
    return DouyinUserPreview(
      userId: '${json['user_id'] ?? ''}',
      secUserId: '${json['sec_user_id'] ?? ''}',
      nickname: '${json['nickname'] ?? '抖音用户'}',
      avatarUrl: '${json['avatar_url'] ?? ''}',
      uniqueId: '${json['unique_id'] ?? ''}',
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      followingsCount: (json['followings_count'] as num?)?.toInt() ?? 0,
      awemeCount: (json['aweme_count'] as num?)?.toInt() ?? 0,
      description: '${json['description'] ?? ''}',
    );
  }
}

class QrLoginSession {
  const QrLoginSession({
    required this.sid,
    required this.token,
    required this.qrcode,
    this.qrcodeIndexUrl = '',
  });

  final String sid;
  final String token;
  final String qrcode;
  final String qrcodeIndexUrl;
}

class CookieLoginStatus {
  const CookieLoginStatus({
    required this.status,
    this.statusText = '',
    this.cookie = '',
    this.cookieReady = false,
    this.verifyUrl = '',
    this.bootstrapCookie = '',
  });

  final String status;
  final String statusText;
  final String cookie;
  final bool cookieReady;
  final String verifyUrl;
  final String bootstrapCookie;

  bool get isConfirmed {
    // MFA 未完成时绝不当成功（即使带了半截 cookie）
    if (isMfa) return false;
    final s = status.toLowerCase().trim();
    final okStatus = s == '3' ||
        s == 'confirmed' ||
        s == 'done' ||
        s == 'success' ||
        s == 'ok';
    if (!okStatus) return false;
    return cookieReady ||
        cookie.contains('sessionid') ||
        cookie.contains('sid_tt=');
  }

  bool get isMfa {
    final s = status.toLowerCase().trim();
    if (s == 'mfa' || s == 'verify' || s == '2046') return true;
    if (s.contains('mfa') || s.contains('verify')) return true;
    final t = statusText;
    return t.contains('身份验证') ||
        t.contains('验证页') ||
        t.contains('二次验证') ||
        t.contains('2046');
  }
}

class DouyinChatConversation {
  const DouyinChatConversation({
    required this.index,
    required this.conversationId,
    required this.nickname,
    this.shortId = '',
    this.avatarUrl = '',
    this.uniqueId = '',
    this.peerUid = '',
    this.lastMessage = '',
    this.lastKind = 'text',
    this.lastThumbUrl = '',
    this.time = '',
    this.timeMs = 0,
    this.unread = false,
    this.spark = false,
    this.sparkDays = 0,
  });

  final int index;
  final String conversationId;
  final String shortId;
  final String nickname;
  final String avatarUrl;
  final String uniqueId;
  final String peerUid;
  final String lastMessage;
  final String lastKind;
  final String lastThumbUrl;
  final String time;
  final int timeMs;
  final bool unread;
  final bool spark;
  final int sparkDays;

  factory DouyinChatConversation.fromJson(Map<String, dynamic> json) {
    final days = (json['spark_days'] as num?)?.toInt() ?? 0;
    final timeMs = toEpochMs(json['time_ms'] ?? json['time']);
    return DouyinChatConversation(
      index: (json['index'] as num?)?.toInt() ?? 0,
      conversationId: '${json['conversation_id'] ?? ''}',
      shortId: '${json['short_id'] ?? ''}',
      nickname: '${json['nickname'] ?? '好友'}',
      avatarUrl: '${json['avatar_url'] ?? ''}',
      uniqueId: '${json['unique_id'] ?? ''}',
      peerUid: '${json['peer_uid'] ?? ''}',
      lastMessage: '${json['last_message'] ?? ''}',
      lastKind: '${json['last_kind'] ?? 'text'}',
      lastThumbUrl: '${json['last_thumb_url'] ?? ''}',
      time: '${json['time'] ?? ''}',
      timeMs: timeMs,
      unread: json['unread'] == true,
      spark: json['spark'] == true || days > 0,
      sparkDays: days,
    );
  }
}

class DouyinChatThread {
  const DouyinChatThread({
    required this.messages,
    this.selfAvatar = '',
    this.peerAvatar = '',
    this.peerNickname = '',
  });

  final List<DouyinChatMessage> messages;
  final String selfAvatar;
  final String peerAvatar;
  final String peerNickname;
}

class DouyinChatMessage {
  const DouyinChatMessage({
    required this.text,
    required this.isSelf,
    this.kind = 'text',
    this.senderUid = '',
    this.time = '',
    this.timeMs = 0,
    this.mediaUrl = '',
    this.thumbUrl = '',
    this.coverUrl = '',
    this.mediaFile = '',
    this.width = 0,
    this.height = 0,
    this.durationSec = 0,
    this.title = '',
    this.subtitle = '',
    this.link = '',
    this.awemeId = '',
    this.followers = 0,
    this.followStatus = '',
  });

  final String text;
  final bool isSelf;
  /// text | image | sticker | emoji | audio | video | card | profile | system | unknown
  final String kind;
  final String senderUid;
  final String time;
  final int timeMs;
  final String mediaUrl;
  final String thumbUrl;
  final String coverUrl;
  final String mediaFile;
  final int width;
  final int height;
  final int durationSec;
  final String title;
  final String subtitle;
  final String link;
  final String awemeId;
  final int followers;
  final String followStatus;

  String get displayImageUrl {
    if (thumbUrl.isNotEmpty) return thumbUrl;
    if (coverUrl.isNotEmpty) return coverUrl;
    return mediaUrl;
  }

  factory DouyinChatMessage.fromJson(Map<String, dynamic> json) {
    final timeMs = toEpochMs(
      json['time_ms'] ?? json['create_time'] ?? json['time'],
    );
    var awemeId = '${json['aweme_id'] ?? json['item_id'] ?? ''}'.trim();
    final link = '${json['link'] ?? ''}';
    if (awemeId.isEmpty) {
      awemeId = extractAwemeId(link);
    }

    return DouyinChatMessage(
      text: '${json['text'] ?? ''}',
      isSelf: json['is_self'] == true,
      kind: '${json['kind'] ?? 'text'}',
      senderUid: '${json['sender_uid'] ?? ''}',
      time: '${json['time'] ?? json['create_time'] ?? ''}',
      timeMs: timeMs,
      mediaUrl: '${json['media_url'] ?? ''}',
      thumbUrl: '${json['thumb_url'] ?? ''}',
      coverUrl: '${json['cover_url'] ?? ''}',
      mediaFile: '${json['media_file'] ?? ''}',
      width: asIntSafe(json['width']),
      height: asIntSafe(json['height']),
      durationSec: asIntSafe(json['duration_sec']),
      title: '${json['title'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
      link: normalizeDouyinWebLink(link, awemeId),
      awemeId: awemeId,
      followers: asIntSafe(json['followers']),
      followStatus: '${json['follow_status'] ?? ''}',
    );
  }
}

int asIntSafe(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

String extractAwemeId(String link) {
  final s = link.trim();
  if (s.isEmpty) return '';
  final patterns = <RegExp>[
    RegExp(r'aweme/detail/(\d{5,})'),
    RegExp(r'share/video/(\d{5,})'),
    RegExp(r'douyin\.com/video/(\d{5,})'),
    RegExp(r'iesdouyin\.com/share/video/(\d{5,})'),
    RegExp(r'snssdk\d+://[^/]*/(\d{15,})'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(s);
    if (m != null) return m.group(1)!;
  }
  final fallback = RegExp(r'(\d{15,})').firstMatch(s);
  return fallback?.group(1) ?? '';
}

String normalizeDouyinWebLink(String link, [String awemeId = '']) {
  final id = awemeId.isNotEmpty ? awemeId : extractAwemeId(link);
  if (id.isNotEmpty) return 'https://www.douyin.com/video/$id';
  final s = link.trim();
  if (s.startsWith('snssdk') || s.startsWith('aweme://')) return '';
  return s;
}

/// 续火花好友（勾选目标）
class DouyinSparkFriend {
  const DouyinSparkFriend({
    required this.nickname,
    this.conversationId = '',
    this.shortId = '',
    this.peerUid = '',
    this.peerSecUid = '',
    this.avatarUrl = '',
    this.lastMessage = '',
    this.spark = false,
    this.sparkDays = 0,
    this.sparkLevel = '',
    this.selected = false,
    this.targetId = 0,
    this.lastRenewAt = '',
    this.lastStatus = '',
  });

  final String conversationId;
  final String shortId;
  final String peerUid;
  final String peerSecUid;
  final String nickname;
  final String avatarUrl;
  final String lastMessage;
  final bool spark;
  final int sparkDays;
  final String sparkLevel;
  final bool selected;
  final int targetId;
  final String lastRenewAt;
  final String lastStatus;

  DouyinSparkFriend copyWith({bool? selected}) {
    return DouyinSparkFriend(
      nickname: nickname,
      conversationId: conversationId,
      shortId: shortId,
      peerUid: peerUid,
      peerSecUid: peerSecUid,
      avatarUrl: avatarUrl,
      lastMessage: lastMessage,
      spark: spark,
      sparkDays: sparkDays,
      sparkLevel: sparkLevel,
      selected: selected ?? this.selected,
      targetId: targetId,
      lastRenewAt: lastRenewAt,
      lastStatus: lastStatus,
    );
  }

  Map<String, dynamic> toSaveJson() => {
        'peer_uid': peerUid,
        'peer_sec_uid': peerSecUid,
        'peer_nickname': nickname,
        'conversation_id': conversationId,
        'short_id': shortId,
        'avatar_url': avatarUrl,
        'spark_days': sparkDays,
      };

  factory DouyinSparkFriend.fromJson(Map<String, dynamic> json) {
    final days = (json['spark_days'] as num?)?.toInt() ?? 0;
    return DouyinSparkFriend(
      conversationId: '${json['conversation_id'] ?? ''}',
      shortId: '${json['short_id'] ?? ''}',
      peerUid: '${json['peer_uid'] ?? ''}',
      peerSecUid: '${json['peer_sec_uid'] ?? ''}',
      nickname: '${json['nickname'] ?? json['peer_nickname'] ?? '好友'}',
      avatarUrl: '${json['avatar_url'] ?? ''}',
      lastMessage: '${json['last_message'] ?? ''}',
      spark: json['spark'] == true || days > 0,
      sparkDays: days,
      sparkLevel: '${json['spark_level'] ?? ''}',
      selected: json['selected'] == true || json['enabled'] == true,
      targetId: (json['target_id'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          0,
      lastRenewAt: '${json['last_renew_at'] ?? ''}',
      lastStatus: '${json['last_status'] ?? ''}',
    );
  }
}

class DouyinSparkFriendsResult {
  const DouyinSparkFriendsResult({
    required this.list,
    this.flame = 0,
    this.flameCostPer = 1,
    this.selectedCount = 0,
    this.hint = '',
  });

  final List<DouyinSparkFriend> list;
  final int flame;
  final int flameCostPer;
  final int selectedCount;
  final String hint;
}

class DouyinSparkRenewResult {
  const DouyinSparkRenewResult({
    required this.okCount,
    required this.failCount,
    required this.total,
    this.flame = 0,
    this.flameCostPer = 1,
    this.flameDeducted = 0,
    this.hint = '',
    this.results = const [],
  });

  final int okCount;
  final int failCount;
  final int total;
  final int flame;
  final int flameCostPer;
  final int flameDeducted;
  final String hint;
  final List<Map<String, dynamic>> results;
}

class DouyinWorkItem {
  const DouyinWorkItem({
    required this.awemeId,
    this.desc = '',
    this.cover = '',
    this.diggCount = 0,
    this.commentCount = 0,
    this.playCount = 0,
    this.category = 'video',
    this.createTime = 0,
    this.isPrivate = false,
  });

  final String awemeId;
  final String desc;
  final String cover;
  final int diggCount;
  final int commentCount;
  final int playCount;
  final String category;
  final int createTime;
  final bool isPrivate;

  factory DouyinWorkItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    final privateStatus = asInt(json['private_status']);
    final isPrivate = json['is_private'] == true ||
        json['is_private'] == 1 ||
        privateStatus > 0;

    return DouyinWorkItem(
      awemeId: '${json['aweme_id'] ?? ''}',
      desc: '${json['desc'] ?? ''}',
      cover: '${json['cover'] ?? ''}',
      diggCount: asInt(json['digg_count']),
      commentCount: asInt(json['comment_count']),
      playCount: asInt(json['play_count']),
      category: '${json['category'] ?? 'video'}',
      createTime: asInt(json['create_time']),
      isPrivate: isPrivate,
    );
  }
}

class DouyinNoticeItem {
  const DouyinNoticeItem({
    this.nid = '',
    this.groupLabel = '',
    this.text = '',
    this.createTime = 0,
    this.userNickname = '',
    this.userAvatar = '',
    this.awemeCover = '',
    this.mergeCount = 0,
  });

  final String nid;
  final String groupLabel;
  final String text;
  final int createTime;
  final String userNickname;
  final String userAvatar;
  final String awemeCover;
  final int mergeCount;

  factory DouyinNoticeItem.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    final user = json['user'];
    final userMap = user is Map ? Map<String, dynamic>.from(user) : null;
    final aweme = json['aweme'];
    final awemeMap = aweme is Map ? Map<String, dynamic>.from(aweme) : null;

    return DouyinNoticeItem(
      nid: '${json['nid'] ?? ''}',
      groupLabel: '${json['group_label'] ?? ''}',
      text: '${json['text'] ?? ''}',
      createTime: asInt(json['create_time']),
      userNickname: '${userMap?['nickname'] ?? ''}',
      userAvatar: '${userMap?['avatar_url'] ?? ''}',
      awemeCover: '${awemeMap?['cover'] ?? ''}',
      mergeCount: asInt(json['merge_count']),
    );
  }
}

class DouyinAccountDetail {
  const DouyinAccountDetail({
    required this.account,
    this.works = const [],
    this.totalFavorited = 0,
    this.liveError = '',
  });

  final DouyinAccount account;
  final List<DouyinWorkItem> works;
  final int totalFavorited;
  final String liveError;
}

class DouyinAwemePlay {
  const DouyinAwemePlay({
    this.awemeId = '',
    this.playUrl = '',
    this.playUrls = const [],
    this.cover = '',
    this.desc = '',
    this.webUrl = '',
    this.duration = 0,
    this.images = const [],
    this.isGallery = false,
  });

  final String awemeId;
  final String playUrl;
  final List<String> playUrls;
  final String cover;
  final String desc;
  final String webUrl;
  final int duration;
  final List<String> images;
  final bool isGallery;

  factory DouyinAwemePlay.fromJson(Map<String, dynamic> json) {
    final urls = <String>[];
    final raw = json['play_urls'];
    if (raw is List) {
      for (final u in raw) {
        final s = '$u'.trim();
        if (s.isNotEmpty) urls.add(s);
      }
    }
    final play = '${json['play_url'] ?? ''}'.trim();
    if (play.isNotEmpty && !urls.contains(play)) {
      urls.insert(0, play);
    }
    final images = <String>[];
    final imgs = json['images'];
    if (imgs is List) {
      for (final u in imgs) {
        final s = '$u'.trim();
        if (s.isNotEmpty) images.add(s);
      }
    }
    return DouyinAwemePlay(
      awemeId: '${json['aweme_id'] ?? ''}',
      playUrl: play.isNotEmpty ? play : (urls.isNotEmpty ? urls.first : ''),
      playUrls: urls,
      cover: '${json['cover'] ?? ''}',
      desc: '${json['desc'] ?? ''}',
      webUrl: '${json['web_url'] ?? ''}',
      duration: asIntSafe(json['duration']),
      images: images,
      isGallery: json['is_gallery'] == true ||
          json['is_gallery'] == 1 ||
          images.length > 1,
    );
  }
}
