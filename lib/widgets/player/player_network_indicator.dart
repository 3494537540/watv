import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 播放器顶栏：Wi-Fi / 流量 指示
class PlayerNetworkIndicator extends StatefulWidget {
  const PlayerNetworkIndicator({super.key});

  @override
  State<PlayerNetworkIndicator> createState() =>
      _PlayerNetworkIndicatorState();
}

class _PlayerNetworkIndicatorState extends State<PlayerNetworkIndicator> {
  _NetworkMode _mode = _NetworkMode.wifi;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = Connectivity().onConnectivityChanged.listen(_apply);
  }

  Future<void> _refresh() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (mounted) _apply(results);
    } catch (_) {}
  }

  void _apply(List<ConnectivityResult> results) {
    _NetworkMode next;
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      next = _NetworkMode.wifi;
    } else if (results.contains(ConnectivityResult.mobile)) {
      next = _NetworkMode.cellular;
    } else {
      next = _NetworkMode.none;
    }
    if (next != _mode) setState(() => _mode = next);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (_mode) {
      _NetworkMode.wifi => (CupertinoIcons.wifi, 'Wi-Fi'),
      _NetworkMode.cellular => (CupertinoIcons.antenna_radiowaves_left_right, '流量'),
      _NetworkMode.none => (CupertinoIcons.wifi_slash, '离线'),
    };

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.92)),
      ),
    );
  }
}

enum _NetworkMode { wifi, cellular, none }
