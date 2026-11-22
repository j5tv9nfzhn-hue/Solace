// 顶层组件拆分（同库 part）
part of '../chat_detail_screen.dart';

class _StreamingBubble extends StatelessWidget {
  final String text;
  final String? reasoning;
  final String? avatarUrl;
  final String name;
  final bool novelMode;
  final bool hasActionBracket;

  /// 小说模式对白颜色（亮色/暗色）。null 时使用默认蓝色。
  final Color? dialogueColorLight;
  final Color? dialogueColorDark;


  const _StreamingBubble({
    required this.text,
    this.reasoning,
    this.avatarUrl,
    this.name = 'AI',
    this.novelMode = false,
    this.hasActionBracket = false,
    this.dialogueColorLight,
    this.dialogueColorDark,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // UI 兜底清洗：先提取思考标签，再清理正文，避免 <think> 泄漏到气泡外
    final cleanedParts = AIService.cleanForStreamDisplay(text);
    final cleanText = MessageSanitizer.sanitizeStream(cleanedParts[0]);
    final thinkExtracted = cleanedParts.length > 1 ? cleanedParts[1] : '';

    final cleanReasoningRaw = reasoning != null && reasoning!.isNotEmpty
        ? MessageSanitizer.sanitizeStream(reasoning!)
        : '';
    // 合并 API reasoning_content 和从 content 中提取的<think>>内容
    final allReasoning = [cleanReasoningRaw, thinkExtracted]
        .where((r) => r.isNotEmpty)
        .join('\n');
    final cleanReasoning = allReasoning.isNotEmpty ? allReasoning : null;
    final hasReasoning = cleanReasoning != null && cleanReasoning.isNotEmpty;
    final brightness = Theme.of(context).brightness;
    final isDarkMode = brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.primary.withOpacity(0.1),
            backgroundImage: AvatarResolver.imageProvider(avatarUrl),
            child: AvatarResolver.imageProvider(avatarUrl) == null
                ? Icon(Icons.auto_awesome, size: 18, color: colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                // 18.3.0 沉浸式：深色下与普通 AI 气泡同款半透明。
                color: isDarkMode
                    ? _MessageBubble._bubbleDark
                    : colorScheme.surfaceContainerHighest,
                border: isDarkMode
                    ? Border.all(color: _MessageBubble._bubbleDarkBorder)
                    : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasReasoning) ...[
                    Text(
                      cleanReasoning!,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.4),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (cleanText.isNotEmpty) ...[
                    Builder(builder: (ctx) {
                      final brightness = Theme.of(ctx).brightness;
                      final baseStyle = TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                      );
                      if (novelMode) {
                        final dialogueColor = brightness == Brightness.dark
                            ? (dialogueColorDark ??
                                _MessageBubble._douyinBlueDark)
                            : (dialogueColorLight ??
                                _MessageBubble._douyinBlue);
                        final spans = _MessageBubble._buildDialogueSpans(
                            cleanText, baseStyle, dialogueColor);
                        if (spans != null) {
                          return Text.rich(TextSpan(children: spans));
                        }
                      }
                      // 动作括号渲染（流式气泡）
                      if (hasActionBracket) {
                        final bracketSpans =
                            _MessageBubble._buildActionBracketSpans(
                                cleanText, baseStyle);
                        if (bracketSpans != null) {
                          return Text.rich(TextSpan(children: bracketSpans));
                        }
                      }
                      return SelectableText(cleanText, style: baseStyle);
                    }),
                  ],
                  if (!hasReasoning && text.isEmpty)
                    TypingIndicator(statusText: '等待中...'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 推理/思考内容折叠区域
