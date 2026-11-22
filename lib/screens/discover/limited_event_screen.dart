import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../config/constants.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/limited_event_service.dart';
import '../../services/life/timed_event_service.dart';
import '../chat/chat_detail_screen.dart';

/// 限定剧情 — 节日 / 角色生日 / 纪念日限时剧情。
///
/// - 内置节日（情人节 / 520 / 圣诞 / 元旦）按公历日期换算，不用建表；
/// - 角色生日 / 纪念日复用定时事件表（`ai_timed_events`）；
/// - 进行中的剧情点“开始剧情”打开聊天并预填一句开场白，用户自己决定发不发，
///   不自动发消息；已错过的显示“等明年”，不提供入口。
class LimitedEventScreen extends StatefulWidget {
  const LimitedEventScreen({super.key});

  @override
  State<LimitedEventScreen> createState() => _LimitedEventScreenState();
}

class _LimitedEventScreenState extends State<LimitedEventScreen> {
  var _occurrences = <LimitedEventOccurrence>[];
  var _characters = <AICharacter>[];
  var _enabled = true;
  var _loading = true;
  var _loadError = false;
  StreamSubscription? _chatSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    super.dispose();
  }

  String? get _userId {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final storage = context.read<LocalStorageRepository>();
      final enabled = storage.getBool(PrefKeys.limitedEventEnabled) ?? true;
      final characters = await storage.getAllAICharactersDeduped();
      final nameById = {
        for (final c in characters) c.id: c.userNickname ?? c.name,
      };

      // 定时事件里的生日 / 纪念日：读不到库或读失败时只展示内置节日，不报错。
      final timed = <LimitedEventOccurrence>[];
      try {
        final db = storage.database;
        if (db != null) {
          final svc = TimedEventService(db);
          final events = await svc.getUpcoming(
            userId: _userId ?? 'local_user',
            days: 366,
          );
          final now = DateTime.now();
          for (final ev in events) {
            final occ = LimitedEventService.fromTimedEvent(
              ev,
              now,
              characterName: nameById[ev.characterId],
            );
            if (occ != null) timed.add(occ);
          }
        }
      } catch (e) {
        debugPrint('限定剧情：定时事件读取失败，仅展示内置节日 — $e');
      }

      final all = [
        ...LimitedEventService.listBuiltins(DateTime.now()),
        ...timed,
      ];
      all.sort((a, b) {
        final rank = (LimitedEventOccurrence o) =>
            o.status == LimitedEventStatus.active
                ? 0
                : o.status == LimitedEventStatus.upcoming
                    ? 1
                    : 2;
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        return a.daysUntil.compareTo(b.daysUntil);
      });

      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _characters = characters;
        _occurrences = all;
        _loading = false;
      });
    } catch (e) {
      debugPrint('限定剧情：加载失败 — $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    final storage = context.read<LocalStorageRepository>();
    await storage.setBool(PrefKeys.limitedEventEnabled, value);
    if (!mounted) return;
    setState(() => _enabled = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? '限定剧情已开启' : '限定剧情已关闭，节日当天角色不再主动提起')),
    );
  }

  /// 点“开始剧情”：有归属角色的直接开聊；内置节日先选一位角色。
  Future<void> _onStart(LimitedEventOccurrence occ) async {
    if (occ.characterId != null) {
      final character = _characters
          .where((c) => c.id == occ.characterId)
          .firstOrNull;
      if (character == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这位角色找不到了，可能已被删除')),
        );
        return;
      }
      await _openChat(character, occ);
      return;
    }
    if (_characters.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有角色，先去添加一位角色吧')),
      );
      return;
    }
    final picked = await showModalBottomSheet<AICharacter>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              leading: Icon(Icons.celebration_outlined),
              title: Text('和谁一起过节？'),
              subtitle: Text('选一位角色，打开聊天开始限定剧情'),
            ),
            ..._characters.map((c) => ListTile(
                  leading: CircleAvatar(
                    child: Text(c.name.isEmpty ? '?' : c.name[0]),
                  ),
                  title: Text(c.userNickname ?? c.name),
                  onTap: () => Navigator.pop(ctx, c),
                )),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      await _openChat(picked, occ);
    }
  }

  /// 打开聊天并预填一句开场白（只填进输入框，用户自己决定发不发）。
  /// 会话查找 / 创建逻辑与通讯录 _startChat 一致。
  Future<void> _openChat(
    AICharacter character,
    LimitedEventOccurrence occ,
  ) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final storage = context.read<LocalStorageRepository>();
    final user = authState.user;
    final invite = '今天是${occ.title}，我们一起过节吧！';

    final sessions = await storage.getChatSessions(user.id);
    final existing =
        sessions.where((s) => s.aiCharacterId == character.id).firstOrNull;
    if (existing != null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            session: existing,
            initialMessage: invite,
          ),
        ),
      );
      return;
    }

    final chatBloc = ChatBloc(storage, AIService(storage));
    _chatSub?.cancel();
    _chatSub = chatBloc.stream.listen((state) {
      if (state is ChatSessionCreated) {
        _chatSub?.cancel();
        _chatSub = null;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatDetailScreen(
                session: state.session,
                initialMessage: invite,
              ),
            ),
          ).then((_) => chatBloc.close());
        } else {
          chatBloc.close();
        }
      }
    });
    chatBloc.add(ChatCreateSession(userId: user.id, character: character));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('限定剧情'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
              ? _buildError()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _buildSwitchCard(cs),
                    const SizedBox(height: 12),
                    ..._occurrences.map((o) => _buildTile(o, cs)),
                    const SizedBox(height: 16),
                    Text(
                      '七夕等农历节日没有固定公历日期，这里不硬编日期；'
                      '想过七夕可以在生活页给角色登记一条自定义节日定时事件。',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('加载失败，请重试'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _load,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerLow,
      elevation: 0,
      child: SwitchListTile(
        title: const Text('限定剧情'),
        subtitle: const Text('开启后，节日当天角色会在聊天里主动提起过节；关闭后不再注入，不弹窗、不推送。'),
        value: _enabled,
        onChanged: _toggleEnabled,
      ),
    );
  }

  Widget _buildTile(LimitedEventOccurrence occ, ColorScheme cs) {
    final isActive = occ.status == LimitedEventStatus.active;
    final icon = occ.title.contains('生日')
        ? Icons.cake_outlined
        : occ.title.contains('纪念')
            ? Icons.favorite_outline
            : Icons.celebration_outlined;
    final statusColor = isActive
        ? cs.primary
        : occ.status == LimitedEventStatus.upcoming
            ? cs.tertiary
            : cs.onSurfaceVariant;
    return Card(
      elevation: 0,
      color: isActive ? cs.primaryContainer.withOpacity(0.5) : cs.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: statusColor, size: 22),
        ),
        title: Text(
          occ.characterName != null
              ? '${occ.title} · ${occ.characterName}'
              : occ.title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${occ.date.month}月${occ.date.day}日 · ${occ.description}',
        ),
        trailing: isActive
            ? FilledButton.tonal(
                onPressed: () => _onStart(occ),
                child: const Text('开始剧情'),
              )
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  occ.statusText,
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ),
      ),
    );
  }
}
