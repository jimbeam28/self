# 修复开发计划

> 分析日期：2026-05-15
> Bug 描述：播放页面侧滑退出、迷你播放栏交互异常、设置不生效、编辑连接崩溃
> 优先级分级：P0 核心功能崩溃 → P1 功能异常 → P2 轻微问题

---

## 总览

| 批次 | 优先级 | 任务数 | 说明 |
|------|--------|--------|------|
| Batch A | P0 | 5 | 核心功能崩溃或不可用，必须优先修复 |
| Batch B | P1 | 1 | 功能异常但可绕过 |
| Batch C | P2 | 1 | 视觉问题，不影响功能 |

---

## Bug 分析

### BUG-1 播放页面侧滑行为异常

**现象**：在音乐播放页面从屏幕上侧滑，直接停止播放并退出应用。

**预期**：侧滑一下退出到文件浏览器页面（应用内返回），连续划两下退出到桌面（应用继续在后台运行，播放音乐）。

**根因**：从 Browser 页面导航到 Player 页面时使用了 `go()` 而非 `push()`。`GoRouter.go()` 会替换整个导航栈，导致 `/player` 成为栈中唯一的路由，侧滑时无法回退到前序页面。涉及 `browser_screen.dart`（3处）和 `mini_player_bar.dart`（2处）。

**影响范围**：用户无法从播放页面返回文件浏览器，必须完全退出应用再重新进入。

---

### BUG-2 迷你播放栏交互异常

**BUG-2a**：点击迷你播放栏非按钮区域（曲目标题/进度条）进入播放页面时，音乐从头开始播放。根因是 `PlayerScreen.initState()` 无条件调用 `_loadAndPlay()`，未检测音频是否已在播放中。

**BUG-2b**：迷你播放栏的播放/暂停按钮点击无反应。根因是外层 `InkWell`（监听全区域点击）与内部 `IconButton` 产生手势冲突，两个 `TapGestureRecognizer` 在竞技场中相互竞争导致都无法胜出。

**BUG-2c**：迷你播放栏的下一曲按钮会跳转到播放页面，而非留在浏览器直接切歌。根因是 `_NextButton.onPressed` 调用了 `GoRouter.of(context).go('/player')` 导航。

**影响范围**：迷你播放栏的三大核心交互（进入播放页、播放控制、切歌）全部异常。

---

### BUG-3 设置不生效 + 编辑连接崩溃

**BUG-3a**：设置页的快退/快进步长修改后，播放页面按钮图标数字不变。根因是按钮使用了硬编码的 `Icons.replay_10` / `Icons.forward_30`，图标上的数字是字形的一部分无法动态改变。**与 BUG-4 合并**。

**BUG-3b**：设置默认播放速度后，播放页面配速不变。根因是 `_loadAndPlay()` 从未调用 `player.setSpeed()`，且 `setDefaultSpeedProvider` 不同步 `currentSpeedProvider`。

**BUG-3c**：连接列表点击竖三点→编辑，直接报错 `LateInitializationError: Field '_state' has not been initialized`。根因是 `ConnectionFormController._state` 为 `late` 字段，在 `ConnectionForm` 的 `initState` 中才初始化，但 `ConnectionEditScreen.build()` 中的 `_needsValidation()` 在 build 阶段就访问了 `_state`，早于 widget 挂载。

**影响范围**：设置形同虚设，编辑连接100%崩溃。

---

### BUG-4 快退/快进按钮图标数字不更新

**现象**：左快退按钮文字始终显示10，右快进文字始终显示30。

**根因**：`player_screen.dart` 中按钮图标使用 `Icons.replay_10` 和 `Icons.forward_30`，数字内嵌在图标中无法动态改变。虽然 `seekStep` 通过 `ref.watch(seekStepProvider)` 正确读取，但只用于 tooltip 和实际跳过逻辑，未用于图标选择。**与 BUG-3a 为同一根因**。

---

## Batch A — P0 严重缺陷

### A-1  播放页面侧滑返回修复

**关联 Bug**：BUG-1
**根因**：Brower→Player 导航使用 `go()` 替换了导航栈，导致侧滑无法返回。`browser_screen.dart` 3处、`mini_player_bar.dart` 2处。

**修复方案**：将所有导航到 `/player` 的 `go()` 改为 `push()`。

```dart
// browser_screen.dart — 3 处 goRouter.go('/player') 改为 goRouter.push('/player')
// 第 194 行（resume 对话框确认后）
// 第 213 行（从头播放对话框）
// 第 226 行（无进度，直接播放）

// mini_player_bar.dart — 2 处
// 第 62 行：onTap: () => GoRouter.of(context).push('/player'),
// 第 216 行：GoRouter.of(context).push('/player'),
```

修复后路由栈变为 `/browser` → `/player`（push叠加），侧滑一次回 `/browser`，再侧滑退出桌面。`AudioPlayer` 是 app 级 Provider，`audio_service` 配置了 `androidStopForegroundOnPause: false`，退出后音频继续播放。

