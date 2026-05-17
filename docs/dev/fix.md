# 修复开发计划

> 分析日期：2026-05-17
> Bug 描述：播放器加载卡住、进度恢复黑屏、定时自定义确认无响应、快进图标异常、播放队列入口与滚动问题
> 优先级分级：P0 核心功能崩溃/不可用 → P1 功能异常但可绕过 → P2 体验与一致性问题

---

## 总览

| 批次 | 优先级 | 任务数 | 说明 |
|------|--------|--------|------|
| Batch A | P0 | 2 | 播放核心链路卡死/黑屏 |
| Batch B | P1 | 3 | 定时与队列交互异常 |
| Batch C | P2 | 4 | UI 图标/布局与增强项 |
| Batch I | P2 | 4 | 历史遗留未完成优化项 |

---

## Bug 分析

### BUG-1 播放器页面长期停留“正在加载音频”

**现象**：从文件列表点歌后实际已开始播放，但播放器页长时间显示“正在加载音频”；在播放器内切上一曲/下一曲或从播放列表切歌时也会复现。

**根因**：
- `lib/features/player/player_screen.dart:138-181` 的 `_loadAndPlay()` 无并发保护，多个入口（`initState`、`_playNext`、`_playPrevious`、队列 onTap）都会触发加载。
- `lib/features/player/player_screen.dart:194-205`、`207-219` 与 `240-286`（队列点击逻辑）会在前一次 load 尚未完成时再次发起 load，导致 `just_audio` stop/setAudioSource/play 链路竞争，UI 状态容易停留在 loading。

**影响范围**：播放器主页面、队列切歌、上下曲操作。

### BUG-2 “恢复播放进度”5秒后黑屏

**现象**：点歌曲后弹“恢复播放进度”，等待 5 秒自动继续后出现黑屏。

**根因**：
- `lib/features/browser/browser_screen.dart:175-229` 使用 `showProgressResumeDialog(...).then(...)` 异步回调 + `addPostFrameCallback` 再导航，链路较绕且吞掉时序错误。
- `lib/features/progress/progress_dialog.dart:58-70` 到期自动 `pop(true)`，与外层 `then` 中再次调度 push 叠加，容易出现 context/route transition 竞态。
- 需求层面当前实现为“每个文件都查进度+弹窗”，与“仅恢复当前播放歌曲一次”需求不一致，放大复现概率。

**影响范围**：文件浏览页点歌入口、进度恢复体验。

### BUG-3 自定义定时确认无响应

**现象**：选择自定义时长后点击“确认”无反应。

**根因**：`lib/features/timer/widgets/timer_button.dart:158-257` 自定义底部弹窗使用 `StatefulBuilder` + 局部变量承载选择状态，且文件存在明显结构异常（重复 `style` 片段与括号结构混乱），导致确认按钮状态与选择值更新不稳定。

**影响范围**：自定义定时停止流程。

### BUG-4 队列显示数量受限且无法滚动

**现象**：播放列表只显示约 10 条，无法上下滑动查看当前队列。

**根因**：
- `lib/features/player/player_screen.dart:223-286` 与 `lib/features/player/widgets/mini_player_bar.dart:147-211` 都用 `Column(mainAxisSize: min) + ...List.generate` 渲染整队列，未使用可滚动容器。
- 两处实现重复，后续改动容易不一致。

**影响范围**：全屏播放器队列、迷你播放器队列。

---

## Batch A — P0 严重缺陷

### A-1 串行化播放器加载状态，修复“正在加载音频”卡住

**关联 Bug**：BUG-1

**根因**：播放器加载流程可重入，多个触发源并发调用 `_loadAndPlay()`。

**修复方案**：
- 在 `PlayerScreen` 增加加载代次/互斥机制（如 `_loadToken` 或 `CancelableOperation`），仅最后一次请求可提交 UI 状态。
- 在 `_playNext/_playPrevious/队列切歌` 中统一改为调用 Provider 层单入口，并加“正在切换中”节流。
- 在 `loadAndPlayProvider` 增加最小互斥（如 `AsyncMutex`/inFlight future），避免 `stop -> setAudioSource -> play` 并发执行。

**需要完成的工作：**
1. 给 `_loadAndPlay()` 增加并发保护和过期结果丢弃逻辑。
2. 统一上下曲与队列切歌入口，避免多处直接重入。
3. 为加载失败和超时补充显式错误态，避免永久 loading。
4. 补充播放器切歌并发场景测试。

