import '../services/cms_message_store.dart';
import '../services/maccms_user_api.dart';
import '../state/cms_auth_controller.dart';

/// 开通 / 兑换会员成功后：写入站内公告 + 系统通知
abstract final class VipMembershipNotice {
  static Future<void> announceSuccess({
    required String title,
    String detail = '',
  }) async {
    final user = CmsAuthController.instance.user;
    final group = user?.groupName.trim() ?? '';
    final expire =
        user == null ? null : CmsUser.formatVipEndDate(user.endTime);
    final points = user?.points;
    final lines = <String>[
      if (detail.trim().isNotEmpty) detail.trim(),
      if (group.isNotEmpty && group != '游客') '当前会员：$group',
      if (expire != null && expire.isNotEmpty) '到期时间：$expire',
      if (points != null) '积分余额：$points',
    ];
    final content = lines.isEmpty ? '会员状态已更新，请在「我的」查看。' : lines.join('\n');
    final id =
        'vip_${user?.userId ?? 0}_${DateTime.now().millisecondsSinceEpoch}';
    await CmsMessageStore.instance.pushLocalNotice(
      id: id,
      title: title.trim().isEmpty ? '会员状态更新' : title.trim(),
      content: content,
      tag: '会员',
      systemNotify: true,
    );
  }
}
