import '../models/douyin_models.dart';

/// 会话列表内存缓存：再次进入秒开
class ChatListCache {
  static final Map<int, List<DouyinChatConversation>> _map = {};

  static List<DouyinChatConversation>? get(int accountId) {
    final list = _map[accountId];
    if (list == null) return null;
    return List<DouyinChatConversation>.of(list);
  }

  static void set(int accountId, List<DouyinChatConversation> list) {
    _map[accountId] = List<DouyinChatConversation>.of(list);
  }
}
