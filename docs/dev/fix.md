# 修复开发计划

> 分析日期：2026-05-16
> 来源：全代码审查（33 个 .dart 文件），共发现 43 个问题
> 优先级分级：P0 内存泄漏/逻辑缺陷 → P1 功能隐患 → P2 代码质量/架构

---

## 总览

| 批次 | 优先级 | 任务数 | 说明 |
|------|--------|--------|------|
| Batch G | P0 | 5 | 内存泄漏、循环依赖、短音频进度清零、负值定时器、HTTP连接泄漏 |
| Batch H | P1 | 10 | 非原子保存、无界缓存、lint抑制、不安全类型转换、静默错误吞噬 |
| Batch I | P2 | 12 | 代码重复、正则缓存、版本硬编码、字符串匹配精度、路由守卫 |

---

## Batch G — P0 严重缺陷

### G-1  修复 NasAudioHandler StreamSubscription 内存泄漏

**关联问题**：AudioHandler 创建 3 个 StreamSubscription 但 dispose() 从未被调用

**根因**：`audio_handler.dart:47-51` — `_stateSub`、`_positionSub`、`_durationSub` 在构造函数中创建。`dispose()` 方法存在（161-165行）但无任何代码调用它。`_audioHandler` 在 `main.dart` 中是顶层变量，`audioHandlerProvider` 只是透传引用，没有在应用退出时清理。

**修复方案**：在 `audioPlayerProvider` 的 `ref.onDispose` 中调用 `audioHandler.dispose()`：

```dart
// main.dart ProviderScope overrides 中：
audioPlayerProvider.overrideWith((ref) {
  final player = AudioPlayer();
  ref.onDispose(() {
    _audioHandler?.dispose();
    player.dispose();
  });
  return player;
}),
```

或在 `NasAudioHandler` 中重写 `AudioService.stop()` 时触发清理。

**涉及文件**：
- `lib/core/services/audio_handler.dart`
- `lib/main.dart`

---

### G-2  打破 skipToNextProvider ↔ loadAndPlayProvider 循环依赖

**关联问题**：两个 Provider 互相引用，靠显式类型注解勉强工作

**根因**：`player_provider.dart:514-580` — `skipToNextProvider` 在公司数中调用 `ref.read(loadAndPlayProvider)()`（526行），而 `loadAndPlayProvider` 内部的 processing listener 回调中调用 `ref.read(skipToNextProvider)()`（580行）。

**修复方案**：将 skipToNext 的逻辑内联到 `loadAndPlayProvider` 中，不单独暴露为 Provider。改为在 `loadAndPlayProvider` 内部定义 `_advanceToNext()` 私有函数：

```dart
final loadAndPlayProvider = Provider<...>((ref) {
  // Internal helper — not a separate provider, so no cycle.
  void _advanceToNext() {
    final queue = ref.read(currentPlayQueueProvider);
    final mode = ref.read(playModeProvider);
    if (queue == null) return;
    final nextIdx = PlayQueue.nextIndex(queue.currentIndex, queue.length, mode);
    if (nextIdx == null) return;
    ref.read(saveProgressProvider)();
    final nextQueue = queue.withIndex(nextIdx);
    ref.read(currentPlayQueueProvider.notifier).state = nextQueue;
    // Recurse via loadAndPlay — this is safe because it's an async callback,
    // not a synchronous Provider construction dependency.
    ref.read(loadAndPlayProvider)();
  }

  return () async {
    // ... in processing listener:  _advanceToNext();  replaces ref.read(skipToNextProvider)()
  };
});
```

`skipToNextProvider` 可以保留作为公开 API（供 player_screen._playNext() 调用），但改为调用内联的 `_advanceToNext`，不再通过 `loadAndPlayProvider` 走一圈。

**涉及文件**：
- `lib/features/player/player_provider.dart`

---

### G-3  修复短音频（<10秒）进度保存逻辑矛盾

**关联问题**：`progress_dao.dart:171` — `shouldClear(positionMs, durationMs)` 中 `positionMs > durationMs - 10000` 对于 `durationMs < 10000` 的文件恒为 true

