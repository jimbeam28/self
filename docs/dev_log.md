---

## [2026-05-10 16:11] CON-01 - 添加 WebDAV 连接

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_screen.dart` — 连接配置页面与提交流程
- `lib/features/connection/widgets/connection_form.dart` — 表单字段、校验与交互状态展示
- `lib/features/connection/connection_provider.dart` — 连接验证状态管理与保存流程
- `lib/core/network/webdav_client.dart` — WebDAV 连接验证调用与结果映射
- `lib/core/database/dao/connection_dao.dart` — 连接配置持久化访问
- `lib/shared/models/connection_config.dart` — 连接配置模型与默认值逻辑

### 测试文件
- `test/features/connection/con_01_test.dart` — 测试用例 16 个（CON-T01~T09, CON-T35~T41）

### 测试结果
- 通过: 16 / 总计: 16

### 备注
- 为完成测试运行，将 `pubspec.yaml` 中 `sqflite_ffi` 更正为 `sqflite_common_ffi`。

---

## [2026-05-10 16:20] CON-02 - 连接验证

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_provider.dart` — 添加重入保护（防重复点击）和 startupValidationProvider（启动自动验证）
- `lib/main.dart` — OnboardingPage 集成 startupValidationProvider，根据验证结果路由跳转
- `lib/features/connection/connection_screen.dart` — 显示启动验证失败的警告横幅

### 测试文件
- `test/features/connection/con_02_test.dart` — 测试用例 8 个（CON-T10 ~ CON-T17）

### 测试结果
- 通过: 8 / 总计: 8

### 备注
- F-009 和 F-010 已由 CON-01 实现，CON-02 补充了重入保护和启动自动验证逻辑
- 启动自动验证在 OnboardingPage 中触发，验证失败时重定向到连接页面供用户重新配置

---

## [2026-05-10 16:25] CON-03 - 连接配置持久化

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- （F-008 ConnectionDao 和 F-011 密码安全存储已由 CON-01 实现，CON-03 仅新增测试）

### 测试文件
- `test/features/connection/con_03_test.dart` — 测试用例 7 个（CON-T18 ~ CON-T24）

### 测试结果
- 通过: 7 / 总计: 7

### 备注
- 使用 sqflite_common_ffi 内存数据库进行 DAO 单元测试
- CON-T23 验证密码列存储引用 key 而非明文密码

---

## [2026-05-10 16:30] CON-04 - 切换当前连接

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_list_screen.dart` — 连接列表管理页面（新建）
- `lib/features/connection/connection_provider.dart` — 添加 switchActiveConnectionProvider
- `lib/features/connection/connection_screen.dart` — 添加管理连接入口按钮
- `lib/main.dart` — 添加 /connections 路由

### 测试文件
- `test/features/connection/con_04_test.dart` — 测试用例 3 个（CON-T25 ~ CON-T27）

### 测试结果
- 通过: 34 / 总计: 34（全部 Connection 模块测试）

### 备注
- 连接列表页面为 CON-05/CON-06 的编辑/删除功能预留了 UI 结构

---

## [2026-05-10 16:37] CON-05 - 编辑连接配置

**模块**: Connection
**状态**: ✅ 成功

### 实现文件
- `lib/features/connection/connection_edit_screen.dart` — 编辑连接页面（新建）
- `lib/features/connection/connection_provider.dart` — 添加 ConnectionUpdater
- `lib/features/connection/widgets/connection_form.dart` — 支持预填初始值和可选密码
- `lib/features/connection/connection_list_screen.dart` — 添加弹出菜单（编辑/删除）
- `lib/main.dart` — 添加 /connections/edit/:id 路由

### 测试文件
- `test/features/connection/con_05_test.dart` — 测试用例 4 个（CON-T28 ~ CON-T30 + 密码更新）

### 测试结果
- 通过: 38 / 总计: 38（全部 Connection 模块测试）

### 备注
- 修改 URL/用户名/密码/基础路径后必须重新验证才能保存
- 仅修改显示名称无需重新验证
- ConnectionForm 支持 passwordRequired=false 用于编辑模式（留空保持原密码）
