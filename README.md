# NAS 音乐/有声书播放器

基于 Flutter 的 Android 音频播放器，通过 WebDAV 协议连接飞牛OS NAS，支持音乐和有声书播放。

## 核心功能

- **NAS 文件浏览**：通过 WebDAV 访问 NAS 上的音乐和有声书文件
- **音频播放**：支持流式播放、后台播放、锁屏媒体控件
- **播放进度记忆**：自动保存每个文件的播放位置，下次续播
- **定时停止**：支持固定时长（5/10/15分钟）和播完当前音频两种模式
- **播放速度调节**：适配有声书等场景

## 技术栈

Flutter · Riverpod · just_audio · audio_service · WebDAV · SQLite · go_router

## 项目结构

```
lib/
├── core/           # 网络、数据库、服务层
├── features/       # 功能模块（连接、浏览、播放、设置）
└── shared/         # 共享模型和组件
```

## 开始

```bash
# 安装依赖
flutter pub get

# 运行
flutter run
```

## 架构概览

```
UI Layer → State Layer (Riverpod) → Service Layer → Data Layer (WebDAV / SQLite)
```

详细架构设计见 [docs/architecture.md](docs/architecture.md)。