**根因**：当 `durationMs = 5000` 时，`durationMs - 10000 = -5000`，任何 `positionMs >= 0` 都满足条件。`shouldSave` 返回 true（`positionMs >= 5000`）时 `shouldClear` 也返回 true，导致 6-9 秒的音频永远无法保存有效进度。

**修复方案**：

```dart
static bool shouldClear(int positionMs, int? durationMs) {
  if (durationMs == null) return false;
  // Only clear when within 10 seconds of the end AND the file is long enough
  // for the 10-second window to be meaningful.
  if (durationMs <= 10000) return false;
  return positionMs > durationMs - 10000;
}
```

**涉及文件**：
- `lib/core/database/dao/progress_dao.dart`

---

### G-4  拦截负值/零值定时器输入

**关联问题**：`timer_service.dart:110` — `startDuration(-5)` 设 `endTime` 到过去，`checkExpired()` 立即返回 true

**根因**：方法无输入校验。

**修复方案**：

```dart
TimerState startDuration(int minutes) {
  if (minutes <= 0) throw ArgumentError.value(minutes, 'minutes', 'must be positive');
  final now = DateTime.now();
  _state = TimerState(
    mode: TimerMode.duration,
    endTime: now.add(Duration(minutes: minutes)),
    startedAt: now,
  );
  return _state!;
}
```

**涉及文件**：
- `lib/core/services/timer_service.dart`

---

### G-5  修复 WebDavClient.validate() 未消费 HTTP 响应体

**关联问题**：`webdav_client.dart:150-173` — `streamedResponse.stream` 从未 drain

**根因**：`validate()` 用 `_httpClient.send()` 获取响应后只检查 `statusCode`，不读取 body stream。HTTP 持久连接无法复用。

**修复方案**：在返回前 drain 响应体：

```dart
final streamedResponse = await _httpClient.send(request);
final statusCode = streamedResponse.statusCode;
// Drain the response body so the HTTP connection can be reused.
await streamedResponse.stream.drain<void>();
```

**涉及文件**：
- `lib/core/network/webdav_client.dart`

---

## Batch H — P1 功能隐患

### H-1  ConnectionSaver.save() 三步操作增加原子性保护

**关联问题**：`connection_provider.dart:172-193` — insert→secureStorage→update 三步非原子

**修复方案**：在步骤2（secureStorage写入）失败时，回滚步骤1（删除已插入的DB行）。在步骤3失败时，至少记录错误日志。

**涉及文件**：
- `lib/features/connection/connection_provider.dart`

---

### H-2  directoryCacheProvider 添加容量上限

**关联问题**：`browser_provider.dart:92` — 内存缓存无界增长

**修复方案**：添加 LRU 淘汰策略或最大条目数限制（如 50 个目录）。最简单的方案：在写入缓存前检查 `cache.length >= 50`，若超限则清除最旧的条目。

**涉及文件**：
- `lib/features/browser/browser_provider.dart`

---

### H-3  替换文件级 lint 抑制为行级抑制

**关联问题**：`browser_screen.dart:10` — `// ignore_for_file: use_build_context_synchronously` 覆盖整个文件

**修复方案**：删除第10行的 `ignore_for_file`，在确实需要异步 context 访问的每行前添加 `// ignore: use_build_context_synchronously`。

**涉及文件**：
- `lib/features/browser/browser_screen.dart`

---

### H-4  PlayQueue.fromMap 安全类型转换 + 边界校验

**关联问题**：`play_queue.dart:180` — `as int` 在 JSON 缺字段时抛 TypeError；`nextIndex` 不校验 current 边界

**修复方案**：
- `fromMap` 中 `map['currentIndex'] as int?` 配合 `?? 0` 默认值
- `nextIndex`/`previousIndex` 添加 `if (current < 0 || current >= length) return null;`
- 构造函数添加 `assert(currentIndex >= 0 && currentIndex < files.length)`

**涉及文件**：
- `lib/shared/models/play_queue.dart`

---

### H-5  _NextButton 切歌失败时显示错误反馈

