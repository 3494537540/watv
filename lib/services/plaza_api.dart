import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_models.dart';
import '../models/plaza_models.dart';
import '../state/auth_controller.dart';

class PlazaApi {
  PlazaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String action) {
    final base = ApiConfig.baseUrl;
    final sep = base.contains('?') ? '&' : '?';
    return Uri.parse('$base${sep}action=${Uri.encodeQueryComponent(action)}');
  }

  Future<Map<String, dynamic>> _post(
    String action,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final token = AuthController.instance.token;
    final payload = <String, dynamic>{
      ...body,
      'client': ApiConfig.client,
      if (auth && token != null && token.isNotEmpty) 'token': token,
    };

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri(action),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              if (auth && token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException('网络连接失败');
    }

    return _parse(res);
  }

  Map<String, dynamic> _parse(http.Response res) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) throw ApiException('服务器返回格式异常');
      json = Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('服务器返回无法解析');
    }
    final code = (json['code'] as num?)?.toInt() ?? -1;
    final msg = '${json['msg'] ?? '请求失败'}';
    if (code != 0) throw ApiException(msg, code: code);
    final data = json['data'];
    if (data == null) return <String, dynamic>{'__msg': msg};
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      map['__msg'] = msg;
      return map;
    }
    return <String, dynamic>{'value': data, '__msg': msg};
  }

  PlazaListResult _listFrom(Map<String, dynamic> data) {
    final raw = data['list'];
    return PlazaListResult(
      list: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => PlazaPost.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      total: (data['total'] as num?)?.toInt() ?? 0,
      page: (data['page'] as num?)?.toInt() ?? 1,
      pageSize: (data['pageSize'] as num?)?.toInt() ?? 20,
    );
  }

  Future<PlazaListResult> list({
    int page = 1,
    int pageSize = 20,
    String keyword = '',
  }) async {
    final data = await _post('plaza_list', {
      'page': page,
      'pageSize': pageSize,
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    }, auth: true);
    return _listFrom(data);
  }

  Future<PlazaListResult> myList({
    int page = 1,
    int pageSize = 20,
    int? status,
  }) async {
    final data = await _post('plaza_my_list', {
      'page': page,
      'pageSize': pageSize,
      if (status != null) 'status': status,
    });
    return _listFrom(data);
  }

  Future<PlazaPost> get(int id) async {
    final data = await _post('plaza_get', {'id': id}, auth: true);
    return PlazaPost.fromJson(data);
  }

  Future<PlazaPost> create({
    required String content,
    List<String> images = const [],
  }) async {
    final data = await _post('plaza_create', {
      'content': content,
      'images': images,
    });
    return PlazaPost.fromJson(data);
  }

  Future<void> delete(int id) async {
    await _post('plaza_delete', {'id': id});
  }

  Future<PlazaPost> like(int id) async {
    final data = await _post('plaza_like', {'id': id});
    return PlazaPost(
      id: (data['id'] as num?)?.toInt() ?? id,
      userId: 0,
      content: '',
      likeCount: (data['like_count'] as num?)?.toInt() ?? 0,
      liked: data['liked'] == true || data['liked'] == 1,
    );
  }

  Future<String> uploadImage(String filePath) async {
    final token = AuthController.instance.token;
    if (token == null || token.isEmpty) {
      throw ApiException('请先登录', code: 401);
    }
    final req = http.MultipartRequest('POST', _uri('plaza_upload'));
    req.headers['Authorization'] = 'Bearer $token';
    req.headers['Accept'] = 'application/json';
    req.fields['token'] = token;
    req.fields['client'] = ApiConfig.client;
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    late http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(const Duration(seconds: 60));
    } catch (_) {
      throw ApiException('上传失败，请检查网络');
    }
    final res = await http.Response.fromStream(streamed);
    final data = _parse(res);
    final path = '${data['path'] ?? ''}'.trim();
    if (path.isEmpty) throw ApiException('上传成功但未返回路径');
    return path;
  }

  Future<PlazaListResult> adminList({
    int page = 1,
    int pageSize = 20,
    int? status,
    String keyword = '',
  }) async {
    final data = await _post('plaza_admin_list', {
      'page': page,
      'pageSize': pageSize,
      if (status != null) 'status': status,
      if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    });
    return _listFrom(data);
  }

  Future<PlazaPost> adminAudit({
    required int id,
    required bool approve,
    String reason = '',
  }) async {
    final data = await _post('plaza_admin_audit', {
      'id': id,
      'decision': approve ? 'approve' : 'reject',
      if (!approve) 'reject_reason': reason,
    });
    return PlazaPost.fromJson(data);
  }

  Future<PlazaStats> adminStats() async {
    final data = await _post('plaza_admin_stats', {});
    return PlazaStats.fromJson(data);
  }
}
