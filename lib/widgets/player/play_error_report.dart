import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/maccms_api.dart';
import '../../state/cms_auth_controller.dart';
import '../dialogx/dialogx.dart';

/// 组装提交到 CMS 留言本的报错正文（后台「留言」可见）
String buildPlayErrorReportContent({
  required String vodId,
  required String title,
  required String sourceName,
  required int sourceIndex,
  required int episodeIndex,
  required String episodeLabel,
  required String playUrl,
  required String errorMsg,
}) {
  final buf = StringBuffer();
  buf.writeln('【App播放报错】');
  buf.writeln('编号：$vodId');
  buf.writeln('名称：${title.trim().isEmpty ? '-' : title.trim()}');
  buf.writeln(
    '线路：${sourceName.trim().isEmpty ? '线路${sourceIndex + 1}' : sourceName.trim()} (#$sourceIndex)',
  );
  final ep = episodeLabel.trim().isNotEmpty
      ? episodeLabel.trim()
      : '第${episodeIndex + 1}集';
  buf.writeln('选集：$ep (#$episodeIndex)');
  buf.writeln('地址：${playUrl.trim().isEmpty ? '-' : playUrl.trim()}');
  buf.writeln('错误：${errorMsg.trim().isEmpty ? '播放失败（未捕获详情）' : errorMsg.trim()}');
  buf.write('请检查修复，谢谢。');
  return buf.toString();
}

/// 弹出报错对话框并提交到苹果 CMS 留言本
Future<void> showPlayErrorReportDialog(
  BuildContext context, {
  required String vodId,
  required String title,
  required String sourceName,
  required int sourceIndex,
  required int episodeIndex,
  required String episodeLabel,
  required String playUrl,
  required String errorMsg,
}) async {
  if (vodId.trim().isEmpty) {
    DialogX.showWarning('缺少影片编号，无法报错');
    return;
  }

  final initial = buildPlayErrorReportContent(
    vodId: vodId,
    title: title,
    sourceName: sourceName,
    sourceIndex: sourceIndex,
    episodeIndex: episodeIndex,
    episodeLabel: episodeLabel,
    playUrl: playUrl,
    errorMsg: errorMsg,
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: const Color(0x66000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return _PlayErrorReportSheet(
        vodId: vodId.trim(),
        initialContent: initial,
      );
    },
  );
}

class _PlayErrorReportSheet extends StatefulWidget {
  const _PlayErrorReportSheet({
    required this.vodId,
    required this.initialContent,
  });

  final String vodId;
  final String initialContent;

  @override
  State<_PlayErrorReportSheet> createState() => _PlayErrorReportSheetState();
}

class _PlayErrorReportSheetState extends State<_PlayErrorReportSheet> {
  late final TextEditingController _content;
  final _verify = TextEditingController();
  final _cms = MacCmsApi();
  Uint8List? _captcha;
  bool _loadingCaptcha = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _content = TextEditingController(text: widget.initialContent);
    final cookie = CmsAuthController.instance.api.sessionCookie;
    if (cookie != null && cookie.isNotEmpty) {
      _cms.adoptCmsSessionCookie(cookie);
    }
    unawaited(_reloadCaptcha());
  }

  @override
  void dispose() {
    _content.dispose();
    _verify.dispose();
    super.dispose();
  }

  Future<void> _reloadCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _error = null;
    });
    try {
      final bytes = await _cms.fetchGbookCaptcha();
      if (!mounted) return;
      setState(() {
        _captcha = bytes;
        _loadingCaptcha = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCaptcha = false;
        _captcha = null;
        _error = e is MacCmsException ? e.message : '验证码加载失败';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _content.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请填写报错内容');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _cms.reportPlayError(
        vodId: widget.vodId,
        content: text,
        verify: _verify.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      DialogX.showSuccess('已提交报错，感谢反馈');
    } on MacCmsException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      // 验证码错误时刷新
      if (e.message.contains('验证码')) {
        _verify.clear();
        unawaited(_reloadCaptcha());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '提交失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final pad = MediaQuery.paddingOf(context);
    InputDecoration fieldDeco({required String hint}) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: 'AppSans',
            color: Color(0xFFA0A4AE),
            fontSize: 14,
          ),
          filled: true,
          fillColor: const Color(0xFFF3F4F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE6E8EE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4C8DFF), width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottom + pad.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFD8DBE2),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '播放报错',
                  style: TextStyle(
                    fontFamily: 'AppSans',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: Color(0xFFC7C7CC),
                ),
              ),
            ],
          ),
          const Text(
            '将发送到留言本，管理员可在后台查看',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 12,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: TextField(
              controller: _content,
              maxLines: null,
              style: const TextStyle(
                fontFamily: 'AppSans',
                color: Color(0xFF1C1C1E),
                fontSize: 14,
                height: 1.45,
              ),
              decoration: fieldDeco(hint: '补充报错说明…'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _verify,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_submit()),
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    color: Color(0xFF1C1C1E),
                    fontSize: 14,
                  ),
                  decoration: fieldDeco(hint: '验证码（开启时必填）'),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap:
                    _loadingCaptcha ? null : () => unawaited(_reloadCaptcha()),
                child: Container(
                  width: 112,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6E8EE)),
                  ),
                  child: _loadingCaptcha
                      ? const CupertinoActivityIndicator()
                      : (_captcha == null
                          ? const Text(
                              '刷新验证码',
                              style: TextStyle(
                                fontFamily: 'AppSans',
                                color: Color(0xFF8E8E93),
                                fontSize: 12,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _captcha!,
                                fit: BoxFit.contain,
                              ),
                            )),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: 'AppSans',
                color: Color(0xFFE5484D),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _submitting ? null : () => unawaited(_submit()),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: _submitting
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                      '提交报错',
                      style: TextStyle(
                        fontFamily: 'AppSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