**关联问题**：`mini_player_bar.dart:319` — 丢弃 loadAndPlayProvider 返回值，失败时无反馈

**修复方案**：添加 SnackBar（与 `_showQueueSheet` 中已有的反馈一致）：

```dart
final loaded = await ref.read(loadAndPlayProvider)();
if (loaded == null && context.mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('切换失败，请检查连接')),
  );
}
```

**涉及文件**：
- `lib/features/player/widgets/mini_player_bar.dart`

---

### H-6  自定义定时选 0:00 时禁用确认按钮

**关联问题**：`timer_button.dart:190` — 0小时0分钟确认后无声关闭

**修复方案**：当 `totalMinutes == 0` 时禁用确认按钮（灰色文字），或弹出时默认选中 5 分钟。

**涉及文件**：
- `lib/features/timer/widgets/timer_button.dart`

---

### H-7  startupValidationProvider 空 id 保护

**关联问题**：`connection_provider.dart:127` — `activeConn.id` 为 null 时 key 变成 `connection_password_null`

**修复方案**：在拼接 key 前检查 `activeConn.id != null`：

```dart
if (activeConn.id == null) return WebDavValidationResult.authError();
final passwordKey = 'connection_password_${activeConn.id}';
```

**涉及文件**：
- `lib/features/connection/connection_provider.dart`

---

### H-8  静默 catch 块添加日志

**关联问题**：`browser_provider.dart:380`、`progress_dao.dart:376` 两处 `catch (_)` 完全静默

**修复方案**：添加 `debugPrint('Error in restoreQueueFromPrefsProvider: $e')`。

**涉及文件**：
- `lib/features/browser/browser_provider.dart`
- `lib/core/database/dao/progress_dao.dart`

---

### H-9  去重 seekStep 双 Provider

**关联问题**：`seekStepSettingProvider`（settings_provider）和 `seekStepProvider`（player_provider）读同一个 key

**修复方案**：删除 `settings_provider.dart` 中的 `seekStepSettingProvider`，统一使用 `player_provider.dart` 中的 `seekStepProvider`。设置页改为直接 import 并 watch `seekStepProvider`。

**涉及文件**：
- `lib/features/settings/settings_provider.dart`
- `lib/features/settings/settings_screen.dart`

---

### H-10  修复 ConnectionEditScreen build 中的副作用

**关联问题**：`connection_edit_screen.dart:108` — `_originalConfig ??= connection` 在 build 阶段执行

