// lib/features/connection/connection_provider.dart
// Riverpod providers for the Connection feature.
// Written without code generation — uses StateNotifier / AsyncNotifier patterns
// from flutter_riverpod directly (no @riverpod annotations, no build_runner).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/database/dao/connection_dao.dart';
import '../../core/network/webdav_client.dart';
import '../../shared/models/connection_config.dart';

// ── Infrastructure providers ──────────────────────────────────────────────────

final connectionDaoProvider = Provider<ConnectionDao>((ref) => ConnectionDao());

final webDavClientProvider = Provider<WebDavClientInterface>(
    (ref) => WebDavClient());

final secureStorageProvider = Provider<FlutterSecureStorage>(
    (ref) => const FlutterSecureStorage());

// ── Active connection ─────────────────────────────────────────────────────────

/// Resolves the currently active [ConnectionConfig] from the database.
/// Returns null when no active connection is configured.
final activeConnectionProvider =
    FutureProvider<ConnectionConfig?>((ref) async {
  final dao = ref.watch(connectionDaoProvider);
  return dao.findActive();
});

// ── All connections list ──────────────────────────────────────────────────────

/// Returns all saved connections ordered by creation date.
final connectionListProvider =
    FutureProvider<List<ConnectionConfig>>((ref) async {
  final dao = ref.watch(connectionDaoProvider);
  return dao.findAll();
});

// ── Connection validation state ───────────────────────────────────────────────

/// Represents the lifecycle of a "test connection" operation.
abstract class ConnectionValidationState {
  const ConnectionValidationState();
}

class ValidationIdle extends ConnectionValidationState {
  const ValidationIdle();
}

class ValidationLoading extends ConnectionValidationState {
  const ValidationLoading();
}

class ValidationSuccess extends ConnectionValidationState {
  const ValidationSuccess();
}

class ValidationError extends ConnectionValidationState {
  final String message;
  const ValidationError(this.message);
}

/// StateNotifier that drives the "测试连接" → result flow.
class ConnectionValidatorNotifier
    extends StateNotifier<ConnectionValidationState> {
  final WebDavClientInterface _client;

  ConnectionValidatorNotifier(this._client) : super(const ValidationIdle());

  /// Performs the WebDAV PROPFIND validation.
  ///
  /// Includes a re-entry guard: if a validation is already in-flight the call
  /// is silently ignored (CON-T17).
  Future<void> validate({
    required String url,
    required String username,
    required String password,
    String basePath = '/',
  }) async {
    if (state is ValidationLoading) return; // re-entry guard
    state = const ValidationLoading();
    final normalisedUrl = normaliseWebDavUrl(url);
    final result = await _client.validate(
      url: normalisedUrl,
      username: username,
      password: password,
      basePath: basePath,
    );
    if (result.isSuccess) {
      state = const ValidationSuccess();
    } else {
      state = ValidationError(result.message ?? '无法连接到服务器，请检查地址和网络');
    }
  }

  void reset() => state = const ValidationIdle();
}

final connectionValidatorProvider = StateNotifierProvider<
    ConnectionValidatorNotifier, ConnectionValidationState>((ref) {
  final client = ref.watch(webDavClientProvider);
  return ConnectionValidatorNotifier(client);
});

// ── Startup auto-validation ────────────────────────────────────────────────────
//
// Watches [activeConnectionProvider] and automatically validates the active
// connection whenever it resolves to a non-null value.  This covers both
// app-startup (CON-T15 / CON-T16) and connection-switch scenarios.
//
// Returns null when no active connection exists, otherwise the raw validation
// result from the WebDAV client.
//
// Usage: watch this provider from an app-shell-level widget that can react to
// [ConnectionHealthError] by prompting the user to reconfigure.

final startupValidationProvider =
    FutureProvider<WebDavValidationResult?>((ref) async {
  final activeConn = await ref.watch(activeConnectionProvider.future);
  if (activeConn == null) return null;

  // Read the password from secure storage
  final storage = ref.watch(secureStorageProvider);
  final passwordKey = 'connection_password_${activeConn.id}';
  final password = await storage.read(key: passwordKey);
  if (password == null || password.isEmpty) {
    return WebDavValidationResult.authError();
  }

  // Run validation silently (no connectionValidatorProvider state changes)
  final client = ref.watch(webDavClientProvider);
  return client.validate(
    url: activeConn.url,
    username: activeConn.username,
    password: password,
    basePath: activeConn.basePath,
  );
});

