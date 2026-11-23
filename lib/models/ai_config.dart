import 'package:equatable/equatable.dart';

/// 模型族：用于法功能等按供应商调整伪装/重试策略
enum ModelFamily {
  openai,
  anthropic,
  google,
  xai,
  domestic,
  other;

  bool get isOverseas =>
      this == openai || this == anthropic || this == google || this == xai;
}

class AIConfig extends Equatable {
  final String id;
  final String providerName;
  final String baseUrl;
  final String apiKey;
  final List<String> extraApiKeys;
  final String modelName;
  final double temperature;
  final int maxTokens;
  final bool isActive;
  final bool isThinkingModel;

  /// 上下文窗口（token）。null = 按模型族推荐；只用于本地历史裁剪，不进请求体。
  final int? contextWindow;

  /// 单次最大输出（token）。null = 按模型族推荐（回退旧 maxTokens）。
  final int? maxOutputTokens;

  /// 推理深度：0=关闭，1=低，2=中，3=高。仅对推理模型 + 已验证家族生效。
  final int reasoningDepth;
  /// 是否多模态（支持看图）。用户手动勾选；为 true 时发图走 OpenAI vision content 数组。
  final bool isMultimodal;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int syncSeq;

  const AIConfig({
    required this.id,
    required this.providerName,
    required this.baseUrl,
    required this.apiKey,
    this.extraApiKeys = const [],
    required this.modelName,
    this.temperature = 0.7,
    this.maxTokens = 2000,
    this.isActive = true,
    this.isThinkingModel = true,
    this.isMultimodal = false,
    this.contextWindow,
    this.maxOutputTokens,
    this.reasoningDepth = 0,
    required this.createdAt,
    this.updatedAt,
    this.syncSeq = 0,
  });

  List<String> get allApiKeys => [apiKey, ...extraApiKeys];

  AIConfig copyWith({
    String? id,
    String? providerName,
    String? baseUrl,
    String? apiKey,
    List<String>? extraApiKeys,
    String? modelName,
    double? temperature,
    int? maxTokens,
    bool? isActive,
    bool? isThinkingModel,
    bool? isMultimodal,
    int? contextWindow,
    int? maxOutputTokens,
    int? reasoningDepth,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncSeq,
  }) {
    return AIConfig(
      id: id ?? this.id,
      providerName: providerName ?? this.providerName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      extraApiKeys: extraApiKeys ?? this.extraApiKeys,
      modelName: modelName ?? this.modelName,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      isActive: isActive ?? this.isActive,
      isThinkingModel: isThinkingModel ?? this.isThinkingModel,
      isMultimodal: isMultimodal ?? this.isMultimodal,
      contextWindow: contextWindow ?? this.contextWindow,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      reasoningDepth: reasoningDepth ?? this.reasoningDepth,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'providerName': providerName,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'extraApiKeys': extraApiKeys.join(','),
      'modelName': modelName,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'isActive': isActive ? 1 : 0,
      'isThinkingModel': isThinkingModel ? 1 : 0,
      'isMultimodal': isMultimodal ? 1 : 0,
      'contextWindow': contextWindow,
      'maxOutputTokens': maxOutputTokens,
      'reasoningDepth': reasoningDepth,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'sync_seq': syncSeq,
    };
  }

