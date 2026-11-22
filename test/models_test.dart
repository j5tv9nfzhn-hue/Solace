import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/user.dart';
import 'package:solace/models/chat_session.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/ai_config.dart';

void main() {
  group('User Model', () {
    late User testUser;

    setUp(() {
      testUser = User(
        id: 'user_1',
        nickname: '测试用户',
        createdAt: DateTime(2026, 1, 1),
      );
    });

    test('创建 User 实例', () {
      expect(testUser.id, 'user_1');
      expect(testUser.nickname, '测试用户');
      expect(testUser.coins, 100);
      expect(testUser.totalCoinsEarned, 100);
      expect(testUser.totalCoinsSpent, 0);
    });

    test('copyWith 正确更新字段', () {
      final updated = testUser.copyWith(nickname: '新名字', coins: 200);
      expect(updated.nickname, '新名字');
      expect(updated.coins, 200);
      expect(updated.id, 'user_1');
    });

    test('toMap 和 fromMap 往返一致', () {
      final map = testUser.toMap();
      final fromMap = User.fromMap(map);
      expect(fromMap.id, testUser.id);
      expect(fromMap.nickname, testUser.nickname);
      expect(fromMap.coins, testUser.coins);
    });

    test('Equatable 比较相同对象', () {
      final user2 = User(
        id: 'user_1',
        nickname: '测试用户',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(testUser, user2);
    });

    test('Equatable 比较不同对象', () {
      final user2 = User(
        id: 'user_2',
        nickname: '其他用户',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(testUser == user2, false);
    });
  });

  group('ChatSession Model', () {
    late ChatSession testSession;

    setUp(() {
      testSession = ChatSession(
        id: 'session_1',
        userId: 'user_1',
        aiCharacterId: 'char_1',
        aiCharacterName: '小助手',
        createdAt: DateTime(2026, 1, 1),
      );
    });

    test('创建 ChatSession 实例', () {
      expect(testSession.id, 'session_1');
      expect(testSession.aiCharacterName, '小助手');
      expect(testSession.intimacyLevel, 0);
      expect(testSession.unreadCount, 0);
      expect(testSession.isBlocked, false);
      expect(testSession.blockedBy, BlockedBy.none);
    });

    test('copyWith 正确更新字段', () {
      final updated = testSession.copyWith(
        intimacyLevel: 50,
        lastMessage: '你好',
        unreadCount: 3,
      );
      expect(updated.intimacyLevel, 50);
      expect(updated.lastMessage, '你好');
      expect(updated.unreadCount, 3);
      expect(updated.id, 'session_1');
    });

    test('copyWith clearBlock 重置封禁状态', () {
      final blocked = testSession.copyWith(
        isBlocked: true,
        blockedBy: BlockedBy.user,
        blockReason: '测试',
      );
      expect(blocked.isBlocked, true);

      final unblocked = blocked.copyWith(clearBlock: true);
      expect(unblocked.isBlocked, false);
      expect(unblocked.blockedBy, BlockedBy.none);
      expect(unblocked.blockReason, null);
    });

    test('toMap 和 fromMap 往返一致', () {
      final map = testSession.toMap();
      final fromMap = ChatSession.fromMap(map);
      expect(fromMap.id, testSession.id);
      expect(fromMap.aiCharacterName, testSession.aiCharacterName);
      expect(fromMap.intimacyLevel, testSession.intimacyLevel);
    });

    test('番外小剧场会话：isSideStory 与父子关系字段', () {
      final sideStory = ChatSession(
        id: 'side_1',
        userId: 'user_1',
        aiCharacterId: 'char_1',
        aiCharacterName: '小助手',
        createdAt: DateTime(2026, 1, 2),
        sessionType: 'side_story',
        parentChatId: 'session_1',
        sideStoryTitle: '海边度假',
      );
      expect(sideStory.isSideStory, true);
      expect(testSession.isSideStory, false);

      final roundTrip = ChatSession.fromMap(sideStory.toMap());
      expect(roundTrip.isSideStory, true);
      expect(roundTrip.parentChatId, 'session_1');
      expect(roundTrip.sideStoryTitle, '海边度假');
    });

    test('BlockedBy 枚举值正确', () {
      expect(BlockedBy.values.length, 3);
      expect(BlockedBy.none.index, 0);
      expect(BlockedBy.user.index, 1);
      expect(BlockedBy.ai.index, 2);
    });
  });

  group('ChatMessage Model', () {
    test('创建 ChatMessage 实例', () {
      final msg = ChatMessage(
        id: 'msg_1',
        chatId: 'session_1',
        senderId: 'user_1',
        content: '你好',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(msg.id, 'msg_1');
      expect(msg.content, '你好');
      expect(msg.senderId, 'user_1');
      expect(msg.type, MessageType.text);
      expect(msg.status, MessageStatus.sent);
    });

    test('MessageType 枚举值正确', () {
      expect(MessageType.values.length, 13);
      expect(MessageType.text.index, 0);
      expect(MessageType.image.index, 1);
      expect(MessageType.audio.index, 2);
      expect(MessageType.file.index, 3);
      expect(MessageType.system.index, 4);
      expect(MessageType.sticker.index, 5);
      expect(MessageType.voice.index, 6);
      expect(MessageType.transfer.index, 7);
      expect(MessageType.redPacket.index, 8);
      expect(MessageType.location.index, 9);
      expect(MessageType.vcard.index, 10);
      expect(MessageType.link.index, 11);
      expect(MessageType.call.index, 12);
    });

    test('MessageStatus 枚举值正确', () {
      expect(MessageStatus.values.length, 7);
      expect(MessageStatus.sending.index, 0);
      expect(MessageStatus.sent.index, 1);
      expect(MessageStatus.delivered.index, 2);
      expect(MessageStatus.read.index, 3);
      expect(MessageStatus.error.index, 4);
      expect(MessageStatus.failed.index, 5);
      expect(MessageStatus.cancelled.index, 6);
    });
  });

  group('AICharacter Model', () {
    test('ReplyMode 枚举值正确', () {
      expect(ReplyMode.values.length, 4);
      expect(ReplyMode.instant.index, 0);
      expect(ReplyMode.normal.index, 1);
      expect(ReplyMode.delayed.index, 2);
      expect(ReplyMode.manual.index, 3);
    });
  });

  group('AIConfig Model', () {
    test('创建 AIConfig 实例', () {
      final config = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        modelName: 'gpt-4',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(config.id, 'config_1');
      expect(config.providerName, 'openai');
      expect(config.modelName, 'gpt-4');
      expect(config.temperature, 0.7);
      expect(config.maxTokens, 2000);
      expect(config.isActive, true);
    });

    test('allApiKeys 返回所有密钥', () {
      final config = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-main',
        extraApiKeys: ['sk-extra1', 'sk-extra2'],
        modelName: 'gpt-4',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(config.allApiKeys.length, 3);
      expect(config.allApiKeys[0], 'sk-main');
      expect(config.allApiKeys[1], 'sk-extra1');
    });

    test('copyWith 正确更新字段', () {
      final config = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        modelName: 'gpt-4',
        createdAt: DateTime(2026, 1, 1),
      );
      final updated = config.copyWith(
        modelName: 'gpt-4-turbo',
        temperature: 0.9,
      );
      expect(updated.modelName, 'gpt-4-turbo');
      expect(updated.temperature, 0.9);
      expect(updated.id, 'config_1');
    });

    test('effectiveContextWindow 未填按模型族默认，填了用填的值', () {
      final openai = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        modelName: 'gpt-4',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(openai.effectiveContextWindow, 128000);
      final custom = openai.copyWith(contextWindow: 64000);
      expect(custom.effectiveContextWindow, 64000);
      final domestic = openai.copyWith(modelName: 'deepseek-chat');
      expect(domestic.effectiveContextWindow, 32768);
    });

    test('effectiveMaxOutputTokens 优先级：显式值 > 旧 maxTokens > 族默认', () {
      final base = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        modelName: 'gpt-4',
        maxTokens: 3000,
        createdAt: DateTime(2026, 1, 1),
      );
      // 未填显式值时沿用旧 maxTokens
      expect(base.effectiveMaxOutputTokens, 3000);
      // 显式值优先于旧 maxTokens
      expect(base.copyWith(maxOutputTokens: 8000).effectiveMaxOutputTokens,
          8000);
      // 旧 maxTokens 为 0 时才回退族默认
      final fallback = base.copyWith(maxTokens: 0);
      expect(fallback.effectiveMaxOutputTokens, 4096);
    });

    test('reasoningPayload 关闭/非推理/不支持的模型时为空', () {
      AIConfig make({required String modelName, int depth = 2}) => AIConfig(
            id: 'config_1',
            providerName: 'openai',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'sk-test',
            modelName: modelName,
            reasoningDepth: depth,
            createdAt: DateTime(2026, 1, 1),
          );
      // 深度 0 = 关闭
      expect(make(modelName: 'o1', depth: 0).reasoningPayload, isEmpty);
      // 非推理模型不发
      expect(
          make(modelName: 'o1').copyWith(isThinkingModel: false)
              .reasoningPayload,
          isEmpty);
      // 不在允许名单里的模型不发
      expect(make(modelName: 'gpt-4').reasoningPayload, isEmpty);
      expect(make(modelName: 'deepseek-chat').reasoningPayload, isEmpty);
    });

    test('reasoningPayload 深度 1/2/3 对应 low/medium/high', () {
      AIConfig make(String modelName, int depth) => AIConfig(
            id: 'config_1',
            providerName: 'openai',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'sk-test',
            modelName: modelName,
            reasoningDepth: depth,
            createdAt: DateTime(2026, 1, 1),
          );
      expect(make('o1', 1).reasoningPayload,
          {'reasoning_effort': 'low'});
      expect(make('o1', 2).reasoningPayload,
          {'reasoning_effort': 'medium'});
      expect(make('gpt-5', 3).reasoningPayload,
          {'reasoning_effort': 'high'});
      expect(ModelBudgetDefaults.reasoningDepthLabel(0), '关闭');
      expect(ModelBudgetDefaults.reasoningDepthLabel(1), '低');
      expect(ModelBudgetDefaults.reasoningDepthLabel(2), '中');
      expect(ModelBudgetDefaults.reasoningDepthLabel(3), '高');
    });

    test('模型预算范围常量', () {
      expect(ModelBudgetDefaults.contextWindowMin, 4096);
      expect(ModelBudgetDefaults.contextWindowMax, 2000000);
      expect(ModelBudgetDefaults.maxOutputTokensMin, 256);
      expect(ModelBudgetDefaults.maxOutputTokensMax, 65536);
    });

    test('toMap 和 fromMap 往返保留三个新字段', () {
      final config = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        modelName: 'o1',
        contextWindow: 64000,
        maxOutputTokens: 8000,
        reasoningDepth: 2,
        createdAt: DateTime(2026, 1, 1),
      );
      final roundTrip = AIConfig.fromMap(config.toMap());
      expect(roundTrip.contextWindow, 64000);
      expect(roundTrip.maxOutputTokens, 8000);
      expect(roundTrip.reasoningDepth, 2);
      // 老数据缺三列时回退默认值
      final legacy = AIConfig.fromMap({
        'id': 'config_1',
        'providerName': 'openai',
        'baseUrl': 'https://api.openai.com/v1',
        'apiKey': 'sk-test',
        'modelName': 'gpt-4',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(legacy.contextWindow, isNull);
      expect(legacy.maxOutputTokens, isNull);
      expect(legacy.reasoningDepth, 0);
    });
  });
}
