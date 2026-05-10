// lib/features/connection/widgets/connection_form.dart
// Stateful form widget for WebDAV connection input fields.
// Exposes a [ConnectionFormController] so the parent screen can read values
// and trigger validation without coupling the form internals.

import 'package:flutter/material.dart';
import '../../../shared/models/connection_config.dart';

// ── Form controller (passed down from screen) ─────────────────────────────────

class ConnectionFormController {
  late _ConnectionFormState _state;

  void _attach(_ConnectionFormState state) => _state = state;

  String get url => _state._urlController.text.trim();
  String get username => _state._usernameController.text.trim();
  String get password => _state._passwordController.text;
  String get displayName => _state._nameController.text.trim();
  String get basePath {
    final v = _state._basePathController.text.trim();
    return v.isEmpty ? '/' : v;
  }

  bool validate() => _state._formKey.currentState?.validate() ?? false;

  void dispose() {} // lifecycle managed by the State
}

// ── Form widget ───────────────────────────────────────────────────────────────

class ConnectionForm extends StatefulWidget {
  final ConnectionFormController controller;

  const ConnectionForm({super.key, required this.controller});

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  final _formKey = GlobalKey<FormState>();

  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _basePathController = TextEditingController(text: '/');

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);

    // Auto-fill display name from URL hostname when user leaves URL field
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    if (_nameController.text.isEmpty) {
      final hostname =
          ConnectionConfig.hostnameFromUrl(_urlController.text.trim());
      if (hostname.isNotEmpty && hostname != _urlController.text.trim()) {
        // Only prefill; don't override if the user already typed something.
        // We use setState here only to trigger rebuild if needed elsewhere.
      }
    }
  }

  /// Called when URL field loses focus — fill display name from hostname if
  /// the user hasn't typed a custom name yet.
  void _onUrlFocusLost() {
    if (_nameController.text.isEmpty) {
      final raw = _urlController.text.trim();
      if (raw.isNotEmpty) {
        final hostname = ConnectionConfig.hostnameFromUrl(raw);
        setState(() => _nameController.text = hostname);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _basePathController.dispose();
    super.dispose();
  }

  // ── Validators ──────────────────────────────────────────────────────────────

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入服务器地址';
    return null; // URL format is validated by WebDavClient.isValidWebDavUrl
  }

  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) return '请输入$fieldName';
    return null;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Server URL ────────────────────────────────────────────────────
          Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _onUrlFocusLost();
            },
            child: TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '服务器地址 *',
                hintText: 'http://192.168.1.100:5005',
                prefixIcon: Icon(Icons.dns_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              validator: _validateUrl,
            ),
          ),
          const SizedBox(height: 16),

          // ── Username ──────────────────────────────────────────────────────
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名 *',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (v) => _validateRequired(v, '用户名'),
          ),
          const SizedBox(height: 16),

          // ── Password ──────────────────────────────────────────────────────
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: '密码 *',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (v) => _validateRequired(v, '密码'),
          ),
          const SizedBox(height: 16),

          // ── Display name (optional) ───────────────────────────────────────
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '显示名称（选填）',
              hintText: '默认取主机名',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // ── Base path (optional) ──────────────────────────────────────────
          TextFormField(
            controller: _basePathController,
            decoration: const InputDecoration(
              labelText: '基础路径（选填）',
              hintText: '/',
              prefixIcon: Icon(Icons.folder_outlined),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            autocorrect: false,
          ),
        ],
      ),
    );
  }
}