**修复方案**：将初始化逻辑移到 `initState()`：

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final config = ref.read(connectionByIdProvider(widget.connectionId)).valueOrNull;
    if (config != null) _originalConfig = config;
  });
}
```

**涉及文件**：
- `lib/features/connection/connection_edit_screen.dart`

---

## Batch I — P2 代码质量/架构

### I-1  TimerState 相等性包含 startedAt

**问题**：`timer_service.dart:67-74` — `operator ==` 不比较 `startedAt`，造成同时长 timer 实例相等

**修复**：在 `==` 和 `hashCode` 中加入 `startedAt`。

**涉及文件**：`lib/core/services/timer_service.dart`

---

### I-2  删除不可达的 catch 块

**问题**：`connection_dao.dart:122-128` — catch 块注释说表可能不存在，但 `_onCreate` 始终创建该表

**修复**：移除 try-catch，直接执行 delete。

**涉及文件**：`lib/core/database/dao/connection_dao.dart`

---

### I-3  缓存 RegExp 为 static const

**问题**：`webdav_client.dart:263,298-301` — 每次方法调用重新创建 RegExp

**修复**：声明为 `static final _propfindPattern = RegExp(...)` 等。

**涉及文件**：`lib/core/network/webdav_client.dart`

---

### I-4  版本号从 package_info_plus 读取

**问题**：`about_screen.dart:9` — 版本号硬编码 `1.0.0`

**修复**：添加 `package_info_plus` 依赖，用 `PackageInfo.fromPlatform()` 读取。

**涉及文件**：`lib/features/settings/about_screen.dart`、`pubspec.yaml`

---

### I-5  TextPainter 添加 dispose()

**问题**：`breadcrumb_bar.dart:57-59` — TextPainter 创建后未释放

**修复**：在 `LayoutBuilder` 回调结束前调用 `textPainter.dispose()`。

**涉及文件**：`lib/features/browser/widgets/breadcrumb_bar.dart`

---

### I-6  错误消息中过滤 URL 敏感信息

**问题**：`webdav_client.dart:242` — `'无法连接到服务器：$e'` 可能泄露 URL

**修复**：使用 `e is SocketException` 类型判断，输出不包含原始 URL 的通用消息。

**涉及文件**：`lib/core/network/webdav_client.dart`

---

### I-7  _sourceMatchesQueue 使用精确路径比对

**问题**：`player_screen.dart:130` — `.contains()` 子串匹配 `/song.mp3` 会误匹配 `/folder/song.mp3`

**修复**：改用 `source.uri.path.endsWith(queue.current.path)` 或比较解码后的完整路径：

```dart
final decodedPath = Uri.decodeComponent(source.uri.path);
return decodedPath.endsWith(queue.current.path);
```

**涉及文件**：`lib/features/player/player_screen.dart`

---

### I-8  进度弹窗 dismiss 时给予反馈

**问题**：`browser_screen.dart:179-226` — 弹窗被 dismiss（null 返回）时无反应

**修复方案**：无需修改——dismiss 表示用户主动取消，保持当前选择是合理的默认行为。可选项：选中当前文件高亮但无需额外反馈。

**涉及文件**：无代码修改（WONTFIX，标记为设计决策）

---

### I-9  提取共享 _ValidationBanner 组件

**问题**：`connection_screen.dart:217-288` 和 `connection_edit_screen.dart:303-375` 含几乎相同的 `_ValidationBanner`/`_Banner` 代码

**修复**：提取到 `lib/features/connection/widgets/validation_banner.dart`。

**涉及文件**：
- `lib/features/connection/widgets/validation_banner.dart`（新建）
- `lib/features/connection/connection_screen.dart`
- `lib/features/connection/connection_edit_screen.dart`

---

### I-10  提取共享队列列表组件

**问题**：`player_screen.dart` 和 `mini_player_bar.dart` 中队列 sheet 逻辑重复

**修复**：提取到 `lib/features/player/widgets/queue_sheet.dart` 作为独立 Widget。

**涉及文件**：
- `lib/features/player/widgets/queue_sheet.dart`（新建）
- `lib/features/player/player_screen.dart`
- `lib/features/player/widgets/mini_player_bar.dart`

---

### I-11  修复通知渠道包名

**问题**：`main.dart:44` — `com.example.nas_audio_player.channel` 是占位符

**修复**：改为与实际 `build.gradle` 中 `applicationId` 一致的包名，或从 AndroidManifest 动态读取。

**涉及文件**：`lib/main.dart`

---

### I-12  添加 GoRouter 路由守卫

**问题**：`main.dart:71-118` — 无 `redirect` 逻辑，可 deep-link 到不可用路由

**修复**：添加 `redirect` 守卫——当无活跃连接时 `/browser` 和 `/player` 重定向到 `/onboarding`，当无队列时 `/player` 重定向到 `/browser`。

**涉及文件**：`lib/main.dart`

---

## 实施顺序建议

```
第 1 步: G-1 (AudioHandler 泄漏)      ← 最影响稳定性的修复
第 2 步: G-2 (Provider 循环依赖)      ← 架构风险
第 3 步: G-3 (短音频进度)             ← 逻辑缺陷
第 4 步: G-4 (负值定时器)             ← 逻辑缺陷
第 5 步: G-5 (HTTP 连接泄漏)          ← 资源泄漏

第 6~10 步: H-1 ~ H-10               ← 全部独立，可并行
第 11~22 步: I-1 ~ I-12              ← 全部独立，I-8 标为 WONTFIX
```

说明：
- G 批次全部独立，但 G-1 和 G-2 建议最先做
- H 批次全部独立，互不依赖
- I 批次为代码质量改进，全部独立