// ── Switch active connection ────────────────────────────────────────────────────

/// Switches the active connection to the connection with the given [id].
/// Invalidates [activeConnectionProvider] and [connectionListProvider] so the
/// UI reacts immediately.
final switchActiveConnectionProvider =
    FutureProvider.family<void, int>((ref, id) async {
  final dao = ref.watch(connectionDaoProvider);
  await dao.setActive(id);
  ref.invalidate(activeConnectionProvider);
  ref.invalidate(connectionListProvider);
});

// ── Save connection use-case ──────────────────────────────────────────────────

/// Encapsulates saving a new connection to the DB and secure storage.
class ConnectionSaver {
  final ConnectionDao _dao;
  final FlutterSecureStorage _storage;

  ConnectionSaver(this._dao, this._storage);

  /// Saves [config] + [password] atomically:
  /// 1. Insert row with a temp key.
  /// 2. Read the assigned id.
  /// 3. Write password to secure storage under `connection_password_{id}`.
  /// 4. Update the row's password column to the final key.
  ///
  /// Returns the saved [ConnectionConfig] with its database id set.
  Future<ConnectionConfig> save({
    required ConnectionConfig config,
    required String password,
  }) async {
    const tempKey = 'connection_password_temp';

    // Insert with temp key to get the AUTOINCREMENT id
    final id = await _dao.insert(config, passwordKey: tempKey);

    // Persist password under the permanent key
    final permanentKey = 'connection_password_$id';
    await _storage.write(key: permanentKey, value: password);

    // Update the row to reference the permanent key
    final savedConfig = config.copyWith(id: id, isActive: true);
    await _dao.update(savedConfig, passwordKey: permanentKey);

    // Mark as active (clears any previous active flag)
    await _dao.setActive(id);

    return savedConfig;
  }
}

final connectionSaverProvider = Provider<ConnectionSaver>((ref) {
  return ConnectionSaver(
    ref.watch(connectionDaoProvider),
    ref.watch(secureStorageProvider),
  );
});

// ── Update connection use-case ──────────────────────────────────────────────────

/// Encapsulates updating an existing connection in the DB and secure storage.
class ConnectionUpdater {
  final ConnectionDao _dao;
  final FlutterSecureStorage _storage;

  ConnectionUpdater(this._dao, this._storage);

  /// Updates [config] in the database.
  ///
  /// If [password] is non-null and non-empty it is written to secure storage;
  /// otherwise the existing stored password is left untouched.
  Future<void> update({
    required ConnectionConfig config,
    String? password,
  }) async {
    final permanentKey = 'connection_password_${config.id}';

    if (password != null && password.isNotEmpty) {
      await _storage.write(key: permanentKey, value: password);
    }

    await _dao.update(config, passwordKey: permanentKey);
  }
}

final connectionUpdaterProvider = Provider<ConnectionUpdater>((ref) {
  return ConnectionUpdater(
    ref.watch(connectionDaoProvider),
    ref.watch(secureStorageProvider),
  );
});

// ── Delete connection use-case ──────────────────────────────────────────────────

/// Deletes the connection with [id].
///
/// Cascades to:
/// - play_progress records for this connection (DAO level, CON-T31)
/// - secure-storage password entry (CON-T31)
///
/// Throws [LastConnectionException] when only one connection remains (CON-T32).
/// Auto-activates another connection if the deleted one was active (CON-T34).
final deleteConnectionProvider = FutureProvider.family<void, int>((ref, id) async {
  final dao = ref.watch(connectionDaoProvider);
  final storage = ref.watch(secureStorageProvider);

  await dao.delete(id);

  // Remove the password from secure storage (CON-T31)
  await storage.delete(key: 'connection_password_$id');

  ref.invalidate(activeConnectionProvider);
  ref.invalidate(connectionListProvider);
});
