import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/constants.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/accessibility_automation_service.dart';
import '../../services/automation_tools.dart';
import '../../services/notification_listener_bridge.dart';
import '../../services/proactive_time_triggers.dart';
import '../../services/reality_context_service.dart';
import '../../services/wellbeing_service.dart';

/// 生活自动化设置页：真实感上下文 / 主动提醒 / 确定性工具 / 通知监听 / 无障碍。
///
/// 权限分级（对标 Operit：标准权限默认可用，无障碍档可选、默认关闭）：
/// - 真实感上下文与确定性工具只用普通权限或系统 Intent，默认可用；
/// - 通知监听与无障碍是可选模块，默认关闭，系统授权只能用户在系统
///   设置里手动开，程序内开不了；
/// - 每工具三档策略（每次询问/允许/拒绝），默认每次询问。
class AutomationSettingsScreen extends StatefulWidget {
  const AutomationSettingsScreen({super.key});

  @override
  State<AutomationSettingsScreen> createState() =>
      _AutomationSettingsScreenState();
}

class _AutomationSettingsScreenState extends State<AutomationSettingsScreen>
    with WidgetsBindingObserver {
  final _timeTriggerState = ProactiveTimeTriggerState();
  final _notificationBridge = NotificationListenerBridge();
  final _accessibilityService = AccessibilityAutomationService();
  final _automationTools = AutomationTools();
  final _wellbeing = WellbeingService();

  RealityContextService? _realityService;
  RealityContextSettings _realitySettings = const RealityContextSettings();
  bool _hasUsageAccess = false;
  bool _hasLocationPermission = false;

  bool _mealEnabled = true;
  bool _longScreenEnabled = true;
  bool _lateNightEnabled = true;

  bool _listenerModuleEnabled = false;
  bool _listenerSystemEnabled = false;

  bool _accessibilityModuleEnabled = false;
  bool _accessibilityServiceEnabled = false;

  Map<String, AutomationToolPolicy> _toolPolicies = {
    for (final id in AutomationTools.allToolIds) id: AutomationToolPolicy.ask,
  };

  final _packageController =
      TextEditingController(text: 'com.android.settings');
  final _uriController = TextEditingController();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _packageController.dispose();
    _uriController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页回来时刷新授权状态（开关值以实际系统状态为准）。
    if (state == AppLifecycleState.resumed) _loadStatuses();
  }

  Future<void> _loadAll() async {
    final storage = context.read<LocalStorageRepository>();
    _realityService = RealityContextService(storage);
    _realitySettings = await _realityService!.loadSettings();
    _mealEnabled = await _timeTriggerState.isEnabled('time_meal');
    _longScreenEnabled =
        await _timeTriggerState.isEnabled('time_long_screen');
    _lateNightEnabled = await _timeTriggerState.isEnabled('time_late_night');
    for (final id in AutomationTools.allToolIds) {
      _toolPolicies[id] = await _automationTools.getPolicy(id);
    }
    await _loadStatuses();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadStatuses() async {
    _hasUsageAccess = await _wellbeing.hasUsageAccess();
    _hasLocationPermission =
        (await Permission.locationWhenInUse.status).isGranted;
    _listenerModuleEnabled =
        await _notificationBridge.isModuleEnabled();
    _listenerSystemEnabled = await _notificationBridge.isSystemEnabled();
    _accessibilityModuleEnabled =
        await _accessibilityService.isModuleEnabled();
    _accessibilityServiceEnabled =
        await _accessibilityService.isServiceEnabled();
    if (mounted) setState(() {});
  }

  Future<void> _saveReality(RealityContextSettings next) async {
    setState(() => _realitySettings = next);
    await _realityService?.saveSettings(next);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openAppSettings() async {
    try {
      await const MethodChannel(MethodChannels.settings)
          .invokeMethod('openAppSettings');
    } catch (e) {
      _showSnack('打不开系统设置：$e');
    }
  }

  Future<void> _runToolTest(
      String toolId, Map<String, String> args) async {
    final result = await _automationTools.execute(
      toolId,
      args,
      confirmed: true,
    );
    _showSnack(result.summary);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('生活自动化'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _sectionTitle('真实感上下文', colorScheme),
                _card(colorScheme, [
                  SwitchListTile(
                    title: const Text('真实感上下文'),
                    subtitle: const Text(
                        '把时间、电量等真实处境告诉角色，只用系统上下文身份注入，不进角色口吻'),
                    value: _realitySettings.enabled,
                    onChanged: (v) =>
                        _saveReality(_realitySettings.copyWith(enabled: v)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('使用时长'),
                    subtitle: Text(_hasUsageAccess
                        ? '最近 3 小时亮屏总分钟（只取总和，不读应用内容）'
                        : '未授权：需在系统设置开“使用情况访问”，否则自动省略'),
                    value: _realitySettings.usageEnabled,
                    onChanged: (v) => _saveReality(
                        _realitySettings.copyWith(usageEnabled: v)),
                  ),
                  _actionRow(
                    label: _hasUsageAccess ? '使用情况访问：已授予' : '去开使用情况访问',
                    onTap: () async {
                      await _wellbeing.requestUsageAccess();
                      await _loadStatuses();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('天气（仅缓存）'),
                    subtitle: const Text('只用 3 小时内缓存天气，无缓存不写，绝不编晴天'),
                    value: _realitySettings.weatherEnabled,
                    onChanged: (v) => _saveReality(
                        _realitySettings.copyWith(weatherEnabled: v)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('定位（粗略）'),
                    subtitle: Text(_hasLocationPermission
                        ? '已授予：只取 1 位小数粗略坐标，不发精确位置'
                        : '未授予：需定位权限，否则自动省略'),
                    value: _realitySettings.locationEnabled,
                    onChanged: (v) => _saveReality(
                        _realitySettings.copyWith(locationEnabled: v)),
                  ),
                  _actionRow(
                    label: _hasLocationPermission ? '定位权限：已授予' : '去开定位权限',
                    onTap: () async {
                      await Permission.locationWhenInUse.request();
                      await _loadStatuses();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('今日日程'),
                    subtitle: const Text(
                        '只读标题与开始时间，不读描述、地点与参与人；未授权自动省略'),
                    value: _realitySettings.calendarEnabled,
                    onChanged: (v) => _saveReality(
                        _realitySettings.copyWith(calendarEnabled: v)),
                  ),
                  _actionRow(
                    label: '去系统设置开日历权限',
                    onTap: _openAppSettings,
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      '步数暂未接入：本机没有计步/健康插件，绝不编假步数，待以后接 Health Connect 再补。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _sectionTitle('主动提醒', colorScheme),
                _card(colorScheme, [
                  SwitchListTile(
                    title: const Text('饭点问吃不吃'),
                    subtitle: const Text('午饭 11:30–13:00、晚饭 17:30–19:00，每天最多 1 次'),
                    value: _mealEnabled,
                    onChanged: (v) async {
                      setState(() => _mealEnabled = v);
                      await _timeTriggerState.setEnabled('time_meal', v);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('玩手机久了提醒'),
                    subtitle: const Text('最近 3 小时亮屏超过 90 分钟，冷却 4 小时，每天最多 2 次'),
                    value: _longScreenEnabled,
                    onChanged: (v) async {
                      setState(() => _longScreenEnabled = v);
                      await _timeTriggerState.setEnabled(
                          'time_long_screen', v);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('半夜还在亮屏催睡'),
                    subtitle: const Text('23:00–06:00 亮屏超过 10 分钟才催，冷却 4 小时，每天最多 1 次'),
                    value: _lateNightEnabled,
                    onChanged: (v) async {
                      setState(() => _lateNightEnabled = v);
                      await _timeTriggerState.setEnabled('time_late_night', v);
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      '三条提醒都只注入上下文、不直接发消息，且情绪类提醒优先于时间提醒；关掉即停。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _sectionTitle('确定性工具', colorScheme),
                _card(colorScheme, [
                  for (final id in AutomationTools.allToolIds) ...[
                    ListTile(
                      title: Text(AutomationTools.toolNames[id] ?? id),
                      subtitle: Text(
                          AutomationTools.toolPermissionNotes[id] ?? ''),
                      trailing: DropdownButton<AutomationToolPolicy>(
                        value: _toolPolicies[id],
                        items: const [
                          DropdownMenuItem(
                            value: AutomationToolPolicy.ask,
                            child: Text('每次询问'),
                          ),
                          DropdownMenuItem(
                            value: AutomationToolPolicy.allow,
                            child: Text('允许'),
                          ),
                          DropdownMenuItem(
                            value: AutomationToolPolicy.deny,
                            child: Text('拒绝'),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _toolPolicies[id] = v);
                          await _automationTools.setPolicy(id, v);
                        },
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _runToolTest(
                            AutomationTools.toolTakeout,
                            {'shopName': '测试店铺', 'dishes': '测试菜品'},
                          ),
                          child: const Text('试：打开美团搜索'),
                        ),
                        OutlinedButton(
                          onPressed: () => _runToolTest(
                            AutomationTools.toolAlarm,
                            {
                              'hour': '8',
                              'minute': '0',
                              'label': 'Solace 测试闹钟',
                            },
                          ),
                          child: const Text('试：设闹钟 8:00'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            final tomorrow = DateTime.now().add(
                              const Duration(days: 1),
                            );
                            final start = DateTime(tomorrow.year,
                                tomorrow.month, tomorrow.day, 9, 0);
                            final end = start.add(
                              const Duration(minutes: 30),
                            );
                            _runToolTest(
                              AutomationTools.toolCalendar,
                              {
                                'title': 'Solace 测试事件',
                                'startMillis':
                                    start.millisecondsSinceEpoch.toString(),
                                'endMillis':
                                    end.millisecondsSinceEpoch.toString(),
                              },
                            );
                          },
                          child: const Text('试：新建日历事件'),
                        ),
                        OutlinedButton(
                          onPressed: () => _runToolTest(
                            AutomationTools.toolNotification,
                            {
                              'title': 'Solace 测试',
                              'body': '这是一条本地测试通知',
                            },
                          ),
                          child: const Text('试：发本地通知'),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '外卖只跳到美团搜索页，不预填支付、不自动下单，支付由你自己在美团里指纹确认；换壁纸需先有本机图片文件，暂不提供试按。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _sectionTitle('通知监听（可选）', colorScheme),
                _card(colorScheme, [
                  SwitchListTile(
                    title: const Text('通知监听'),
                    subtitle: Text(_listenerSystemEnabled
                        ? '系统已授予通知访问'
                        : '未授予：需在系统设置→通知访问里手动开，程序内开不了'),
                    value: _listenerModuleEnabled,
                    onChanged: (v) async {
                      setState(() => _listenerModuleEnabled = v);
                      await _notificationBridge.setModuleEnabled(v);
                      if (v && !_listenerSystemEnabled) {
                        await _notificationBridge.openSystemSettings();
                      }
                    },
                  ),
                  _actionRow(
                    label: '去系统设置开通知访问',
                    onTap: () async {
                      await _notificationBridge.openSystemSettings();
                      await _loadStatuses();
                    },
                  ),
                  _actionRow(
                    label: '查看最近通知',
                    onTap: () async {
                      final items =
                          await _notificationBridge.getRecent();
                      if (!mounted) return;
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('最近通知'),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: items.isEmpty
                                ? const Text('暂无通知（模块未开、未授权，或通知栏为空）。')
                                : ListView(
                                    shrinkWrap: true,
                                    children: [
                                      for (final n in items)
                                        ListTile(
                                          title: Text(n.title.isEmpty
                                              ? n.packageName
                                              : n.title),
                                          subtitle: Text(n.text),
                                          trailing: n.hasReplyAction
                                              ? const Text('可回复')
                                              : null,
                                        ),
                                    ],
                                  ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text(
                      '只读通知栏摘要、在你点的通知上代回、只点音乐通知的播放/暂停；不联网、不上传。关掉即停用。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _sectionTitle('无障碍（可选模块）', colorScheme),
                _card(colorScheme, [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '核心功能不依赖它，关掉不影响任何核心体验。只按你的明确指令打开指定 App 的指定页面，停在打开页即止；不读屏、不模拟点击、不自动点确认/支付/提交。',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('无障碍模块'),
                    subtitle: Text(_accessibilityServiceEnabled
                        ? '系统无障碍服务已开启'
                        : '未开启：需在系统无障碍设置里手动开，程序内开不了'),
                    value: _accessibilityModuleEnabled,
                    onChanged: (v) async {
                      setState(() => _accessibilityModuleEnabled = v);
                      await _accessibilityService.setModuleEnabled(v);
                      if (v && !_accessibilityServiceEnabled) {
                        await _accessibilityService.openSystemSettings();
                      }
                    },
                  ),
                  _actionRow(
                    label: '去系统无障碍设置',
                    onTap: () async {
                      await _accessibilityService.openSystemSettings();
                      await _loadStatuses();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: TextField(
                      controller: _packageController,
                      decoration: const InputDecoration(
                        labelText: '目标 App 包名',
                        hintText: '如 com.android.settings',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _uriController,
                      decoration: const InputDecoration(
                        labelText: '指定页面深链（可选）',
                        hintText: '不填则只打开 App 首页',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final result =
                              await _accessibilityService.openAppPage(
                            packageName: _packageController.text,
                            uri: _uriController.text.isEmpty
                                ? null
                                : _uriController.text,
                          );
                          _showSnack(result.message);
                        },
                        child: const Text('打开该 App（停在打开页，不自动操作）'),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _sectionTitle('权限分级说明', colorScheme),
                _card(colorScheme, const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '标准权限（默认可用）：真实感上下文、确定性工具，只用普通权限或系统 Intent。\n\n'
                      '可选模块（默认关闭）：通知监听、无障碍，需你去系统设置里手动授权，随时可关。\n\n'
                      '不用 Shizuku、不要求 root。所有数据只留在本机，不上传。',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _card(ColorScheme colorScheme, List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _actionRow({required String label, required VoidCallback onTap}) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
      dense: true,
    );
  }
}