**涉及文件**：
- `lib/features/player/player_screen.dart`
- `lib/features/player/player_provider.dart`
- `test/features/player/`（新增并发场景测试）

---

### A-2 重构进度恢复入口，移除 5 秒自动弹窗导航竞态

**关联 Bug**：BUG-2

**根因**：进度弹窗关闭与播放器页面跳转由多层异步回调驱动，存在 route/context 时序竞态。

**修复方案**：
- 将 `showProgressResumeDialog(...).then(...)` 改成 `await` 顺序流程，避免 `addPostFrameCallback` 套娃。
- 调整策略为“仅恢复当前正在播放歌曲的进度”：
  - 启动时读取一次最近播放记录，填充 `currentPlayQueue.startPositionMs`。
  - 点歌曲时默认直接播放，不再逐曲弹“恢复播放进度”。
- 对“恢复播放”场景加最小兜底：进度无效时回退到 0 而非黑屏。

**需要完成的工作：**
1. 浏览器点歌流程改为 `await` 串行导航。
2. 删除逐文件恢复弹窗触发点，保留启动恢复。
3. 增加启动恢复与点击播放继续播放的测试覆盖。

**涉及文件**：
- `lib/features/browser/browser_screen.dart`
- `lib/features/progress/progress_dialog.dart`
- `lib/features/progress/progress_provider.dart`
- `lib/features/player/player_provider.dart`
- `test/features/progress/`

---

## Batch B — P1 功能异常

### B-1 修复自定义定时确认按钮无响应

**关联 Bug**：BUG-3

**根因**：自定义定时弹窗状态管理和结构实现不稳定，确认动作与当前选值存在脱节。

**修复方案**：
- 提取独立 `StatefulWidget`（或 `ConsumerStatefulWidget`）承载小时/分钟状态，去除局部变量 + `StatefulBuilder` 组合。
- 清理重复/损坏的 Widget 结构，保证确认按钮仅在总分钟 > 0 时可点，并稳定调用 `startDurationTimerProvider`。

**需要完成的工作：**
1. 重构自定义定时弹窗为独立组件。
2. 修复确认按钮启用态和回调。
3. 增加 0 分钟禁用、非 0 分钟生效测试。

**涉及文件**：
- `lib/features/timer/widgets/timer_button.dart`
- `test/features/timer/`

---

### B-2 队列弹窗改为可滚动列表（全屏与迷你栏）

**关联 Bug**：BUG-4

**根因**：使用非滚动 `Column` 直接展开队列项。

**修复方案**：
- 队列弹窗主体改为 `DraggableScrollableSheet + ListView.builder` 或 `SizedBox + ListView.builder`。
- 统一提取共享队列组件，避免两处重复实现偏移。

**需要完成的工作：**
1. 实现可滚动队列列表。
2. 统一 `player_screen` 与 `mini_player_bar` 的队列弹窗实现。
3. 验证长队列（>100）可滑动、可点选。

**涉及文件**：
- `lib/features/player/player_screen.dart`
- `lib/features/player/widgets/mini_player_bar.dart`
- `lib/features/player/widgets/queue_sheet.dart`

---

### B-3 将播放列表按钮迁移到“下一曲”右侧

**关联 Bug**：播放器布局调整请求

**根因**：播放列表入口仍放在 AppBar（`lib/features/player/player_screen.dart:320-329`），与交互预期不一致。

**修复方案**：
- 删除 AppBar 右上角队列按钮。
- 在 `_PlaybackControls` 中 `next` 按钮右侧增加队列按钮并复用同一 `showQueueSheet`。

**需要完成的工作：**
1. 调整控制条布局和触控间距。
2. 保留可访问性（tooltip/语义标签）。
3. 更新相关 widget 测试快照/点击路径。

**涉及文件**：
- `lib/features/player/player_screen.dart`
- `test/features/player/`

---

## Batch C — P2 体验与一致性

### C-1 修复快进按钮图标：改为“顺时针回转箭头”语义

**关联 Bug**：快进图标显示为右直线箭头

**根因**：`lib/features/player/player_screen.dart:722-728` 的 `_iconForSeekForward` 默认返回 `Icons.forward`。

**修复方案**：
- 将快进统一为 `replay` 的镜像语义（优先 `Icons.replay` + 旋转/翻转，或使用更接近“快进回转”的 Material Symbol）。
- 与快退图标形成方向相反的一致视觉体系。

