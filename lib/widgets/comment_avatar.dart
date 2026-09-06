import 'dart:io';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../state/cms_auth_controller.dart';
import '../utils/qq_avatar.dart';

/// 评论头像：直连 → QQ 头像 → 面板反代 → 本机路径 → 首字色块
class CommentAvatar extends StatefulWidget {
  const CommentAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 36,
  });

  final String name;
  final String? url;
  final double size;

  @override
  State<CommentAvatar> createState() => _CommentAvatarState();
}

class _CommentAvatarState extends State<CommentAvatar> {
  late String _phase; // direct | qq | proxy | local | letter

  @override
  void initState() {
    super.initState();
    _phase = _initialPhase();
  }

  @override
  void didUpdateWidget(covariant CommentAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.name != widget.name) {
      _phase = _initialPhase();
    }
  }

  String _initialPhase() {
    final raw = _resolvedUrl();
    if (raw == null || raw.isEmpty) {
      return _qqUrl() != null ? 'qq' : 'letter';
    }
    if (_isLocalPath(raw)) return 'local';
    return 'direct';
  }

  String? _qqUrl() {
    final me = CmsAuthController.instance.user;
    return QqAvatar.urlFromCandidates([
      widget.name,
      me?.userName,
      me?.qq,
      me?.nickName,
      if (me != null && me.userId > 0) '${me.userId}',
    ]);
  }

  String? _resolvedUrl() {
    var u = (widget.url ?? '').trim();
    if (u.isEmpty || u == 'null') {
      final me = CmsAuthController.instance.user;
      if (me != null) {
        final n = widget.name.trim();
        if (n.isNotEmpty &&
            (n == me.displayName.trim() ||
                n == me.userName.trim() ||
                n == me.nickName.trim() ||
                n == '用户${me.userId}')) {
          u = me.avatarUrl?.trim() ?? '';
        }
      }
    }
    if (u.isEmpty || u == 'null') {
      u = _qqUrl() ?? '';
    }
    if (u.isEmpty || u == 'null') return null;
    if (u.startsWith('//')) return 'https:$u';
    if (!u.contains('://') &&
        !_isLocalPath(u) &&
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(u)) {
      if (u.startsWith('/')) return '${ApiConfig.macCmsBase}$u';
      return '${ApiConfig.macCmsBase}/$u';
    }
    return u;
  }

  bool _isLocalPath(String p) {
    return (p.length > 2 && p[1] == ':') ||
        p.contains('\\') ||
        p.contains('/cms_avatar_') ||
        p.startsWith('/data/') ||
        p.startsWith('/var/') ||
        p.startsWith('/Users/') ||
        p.startsWith('/home/') ||
        p.startsWith('/private/var/') ||
        p.startsWith('file:');
  }

  Color _colorFor(String name) {
    final s = name.trim().isEmpty ? '?' : name.trim();
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    const palette = <Color>[
      Color(0xFF5AC8FA),
      Color(0xFF34C759),
      Color(0xFFFF9F0A),
      Color(0xFFFF375F),
      Color(0xFFBF5AF2),
      Color(0xFF64D2FF),
      Color(0xFFFFD60A),
      Color(0xFF30B0C7),
    ];
    return palette[h % palette.length];
  }

  Widget _letter() {
    final name = widget.name.trim();
    final ch = name.isNotEmpty ? name[0] : '?';
    final bg = _colorFor(name);
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      color: bg,
      child: Text(
        ch,
        style: TextStyle(
          fontFamily: 'AppSans',
          fontSize: widget.size * 0.38,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _network(String url, {required String failPhase}) {
    return Image.network(
      url,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Referer': 'https://www.qq.com/',
      },
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _phase != failPhase && _phase != 'letter') {
            setState(() => _phase = failPhase);
          }
        });
        return _letter();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl();
    Widget child;
    if (_phase == 'letter') {
      child = _letter();
    } else if (_phase == 'local' || (url != null && _isLocalPath(url))) {
      var path = url ?? '';
      if (path.startsWith('file:')) {
        path = Uri.parse(path).toFilePath();
      }
      final f = File(path);
      child = f.existsSync()
          ? Image.file(
              f,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _letter(),
            )
          : _letter();
    } else if (_phase == 'qq') {
      final qq = _qqUrl();
      child = qq == null
          ? _letter()
          : _network(qq, failPhase: 'letter');
    } else if (_phase == 'proxy' && url != null) {
      child = _network(
        ApiConfig.huihuoImgProxyUrl(url),
        failPhase: 'qq',
      );
    } else if (url != null && url.isNotEmpty) {
      child = Image.network(
        url,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Referer': '${ApiConfig.macCmsBase}/',
        },
        errorBuilder: (_, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_phase == 'direct') {
              setState(() => _phase = _qqUrl() != null ? 'qq' : 'proxy');
            }
          });
          return _letter();
        },
      );
    } else {
      child = _letter();
    }

    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: child,
      ),
    );
  }
}