**需要完成的工作：**
1. `browser_screen.dart`：3 处 `go('/player')` → `push('/player')`
2. `mini_player_bar.dart`：2 处 `go('/player')` → `push('/player')`

**涉及文件**：
- `lib/features/browser/browser_screen.dart`
- `lib/features/player/widgets/mini_player_bar.dart`

---

### A-2  迷你播放栏进入播放页面不重新加载

**关联 Bug**：BUG-2a
**根因**：`PlayerScreen.initState()` 无条件调用 `_loadAndPlay()`（player_screen.dart 第110行），该方法会 `player.stop()` + `player.setAudioSource()` + `player.play()`，导致从头播放。未检测"音频已在播放中"的场景。

**修复方案**：在 `initState()` 或 `_loadAndPlay()` 开头添加守卫——如果音频当前正在播放或已加载完毕，跳过加载直接显示 UI。

```dart
// player_screen.dart initState() 中
void initState() {
  super.initState();
  final player = ref.read(audioPlayerProvider);
  if (player.playing || player.processingState == ProcessingState.ready) {
    _loadState = PlayerLoadState.ready;
    _setupListeners();
    return;
  }
  _loadAndPlay();
}
```

**需要完成的工作：**
1. 在 `initState()` 中添加音频已播放/已就绪的检测，跳过 `_loadAndPlay()`
2. 测试：正在播放中点击迷你播放栏进入，音乐不中断

**涉及文件**：
- `lib/features/player/player_screen.dart`

---

### A-3  迷你播放栏播放按钮手势冲突修复

**关联 Bug**：BUG-2b
**根因**：`mini_player_bar.dart` 第61行外层 `InkWell`（全区域点击导航）包裹了第164行的 `IconButton`。两个 widget 都注册 `TapGestureRecognizer`，在 Flutter 手势竞技场中竞争导致均无法胜出。

**修复方案**：将外层 `InkWell` 替换为仅包裹曲目标题区域的 `GestureDetector`，让按钮区域脱离导航点击范围。

```dart
// 修改前（有冲突）：
InkWell(
  onTap: () => GoRouter.of(context).go('/player'),
  child: Row(children: [
    Expanded(child: Text(title)),
    IconButton(onPressed: _togglePlayPause),  // 冲突！
  ]),
)

// 修改后（消除冲突）：
Row(children: [
  GestureDetector(
    onTap: () => GoRouter.of(context).push('/player'),
    child: Expanded(child: Text(title)),
  ),
  IconButton(onPressed: _togglePlayPause),  // 不再冲突
])
```

**需要完成的工作：**
1. 移除顶层 `InkWell`
2. 用 `GestureDetector` 包裹曲目标题区域（`Expanded(child: Text(...))`）
3. `IconButton` 保持在 `GestureDetector` 外部

**涉及文件**：
- `lib/features/player/widgets/mini_player_bar.dart`

---

### A-4  默认播放速度设置应用

**关联 Bug**：BUG-3b
**根因**：`_loadAndPlay()`（player_screen.dart）从未调用 `player.setSpeed(defaultSpeed)`，默认速度设置被忽略。`setDefaultSpeedProvider`（player_provider.dart 第264行）只持久化不更新运行时状态。

**修复方案**：

1. 在 `_loadAndPlay()` 的 `player.play()` 之前应用默认速度：
```dart
// player_screen.dart _loadAndPlay() 第171行之前添加
final defaultSpeed = ref.read(defaultSpeedProvider);
if (defaultSpeed != 1.0) {
  await player.setSpeed(defaultSpeed);
  ref.read(currentSpeedProvider.notifier).state = defaultSpeed;
}
```

2. 在 `setDefaultSpeedProvider` 中同步更新运行时：
```dart
// player_provider.dart setDefaultSpeedProvider 中添加
ref.read(currentSpeedProvider.notifier).state = speed;
```

**需要完成的工作：**
1. `_loadAndPlay()` 中 `player.play()` 前读取并应用 `defaultSpeedProvider`
2. `setDefaultSpeedProvider` 中同步更新 `currentSpeedProvider`
3. 测试：修改默认速度后播放新曲目，实际速度应用新值

**涉及文件**：
- `lib/features/player/player_screen.dart`
- `lib/features/player/player_provider.dart`

---

### A-5  编辑连接 LateInitializationError 修复

**关联 Bug**：BUG-3c
**根因**：`ConnectionFormController._state`（connection_form.dart 第13行）是 `late` 字段，仅在 `_ConnectionFormState.initState()` 调用 `_attach(this)` 时初始化。但 `ConnectionEditScreen.build()` 在 widget 挂载前就通过 `_needsValidation()` → `_formController.url` 访问了 `_state`，导致崩溃。时序：build → _canSave() → _needsValidation() → _formController.url → _state 未初始化 → 崩溃。

**修复方案**：在 `ConnectionFormController` 中添加初始化检测，在 `_needsValidation()` 中添加守卫。

```dart
// connection_form.dart ConnectionFormController 类中
bool get isAttached {
  try { _state; return true; } on LateInitializationError { return false; }
}
```

