import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/auth_models.dart';
import '../models/membership_models.dart';
import '../state/auth_controller.dart';

class MembershipApi {
  MembershipApi({http.Client? client}) : _client = client ?? http.Client();

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

  Future<VipCatalogResult> vipCatalog() async {
    final data = await _post('vip_catalog', {}, auth: true);
    final list = data['list'];
    final settings = data['settings'] is Map
        ? Map<String, dynamic>.from(data['settings'] as Map)
        : <String, dynamic>{};
    final meRaw = data['me'];
    return VipCatalogResult(
      list: list is List
          ? list
              .whereType<Map>()
              .map((e) => VipPackage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      mockPay: settings['mock_pay'] == true,
      freeMaxAccounts:
          (settings['free_max_douyin_accounts'] as num?)?.toInt() ?? 3,
      vipMaxAccounts:
          (settings['vip_max_douyin_accounts'] as num?)?.toInt() ?? 20,
      flameCostSparkRenew:
          (settings['flame_cost_spark_renew'] as num?)?.toInt() ?? 1,
      me: meRaw is Map
          ? AuthUser.fromJson(Map<String, dynamic>.from(meRaw))
          : null,
    );
  }

  Future<FlameCatalogResult> flameCatalog() async {
    final data = await _post('flame_catalog', {}, auth: true);
    final list = data['list'];
    final settings = data['settings'] is Map
        ? Map<String, dynamic>.from(data['settings'] as Map)
        : <String, dynamic>{};
    final meRaw = data['me'];
    return FlameCatalogResult(
      list: list is List
          ? list
              .whereType<Map>()
              .map((e) => FlamePackage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      mockPay: settings['mock_pay'] == true,
      flameCostSparkRenew:
          (settings['flame_cost_spark_renew'] as num?)?.toInt() ?? 1,
      me: meRaw is Map
          ? AuthUser.fromJson(Map<String, dynamic>.from(meRaw))
          : null,
    );
  }

  Future<OrderCreateResult> createOrder({
    required String type,
    required int packageId,
    bool autoPay = true,
  }) async {
    final data = await _post('membership_order_create', {
      'type': type,
      'package_id': packageId,
      'auto_pay': autoPay,
    });
    final orderRaw = data['order'];
    if (orderRaw is! Map) throw ApiException('订单创建失败');
    final userRaw = data['user'];
    return OrderCreateResult(
      order: MembershipOrder.fromJson(Map<String, dynamic>.from(orderRaw)),
      user: userRaw is Map
          ? AuthUser.fromJson(Map<String, dynamic>.from(userRaw))
          : null,
      message: '${data['__msg'] ?? ''}',
    );
  }
}