**需要完成的工作：**
1. 替换快进 icon 映射逻辑。
2. 校验 10s/30s/60s 三档一致性。

**涉及文件**：
- `lib/features/player/player_screen.dart`

---

### C-2 修复 60 秒步长图标走错分支

**关联 Bug**：步长设置 60 秒时显示直线箭头

**根因**：`_iconForSeekForward/_iconForSeekBackward` 仅处理 5/10/30，60 落入 `default`。

**修复方案**：
- 为 60 秒显式分支（如 `replay` + `60s` 文本样式），避免 default 落回错误图标。

**需要完成的工作：**
1. 增加 60 秒图标映射。
2. 增加 seekStep=60 的 UI 测试断言。

**涉及文件**：
- `lib/features/player/player_screen.dart`
- `test/features/player/ply_02_test.dart`

---

### C-3 自定义停止时长增加“上次时长”快捷项

**关联 Bug**：定时设置缺少上次时长复用

**根因**：当前 `TimerBottomSheet` 仅有固定 5/10/播完停止/自定义选项，未持久化上次自定义时长。

**修复方案**：
- 持久化最近一次自定义分钟数（SharedPreferences）。
- 在弹窗顶部加入“上次时长（xx分钟）”选项，点击即设置。

**需要完成的工作：**
1. 定义 `last_custom_timer_minutes` 存储 key。
2. 新增读取/写入 provider 与 UI 展示逻辑。
3. 增加无历史值时隐藏该项的行为测试。

**涉及文件**：
- `lib/features/timer/timer_provider.dart`
- `lib/features/timer/widgets/timer_button.dart`
- `test/features/timer/`

---

### C-4 精简进度持久化：仅保存“当前播放歌曲”并在启动恢复

**关联 Bug**：逐曲保存导致恢复弹窗泛滥与异常

**根因**：当前设计按 `(connectionId, filePath)` 全量保存，多入口频繁写入与逐曲恢复查询。

**修复方案**：
- 改为单记录模型（当前播放项 + 位置 + 时长 + 时间戳）。
- App 启动时读取单记录填充当前队列；点“播放”时续播。

**需要完成的工作：**
1. 新增/迁移 DAO 接口到“单活跃进度”模型。
2. 调整浏览器与播放器调用链。
3. 补充迁移兼容策略（首次升级时保留最近一条）。

**涉及文件**：
- `lib/core/database/dao/progress_dao.dart`
- `lib/features/progress/progress_provider.dart`
- `lib/features/browser/browser_provider.dart`
- `lib/features/browser/browser_screen.dart`
- `lib/features/player/player_provider.dart`

---

## Batch I — P2 历史遗留未完成项（保留）

### I-4 版本号从 package_info_plus 读取

**修复方案**：将设置页关于页面版本号由硬编码改为 `PackageInfo.fromPlatform()`。

**涉及文件**：
- `lib/features/settings/about_screen.dart`
- `pubspec.yaml`

---

### I-9 提取共享 _ValidationBanner 组件

**修复方案**：抽出连接页复用验证提示组件，消除重复代码。

**涉及文件**：
- `lib/features/connection/widgets/validation_banner.dart`
- `lib/features/connection/connection_screen.dart`
- `lib/features/connection/connection_edit_screen.dart`

---

### I-10 提取共享队列列表组件

**修复方案**：抽出 `queue_sheet.dart`，供全屏播放器与迷你栏复用。

**涉及文件**：
- `lib/features/player/widgets/queue_sheet.dart`
- `lib/features/player/player_screen.dart`
- `lib/features/player/widgets/mini_player_bar.dart`

---

### I-12 添加 GoRouter 路由守卫

**修复方案**：无连接时禁止进入 `/browser`、`/player`；无队列时禁止进入 `/player`。

**涉及文件**：
- `lib/main.dart`

---

## 实施顺序建议

1. `A-1` → `A-2`
说明：先稳定播放器加载链路，再处理进度恢复链路，避免交叉竞态。
2. `B-1` → `B-2` → `B-3`
说明：先修复无响应，再修复队列可滚动与入口位置。
3. `C-1` + `C-2` + `C-3`
说明：均为低风险 UI/交互一致性，可并行。
4. `C-4`
说明：涉及数据模型调整，需单独评审与迁移验证。
5. `I-4`、`I-9`、`I-10`、`I-12`
说明：历史遗留优化项，独立排期。
