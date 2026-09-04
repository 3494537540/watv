class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.nickname,
    this.email = '',
    this.mobile = '',
    this.avatar = '',
    this.role = 'user',
    this.vipLevel = 0,
    this.vipExpireAt = '',
    this.vipStatus = 'none',
    this.vipLabel = '非会员',
    this.isVip = false,
    this.flame = 0,
  });

  final int id;
  final String username;
  final String nickname;
  final String email;
  final String mobile;
  final String avatar;
  final String role;
  final int vipLevel;
  final String vipExpireAt;
  final String vipStatus;
  final String vipLabel;
  final bool isVip;
  final int flame;

  String get displayName {
    final n = nickname.trim();
    if (n.isNotEmpty) return n;
    return username;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: '${json['username'] ?? ''}',
      nickname: '${json['nickname'] ?? json['username'] ?? ''}',
      email: '${json['email'] ?? ''}',
      mobile: '${json['mobile'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
      role: '${json['role'] ?? 'user'}',
      vipLevel: (json['vip_level'] as num?)?.toInt() ?? 0,
      vipExpireAt: '${json['vip_expire_at'] ?? ''}',
      vipStatus: '${json['vip_status'] ?? 'none'}',
      vipLabel: '${json['vip_label'] ?? '非会员'}',
      isVip: json['is_vip'] == true || json['is_vip'] == 1,
      flame: (json['flame'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'email': email,
        'mobile': mobile,
        'avatar': avatar,
        'role': role,
        'vip_level': vipLevel,
        'vip_expire_at': vipExpireAt,
        'vip_status': vipStatus,
        'vip_label': vipLabel,
        'is_vip': isVip,
        'flame': flame,
      };
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
    this.tokenExpired,
  });

  final String token;
  final AuthUser user;
  final int? tokenExpired;

  factory AuthSession.fromLoginData(Map<String, dynamic> data) {
    final userRaw = data['user'];
    final userMap = userRaw is Map
        ? Map<String, dynamic>.from(userRaw)
        : <String, dynamic>{};
    return AuthSession(
      token: '${data['token'] ?? ''}',
      tokenExpired: (data['token_expired'] as num?)?.toInt(),
      user: AuthUser.fromJson(userMap),
    );
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.code = -1});

  final String message;
  final int code;

  @override
  String toString() => message;
}

class CodeSendResult {
  const CodeSendResult({
    required this.message,
    this.devCode,
    this.expiresIn = 600,
  });

  final String message;
  final String? devCode;
  final int expiresIn;
}

class RegisterPendingResult {
  const RegisterPendingResult({
    required this.email,
    required this.needVerify,
    this.expiresIn = 0,
    this.message = '',
  });

  final String email;
  final bool needVerify;
  final int expiresIn;
  final String message;
}
