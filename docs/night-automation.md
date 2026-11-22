# 生活自动化（夜间升级线，night/automation）

Solace 的生活自动化分两档。铁律：一切只留在本机，不上传数据；
人设隔离——自动化工具对角色不可见，角色看不到工具定义，只收到
执行结果作为上下文，再用自己的口吻说话；绝不自动支付。

## 一、普通权限档（主力，默认可用）

### 1. 真实感上下文

`lib/services/reality_context_service.dart`，注入点在
`AIService._buildMessages`（`ai_service/context_forgiveness.dart`），
以独立的 `system` 消息、`<internal_context type="reality">` 身份注入，
不是角色口吻；5 分钟缓存，总开关关闭或采集失败时不注入、不阻塞聊天。

| 来源 | 权限/开启方式 | 开不了时 |
|---|---|---|
| 时间/日期/星期、电量与充电状态 | 无需权限 | 电量读不到就省略该行 |
| 最近 3 小时亮屏总分钟 | 系统设置 → 使用情况访问 | 传 0 / 省略该行 |
| 天气 | 无（只读 3 小时内缓存） | 无缓存不写，绝不拿默认晴天冒充 |
| 定位 | 定位权限 | 省略；只取 1 位小数粗略坐标 |
| 今日日程 | 系统设置 → 日历权限 | 省略；原生读 `CalendarContract`，只取标题+开始时间，上限 10 条 |
| 步数 | —— | **暂未接入**：无计步/健康插件，绝不编假步数 |

隐私：使用时长只取总分钟，不取应用名与应用内文字；日程不读描述、
地点、参与人；定位不发精确经纬度。快照随聊天请求发给用户自己配置
的模型接口（与聊天内容同一条路），不上传到任何 Solace 服务。

开关：设置 → 生活自动化 → 真实感上下文。总开关默认开；使用时长、
定位、日程默认关；天气缓存默认开。

### 2. 主动提醒（时间触发）

`lib/services/proactive_trigger_rules.dart`（`builtinTimeRules` 与
`matchTimeBased`）+ `lib/services/proactive_time_triggers.dart`
（开关/冷却/每日上限，`SharedPreferences` 持久化）+ 决策引擎
`proactive_decision_engine.dart` 快路径（情绪规则优先，零 LLM 开销）。

| 规则 | 窗口/条件 | 节流 |
|---|---|---|
| 饭点问吃不吃 | 11:30–13:00、17:30–19:00 | 冷却 4 小时，每天 1 次 |
| 玩手机久了提醒 | 最近 3 小时亮屏 ≥ 90 分钟 | 冷却 4 小时，每天 2 次 |
| 半夜还在亮屏催睡 | 23:00–06:00 且亮屏 ≥ 10 分钟 | 冷却 4 小时，每天 1 次 |

三条都只注入上下文、不直接发消息；未授权使用情况访问时，带亮屏
下限的规则自然不命中（降级为只看时间）。每条可单独关，默认全开。

### 3. 确定性工具

`lib/services/automation_tools.dart`。每工具三档策略（每次询问/
允许/拒绝，默认每次询问，对标 Operit）。执行结果只产出一句话摘要
供上下文用，工具 schema 绝不进角色 prompt。

| 工具 | 做法 | 权限/降级 |
|---|---|---|
| 外卖深链 | 美团外卖 `meituanwaimai://waimai.meituan.com/search?query=`，备选美团主 App `imeituan://www.meituan.com/search?q=`；只带店名+菜名搜索词 | 未装 App 时留文字，不跳；不预填支付、不自动下单，支付由用户在美团里自己指纹确认 |
| 设闹钟 | 系统 `AlarmClock.ACTION_SET_ALARM` Intent（`EXTRA_SKIP_UI=false`，用户自己点确认） | 无时钟应用时报失败 |
| 新建日历事件 | 系统 `ACTION_INSERT` 日历新建页（用户自己点保存） | 无需日历读写权限；无日历应用时报失败 |
| 发本地通知 | 复用 `NotificationService`（即时/延时） | 需通知权限；精确闹钟未授权时延时通知可能失败 |
| 换壁纸 | `WallpaperManager.setBitmap` | `SET_WALLPAPER` 为普通权限；图片须是本机文件，不存在/解码失败时报失败 |

## 二、通知监听（可选，默认关闭）

`android/.../NotificationBridgeService.kt` +
`lib/services/notification_listener_bridge.dart`。
只读通知栏标题/正文摘要与可回复/可播放动作的存在性，不读 App 内
文字、不截屏、不模拟点击。代回只在用户主动点的通知上用系统
`RemoteInput` 递送；音乐控制只点音乐通知自带的播放/暂停动作。
系统授权（通知访问）只能用户在系统设置里手动开；模块开关关掉即
停用全部动作。

## 三、无障碍档（可选模块，默认关闭）

`android/.../SolaceAccessibilityService.kt` +
`lib/services/accessibility_automation_service.dart`。
对标 Operit 的公开做法：工具权限分级、默认每次询问、操作前明确
说明、可随时关；但本模块比 Operit 更收敛——**不做 Shizuku、不要求
root、不读屏、不做手势**。

- 服务骨架：`onAccessibilityEvent` 刻意空实现；配置
  `canRetrieveWindowContent=false`、`canPerformGestures=false`；
  全服务无 `performAction`、无手势、无读屏。
- 安全演示流程：设置页输入目标 App 包名（+可选深链）→ 亲手点按钮 →
  原生侧二次校验模块开关 → 普通 Intent 打开目标页面 → 停在打开页
  即止，绝不自动点确认/支付/提交。
- 设置页与系统设置里的文案都写明：“核心功能不依赖它，关掉不影响
  任何核心体验”。

注意：仓库旧的 `strings.xml` 里有一条
`accessibility_service_description`（“让 AI 角色能够感知屏幕内容、
辅助点击和滑动操作”），与本模块的实际行为不符；本次未删它（无任何
代码引用），新增了诚实的 `solace_accessibility_service_description`
供新服务使用，旧文案待 Julie 决定是否删除。

## 四、设置入口

设置 → 生活自动化（`lib/screens/profile/automation_settings_screen.dart`）：
上下文开关与授权状态、提醒开关、工具策略与试按按钮、通知监听、
无障碍、权限分级说明。从系统设置页返回后用生命周期监听刷新授权状态。

## 五、未验证与待拍板

- 本机无 Flutter/JDK/Android SDK，未跑 `flutter analyze/test/build`；
  CI 未跑；未真机；未实测权限弹窗、系统设置跳转、美团 Scheme 跳转、
  通知代回、音乐控制、无障碍打开 App。
- 天气目前只有缓存来源：从未缓存过天气时上下文里没有天气；是否接
  一个在线天气接口（需联网与定位）待定。
- 步数未接入：接 Health Connect 还是系统计步传感器待定。
- 深夜催睡提醒与既有静默时段（23:00–07:00 不主动发消息，
  `ProactivePolicyService`）的关系：时间规则只注入上下文、不直接
  发消息，所以不冲突；但若以后要把它做成推送式提醒，需另定策略。
- 两个提交曾因多线共享同一仓库目录、HEAD 被其他线切走而落到
  `night/ui-ux` 与 `night/features` 分支上（`9086132`、`93cbb5f`）；
  本分支用 cherry-pick 取回了内容，另两个分支上的重复提交未动
  （避免改写他人分支历史），以本分支为准。
