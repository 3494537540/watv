import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/relative_time.dart';
import 'app_security.dart';

/// CMS 站内消息条目
class CmsMessageItem {
  const CmsMessageItem({
    required this.id,
    required this.title,
    required this.content,
    this.timeText = '',
    this.createdAt = 0,
    this.read = false,
    this.link = '',
    this.tag = '',
    this.subtitle = '',
    this.coverUrl = '',
    this.accent = '',
    this.style = 'normal',
  });

  final String id;
  final String title;
  final String content;
  final String timeText;
  final int createdAt;
  final bool read;
  /// 可选外链（哇TV 面板通知）
  final String link;
  final String tag;
  final String subtitle;
  final String coverUrl;
  /// #RRGGBB
  final String accent;
  /// normal / important / promo
  final String style;

  CmsMessageItem copyWith({
    bool? read,
    String? link,
    String? tag,
    String? subtitle,
    String? coverUrl,
    String? accent,
    String? style,
  }) =>
      CmsMessageItem(
        id: id,
        title: title,
        content: content,
        timeText: timeText,
        createdAt: createdAt,
        read: read ?? this.read,
        link: link ?? this.link,
        tag: tag ?? this.tag,
        subtitle: subtitle ?? this.subtitle,
        coverUrl: coverUrl ?? this.coverUrl,
        accent: accent ?? this.accent,
        style: style ?? this.style,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'timeText': timeText,
        'createdAt': createdAt,
        'read': read,
        'link': link,
        'tag': tag,
        'subtitle': subtitle,
        'coverUrl': coverUrl,
        'accent': accent,
        'style': style,
      };

  factory CmsMessageItem.fromJson(Map<String, dynamic> j) => CmsMessageItem(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        content: '${j['content'] ?? ''}',
        timeText: '${j['timeText'] ?? ''}',
        createdAt: int.tryParse('${j['createdAt'] ?? ''}') ??
            (j['createdAt'] is num ? (j['createdAt'] as num).toInt() : 0),
        read: j['read'] == true,
        link: '${j['link'] ?? ''}',
        tag: '${j['tag'] ?? ''}',
        subtitle: '${j['subtitle'] ?? ''}',
        coverUrl: '${j['coverUrl'] ?? j['cover_url'] ?? ''}',
        accent: '${j['accent'] ?? ''}',
        style: '${j['style'] ?? 'normal'}',
      );
}

/// MacCMS 站内会员（Cookie 会话）
class CmsUser {
  const CmsUser({
    required this.userId,
    required this.userName,
    this.nickName = '',
    this.email = '',
    this.qq = '',
    this.phone = '',
    this.portrait = '',
    this.points = 0,
    this.extend = 0,
    this.groupName = '',
    this.endTime = '',
  });

  final int userId;
  final String userName;
  final String nickName;
  final String email;
  final String qq;
  final String phone;
  final String portrait;
  final int points;
  /// 推广注册数（vfed: user_extend）
  final int extend;
  final String groupName;
  final String endTime;

  String get displayName {
    final n = nickName.trim();
    if (n.isNotEmpty && n != '会员') return n;
    final u = userName.trim();
    if (u.isNotEmpty && u != '会员') return u;
    return u.isEmpty ? '会员' : u;
  }

  String? get avatarUrl {
    final p = portrait.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    // 本机绝对路径：Windows盘符 / Android/iOS 文档目录选图
    final isLocal = (p.length > 2 && p[1] == ':') ||
        p.contains('\\') ||
        p.contains('/cms_avatar_') ||
        p.startsWith('/data/') ||
        p.startsWith('/var/') ||
        p.startsWith('/Users/') ||
        p.startsWith('/home/') ||
        p.startsWith('/private/var/');
    if (isLocal) return p;
    if (p.startsWith('/')) return '${ApiConfig.macCmsBase}$p';
    return '${ApiConfig.macCmsBase}/$p';
  }

  CmsUser copyWith({
    int? userId,
    String? userName,
    String? nickName,
    String? email,
    String? qq,
    String? phone,
    String? portrait,
    int? points,
    int? extend,
    String? groupName,
    String? endTime,
  }) {
    return CmsUser(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      nickName: nickName ?? this.nickName,
      email: email ?? this.email,
      qq: qq ?? this.qq,
      phone: phone ?? this.phone,
      portrait: portrait ?? this.portrait,
      points: points ?? this.points,
      extend: extend ?? this.extend,
      groupName: groupName ?? this.groupName,
      endTime: endTime ?? this.endTime,
    );
  }

  /// 用另一份资料补全空字段（不覆盖已有有效值）
  CmsUser merge(CmsUser other) {
    return CmsUser(
      userId: userId > 0 ? userId : other.userId,
      userName: _betterName(userName, other.userName),
      nickName: nickName.trim().isNotEmpty ? nickName : other.nickName,
      email: email.trim().isNotEmpty ? email : other.email,
      qq: qq.trim().isNotEmpty ? qq : other.qq,
      phone: phone.trim().isNotEmpty ? phone : other.phone,
      portrait: portrait.trim().isNotEmpty ? portrait : other.portrait,
      // 积分 / 推广：任一端解析到 ≥0 的明确值时，优先用「有标签解析」的更大可信来源
      points: _preferStat(points, other.points),
      extend: _preferStat(extend, other.extend),
      groupName: groupName.trim().isNotEmpty ? groupName : other.groupName,
      endTime: endTime.trim().isNotEmpty ? endTime : other.endTime,
    );
  }