  factory AIConfig.fromMap(Map<String, dynamic> map) {
    final extraKeysStr = map['extraApiKeys'] as String? ?? '';
    final extraKeys = extraKeysStr.isEmpty ? <String>[] : extraKeysStr.split(',');
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return AIConfig(
      id: (map['id'] as String?) ?? '',
      providerName: (map['providerName'] as String?) ?? '',
      baseUrl: (map['baseUrl'] as String?) ?? '',
      apiKey: (map['apiKey'] as String?) ?? '',
      extraApiKeys: extraKeys,
      modelName: (map['modelName'] as String?) ?? '',
      temperature: (map['temperature'] as double?) ?? 0.7,
      maxTokens: (map['maxTokens'] as int?) ?? 2048,
      isActive: map['isActive'] == 1,
      isThinkingModel: map['isThinkingModel'] == null ? true : map['isThinkingModel'] == 1,
      isMultimodal: map['isMultimodal'] == 1,
      contextWindow: (map['contextWindow'] as num?)?.toInt(),
      maxOutputTokens: (map['maxOutputTokens'] as num?)?.toInt(),
      reasoningDepth: (map['reasoningDepth'] as num?)?.toInt() ?? 0,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: tryParseDateTime(map['updatedAt']),
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  /// 已知非推理模型名称关键词（不区分大小写）
  /// 匹配到任一关键词的模型会自动关闭 isThinkingModel，启用 PromptRewriter
  static const _nonThinkingKeywords = [
    'deepseek-v3', 'deepseek-chat', 'deepseek-v2',
    'deepseek-v4', 'deepseek-v4-flash', 'deepseek-v4-pro',
    'qwen-max', 'qwen-plus', 'qwen-turbo', 'qwen-long', 'qwen2.5', 'qwen3', 'qwen3.7',
    'minimax', 'abab',
    'glm-4', 'glm-3', 'chatglm',
    'hunyuan',
    'yi-1.5', 'yi-lightning', 'yi-large', 'yi-medium',
    'spark', 'general',
    'ernie', 'baidu',
    'moonshot', 'kimi',
    'step-',
    'internlm',
    'llama-3', 'llama3', 'mistral', 'mixtral', 'command-r',
    // 海外常见非推理/低推理型号
    'gpt-4o-mini', 'gpt-4o', 'gpt-3.5', 'gpt-4-turbo', 'gpt-4.1', 'gpt-4.1-mini',
    'gpt-4.1-nano', 'gpt-5-mini', 'gpt-5-nano', 'gpt-5-chat',
    'claude-3-haiku', 'claude-3-5-haiku', 'claude-3-opus',
    'claude-3-5-sonnet', 'claude-sonnet-4', 'claude-haiku',
    'gemini-1.5', 'gemini-2.0-flash', 'gemini-2.5-flash',
    'grok-2', 'grok-3-mini', 'grok-4-fast',
  ];

  /// 自动检测模型是否为非推理模型（根据模型名称关键词判断）
  static bool isKnownNonThinkingModel(String modelName) {
    final lower = modelName.toLowerCase();
    return _nonThinkingKeywords.any((kw) => lower.contains(kw));
  }

  /// 按模型名 / baseURL 推断模型族（法功能海外策略与预算默认用）。
  ///
  /// 优先级：模型名关键词 > 端点/服务商。族是模型的属性，不是端点的：
  /// 中转站上任何模型都可能走 OpenAI 兼容端点（baseUrl 含 openai.com），
  /// 不能因为端点就把 deepseek-chat 判成 openai 族。
  /// 模型名没有关键词时才用端点兜底（如 custom 模型名 + 官方端点）。
  static ModelFamily detectModelFamily({
    required String modelName,
    String baseUrl = '',
    String providerName = '',
  }) {
    final m = modelName.toLowerCase();
    final b = baseUrl.toLowerCase();
    final p = providerName.toLowerCase();
    final blob = '$m $b $p';

    // 1) 模型名关键词优先。
    if (m.contains('claude')) return ModelFamily.anthropic;
    if (m.contains('gemini')) return ModelFamily.google;
    if (m.contains('grok')) return ModelFamily.xai;
    const domestic = [
      'deepseek', 'qwen', 'glm', 'chatglm', 'hunyuan', 'minimax', 'abab',
      'moonshot', 'kimi', 'yi-', 'spark', 'ernie', 'internlm', 'step-',
      'doubao', '豆包',
    ];
    if (domestic.any((k) => m.contains(k))) return ModelFamily.domestic;
    if (m.contains('gpt-')) return ModelFamily.openai;

    // 2) 模型名无关键词时，用端点/服务商兜底。
    if (blob.contains('anthropic')) return ModelFamily.anthropic;
    if (blob.contains('generativelanguage') || blob.contains('googleapis')) {
      return ModelFamily.google;
    }
    if (blob.contains('x.ai') || blob.contains('api.x.ai')) {
      return ModelFamily.xai;
    }
    if (blob.contains('openai.com') || blob.contains('api.openai')) {
      return ModelFamily.openai;
    }
    if (domestic.any((k) => blob.contains(k))) {
      return ModelFamily.domestic;
    }
    return ModelFamily.other;
  }

  /// 当前配置对应的模型族
  ModelFamily get modelFamily => detectModelFamily(
        modelName: modelName,
        baseUrl: baseUrl,
        providerName: providerName,
      );

  /// 法功能是否应对该配置启用「海外加强伪装」
  /// 海外模型安全分类器更敏感：推理/非推理都加强，不再只看 isThinkingModel
  bool get faOverseasBoost => modelFamily.isOverseas;

  /// 是否启用推理深度（关闭或非推理模型时无效果）。
  bool get reasoningEnabled => reasoningDepth > 0 && isThinkingModel;

  /// 本次请求实际生效的上下文窗口（token）。未设置时按模型族推荐。
  int get effectiveContextWindow =>
      contextWindow ?? ModelBudgetDefaults.contextWindowFor(modelFamily);

  /// 本次请求实际生效的最大输出（token）。
  ///
  /// 优先显式 maxOutputTokens；否则沿用旧 maxTokens；都没有才按族推荐，
  /// 保证历史配置（只填过 maxTokens）行为不变。
  int get effectiveMaxOutputTokens {
    final explicit = maxOutputTokens;
    if (explicit != null && explicit > 0) return explicit;
    if (maxTokens > 0) return maxTokens;
    return ModelBudgetDefaults.maxOutputTokensFor(modelFamily);
  }

  /// 推理深度 → 请求体附加参数（未知组合返回空，不污染 payload）。
  Map<String, dynamic> get reasoningPayload {
    if (!reasoningEnabled) return const {};
    if (!ModelBudgetDefaults.supportsReasoningEffort(modelName)) return const {};
    return {
      'reasoning_effort':
          ModelBudgetDefaults.reasoningEffortLabel(reasoningDepth),
    };
  }

  @override
  List<Object?> get props => [
        id,
        providerName,
        baseUrl,
        apiKey,
        extraApiKeys,
        modelName,
        temperature,
        maxTokens,
        isActive,
        isThinkingModel,
        isMultimodal,
        contextWindow,
        maxOutputTokens,
        reasoningDepth,
        createdAt,
        updatedAt,
        syncSeq,
      ];
}

/// 模型预算推荐（纯函数，单一来源）。
///
/// 用户没填上下文窗口 / 最大输出时，按模型族给一个保守默认值；
/// 设置页把这里的结果作为初始建议值，用户可随时覆盖。
class ModelBudgetDefaults {
  ModelBudgetDefaults._();

  /// 各族的默认上下文窗口（token）。
  static int contextWindowFor(ModelFamily family) => switch (family) {
        ModelFamily.openai => 128000,
        ModelFamily.anthropic => 200000,
        ModelFamily.google => 1000000,
        ModelFamily.xai => 131072,
        ModelFamily.domestic => 32768,
        ModelFamily.other => 32768,
      };

  /// 各族的默认单次最大输出（token）。
  static int maxOutputTokensFor(ModelFamily family) => switch (family) {
        ModelFamily.openai => 4096,
        ModelFamily.anthropic => 4096,
        ModelFamily.google => 8192,
        ModelFamily.xai => 4096,
        ModelFamily.domestic => 2048,
        ModelFamily.other => 2048,
      };

  /// 上下文窗口可填范围（UI 与写库兜底共用）。
  static const int contextWindowMin = 4096;
  static const int contextWindowMax = 2000000;

  /// 最大输出可填范围。
  static const int maxOutputTokensMin = 256;
  static const int maxOutputTokensMax = 65536;

  /// 是否属于已知支持 `reasoning_effort` 的 OpenAI 系推理模型。
  ///
  /// 只列 o 系列 / gpt-5 系 / 显式带 reasoning 的型号；其它家族一律不发字段，
  /// 避免 OpenAI 兼容中转站因未知字段直接 400。
  static bool supportsReasoningEffort(String modelName) {
    final m = modelName.toLowerCase();
    const keys = ['o1', 'o3', 'o4', 'gpt-5', 'reasoning'];
    return keys.any(m.contains);
  }

  /// 推理深度 → `reasoning_effort` 取值（low / medium / high）。
  static String reasoningEffortLabel(int depth) => switch (depth) {
        <= 1 => 'low',
        2 => 'medium',
        _ => 'high',
      };

  /// 推理深度 → 中文标签（界面展示用）。
  static String reasoningDepthLabel(int depth) => switch (depth) {
        <= 0 => '关闭',
        1 => '低',
        2 => '中',
        _ => '高',
      };
}
