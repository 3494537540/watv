import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/maccms_api.dart';
import '../state/cms_auth_controller.dart';
import 'dialogx/dialogx.dart';

/// 搜索无结果 → 求片（CMS 留言本）
Future<void> showRequestVodSheet(
  BuildContext context, {
  required String keyword,
}) async {
  final kw = keyword.trim();
  if (kw.isEmpty) {
    DialogX.showWarning('请先输入片名');
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: const Color(0x66000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _RequestVodSheet(keyword: kw),
  );
}

InputDecoration _lightFieldDecoration({required String hint}) {
  return InputDecoration(
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

class _RequestVodSheet extends StatefulWidget {
  const _RequestVodSheet({required this.keyword});

  final String keyword;

  @override
  State<_RequestVodSheet> createState() => _RequestVodSheetState();
}

class _RequestVodSheetState extends State<_RequestVodSheet> {
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
    _content = TextEditingController(
      text: '【App求片】\n关键词：${widget.keyword}\n站内暂无资源，请尽快收录，谢谢！',
    );
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
      setState(() => _error = '请填写求片内容');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _cms.submitGbook(
        content: text,
        rid: '0',
        verify: _verify.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      DialogX.showSuccess('求片已提交，感谢反馈');
    } on MacCmsException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      if (e.message.contains('验证码')) {
        _verify.clear();
        unawaited(_reloadCaptcha());
      }
    } catch (_) {
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
                  '求片',
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
            '提交后管理员可在后台「留言本」查看',
            style: TextStyle(
              fontFamily: 'AppSans',
              fontSize: 12,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            maxLines: 5,
            style: const TextStyle(
              fontFamily: 'AppSans',
              color: Color(0xFF1C1C1E),
              fontSize: 14,
              height: 1.45,
            ),
            decoration: _lightFieldDecoration(hint: '描述想看的影片…'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _verify,
                  style: const TextStyle(
                    fontFamily: 'AppSans',
                    color: Color(0xFF1C1C1E),
                    fontSize: 14,
                  ),
                  decoration: _lightFieldDecoration(hint: '验证码（开启时必填）'),
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
                backgroundColor: const Color(0xFF1ECAD3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: _submitting
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                      '提交求片',
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