  static int _preferStat(int a, int b) {
    if (a > 0) return a;
    if (b > 0) return b;
    return a;
  }

  static String _betterName(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.isNotEmpty && x != '会员') return x;
    if (y.isNotEmpty && y != '会员') return y;
    return x.isNotEmpty ? x : y;
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'user_name': userName,
        'user_nick_name': nickName,
        'user_email': email,
        'user_qq': qq,
        'user_phone': phone,
        'user_portrait': portrait,
        'user_points': points,
        'user_extend': extend,
        'group_name': groupName,
        'user_end_time': endTime,
      };

  factory CmsUser.fromJson(Map<String, dynamic> json) {
    return CmsUser(
      userId: (json['user_id'] as num?)?.toInt() ??
          int.tryParse('${json['user_id'] ?? 0}') ??
          0,
      userName: '${json['user_name'] ?? ''}',
      nickName: '${json['user_nick_name'] ?? json['user_nick'] ?? ''}',
      email: '${json['user_email'] ?? ''}',
      qq: '${json['user_qq'] ?? ''}',
      phone: '${json['user_phone'] ?? ''}',
      portrait: '${json['user_portrait'] ?? ''}',
      points: (json['user_points'] as num?)?.toInt() ??
          int.tryParse('${json['user_points'] ?? 0}') ??
          0,
      extend: (json['user_extend'] as num?)?.toInt() ??
          int.tryParse('${json['user_extend'] ?? 0}') ??
          0,
      groupName: '${json['group_name'] ?? json['user_group_name'] ?? ''}',
      endTime: '${json['user_end_time'] ?? ''}',
    );
  }
}

class CmsUlogItem {
  const CmsUlogItem({
    required this.id,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.typeName = '',
    this.link = '',
    this.timeText = '',
    this.playedAt = 0,
    this.episodeLabel = '',
    this.episodeNid = 0,
    this.progress = 0,
  });

  final String id;
  final String vodId;
  final String name;
  final String pic;
  final String remarks;
  final String typeName;
  final String link;
  /// 展示用时间文案（如 3分钟前）
  final String timeText;
  /// 毫秒时间戳，用于排序
  final int playedAt;
  /// 如「第3集」「HD」
  final String episodeLabel;
  final int episodeNid;
  /// 0~1 当前集播放进度
  final double progress;

  String? get coverUrl {
    final p = pic.trim();
    if (p.isEmpty) return null;
    final lower = p.toLowerCase();
    if (lower.contains('nopic') ||
        lower.contains('nopicture') ||
        lower.contains('no_pic') ||
        lower.endsWith('default.png') ||
        lower.endsWith('default.jpg')) {
      return null;
    }
    if (p.startsWith('//')) return 'https:$p';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.startsWith('/')) return '${ApiConfig.macCmsBase}$p';
    return '${ApiConfig.macCmsBase}/$p';
  }

  String get episodeDisplay {
    final e = episodeLabel.trim();
    if (e.isNotEmpty) return e;
    if (episodeNid > 0) return '第$episodeNid集';
    return '';
  }
}

class CmsUserException implements Exception {
  CmsUserException(this.message, {this.code = -1});
  final String message;
  final int code;
  @override
  String toString() => message;
}

class _CmsHttpResult {
  _CmsHttpResult({
    required this.statusCode,
    required this.bodyBytes,
    required this.cookies,
  });

  final int statusCode;
  final Uint8List bodyBytes;
  final List<Cookie> cookies;

  String get body => utf8.decode(bodyBytes);
}

/// 苹果 CMS 会员登录 / 收藏 / 播放记录
///
/// 使用 dart:io [HttpClient]，确保多个 Set-Cookie（PHPSESSID + user_id + user_name…）
/// 全部收入会话；package:http 在多 Cookie 场景下容易丢字段。
class MacCmsUserApi {
  MacCmsUserApi();

