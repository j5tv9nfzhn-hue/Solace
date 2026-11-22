// 通话消息与基础工具（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocCallsBase on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore {
  bool _isAIRefusal(String content) => isAIRefusal(content);


  bool get _isPureAIForced => _storage.isPureAiModeEnabled();


  String _fallbackForRefusal(String userMessage) =>
      fallbackForRefusal(userMessage);


  /// 从用户消息中移除“系统提示”指令部分，用于保存到聊天记录
  String _stripSystemDirective(String text) => stripSystemDirective(text);


  // ═══════════════════════════════════════════════════════
  // 桥接层辅助方法（渐进迁移：优先用新适配器，回退到旧服务）
  // ═══════════════════════════════════════════════════════


  /// 是否使用新适配器（当 _aiAdapter 不为空时启用）
  bool get _useAdapter => _aiAdapter != null;


  int _getTypingDelay(String personality) => getTypingDelay(personality);


  List<String> _extractKeywords(String text) => extractKeywords(text);


  String _formatAiError(Object error) => formatAiError(error);


  double _avgMessageLength(String chatId) {
    final lengths = _msgLengths[chatId] ?? [];
    if (lengths.isEmpty) return 0;
    return lengths.reduce((a, b) => a + b) / lengths.length;
  }


  Future<LlmSettings> _loadLlmSettings() async {
    final config = await _storage.getActiveAIConfig();
    if (config != null) {
      return LlmSettings(
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        model: config.modelName,
      );
    }
    return const LlmSettings();
  }
}
