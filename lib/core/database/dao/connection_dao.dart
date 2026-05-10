// lib/core/database/dao/connection_dao.dart
// Data-access object for the `connections` table.
// The `password` column stores a flutter_secure_storage reference key.

import 'package:sqflite/sqflite.dart';
import '../../database/database_helper.dart';
import '../../../shared/models/connection_config.dart';

class ConnectionDao {
  final DatabaseHelper _helper;

  ConnectionDao({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  Future<Database> get _db async => _helper.database;

  // ── Insert ──────────────────────────────────────────────────────────────────

  /// Inserts a new connection row. Returns the new row id.
  /// [passwordKey] is the flutter_secure_storage reference key.
  Future<int> insert(ConnectionConfig config, {required String passwordKey}) async {
    final db = await _db;
    final map = config.toMap(passwordKey: passwordKey);
    map.remove('id'); // let AUTOINCREMENT assign it
    return db.insert('connections', map);
  }

  // ── Query ───────────────────────────────────────────────────────────────────

  Future<List<ConnectionConfig>> findAll() async {
    final db = await _db;
    final rows = await db.query('connections', orderBy: 'created_at ASC');
    return rows.map(ConnectionConfig.fromMap).toList();
  }

  Future<ConnectionConfig?> findById(int id) async {
    final db = await _db;
    final rows =
        await db.query('connections', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ConnectionConfig.fromMap(rows.first);
  }

  Future<ConnectionConfig?> findActive() async {
    final db = await _db;
    final rows = await db
        .query('connections', where: 'is_active = 1', limit: 1);
    if (rows.isEmpty) return null;
    return ConnectionConfig.fromMap(rows.first);
  }

  /// Returns the password reference key stored for [id].
  Future<String?> findPasswordKey(int id) async {
    final db = await _db;
    final rows = await db.query(
      'connections',
      columns: ['password'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return rows.first['password'] as String?;
  }

  // ── Update ──────────────────────────────────────────────────────────────────

  Future<int> update(ConnectionConfig config, {required String passwordKey}) async {
    final db = await _db;
    final map = config.toMap(passwordKey: passwordKey);
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    return db.update('connections', map,
        where: 'id = ?', whereArgs: [config.id]);
  }

  /// Sets [id] as the only active connection (clears all others).
  Future<void> setActive(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('connections', {'is_active': 0});
      await txn.update(
        'connections',
        {'is_active': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // ── Delete ──────────────────────────────────────────────────────────────────

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM connections');
    return (result.first['cnt'] as int?) ?? 0;
  }
}