  static const _cookieKey = 'maccms_user_cookie';
  final Map<String, String> _cookieMap = {};

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  String? get sessionCookie {
    if (_cookieMap.isEmpty) return null;
    return _cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> loadCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_cookieKey);
    if (saved == null || saved.isEmpty) return;
    _applyCookieHeader(saved);
  }

  Future<void> _persistCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final c = sessionCookie;
    if (c == null || c.isEmpty) {
      await prefs.remove(_cookieKey);
    } else {
      await prefs.setString(_cookieKey, c);
    }
  }

  void _applyCookieHeader(String raw) {
    for (final p in raw.split(';')) {
      final s = p.trim();
      final i = s.indexOf('=');
      if (i <= 0) continue;
      final k = s.substring(0, i).trim();
      final v = s.substring(i + 1).trim();
      if (k.isEmpty) continue;
      // 跳过 Cookie 属性
      if ({'path', 'domain', 'expires', 'max-age', 'secure', 'httponly', 'samesite'}
          .contains(k.toLowerCase())) {
        continue;
      }
      _cookieMap[k] = v;
    }
  }

  void _mergeCookies(List<Cookie> cookies) {
    for (final c in cookies) {
      if (c.name.isEmpty) continue;
      _cookieMap[c.name] = c.value;
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${ApiConfig.macCmsBase}$path').replace(
      queryParameters: query,
    );
  }

  Future<_CmsHttpResult> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? form,
    bool asAjax = true,
  }) async {
    final client = HttpClient()
      ..userAgent = _ua
      ..connectionTimeout = const Duration(seconds: 12);
    AppSecurity.instance.hardenClient(client);
    try {
      final req = await client.openUrl(method, uri);
      if (asAjax) {
        req.headers.set(
          HttpHeaders.acceptHeader,
          'application/json, text/javascript, */*; q=0.01',
        );
        req.headers.set('X-Requested-With', 'XMLHttpRequest');
      } else {
        // 会员页 HTML（plays/favs）必须像浏览器一样请求，否则站点常返回 JSON 空壳
        req.headers.set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        );
      }
      req.headers.set(HttpHeaders.refererHeader, '${ApiConfig.macCmsBase}/');
      final cookie = sessionCookie;
      if (cookie != null && cookie.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      headers?.forEach((k, v) => req.headers.set(k, v));

      if (form != null) {
        final body = form.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&');
        final bytes = utf8.encode(body);
        req.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded',
        );
        req.contentLength = bytes.length;
        req.add(bytes);
      }

      final res = await req.close().timeout(const Duration(seconds: 20));
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      final cookies = List<Cookie>.from(res.cookies);
      res.headers.forEach((name, values) {
        if (name.toLowerCase() != 'set-cookie') return;
        for (final v in values) {
          try {
            cookies.add(Cookie.fromSetCookieValue(v));
          } catch (_) {
            final nv = v.split(';').first;
            final i = nv.indexOf('=');
            if (i > 0) {
              cookies.add(
                Cookie(nv.substring(0, i).trim(), nv.substring(i + 1).trim()),
              );
            }
          }
        }
      });
      _mergeCookies(cookies);
      await _persistCookie();
      return _CmsHttpResult(
        statusCode: res.statusCode,
        bodyBytes: builder.takeBytes(),
        cookies: cookies,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> fetchCaptcha() async {
    final res = await _request(
      'GET',
      _uri('/index.php/verify/index.html', {
        'r': '${DateTime.now().millisecondsSinceEpoch}',
      }),
    );
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw CmsUserException('验证码获取失败');
    }
    return res.bodyBytes;
  }

  Future<CmsUser> login({
    required String userName,
    required String password,
    required String verify,
  }) async {
    final res = await _request(
      'POST',
      _uri('/index.php/user/login.html'),
      form: {
        'user_name': userName.trim(),
        'user_pwd': password,
        'verify': verify.trim(),
      },
    );
    final data = _decodeJsonBody(res.body);
    final code = int.tryParse('${data['code']}') ?? -1;
    final msg = '${data['msg'] ?? '登录失败'}';
    if (code != 1) throw CmsUserException(msg, code: code);

    // 登录账号名兜底（站点 Cookie / HTML 解析失败时仍能显示）
    final fallback = CmsUser(
      userId: int.tryParse(_cookieMap['user_id'] ?? '') ?? 0,
      userName: userName.trim(),
    );
    try {
      final profile = await fetchProfile();
      return profile.merge(fallback).merge(_userFromCookies() ?? fallback);
    } catch (_) {
      final fromCookie = _userFromCookies();
      if (fromCookie != null) return fromCookie.merge(fallback);
      return fallback;
    }
  }

  Future<void> register({
    required String userName,
    required String password,
    required String password2,
    required String verify,
  }) async {
    final res = await _request(
      'POST',
      _uri('/index.php/user/reg.html'),
      form: {
        'user_name': userName.trim(),
        'user_pwd': password,
        'user_pwd2': password2,
        'verify': verify.trim(),
      },
    );
    final data = _decodeJsonBody(res.body);
    final code = int.tryParse('${data['code']}') ?? -1;
    final msg = '${data['msg'] ?? '注册失败'}';
    if (code != 1) throw CmsUserException(msg, code: code);
  }

  Future<void> logout() async {
    try {
      await _request('GET', _uri('/index.php/user/logout.html'));
    } catch (_) {}
    _cookieMap.clear();
    await _persistCookie();
  }

  /// 拉取会员中心资料（需已登录 Cookie）
  Future<CmsUser> fetchProfile() async {
    await loadCookie();
    final res = await _request(
      'GET',
      _uri('/index.php/user/index.html'),
      asAjax: false,
    );
    final raw = res.body.trim();
    _ensureLoggedInPayload(raw);

    final fromCookie = _userFromCookies();
    final fromHtml = _parseUserHtml(raw);
    final fromInfo = await _tryFetchInfoHtml();

    var user = (fromCookie ?? const CmsUser(userId: 0, userName: ''))
        .merge(fromHtml)
        .merge(fromInfo ?? const CmsUser(userId: 0, userName: ''));

    if (user.userName.trim().isEmpty || user.userName == '会员') {
      if (fromCookie != null && fromCookie.userName.isNotEmpty) {
        user = user.copyWith(userName: fromCookie.userName);
      }
    }
    if (user.userId == 0 &&
        (user.userName.isEmpty || user.userName == '会员') &&
        user.points == 0) {
      if (raw.contains('fed-user-login') || raw.contains('name="user_pwd"')) {
        throw CmsUserException('未登录', code: 401);
      }
    }
    if (user.userName.trim().isEmpty) {
      user = user.copyWith(userName: '会员');
    }
    return user;
  }

  Future<CmsUser?> _tryFetchInfoHtml() async {
    try {
      final res = await _request(
        'GET',
        _uri('/index.php/user/info.html'),
        asAjax: false,
      );
      final raw = res.body.trim();
      if (raw.contains('"code":0') && raw.contains('未登录')) return null;
      return _parseUserHtml(raw);
    } catch (_) {
      return null;
    }
  }

  /// 更新会员资料（兼容常见 MacCMS 表单字段）
  Future<void> updateInfo({
    String? nickName,
    String? portrait,
    String? qq,
    String? email,
  }) async {
    await loadCookie();
    final form = <String, String>{};
    if (nickName != null && nickName.trim().isNotEmpty) {
      form['user_nick_name'] = nickName.trim();
      form['user_nick'] = nickName.trim();
    }
    if (portrait != null &&
        portrait.trim().isNotEmpty &&
        (portrait.startsWith('http://') || portrait.startsWith('https://'))) {
      form['user_portrait'] = portrait.trim();
    }
    if (qq != null) form['user_qq'] = qq.trim();
    if (email != null) form['user_email'] = email.trim();
    if (form.isEmpty) return;

    final res = await _request(
      'POST',
      _uri('/index.php/user/info.html'),
      form: form,
      asAjax: true,
    );
    final raw = res.body.trim();
    if (raw.contains('未登录') || raw.contains('"code":0')) {
      // 部分主题用非 ajax；再试一次 HTML 提交
      final res2 = await _request(
        'POST',
        _uri('/index.php/user/info.html'),
        form: form,
        asAjax: false,
      );
      final raw2 = res2.body.trim();
      if (raw2.contains('未登录')) {
        throw CmsUserException('未登录', code: 401);
      }
    }
  }

  /// 列表 kind（本 App 约定）：1=收藏页 2=点播页
  /// MacCMS ajax type：1浏览 2收藏 3想看 4点播 5下载
  static const ulogBrowse = 1;
  static const ulogFav = 2;
  static const ulogWish = 3;
  static const ulogPlay = 4;
  static const ulogDown = 5;

  /// 把 App 列表 kind 映射为 CMS ajax `type`
  static int cmsUlogType(int listKind) {
    if (listKind == 1) return ulogFav;
    if (listKind == 2) return ulogPlay;
    return listKind;
  }

  /// [type] 传 App 列表 kind：1收藏 / 2点播（内部会映射 CMS type）
  /// HTML 列表无封面时，会再拉 ajax 合并 `vod_pic`
  Future<List<CmsUlogItem>> fetchUlog({
    required int type,
    int page = 1,
    int limit = 24,
  }) async {
    await loadCookie();

    List<CmsUlogItem> fromPage = const [];
    if (type == 1 || type == 2) {
      final path = type == 1
          ? '/index.php/user/favs.html'
          : '/index.php/user/plays.html';
      final pageRes = await _request('GET', _uri(path), asAjax: false);
      final html = pageRes.body;
      _ensureLoggedInPayload(html);
      fromPage = _parseUlogHtml(html);
    }

    final cmsType = cmsUlogType(type);
    final fromAjax = await _fetchUlogAjaxList(
      cmsType: cmsType,
      page: page,
      limit: limit,
    );

    if (fromPage.isEmpty) {
      return fromAjax.take(limit).toList();
    }

    // HTML 有条目但通常无封面 → 用 ajax / 同 id 补全 pic、时间等
    final byId = <String, CmsUlogItem>{
      for (final e in fromAjax)
        if (e.vodId.isNotEmpty) e.vodId: e,
    };
    return [
      for (final p in fromPage.take(limit))
        () {
          final a = byId[p.vodId];
          if (a == null) return p;
          return CmsUlogItem(
            id: p.id,
            vodId: p.vodId,
            name: p.name.trim().isNotEmpty && !p.name.startsWith('影片')
                ? p.name
                : (a.name.trim().isNotEmpty ? a.name : p.name),
            pic: p.pic.trim().isNotEmpty && !p.pic.toLowerCase().contains('nopic')
                ? p.pic
                : a.pic,
            remarks: p.remarks.trim().isNotEmpty ? p.remarks : a.remarks,
            typeName:
                p.typeName.trim().isNotEmpty ? p.typeName : a.typeName,
            link: p.link.trim().isNotEmpty ? p.link : a.link,
            timeText:
                a.timeText.trim().isNotEmpty ? a.timeText : p.timeText,
            playedAt: a.playedAt > 0 ? a.playedAt : p.playedAt,
            episodeLabel: p.episodeLabel.trim().isNotEmpty
                ? p.episodeLabel
                : a.episodeLabel,
            episodeNid: p.episodeNid > 0 ? p.episodeNid : a.episodeNid,
            progress: p.progress > 0 ? p.progress : a.progress,
          );
        }(),
    ];
  }

  Future<List<CmsUlogItem>> _fetchUlogAjaxList({
    required int cmsType,
    int page = 1,
    int limit = 24,
  }) async {
    final res = await _request(
      'GET',
      _uri('/index.php/user/ajax_ulog/', {
        'ac': 'list',
        'mid': '1',
        'id': '0',
        'type': '$cmsType',
        'page': '$page',
        'limit': '$limit',
      }),
      asAjax: true,
    );
    final raw = res.body.trim();
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final code = int.tryParse('${decoded['code']}') ?? -1;
        final msg = '${decoded['msg'] ?? ''}';
        if (code == 0 && (msg.contains('未登录') || msg.contains('登录'))) {
          throw CmsUserException('未登录', code: 401);
        }
        if (code == 1) {
          dynamic list = decoded['list'] ?? decoded['data'];
          if (list is Map) {
            list = list['list'] ?? list['data'] ?? list['info'];
          }
          if (list is List) {
            return [
              for (final e in list)
                if (e is Map) _ulogFromMap(Map<String, dynamic>.from(e)),
            ].where((e) => e.vodId.isNotEmpty || e.name.isNotEmpty).toList();
          }
          return const [];
        }
      }
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is Map) _ulogFromMap(Map<String, dynamic>.from(e)),
        ].where((e) => e.vodId.isNotEmpty || e.name.isNotEmpty).toList();
      }
    } on CmsUserException {
      rethrow;
    } catch (_) {}
    return const [];
  }

  /// [type] 必须用 CMS 常量：ulogFav=2 / ulogPlay=4 等
  Future<void> setUlog({
    required String vodId,
    required int type,
    int sid = 0,
    int nid = 0,
  }) async {
    await loadCookie();
    final res = await _request(
      'GET',
      _uri('/index.php/user/ajax_ulog/', {
        'ac': 'set',
        'mid': '1',
        'id': vodId,
        'type': '$type',
        'sid': '$sid',
        'nid': '$nid',
      }),
      asAjax: true,
    );
    final raw = res.body.trim();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final code = int.tryParse('${decoded['code']}') ?? -1;
        final msg = '${decoded['msg'] ?? ''}';
        if (code == 0 && (msg.contains('未登录') || msg.contains('登录'))) {
          throw CmsUserException('未登录', code: 401);
        }
        if (code == 0 && msg.isNotEmpty) {
          throw CmsUserException(msg);
        }
      }
    } on CmsUserException {
      rethrow;
    } catch (_) {}
  }

  /// 删除会员记录（收藏等）。[ids] 为 ulog_id，逗号分隔；[type] 列表类型 2=收藏
  Future<void> delUlog({
    required String ids,
    int type = 2,
    bool clearAll = false,
  }) async {
    await loadCookie();
    final res = await _request(
      'POST',
      _uri('/index.php/user/ulog_del'),
      form: {
        'ids': ids,
        'type': '$type',
        'all': clearAll ? '1' : '0',
      },
      asAjax: true,
    );
    final raw = res.body.trim();
    if (raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final code = int.tryParse('${decoded['code']}') ?? -1;
        final msg = '${decoded['msg'] ?? ''}';
        if (code == 0 && (msg.contains('未登录') || msg.contains('登录'))) {
          throw CmsUserException('未登录', code: 401);
        }
        if (code == 0 && msg.isNotEmpty) {
          throw CmsUserException(msg);
        }
      }
    } on CmsUserException {
      rethrow;
    } catch (_) {}
  }

  /// 更新播放量（站点统计；与会员播放记录无关）
  Future<void> updateHits({required String vodId}) async {
    await loadCookie();
    try {
      await _request(
        'GET',
        _uri('/index.php/ajax/hits', {
          'mid': '1',
          'id': vodId,
          'type': 'update',
        }),
        asAjax: true,
      );
    } catch (_) {
      try {
        await _request(
          'GET',
          _uri('/index.php/ajax/hits.html', {
            'mid': '1',
            'id': vodId,
            'type': 'update',
          }),
          asAjax: true,
        );
      } catch (_) {}
    }
  }

  void _ensureLoggedInPayload(String raw) {
    final t = raw.trim();
    if (t.startsWith('{')) {
      try {
        final j = jsonDecode(t);
        if (j is Map) {
          final code = int.tryParse('${j['code']}') ?? -1;
          final msg = '${j['msg'] ?? ''}';
          if (code == 0 && (msg.contains('未登录') || msg.contains('登录'))) {
            throw CmsUserException('未登录', code: 401);
          }
        }
      } on CmsUserException {
        rethrow;
      } catch (_) {}
    }
    if (t.contains('"msg":"未登录"') || t.contains('data-msg="未登录"')) {
      throw CmsUserException('未登录', code: 401);
    }
  }

  Map<String, dynamic> _decodeJsonBody(String raw) {
    final t = raw.trim();
    try {
      final decoded = jsonDecode(t);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (t.contains('成功')) return {'code': 1, 'msg': '成功'};
    throw CmsUserException('服务器返回异常');
  }

  CmsUser? _userFromCookies() {
    String dec(String? v) {
      if (v == null || v.isEmpty) return '';
      try {
        return Uri.decodeComponent(v.replaceAll('+', ' '));
      } catch (_) {
        return v;
      }
    }

    final id = int.tryParse(_cookieMap['user_id'] ?? '') ?? 0;
    final name = dec(_cookieMap['user_name']);
    final group = dec(_cookieMap['group_name']);
    final portrait = dec(_cookieMap['user_portrait']);
    if (id == 0 && name.isEmpty) return null;
    return CmsUser(
      userId: id,
      userName: name.isEmpty ? '会员' : name,
      groupName: group,
      portrait: portrait,
    );
  }

  CmsUlogItem _ulogFromMap(Map<String, dynamic> m) {
    final data = m['data'];
    final vod = data is Map ? Map<String, dynamic>.from(data) : m;
    final typeMap = vod['type'];
    final typeName = typeMap is Map
        ? '${typeMap['type_name'] ?? ''}'
        : '${vod['type_name'] ?? ''}';
    final vodId =
        '${vod['vod_id'] ?? m['ulog_rid'] ?? vod['id'] ?? m['id'] ?? ''}'
            .trim();
    final name =
        '${vod['vod_name'] ?? vod['name'] ?? m['name'] ?? ''}'.trim();
    final pic =
        '${vod['vod_pic'] ?? vod['pic'] ?? m['pic'] ?? ''}'.trim();
    final link = '${vod['link'] ?? m['link'] ?? ''}'.trim();
    final linkId = RegExp(r'/id/(\d+)').firstMatch(link)?.group(1);
    return CmsUlogItem(
      id: '${m['ulog_id'] ?? m['id'] ?? vodId}',
      vodId: vodId.isNotEmpty ? vodId : (linkId ?? ''),
      name: name.isEmpty ? '未命名' : name,
      pic: pic,
      remarks: '${vod['vod_remarks'] ?? vod['remarks'] ?? ''}'.trim(),
      typeName: typeName.trim(),
      link: link,
      timeText: _ulogTimeText(m),
      playedAt: _ulogPlayedAt(m),
    );
  }

  static int _ulogPlayedAt(Map<String, dynamic> m) {
    final t = m['ulog_time'] ?? m['time'] ?? m['create_time'];
    if (t is num) {
      final n = t.toInt();
      // 秒级时间戳
      if (n > 1000000000 && n < 100000000000) return n * 1000;
      return n;
    }
    final s = '$t'.trim();
    if (s.isEmpty) return 0;
    final asInt = int.tryParse(s);
    if (asInt != null) {
      if (asInt > 1000000000 && asInt < 100000000000) return asInt * 1000;
      return asInt;
    }
    final dt = DateTime.tryParse(s);
    return dt?.millisecondsSinceEpoch ?? 0;
  }

  static String _ulogTimeText(Map<String, dynamic> m) {
    final ms = _ulogPlayedAt(m);
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return '今天 $hm';
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hm';
    if (dt.year == now.year) return '${dt.month}月${dt.day}日';
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  /// 解析 vfed 会员中心 HTML（banner: 积分 / 等级 / 推广）
  CmsUser _parseUserHtml(String html) {
    if (html.trim().startsWith('{')) {
      return const CmsUser(userId: 0, userName: '');
    }

    String pick(List<String> patterns, [String def = '']) {
      for (final p in patterns) {
        final m = RegExp(p, caseSensitive: false).firstMatch(html);
        if (m != null) {
          final g = _strip(m.group(1) ?? '');
          if (g.isNotEmpty) return g;
        }
      }
      return def;
    }

    final name = pick([
      r'fed-text-white[^>]*>([^<]{1,32})</span>',
      r'用户名</span>\s*<span[^>]*>\s*([^<]{1,32})\s*</span>',
      r'账号[：:]\s*(?:<[^>]+>\s*)*([^\s<]{2,32})',
    ]);

    // vfed brief：按标签精确取值，避免积分/推广串号
    var points = 0;
    var extend = 0;
    var group = '';
    final brief = RegExp(
      r'fed-user-brief[\s\S]*?</ul>',
      caseSensitive: false,
    ).firstMatch(html)?.group(0);
    final scope = brief ?? html;
    for (final m in RegExp(
      r'<li\b[^>]*>[\s\S]*?fed-text-gules[^>]*>([^<]*)</span>\s*<span[^>]*>([^<]*)</span>',
      caseSensitive: false,
    ).allMatches(scope)) {
      final value = _strip(m.group(1) ?? '');
      final label = _strip(m.group(2) ?? '');
      if (label.contains('积分')) {
        points = int.tryParse(value) ?? points;
      } else if (label.contains('等级') || label.contains('会员')) {
        if (value.isNotEmpty) group = value;
      } else if (label.contains('推广')) {
        extend = int.tryParse(value) ?? extend;
      }
    }
    if (points == 0) {
      points = int.tryParse(pick([
            r'>(\d+)</span>\s*<span[^>]*>\s*我的积分',
            r'(\d+)\s*积分',
            r'积分[：:]\s*(?:<[^>]+>\s*)*(\d+)',
          ], '0')) ??
          0;
    }
    if (extend == 0) {
      extend = int.tryParse(pick([
            r'>(\d+)</span>\s*<span[^>]*>\s*推广注册',
            r'(\d+)\s*关注者',
            r'推广注册[：:]\s*(?:<[^>]+>\s*)*(\d+)',
          ], '0')) ??
          0;
    }
    if (group.isEmpty) {
      group = pick([
        r'>([^<]{1,32})</span>\s*<span[^>]*>\s*我的等级',
        r'会员组[：:]\s*(?:<[^>]+>\s*)*([^\s<]{1,32})',
      ]);
    }

    final portrait = pick([
      r'''fed-user-avat[^>]+src=["']([^"']+)["']''',
      r'class="[^"]*avatar[^"]*"\s+src="([^"]+)"',
    ]);
    final email = pick([
      r'''name=["']user_email["'][^>]*value=["']([^"']+)["']''',
    ]);
    final phone = pick([
      r'''name=["']user_phone["'][^>]*value=["'](\d{5,15})["']''',
    ]);
    final id = int.tryParse(pick([
          r'user_id\W{0,6}(\d+)',
          r'UID[：:]\s*(?:<[^>]+>\s*)*(\d+)',
        ], '0')) ??
        0;

    return CmsUser(
      userId: id,
      userName: name,
      email: email,
      phone: phone,
      portrait: portrait,
      points: points,
      extend: extend,
      groupName: group,
    );
  }

  List<CmsUlogItem> _parseUlogHtml(String html) {
    final list = <CmsUlogItem>[];
    final seen = <String>{};

    void addItem({
      required String id,
      required String name,
      String pic = '',
      String typeName = '',
      String link = '',
      int episodeNid = 0,
    }) {
      final vodId = id.trim();
      if (vodId.isEmpty || !RegExp(r'^\d+$').hasMatch(vodId)) return;
      if (!seen.add(vodId)) return;
      final title = name.trim();
      list.add(
        CmsUlogItem(
          id: vodId,
          vodId: vodId,
          name: title.isEmpty ? '影片$vodId' : title,
          pic: pic,
          typeName: typeName.trim(),
          link: link,
          episodeNid: episodeNid,
          episodeLabel: episodeNid > 0 ? '第$episodeNid集' : '',
        ),
      );
    }

    // 只解析会员列表区域，避免页脚 / 推荐误匹配
    var scope = html;
    final listScope = RegExp(
      r'fed-user-list[\s\S]*?(?=fed-page|fed-foot|</form>|</body>)',
      caseSensitive: false,
    ).firstMatch(html);
    if (listScope != null) {
      scope = listScope.group(0) ?? html;
    } else {
      final formScope = RegExp(
        r'''name=["']ids\[\]["'][\s\S]{0,800}''',
        caseSensitive: false,
      ).allMatches(html);
      if (formScope.isNotEmpty) {
        scope = formScope.map((m) => m.group(0) ?? '').join('\n');
      }
    }

    // 每一条：checkbox + 链接  [类型] 片名? [rid-sid-nid]
    for (final m in RegExp(
      r'''name=["']ids\[\]["'][^>]*value=["'](\d+)["'][\s\S]{0,400}?href=["']([^"']+)["'][^>]*>\s*\[([^\]]*)\]\s*([^<]*?)\s*\[(\d+)\s*-\s*(\d+)\s*-\s*(\d+)\]''',
      caseSensitive: false,
    ).allMatches(scope)) {
      final link = m.group(2) ?? '';
      final typeName = _strip(m.group(3) ?? '');
      var name = _strip(m.group(4) ?? '');
      name = name.replaceAll(RegExp(r'^\[|\]$'), '').trim();
      final rid = m.group(5) ?? '';
      final nid = int.tryParse(m.group(7) ?? '') ?? 0;
      final idFromLink =
          RegExp(r'/id/(\d+)').firstMatch(link)?.group(1) ?? rid;
      addItem(
        id: idFromLink,
        name: name,
        typeName: typeName,
        link: link,
        episodeNid: nid,
      );
    }

    if (list.isNotEmpty) return list;

    // 退一步：列表区内的 a 标签
    for (final m in RegExp(
      r'''<a\b[^>]*href=["']([^"']*(?:/vod/|/id/)[^"']*)["'][^>]*>\s*\[([^\]]*)\]\s*([^<]*?)\s*\[(\d+)\s*-\s*(\d+)\s*-\s*(\d+)\]\s*</a>''',
      caseSensitive: false,
    ).allMatches(scope)) {
      final link = m.group(1) ?? '';
      final typeName = _strip(m.group(2) ?? '');
      var name = _strip(m.group(3) ?? '');
      name = name.replaceAll(RegExp(r'^\[|\]$'), '').trim();
      final rid = m.group(4) ?? '';
      final nid = int.tryParse(m.group(6) ?? '') ?? 0;
      final idFromLink =
          RegExp(r'/id/(\d+)').firstMatch(link)?.group(1) ?? rid;
      addItem(
        id: idFromLink,
        name: name,
        typeName: typeName,
        link: link,
        episodeNid: nid,
      );
    }

    return list;
  }

  /// 站内消息：优先 ajax JSON，其次 msgs.html 解析
  Future<List<CmsMessageItem>> fetchMessages() async {
    final out = <CmsMessageItem>[];
    try {
      final ajax = await _request(
        'GET',
        _uri('/index.php/user/ajax_msg/', {'ac': 'list'}),
        asAjax: true,
      );
      final decoded = _tryJson(ajax.body);
      if (decoded != null) {
        final list = decoded['list'] ?? decoded['data'] ?? decoded['msg'];
        if (list is List) {
          for (final e in list) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            final id = '${m['msg_id'] ?? m['id'] ?? ''}'.trim();
            final title =
                '${m['msg_title'] ?? m['title'] ?? m['name'] ?? ''}'.trim();
            final content =
                '${m['msg_content'] ?? m['content'] ?? m['text'] ?? ''}'
                    .trim();
            final cleanTitle = _cleanNoticeText(title);
            final cleanContent = _cleanNoticeText(content);
            if (id.isEmpty && cleanTitle.isEmpty && cleanContent.isEmpty) {
              continue;
            }
            if ((cleanTitle.isNotEmpty && _looksLikeHtmlJunk(cleanTitle)) ||
                (cleanContent.isNotEmpty &&
                    _looksLikeHtmlJunk(cleanContent))) {
              continue;
            }
            final status = (m['msg_status'] as num?)?.toInt() ??
                (m['status'] as num?)?.toInt() ??
                0;
            final timeRaw = m['msg_time'] ?? m['time'] ?? m['create_time'];
            final createdAt = _parseTimeMs(timeRaw);
            var timeText = '';
            if (createdAt > 0) {
              timeText = formatAgo(createdAt);
            } else {
              timeText = '$timeRaw'.trim();
              if (RegExp(r'^\d{9,13}$').hasMatch(timeText)) {
                timeText = '';
              }
            }
            out.add(
              CmsMessageItem(
                id: id.isEmpty ? 'm${out.length}' : id,
                title: cleanTitle.isEmpty ? '站内通知' : cleanTitle,
                content: cleanContent,
                timeText: timeText,
                createdAt: createdAt,
                // MacCMS：0 未读，1 已读
                read: status == 1,
              ),
            );
          }
        }
      }
    } catch (_) {}

    if (out.isNotEmpty) return out;

    try {
      final page = await _request(
        'GET',
        _uri('/index.php/user/msgs.html'),
        asAjax: false,
      );
      out.addAll(_parseMsgsHtml(page.body));
    } catch (_) {}

    if (out.isNotEmpty) return out;

    // 不再抓取留言本 HTML（易解析成 class= 脏数据）；交给本地系统通知兜底
    return out;
  }

  List<CmsMessageItem> _parseMsgsHtml(String html) {
    final out = <CmsMessageItem>[];
    // 常见：标题 + 时间 + 正文块
    final blocks = RegExp(
      r'''<(?:li|div)[^>]*(?:msg|message|notice)[^>]*>[\s\S]*?</(?:li|div)>''',
      caseSensitive: false,
    ).allMatches(html);
    for (final b in blocks) {
      final chunk = b.group(0) ?? '';
      final title = _firstMatch(
            chunk,
            [
              r'''class=["'][^"']*title[^"']*["'][^>]*>([^<]+)''',
              r'''<(?:h[1-6]|strong|b)[^>]*>([^<]{2,80})</''',
            ],
          ) ??
          '';
      final content = _strip(
        _firstMatch(
              chunk,
              [
                r'''class=["'][^"']*(?:content|cont|text|body)[^"']*["'][^>]*>([\s\S]*?)</''',
              ],
            ) ??
            '',
      );
      final time = _firstMatch(
            chunk,
            [
              r'''class=["'][^"']*time[^"']*["'][^>]*>([^<]+)''',
              r'''(\d{4}[-/]\d{1,2}[-/]\d{1,2}[^\d<]*)''',
            ],
          ) ??
          '';
      final cleanTitle = _strip(title);
      final cleanContent = _cleanNoticeText(content);
      if (cleanTitle.isEmpty && cleanContent.isEmpty) continue;
      if (_looksLikeHtmlJunk(cleanTitle) || _looksLikeHtmlJunk(cleanContent)) {
        continue;
      }
      out.add(
        CmsMessageItem(
          id: 'html_${out.length}_${cleanTitle.hashCode}',
          title: cleanTitle.isEmpty ? '站内通知' : cleanTitle,
          content: cleanContent,
          timeText: _strip(time),
          createdAt: _parseTimeMs(time),
          read: chunk.contains('已读') || chunk.contains('read'),
        ),
      );
      if (out.length >= 40) break;
    }
    return out;
  }

  static bool _looksLikeHtmlJunk(String s) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return true;
    if (t.contains('class=') ||
        t.contains('name=') ||
        t.contains('data-') ||
        t.contains('aria-') ||
        t.contains('<') ||
        t.contains('gbook_') ||
        t.contains('cmt-')) {
      return true;
    }
    return false;
  }

  static String _cleanNoticeText(String raw) {
    var t = _strip(raw);
    t = t
        .replaceAll(RegExp(r'''class=["'][^"']*["']'''), ' ')
        .replaceAll(RegExp(r'''name=["'][^"']*["']'''), ' ')
        .replaceAll(RegExp(r'''data-[a-z-]+=["'][^"']*["']'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_looksLikeHtmlJunk(t)) return '';
    return t;
  }

  // ignore: unused_element
  List<CmsMessageItem> _parseGbookAsNotices(String html) {
    return const [];
  }

  static String? _firstMatch(String src, List<String> patterns) {
    for (final p in patterns) {
      final m = RegExp(p, caseSensitive: false).firstMatch(src);
      final g = m?.group(1)?.trim();
      if (g != null && g.isNotEmpty) return g;
    }
    return null;
  }

  static int _parseTimeMs(Object? raw) {
    if (raw == null) return 0;
    if (raw is num) {
      final n = raw.toInt();
      if (n > 1000000000000) return n;
      if (n > 1000000000) return n * 1000;
      return n;
    }
    final s = '$raw'.trim();
    final asInt = int.tryParse(s);
    if (asInt != null) return _parseTimeMs(asInt);
    final dt = DateTime.tryParse(s.replaceAll('/', '-'));
    return dt?.millisecondsSinceEpoch ?? 0;
  }

  Map<String, dynamic>? _tryJson(String raw) {
    final t = raw.trim();
    if (t.isEmpty || !(t.startsWith('{') || t.startsWith('['))) return null;
    try {
      final decoded = jsonDecode(t);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) return {'list': decoded};
    } catch (_) {}
    return null;
  }

  static String _strip(String raw) => raw
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
