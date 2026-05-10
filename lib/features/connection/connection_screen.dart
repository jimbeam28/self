// lib/features/connection/connection_screen.dart
// Full UI for CON-01: Add WebDAV connection.
//
// Flow:
//   User fills form → "测试连接" → loading spinner
//     ↳ success: green banner, "保存" button enabled
//     ↳ failure: red banner with error message
//   "保存" → write to DB + secure storage → navigate to Browser page

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/webdav_client.dart';
import '../../shared/models/connection_config.dart';
import 'connection_provider.dart';
import 'widgets/connection_form.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final _formController = ConnectionFormController();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final validationState = ref.watch(connectionValidatorProvider);
    final isValidated = validationState is ValidationSuccess;
    final isValidating = validationState is ValidationLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加 WebDAV 连接'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Form fields
              ConnectionForm(controller: _formController),
              const SizedBox(height: 24),

              // Validation result banner
              _ValidationBanner(state: validationState),
              if (validationState is! ValidationIdle)
                const SizedBox(height: 16),

              // "测试连接" button
              ElevatedButton.icon(
                onPressed: isValidating || _isSaving
                    ? null
                    : _onTestConnection,
                icon: isValidating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find_outlined),
                label: Text(isValidating ? '连接中…' : '测试连接'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // "保存" button — only enabled after successful validation
              FilledButton.icon(
                onPressed:
                    (isValidated && !_isSaving) ? _onSave : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? '保存中…' : '保存'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Handlers ─────────────────────────────────────────────────────────────────

  Future<void> _onTestConnection() async {
    // Validate form fields first
    if (!_formController.validate()) return;

    final validator = ref.read(connectionValidatorProvider.notifier);
    await validator.validate(
      url: _formController.url,
      username: _formController.username,
      password: _formController.password,
      basePath: _formController.basePath,
    );
  }

  Future<void> _onSave() async {
    if (!_formController.validate()) return;

    setState(() => _isSaving = true);
    try {
      final saver = ref.read(connectionSaverProvider);

      // Determine display name: use user input or fall back to hostname
      final rawName = _formController.displayName;
      final effectiveName = rawName.isNotEmpty
          ? rawName
          : ConnectionConfig.hostnameFromUrl(_formController.url);

      final now = DateTime.now();
      // Normalise URL before saving (auto-prepend http:// if no scheme)
      final normalisedUrl = normaliseWebDavUrl(_formController.url);

      final config = ConnectionConfig(
        name: effectiveName,
        url: normalisedUrl,
        username: _formController.username,
        basePath: _formController.basePath,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      await saver.save(
        config: config,
        password: _formController.password,
      );

      // Invalidate dependent providers so they reload
      ref.invalidate(activeConnectionProvider);
      ref.invalidate(connectionListProvider);

      if (mounted) {
        // Navigate to Browser page
        context.go('/browser');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ── Validation banner widget ──────────────────────────────────────────────────

class _ValidationBanner extends StatelessWidget {
  final ConnectionValidationState state;

  const _ValidationBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state is ValidationIdle) return const SizedBox.shrink();

    if (state is ValidationSuccess) {
      return _Banner(
        icon: Icons.check_circle_outline,
        message: '连接成功！',
        backgroundColor: Colors.green.shade50,
        foregroundColor: Colors.green.shade800,
        iconColor: Colors.green,
      );
    }

    if (state is ValidationError) {
      return _Banner(
        icon: Icons.error_outline,
        message: (state as ValidationError).message,
        backgroundColor: Colors.red.shade50,
        foregroundColor: Colors.red.shade900,
        iconColor: Colors.red,
      );
    }

    // Loading — no banner shown (button already shows spinner)
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color iconColor;

  const _Banner({
    required this.icon,
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foregroundColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