```dart
// connection_edit_screen.dart _needsValidation() 第195行
bool _needsValidation() {
  if (_originalConfig == null) return true;
  if (!_formController.isAttached) return false;  // 守卫
  return _formController.url != _originalConfig!.url || ...;
}
```

**需要完成的工作：**
1. `ConnectionFormController` 添加 `isAttached` getter
2. `_needsValidation()` 添加 `isAttached` 守卫条件

**涉及文件**：
- `lib/features/connection/widgets/connection_form.dart`
- `lib/features/connection/connection_edit_screen.dart`

---

## Batch B — P1 功能异常

### B-1  迷你播放栏下一曲按钮不跳转页面

**关联 Bug**：BUG-2c
**根因**：`mini_player_bar.dart` 第216行 `_NextButton.onPressed` 在更新队列后调用了 `GoRouter.of(context).go('/player')`。按钮应直接加载下一曲音频并留在当前页面。

**修复方案**：在 `_NextButton.onPressed` 中直接完成音频加载播放，移除导航调用。

```dart
onPressed: () async {
  final notifier = ref.read(currentPlayQueueProvider.notifier);
  final nextIdx = notifier.state.nextIndex;
  if (nextIdx == null) return;
  notifier.state = notifier.state.advanceTo(nextIdx);

  final conn = ref.read(activeConnectionProvider).valueOrNull;
  if (conn == null) return;
  final password = await ref.read(secureStorageProvider.future);
  final source = AudioSourceBuilder.buildWithBasePath(
    baseUrl: conn.url,
    filePath: notifier.state.current.path,
    username: conn.username,
    password: password,
  );
  final player = ref.read(audioPlayerProvider);
  await player.stop();
  await player.setAudioSource(source);
  await player.play();
  // 不调用 GoRouter 导航，留在当前页面
},
```

**需要完成的工作：**
1. 在 `_NextButton.onPressed` 中读取连接信息和凭据，直接加载下一曲
2. 移除 `GoRouter.of(context).go('/player')` 调用
3. 测试：在浏览器点击下一曲，歌曲切换且停留在浏览器页面

**涉及文件**：
- `lib/features/player/widgets/mini_player_bar.dart`

---

## Batch C — P2 轻微问题

### C-1  快退/快进按钮图标动态显示步长

**关联 Bug**：BUG-1b、BUG-3a
**根因**：`player_screen.dart` 第682行 `Icons.replay_10`、第718行 `Icons.forward_30`，图标内数字硬编码。`seekStep` 通过 `ref.watch(seekStepProvider)` 正确读取并用于 tooltip 和跳过逻辑，但图标未动态选择。

**修复方案**：根据 `seekStep` 动态选择图标，添加辅助方法：

```dart
IconData _iconForSeekBackward(int seconds) {
  switch (seconds) {
    case 5:  return Icons.replay_5;
    case 10: return Icons.replay_10;
    case 30: return Icons.replay_30;
    default: return Icons.replay;  // 15s, 60s 用通用图标
  }
}

IconData _iconForSeekForward(int seconds) {
  switch (seconds) {
    case 5:  return Icons.forward_5;
    case 10: return Icons.forward_10;
    case 30: return Icons.forward_30;
    default: return Icons.forward;  // 15s, 60s 用通用图标
  }
}
```

修改第682行：`icon: Icons.replay_10` → `icon: _iconForSeekBackward(seekStep)`
修改第718行：`icon: Icons.forward_30` → `icon: _iconForSeekForward(seekStep)`

对于 15s 和 60s（没有对应 Material Icon 的步长），可以在通用图标旁叠加 `Text('${seekStep}')` 标签，或在 `_buildSkipButton` 中增加 `label` 参数。

**需要完成的工作：**
1. 添加 `_iconForSeekBackward` / `_iconForSeekForward` 辅助方法
2. 替换快退/快进按钮的硬编码图标为动态选择
3. 可选：为无对应图标的步长添加文字标签

**涉及文件**：
- `lib/features/player/player_screen.dart`

---

## 实施顺序建议

```
A-5 (编辑连接崩溃)       ← 独立，无依赖，30 分钟
A-4 (默认速度设置)         ← 独立，无依赖，30 分钟
A-2 (进入播放不重加载)     ← 独立，无依赖，30 分钟
  ↓
A-1 (侧滑返回修复)        ← 独立，与 A-3 同文件但无依赖，30 分钟
A-3 (播放按钮手势冲突)     ← 独立，与 A-1 同文件但无依赖，30 分钟
  ↓
B-1 (下一曲不跳转)        ← 与 A-1/A-3 同文件，建议在 A-1 和 A-3 后处理，1 小时
  ↓
C-1 (图标动态显示)        ← 独立，30 分钟
```

说明：
- A-1、A-3、B-1 都涉及 `mini_player_bar.dart`，建议按顺序处理避免合并冲突
- A-5 是纯独立修复，可最先处理
- 所有 P0 修复合计约 2.5 小时
- 全部修复合计约 4 小时
