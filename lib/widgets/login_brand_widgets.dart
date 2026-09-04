import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../pages/legal_doc_page.dart';
import '../theme/app_colors.dart';
import 'app_page_route.dart';

/// 登录页协议勾选行（可点开用户协议 / 隐私政策）
class LoginAgreementRow extends StatelessWidget {
  const LoginAgreementRow({
    super.key,
    required this.agreed,
    required this.onChanged,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;

  void _open(BuildContext context, LegalDocKind kind) {
    Navigator.of(context).push(
      AppPageRoute<void>(builder: (_) => LegalDocPage(kind: kind)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => onChanged(!agreed),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                agreed
                    ? CupertinoIcons.checkmark_alt_circle_fill
                    : CupertinoIcons.circle,
                size: 16,
                color: agreed ? AppColors.brand : AppColors.textHint,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'AppSans',
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFFB0B0B0),
                ),
                children: [
                  const TextSpan(text: '我已阅读并同意 '),
                  TextSpan(
                    text: '用户协议',
                    style: TextStyle(color: AppColors.brand),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(context, LegalDocKind.userAgreement),
                  ),
                  const TextSpan(text: ' 和 '),
                  TextSpan(
                    text: '隐私政策',
                    style: TextStyle(color: AppColors.brand),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(context, LegalDocKind.privacyPolicy),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// QQ 互联登录按钮图标（使用你提供的 QQ.svg，不加蓝底）
class QqBrandIcon extends StatelessWidget {
  const QqBrandIcon({super.key, this.size = 48});

  final double size;

  static const _asset = 'assets/images/login_qq.svg';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        _asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
