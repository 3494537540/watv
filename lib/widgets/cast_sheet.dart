import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player/dlna_cast_service.dart';
import 'dialogx/dialogx.dart';

/// 投屏面板：白底中性配色，无演示设备
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
    builder: (ctx) => _CastSheet(
      mediaUrl: mediaUrl,
      title: title,
      onCastStarted: onCastStarted,
      onCastStopped: onCastStopped,
    ),
  );
}

class _CastSheet extends StatefulWidget {
  const _CastSheet({
    required this.mediaUrl,
    required this.title,
    this.onCastStarted,
    this.onCastStopped,
  });

  final String mediaUrl;
  final String title;
  final VoidCallback? onCastStarted;
  final VoidCallback? onCastStopped;

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  static const _bg = Color(0xFFFFFFFF);
  static const _soft = Color(0xFFF5F5F7);
  static const _line = Color(0xFFE5E5EA);
  static const _ink = Color(0xFF1C1C1E);
  static const _muted = Color(0xFF8E8E93);
  static const _accent = Color(0xFF1C1C1E);

  final _svc = DlnaCastService.instance;
  List<DlnaDevice> _devices = const [];
  bool _scanning = false;
  bool _casting = false;
  bool _paused = false;
  DlnaDevice? _active;
  String? _hint;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _hint = null;
    });
    try {
      final list = await _svc.search();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _scanning = false;
        _hint = list.isEmpty
            ? '未发现设备，请确认电视与手机在同一 Wi‑Fi 后重试'
            : '发现 ${list.length} 台设备';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _devices = const [];
        _scanning = false;
        _hint = '搜索失败，请检查网络权限后重试';
      });
    }
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

  Future<void> _copyUrl() async {
    final url = widget.mediaUrl.trim();
    if (url.isEmpty) {
      DialogX.showWarning('暂无播放地址');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    DialogX.showSuccess('播放地址已复制');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.72;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: const BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D1D6),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _soft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        CupertinoIcons.tv,
                        color: _ink,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '投屏',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                          Text(
                            '手机与电视需连接同一 Wi‑Fi',
                            style: TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 12,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _scanning ? null : _scan,
                      icon: Icon(
                        CupertinoIcons.refresh,
                        color: _scanning ? _muted : _ink,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _soft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.play_fill,
                        size: 14,
                        color: _muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_active != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _ConnectedCard(
                    device: _active!,
                    paused: _paused,
                    onPause: _togglePause,
                    onStop: _stop,
                  ),
                ),
              if (_hint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _hint!,
                      style: const TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: _muted,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: _devices.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Text(
                            _scanning ? '正在搜索设备…' : '暂无可用设备',
                            style: const TextStyle(
                              fontFamily: 'AppSans',
                              fontSize: 14,
                              color: _muted,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                        shrinkWrap: true,
                        itemCount: _devices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final d = _devices[i];
                          final on = _active?.usn == d.usn;
                          return _DeviceTile(
                            device: d,
                            active: on,
                            busy: _casting && !on,
                            onTap: on || _casting ? null : () => _castTo(d),
                          );
                        },
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12 + bottom),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyUrl,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          side: const BorderSide(color: _line),
                          backgroundColor: _soft,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
                        label: const Text(
                          '复制地址',
                          style: TextStyle(fontFamily: 'AppSans'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _scanning ? null : _scan,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFAEAEB2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          _scanning
                              ? CupertinoIcons.hourglass
                              : CupertinoIcons.search,
                          size: 16,
                        ),
                        label: Text(
                          _scanning ? '搜索中' : '重新搜索',
                          style: const TextStyle(fontFamily: 'AppSans'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({
    required this.device,
    required this.paused,
    required this.onPause,
    required this.onStop,
  });

  final DlnaDevice device;
  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '正在投屏',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            device.name,
            style: const TextStyle(
              fontFamily: 'AppSans',
              fontSize: 13,
              color: Color(0xFF636366),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniAction(
                  icon: paused
                      ? CupertinoIcons.play_fill
                      : CupertinoIcons.pause_fill,
                  label: paused ? '继续' : '暂停',
                  onTap: onPause,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniAction(
                  icon: CupertinoIcons.stop_fill,
                  label: '断开',
                  onTap: onStop,
                  danger: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: danger ? const Color(0x14FF3B30) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: danger ? const Color(0xFFE53935) : const Color(0xFF1C1C1E),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: danger
                      ? const Color(0xFFE53935)
                      : const Color(0xFF1C1C1E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.active,
    required this.busy,
    required this.onTap,
  });

  final DlnaDevice device;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E5EA)),
                ),
                child: Icon(
                  CupertinoIcons.tv,
                  color: active
                      ? const Color(0xFF1C1C1E)
                      : const Color(0xFF636366),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.manufacturer.isNotEmpty
                          ? device.manufacturer
                          : 'DLNA 设备',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 12,
                        color: active
                            ? Colors.white70
                            : const Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  active ? '已连接' : '投屏',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : const Color(0xFF1C1C1E),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
