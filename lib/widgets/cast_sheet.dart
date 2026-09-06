import 'dart:async';

import 'package:airplay_button/air_play_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/dlna_cast_service.dart';
import '../player/ios_airplay.dart';
import '../theme/app_colors.dart';
import 'dialogx/dialogx.dart';

/// 投屏：短弹层；全屏可走侧栏 [CastPanel]
Future<void> showCastSheet({
  required BuildContext context,
  required String mediaUrl,
  required String title,
  VoidCallback? onCastStarted,
  VoidCallback? onCastStopped,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    barrierColor: const Color(0x66000000),
    builder: (ctx) {
      return GestureDetector(
        onTap: () => Navigator.of(ctx).maybePop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {},
          child: Align(
            alignment: Alignment.bottomCenter,
            child: CastPanel(
              mediaUrl: mediaUrl,
              title: title,
              compact: true,
              onClose: () => Navigator.of(ctx).maybePop(),
              onCastStarted: onCastStarted,
              onCastStopped: onCastStopped,
            ),
          ),
        ),
      );
    },
  );
}

/// 投屏内容（底栏短弹 / 全屏侧栏共用）
class CastPanel extends StatefulWidget {
  const CastPanel({
    super.key,
    required this.mediaUrl,
    required this.title,
    required this.onClose,
    this.onCastStarted,
    this.onCastStopped,
    this.compact = true,
    this.asSide = false,
  });

  final String mediaUrl;
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onCastStarted;
  final VoidCallback? onCastStopped;
  final bool compact;
  final bool asSide;

  @override
  State<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends State<CastPanel> {
  static const _bg = Color(0xFFFFFFFF);
  static const _soft = Color(0xFFF5F5F7);
  static const _ink = Color(0xFF1C1C1E);
  static const _muted = Color(0xFF8E8E93);

  final _svc = DlnaCastService.instance;
  List<DlnaDevice> _devices = const [];
  bool _scanning = false;
  bool _casting = false;
  bool _paused = false;
  DlnaDevice? _active;

  bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Color get _accent => AppColors.brand;

  @override
  void initState() {
    super.initState();
    // iOS / Android 都自动搜局域网设备（内置 DLNA 投屏）
    unawaited(_scan());
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final list = await _svc.search();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _scanning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _devices = const [];
        _scanning = false;
      });
    }
  }

  Future<void> _openAirPlay() async {
    HapticFeedback.mediumImpact();
    final ok = await IosAirPlay.showPicker();
    if (!ok) {
      DialogX.showWarning('无法打开 AirPlay');
      return;
    }
    widget.onCastStarted?.call();
  }

  Future<void> _castTo(DlnaDevice d) async {
    if (widget.mediaUrl.trim().isEmpty) {
      DialogX.showWarning('当前没有可投屏的播放地址');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _casting = true;
      _paused = false;
    });
    try {
      await _svc.cast(
        device: d,
        mediaUrl: widget.mediaUrl,
        title: widget.title,
      );
      if (!mounted) return;
      setState(() {
        _active = d;
        _casting = false;
      });
      widget.onCastStarted?.call();
      DialogX.showSuccess('已投屏到 ${d.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _casting = false);
      DialogX.showError('投屏失败：$e');
    }
  }

  Future<void> _togglePause() async {
    final d = _active;
    if (d == null) return;
    try {
      if (_paused) {
        await _svc.play(d);
      } else {
        await _svc.pause(d);
      }
      if (!mounted) return;
      setState(() => _paused = !_paused);
    } catch (_) {
      DialogX.showWarning('操作失败');
    }
  }

  Future<void> _stop() async {
    final d = _active;
    if (d == null) return;
    try {
      await _svc.stop(d);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _active = null;
      _paused = false;
    });
    widget.onCastStopped?.call();
    DialogX.showSuccess('已停止投屏');
  }

  Widget _castIcon({double size = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.cast_rounded,
        color: _accent,
        size: size * 0.48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final radius = widget.asSide
        ? BorderRadius.zero
        : const BorderRadius.vertical(top: Radius.circular(16));

    return Material(
      color: _bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        left: false,
        top: widget.asSide,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, widget.asSide ? 8 : 10, 12, 12 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.asSide)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D1D6),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              Row(
                children: [
                  _castIcon(size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '投屏',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        Text(
                          _isIos ? 'AirPlay / 局域网设备' : '同一 Wi‑Fi 下的电视',
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Color(0xFFC7C7CC),
                      size: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isIos) ...[
                // ① AirPlay：系统路由面板（搜 Apple TV / AirPlay 音箱等）
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openAirPlay,
                        icon: const Icon(Icons.airplay_rounded, size: 18),
                        label: const Text(
                          'AirPlay 搜设备',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: AirPlayButton(
                        size: 40,
                        tintColor: _accent,
                        activeTintColor: _accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'AirPlay：把当前视频投到 Apple TV / 支持 AirPlay 的设备\n'
                  '屏幕镜像：请下拉控制中心点「屏幕镜像」搜同屏设备',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 11,
                    height: 1.35,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 12),
                // ② 内置 DLNA：搜电视盒子
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '内置投屏（局域网）',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(
                      _scanning
                          ? '搜索中…'
                          : (_devices.isEmpty
                              ? '未发现'
                              : '发现 ${_devices.length} 台'),
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: _muted,
                      ),
                    ),
                    TextButton(
                      onPressed: _scanning ? null : _scan,
                      child: Text(
                        '刷新',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _scanning
                            ? '正在搜索…'
                            : (_devices.isEmpty
                                ? '未发现设备'
                                : '发现 ${_devices.length} 台'),
                        style: const TextStyle(
                          fontFamily: 'AppSans',
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _scanning ? null : _scan,
                      child: Text(
                        '刷新',
                        style: TextStyle(
                          fontFamily: 'AppSans',
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_active != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _soft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '正在投屏 · ${_active!.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _togglePause,
                        child: Text(_paused ? '继续' : '暂停'),
                      ),
                      TextButton(
                        onPressed: _stop,
                        child: const Text(
                          '断开',
                          style: TextStyle(color: Color(0xFFE53935)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_devices.isNotEmpty) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: widget.asSide ? 280 : 180,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final d = _devices[i];
                      final on = _active?.usn == d.usn;
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: on ? _accent.withValues(alpha: 0.12) : _soft,
                        leading: Icon(Icons.tv_rounded, color: _accent),
                        title: Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        trailing: _casting && !on
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                on ? '已连接' : '投屏',
                                style: TextStyle(
                                  fontFamily: 'AppSans',
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                  fontSize: 13,
                                ),
                              ),
                        onTap: on || _casting ? null : () => _castTo(d),
                      );
                    },
                  ),
                ),
              ] else if (_isIos && !_scanning) ...[
                const SizedBox(height: 4),
                const Text(
                  '未搜到局域网电视时，可试 AirPlay 或控制中心「屏幕镜像」',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 11,
                    color: _muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
