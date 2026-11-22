import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/ai_character.dart';
import '../../models/dream_diary_entry.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/dream_diary_service.dart';

/// 梦境日记 — 用户写给角色的脑洞剧情。
///
/// - 只存在手机本地（SharedPreferences JSON 列表），不上传；
/// - 每篇默认不分享给角色，逐条打开“分享给TA”后，内容才会注入单聊 prompt，
///   角色才能读到并回应；关闭分享后下次聊天不再注入。
class DreamDiaryScreen extends StatefulWidget {
  const DreamDiaryScreen({super.key});

  @override
  State<DreamDiaryScreen> createState() => _DreamDiaryScreenState();
}

class _DreamDiaryScreenState extends State<DreamDiaryScreen> {
  var _characters = <AICharacter>[];
  var _entries = <DreamDiaryEntry>[];
  String? _filterCharacterId;
  var _loading = true;
  var _loadError = false;

  static const _moodOptions = ['甜', '刀', '悬疑', '日常', '脑洞'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final storage = context.read<LocalStorageRepository>();
      final characters = await storage.getAllAICharactersDeduped();
      final entries = await DreamDiaryService.loadAll(storage);
      if (!mounted) return;
      setState(() {
        _characters = characters;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      debugPrint('梦境日记：加载失败 — $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  List<DreamDiaryEntry> get _visibleEntries {
    if (_filterCharacterId == null) return _entries;
    return _entries
        .where((e) => e.characterId == _filterCharacterId)
        .toList();
  }

  String _characterName(String characterId) {
    final found =
        _characters.where((c) => c.id == characterId).firstOrNull;
    return found?.userNickname ?? found?.name ?? '已删除的角色';
  }

  Future<void> _toggleShare(DreamDiaryEntry entry, bool shared) async {
    final storage = context.read<LocalStorageRepository>();
    await DreamDiaryService.updateEntry(
      storage,
      entry.copyWith(sharedWithCharacter: shared),
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(shared ? '已分享给TA，下次聊天TA就能读到' : '已取消分享，TA 不会再读到这篇'),
      ),
    );
  }

  Future<void> _deleteEntry(DreamDiaryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这篇日记？'),
        content: Text('《${entry.title.isEmpty ? '无标题' : entry.title}》删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final storage = context.read<LocalStorageRepository>();
    await DreamDiaryService.deleteEntry(storage, entry.id);
    await _load();
  }

  Future<void> _showWriteDialog() async {
    if (_characters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有角色，先去添加一位角色吧')),
      );
      return;
    }
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    var selectedCharacter = _filterCharacterId != null
        ? _characters
            .where((c) => c.id == _filterCharacterId)
            .firstOrNull
        : null;
    selectedCharacter ??= _characters.first;
    var selectedMood = '';
    var share = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('写一篇梦境日记'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<AICharacter>(
                  value: selectedCharacter,
                  decoration: const InputDecoration(labelText: '写给谁'),
                  items: _characters
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.userNickname ?? c.name),
                          ))
                      .toList(),
                  onChanged: (c) =>
                      setDialogState(() => selectedCharacter = c),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '给这场脑洞起个名字',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '剧情',
                    hintText: '写下你和TA的脑洞剧情……',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('心情'),
                Wrap(
                  spacing: 8,
                  children: _moodOptions
                      .map((m) => ChoiceChip(
                            label: Text(m),
                            selected: selectedMood == m,
                            onSelected: (_) => setDialogState(() {
                              selectedMood = selectedMood == m ? '' : m;
                            }),
                          ))
                      .toList(),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('分享给TA'),
                  subtitle: const Text('打开后，角色会在聊天里读到并回应这篇日记'),
                  value: share,
                  onChanged: (v) =>
                      setDialogState(() => share = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (contentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('先写点剧情内容吧')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final storage = context.read<LocalStorageRepository>();
    await DreamDiaryService.createEntry(
      storage: storage,
      characterId: selectedCharacter!.id,
      title: titleController.text,
      content: contentController.text,
      mood: selectedMood,
      sharedWithCharacter: share,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(share ? '已保存并分享给TA' : '已保存（未分享，角色读不到）'),
      ),
    );
  }

  void _showDetail(DreamDiaryEntry entry) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(entry.title.isEmpty ? '无标题' : entry.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_characterName(entry.characterId)} · ${_formatDate(entry.createdAt)}'
                '${entry.mood.isEmpty ? '' : ' · 心情：${entry.mood}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(entry.content),
              const SizedBox(height: 12),
              Text(
                entry.sharedWithCharacter
                    ? '已分享给TA：下次聊天TA能读到这篇。'
                    : '未分享：只有你能看到，TA 读不到。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteEntry(entry);
            },
            child: const Text('删除'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('梦境日记'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showWriteDialog,
        tooltip: '写日记',
        child: const Icon(Icons.edit_outlined),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
              ? _buildError()
              : Column(
                  children: [
                    _buildFilterRow(cs),
                    Expanded(
                      child: _visibleEntries.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: _visibleEntries.length,
                              itemBuilder: (ctx, i) =>
                                  _buildTile(_visibleEntries[i], cs),
                            ),
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
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildFilterRow(ColorScheme cs) {
    if (_characters.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('全部'),
            selected: _filterCharacterId == null,
            onSelected: (_) =>
                setState(() => _filterCharacterId = null),
          ),
          const SizedBox(width: 8),
          ..._characters.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.userNickname ?? c.name),
                  selected: _filterCharacterId == c.id,
                  onSelected: (_) =>
                      setState(() => _filterCharacterId = c.id),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.nightlight_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text('还没有梦境日记', style: tt.titleMedium),
            const SizedBox(height: 8),
            Text(
              '把你和TA的脑洞剧情写下来；打开“分享给TA”后，\n角色会在聊天里读到并回应。默认不分享。',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _showWriteDialog,
              child: const Text('写第一篇'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(DreamDiaryEntry entry, ColorScheme cs) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.nightlight_outlined, color: cs.primary, size: 22),
        ),
        title: Text(
          entry.title.isEmpty ? '无标题' : entry.title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_characterName(entry.characterId)} · ${_formatDate(entry.createdAt)}'
              '${entry.mood.isEmpty ? '' : ' · ${entry.mood}'}',
            ),
            Text(
              entry.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                const Text('分享给TA', style: TextStyle(fontSize: 12)),
                Switch(
                  value: entry.sharedWithCharacter,
                  onChanged: (v) => _toggleShare(entry, v),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: '删除',
                  onPressed: () => _deleteEntry(entry),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _showDetail(entry),
      ),
    );
  }
}
