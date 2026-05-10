// lib/features/settings/settings_screen.dart
// Settings page UI.
//
// Sections:
//   - 播放设置: default playback speed, seek step
//   - 外观: theme mode
//   - 连接: manage NAS connections
//   - 关于: about page

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../player/player_provider.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // ── 播放设置 ──────────────────────────────────────────────
          const _SectionHeader(title: '播放设置'),
          _DefaultSpeedTile(),
          _SeekStepTile(),

          const Divider(),

          // ── 外观 ──────────────────────────────────────────────────
          const _SectionHeader(title: '外观'),
          _ThemeModeTile(),

          const Divider(),

          // ── 连接 ──────────────────────────────────────────────────
          const _SectionHeader(title: '连接'),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('管理 NAS 连接'),
            subtitle: const Text('添加、编辑或切换连接'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/connections'),
          ),

          const Divider(),

          // ── 关于 ──────────────────────────────────────────────────
          const _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于本应用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

// ── Default speed tile (SET-01) ────────────────────────────────────────────────

class _DefaultSpeedTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSpeed = ref.watch(defaultSpeedProvider);

    return ListTile(
      leading: const Icon(Icons.speed),
      title: const Text('默认播放速度'),
      subtitle: Text('${currentSpeed}x'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSpeedDialog(context, ref, currentSpeed),
    );
  }

  void _showSpeedDialog(
      BuildContext context, WidgetRef ref, double currentSpeed) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择默认播放速度'),
          children: speedOptions.map((speed) {
            final isSelected = (speed - currentSpeed).abs() < 0.01;
            return RadioListTile<double>(
              title: Text('${speed}x'),
              value: speed,
              groupValue: currentSpeed,
              selected: isSelected,
              onChanged: (value) {
                if (value != null) {
                  ref.read(setDefaultSpeedProvider)(value);
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        );
      },
    );
  }
}

// ── Seek step tile (SET-04) ────────────────────────────────────────────────────

class _SeekStepTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStep = ref.watch(seekStepSettingProvider);

    return ListTile(
      leading: const Icon(Icons.fast_forward),
      title: const Text('快进/快退步长'),
      subtitle: Text(labelForSeekStep(currentStep)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSeekStepDialog(context, ref, currentStep),
    );
  }

  void _showSeekStepDialog(
      BuildContext context, WidgetRef ref, int currentStep) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择快进/快退步长'),
          children: seekStepOptions.map((step) {
            final isSelected = step == currentStep;
            return RadioListTile<int>(
              title: Text(labelForSeekStep(step)),
              value: step,
              groupValue: currentStep,
              selected: isSelected,
              onChanged: (value) {
                if (value != null) {
                  ref.read(setSeekStepSettingProvider)(value);
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        );
      },
    );
  }
}

// ── Theme mode tile (SET-03) ───────────────────────────────────────────────────

class _ThemeModeTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentThemeMode = ref.watch(themeModeProvider);

    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('主题'),
      subtitle: Text(labelForThemeMode(currentThemeMode)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeDialog(context, ref, currentThemeMode),
    );
  }

  void _showThemeDialog(
      BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    final modes = ThemeMode.values;

    showDialog<void>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择主题'),
          children: modes.map((mode) {
            final isSelected = mode == currentMode;
            return RadioListTile<ThemeMode>(
              title: Text(labelForThemeMode(mode)),
              value: mode,
              groupValue: currentMode,
              selected: isSelected,
              onChanged: (value) {
                if (value != null) {
                  ref.read(setThemeModeProvider)(value);
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        );
      },
    );
  }
}
