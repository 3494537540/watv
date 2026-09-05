import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/auth_models.dart';
import '../services/plaza_api.dart';
import '../services/app_permission.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogx/dialogx.dart';

/// 底部弹窗发帖
Future<bool> showPlazaComposeSheet(BuildContext context) async {
  HapticFeedback.selectionClick();
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) => const PlazaComposeSheet(),
  );
  return result == true;
}

class PlazaComposeSheet extends StatefulWidget {
  const PlazaComposeSheet({super.key});

  @override
  State<PlazaComposeSheet> createState() => _PlazaComposeSheetState();
}

class _PlazaComposeSheetState extends State<PlazaComposeSheet> {
  final _api = PlazaApi();
  final _ctrl = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _files = [];
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_files.length >= 9) {
      DialogX.showWarning('最多 9 张图片');
      return;
    }
    final allowed = await AppPermission.requestWithRationale(
      AppPermissionKind.photos,
      context: context,
      title: '需要访问相册',
      message: '发帖配图需要从相册选择图片，仅在你主动选择时读取。',
    );
    if (!allowed) return;
    try {
      final list = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (list.isEmpty) return;
      setState(() {
        for (final f in list) {
          if (_files.length >= 9) break;
          _files.add(f);
        }
      });
    } catch (_) {
      DialogX.showError('无法选择图片');
    }
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      DialogX.showWarning('请填写内容');
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    DialogX.showWait('发布中…');
    try {
      final paths = <String>[];
      for (final f in _files) {
        paths.add(await _api.uploadImage(f.path));
      }
      await _api.create(content: text, images: paths);
      DialogX.showSuccess('已提交，等待审核');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      DialogX.showError(e.message);
    } catch (_) {
      DialogX.showError('发布失败');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).maybePop(false),
                        child: Text(
                          '取消',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          '发帖',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: _submitting ? null : _submit,
                        child: Text(
                          '发布',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontWeight: FontWeight.w600,
                            color: _submitting
                                ? AppColors.disabled
                                : AppColors.iosBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + safe),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _ctrl,
                          autofocus: true,
                          maxLines: 6,
                          maxLength: 2000,
                          style: const TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 16,
                            height: 1.4,
                            color: AppColors.text,
                          ),
                          decoration: const InputDecoration(
                            hintText: '分享你的想法…',
                            hintStyle: TextStyle(color: AppColors.textHint),
                            border: InputBorder.none,
                            counterStyle: TextStyle(fontFamily: 'AppSans'),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < _files.length; i++)
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      File(_files[i].path),
                                      width: 88,
                                      height: 88,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() => _files.removeAt(i));
                                      },
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(2),
                                        child: const Icon(
                                          CupertinoIcons.xmark,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (_files.length < 9)
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _pick();
                                },
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F2F7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.photo_on_rectangle,
                                    color: Color(0xFF8E8E93),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '发布后需审核通过才会出现在广场',
                          style: TextStyle(
                            fontFamily: 'AppSans',
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
