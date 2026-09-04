import 'package:flutter/cupertino.dart';

import '../legal/legal_docs.dart';
import '../theme/app_colors.dart';

enum LegalDocKind { userAgreement, privacyPolicy }

/// 用户协议 / 隐私政策阅读页
class LegalDocPage extends StatelessWidget {
  const LegalDocPage({super.key, required this.kind});

  final LegalDocKind kind;

  String get _title => kind == LegalDocKind.userAgreement
      ? LegalDocs.userAgreementTitle
      : LegalDocs.privacyPolicyTitle;

  String get _body => kind == LegalDocKind.userAgreement
      ? LegalDocs.userAgreement
      : LegalDocs.privacyPolicy;

  @override
  Widget build(BuildContext context) {
    final page = AppPalette.page(context);
    final text = AppPalette.text(context);
    final secondary = AppPalette.textSecondary(context);
    final surface = AppPalette.surface(context);
    final line = AppPalette.line(context);

    return CupertinoPageScaffold(
      backgroundColor: page,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: surface,
        border: Border(bottom: BorderSide(color: line, width: 0.5)),
        middle: Text(
          _title,
          style: TextStyle(
            fontFamily: 'AppSans',
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(
              _body.trim(),
              style: TextStyle(
                fontFamily: 'AppSans',
                fontSize: 14,
                height: 1.65,
                color: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
