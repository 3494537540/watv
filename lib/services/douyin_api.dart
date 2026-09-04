import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_models.dart';
import '../models/douyin_models.dart';
import '../state/auth_controller.dart';

class DouyinApi {
  DouyinApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _admin(String action) {
    final base = ApiConfig.baseUrl;
    final sep = base.contains('?') ? '&' : '?';
    return Uri.parse('$base${sep}action=${Uri.encodeQueryComponent(action)}');
  }

  Uri _cookie(String action, [Map<String, String>? query]) {
    final q = <String, String>{
      'action': action,
      ...?query,
    };
    return Uri.parse(ApiConfig.cookieApi).replace(queryParameters: q);
  }

  Future<Map<String, dynamic>> _decode(http.Response res) async {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) throw ApiException('服务器返回格式异常');
      json = Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('服务器返回无法解析（HTTP ${res.statusCode}）');
    }
    final code = (json['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw ApiException('${json['msg'] ?? '请求失败'}', code: code);
    }
    final data = json['data'];
    if (data == null) return <String, dynamic>{};
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{'value': data};
  }

  Future<Map<String, dynamic>> _adminPost(
    String action,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final token = AuthController.instance.token;
    if (token == null || token.isEmpty) {
      throw ApiException('请先登录', code: 401);
    }
    late http.Response res;
    try {
      res = await _client
          .post(
            _admin(action),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              ...body,
              'client': ApiConfig.client,
              'token': token,
            }),
          )
          .timeout(timeout);
    } catch (_) {
      throw ApiException('网络连接失败，请检查接口地址与服务是否启动');
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _adminGet(String action) async {
    final token = AuthController.instance.token;
    if (token == null || token.isEmpty) {
      throw ApiException('请先登录', code: 401);
    }
    late http.Response res;
    try {
      res = await _client
          .get(
            _admin(action),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw ApiException('网络连接失败，请检查接口地址与服务是否启动');
    }
    return _decode(res);
  }

  Future<List<DouyinAccount>> myList() async {
    final data = await _adminGet('douyin_my_list');
    final list = data['list'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => DouyinAccount.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 账号详情：实时概览 + 作品预览（不含私信，较快）
  Future<DouyinAccountDetail> myGet({
    required int accountId,
    int worksCount = 6,
  }) async {
    final data = await _adminPost(
      'douyin_my_get',
      {
        'id': accountId,
        'works_count': worksCount,
      },
      timeout: const Duration(seconds: 45),
    );
    final accountRaw = data['account'];
    final account = accountRaw is Map
        ? DouyinAccount.fromJson(Map<String, dynamic>.from(accountRaw))
        : DouyinAccount(
            id: accountId,
            douyinUid: '',
            nickname: '抖音账号',
          );
    final worksRaw = data['works'];
    final works = worksRaw is List
        ? worksRaw
            .whereType<Map>()
            .map((e) => DouyinWorkItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <DouyinWorkItem>[];
    final live = data['live'];
    int favorited = 0;
    if (live is Map) {
      final stats = live['stats'];
      if (stats is Map) {
        final v = stats['total_favorited'];
        if (v is num) {
          favorited = v.toInt();
        } else {
          favorited = int.tryParse('$v') ?? 0;
        }
      }
    }
    return DouyinAccountDetail(
      account: account,
      works: works,
      totalFavorited: favorited,
      liveError: '${data['live_error'] ?? ''}',
    );
  }

  Future<List<DouyinNoticeItem>> myNotices({
    required int accountId,
    int count = 5,
    String tab = 'all',
  }) async {
    final data = await _adminPost(
      'douyin_my_notices',
      {
        'id': accountId,
        'count': count,
        'tab': tab,
      },
      timeout: const Duration(seconds: 40),
    );
    final list = data['list'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => DouyinNoticeItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<DouyinChatConversation>> myChats({
    required int accountId,
    int limit = 80,
    bool fast = true,
  }) async {
    late http.Response res;
    try {
      final token = AuthController.instance.token;
      if (token == null || token.isEmpty) {
        throw ApiException('请先登录', code: 401);
      }
      res = await _client
          .post(
            _admin('douyin_my_chats'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'id': accountId,
              'limit': limit,
              'fast': fast ? 1 : 0,
              'client': ApiConfig.client,
              'token': token,
            }),
          )
          .timeout(Duration(seconds: fast ? 90 : 180));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('拉取私信会话失败，请检查网络与服务');
    }
    final data = await _decode(res);
    final list = data['list'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => DouyinChatConversation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 解析作品播放/下载直链
  Future<DouyinAwemePlay> awemePlay({
    required int accountId,
    String awemeId = '',
    String link = '',
  }) async {
    final data = await _adminPost(
      'douyin_aweme_play',
      {
        'id': accountId,
        if (awemeId.isNotEmpty) 'aweme_id': awemeId,
        if (link.isNotEmpty) 'link': link,
      },
      timeout: const Duration(seconds: 45),
    );
    return DouyinAwemePlay.fromJson(data);
  }

  Future<DouyinChatThread> myChatMessages({
    required int accountId,
    required String conversation,
    String shortId = '',
    int limit = 200,
  }) async {
    late http.Response res;
    try {
      final token = AuthController.instance.token;
      if (token == null || token.isEmpty) {
        throw ApiException('请先登录', code: 401);
      }
      res = await _client
          .post(
            _admin('douyin_my_chat_messages'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'id': accountId,
              'conversation': conversation,
              'short_id': shortId,
              'limit': limit,
              'client': ApiConfig.client,
              'token': token,
            }),
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('拉取聊天记录失败');
    }
    final data = await _decode(res);
    final list = data['list'];
    final peer = data['peer'];
    final messages = list is List
        ? list
            .whereType<Map>()
            .map((e) => DouyinChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <DouyinChatMessage>[];
    final peerMap = peer is Map ? Map<String, dynamic>.from(peer) : <String, dynamic>{};
    return DouyinChatThread(
      messages: messages,
      selfAvatar: '${data['self_avatar'] ?? ''}',
      peerAvatar: '${peerMap['avatar_url'] ?? ''}',
      peerNickname: '${peerMap['nickname'] ?? ''}',
    );
  }

  Future<void> unbind(int id) async {
    await _adminPost('douyin_unbind', {'id': id});
  }

  /// 续火花：好友列表（含火花 / 已勾选）
  Future<DouyinSparkFriendsResult> sparkFriends({
    required int accountId,
    int limit = 200,
  }) async {
    final data = await _adminPost(
      'douyin_spark_friends',
      {'id': accountId, 'limit': limit},
      timeout: const Duration(seconds: 180),
    );
    final list = data['list'];
    final friends = list is List
        ? list
            .whereType<Map>()
            .map((e) => DouyinSparkFriend.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <DouyinSparkFriend>[];
    return DouyinSparkFriendsResult(
      list: friends,
      flame: (data['flame'] as num?)?.toInt() ?? 0,
      flameCostPer: (data['flame_cost_per'] as num?)?.toInt() ?? 1,
      selectedCount: (data['selected_count'] as num?)?.toInt() ?? 0,
      hint: '${data['hint'] ?? ''}',
    );
  }

  /// 保存续火勾选
  Future<List<DouyinSparkFriend>> sparkTargetsSave({
    required int accountId,
    required List<DouyinSparkFriend> targets,
    bool replace = true,
  }) async {
    final data = await _adminPost('douyin_spark_targets_save', {
      'id': accountId,
      'replace': replace,
      'targets': targets.map((e) => e.toSaveJson()).toList(),
    });
    final list = data['list'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => DouyinSparkFriend.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 立即续火（服务端代发私信，手机不弹浏览器）
  Future<DouyinSparkRenewResult> sparkRenew({
    required int accountId,
    String message = '',
    List<int>? targetIds,
    bool flameCost = true,
  }) async {
    final body = <String, dynamic>{
      'id': accountId,
      'message': message,
      'flame_cost': flameCost,
    };
    if (targetIds != null && targetIds.isNotEmpty) {
      body['target_ids'] = targetIds;
    }
    final data = await _adminPost(
      'douyin_spark_renew',
      body,
      timeout: const Duration(minutes: 8),
    );
    final results = data['results'];
    return DouyinSparkRenewResult(
      okCount: (data['ok_count'] as num?)?.toInt() ?? 0,
      failCount: (data['fail_count'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
      flame: (data['flame'] as num?)?.toInt() ?? 0,
      flameCostPer: (data['flame_cost_per'] as num?)?.toInt() ?? 1,
      flameDeducted: (data['flame_deducted'] as num?)?.toInt() ?? 0,
      hint: '${data['hint'] ?? ''}',
      results: results is List
          ? results
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
    );
  }

  Future<int> bind({
    required String cookie,
    required DouyinUserPreview user,
    String sid = '',
  }) async {
    final data = await _adminPost('douyin_bind', {
      'cookie': cookie,
      'sid': sid,
      'user': user.toBindJson(),
    });
    return (data['id'] as num?)?.toInt() ?? 0;
  }

  Future<DouyinUserPreview> getUserInfo({
    required String cookie,
    String sid = '',
  }) async {
    late http.Response res;
    try {
      res = await _client
          .post(
            _cookie('get_user_info'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: jsonEncode({'cookie': cookie, 'sid': sid}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw ApiException('拉取抖音资料失败，请检查网络');
    }
    final data = await _decode(res);
    final user = data['user'];
    if (user is! Map) throw ApiException('未获取到抖音用户信息');
    return DouyinUserPreview.fromJson(Map<String, dynamic>.from(user));
  }

  Future<QrLoginSession> getQrcode() async {
    late http.Response res;
    try {
      res = await _client
          .get(_cookie('get_qrcode'))
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw ApiException('获取二维码失败');
    }
    final data = await _decode(res);
    return QrLoginSession(
      sid: '${data['sid'] ?? ''}',
      token: '${data['token'] ?? ''}',
      qrcode: '${data['qrcode'] ?? ''}',
      qrcodeIndexUrl: '${data['qrcode_index_url'] ?? ''}',
    );
  }

  Future<CookieLoginStatus> checkQrconnect({
    required String sid,
    required String token,
  }) async {
    late http.Response res;
    try {
      res = await _client
          .get(_cookie('check_qrconnect', {'sid': sid, 'token': token}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException('扫码状态查询失败');
    }
    final data = await _decode(res);
    return CookieLoginStatus(
      status: '${data['status'] ?? ''}',
      statusText: '${data['status_text'] ?? ''}',
      cookie: '${data['cookie'] ?? ''}',
      cookieReady: data['cookie_ready'] == true,
      verifyUrl: '${data['verify_url'] ?? ''}',
      bootstrapCookie: '${data['bootstrap_cookie'] ?? ''}',
    );
  }

  Future<String> webLoginStart() async {
    late http.Response res;
    try {
      res = await _client
          .post(
            _cookie('web_login_start'),
            headers: {'Content-Type': 'application/json'},
            body: '{}',
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException('启动网页登录失败');
    }
    final data = await _decode(res);
    final sid = '${data['sid'] ?? ''}';
    if (sid.isEmpty) throw ApiException('未返回登录会话');
    return sid;
  }

  Future<CookieLoginStatus> browserLoginStatus(String sid) async {
    late http.Response res;
    try {
      res = await _client
          .get(_cookie('browser_login_status', {'sid': sid}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException('网页登录状态查询失败');
    }
    final data = await _decode(res);
    return CookieLoginStatus(
      status: '${data['status'] ?? ''}',
      statusText: '${data['status_text'] ?? ''}',
      cookie: '${data['cookie'] ?? ''}',
      cookieReady: data['cookie_ready'] == true,
      verifyUrl: '${data['verify_url'] ?? ''}',
      bootstrapCookie: '${data['bootstrap_cookie'] ?? ''}',
    );
  }
}
