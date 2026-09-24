import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/session_models.dart';

class AppDatabase {
  Database? _db;
  UserProfile? _webUser;
  ClinicProfile? _webClinic;
  final Map<String, Map<String, Map<String, dynamic>>> _memory = {};
  final Map<String, Map<String, dynamic>> _pending = {};

  Future<Database> get instance async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not used on web.');
    }
    if (_db != null) {
      return _db!;
    }
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, 'nabi_dental.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createV1(db);
        await _createV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2(db);
        }
      },
    );
    return _db!;
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE profile_snapshot (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        user_json TEXT NOT NULL,
        clinic_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_changes (
        client_change_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        base_version INTEGER,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE kv (
        collection TEXT NOT NULL,
        id TEXT NOT NULL,
        json TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (collection, id)
      )
    ''');
  }

  Future<void> saveSnapshot({required UserProfile user, required ClinicProfile clinic}) async {
    if (kIsWeb) {
      _webUser = user;
      _webClinic = clinic;
      return;
    }
    final db = await instance;
    await db.insert(
      'profile_snapshot',
      {
        'id': 1,
        'user_json': jsonEncode(user.toJson()),
        'clinic_json': jsonEncode(clinic.toJson()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<(UserProfile, ClinicProfile)?> readSnapshot() async {
    if (kIsWeb) {
      if (_webUser == null || _webClinic == null) {
        return null;
      }
      return (_webUser!, _webClinic!);
    }
    final db = await instance;
    final rows = await db.query('profile_snapshot', where: 'id = 1');
    if (rows.isEmpty) {
      return null;
    }
    final user = UserProfile.fromJson(jsonDecode(rows.first['user_json'] as String) as Map<String, dynamic>);
    final clinic = ClinicProfile.fromJson(jsonDecode(rows.first['clinic_json'] as String) as Map<String, dynamic>);
    return (user, clinic);
  }

  Future<void> upsertAll(String collection, List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await upsert(collection, row);
    }
  }

  Future<void> upsert(String collection, Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final deleted = row['deleted_at'] != null ? 1 : 0;
    if (kIsWeb) {
      _memory.putIfAbsent(collection, () => {});
      _memory[collection]![id] = {...row, '_deleted': deleted};
      return;
    }
    final db = await instance;
    await db.insert(
      'kv',
      {
        'collection': collection,
        'id': id,
        'json': jsonEncode(row),
        'deleted': deleted,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> list(String collection, {bool includeDeleted = false}) async {
    if (kIsWeb) {
      return (_memory[collection] ?? {}).values.where((row) {
        return includeDeleted || row['_deleted'] != 1;
      }).map((row) {
        final copy = Map<String, dynamic>.from(row);
        copy.remove('_deleted');
        return copy;
      }).toList();
    }
    final db = await instance;
    final rows = await db.query(
      'kv',
      where: includeDeleted ? 'collection = ?' : 'collection = ? AND deleted = 0',
      whereArgs: [collection],
    );
    return rows.map((row) => jsonDecode(row['json'] as String) as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>?> get(String collection, String id) async {
    final rows = await list(collection, includeDeleted: true);
    for (final row in rows) {
      if (row['id'].toString() == id) {
        return row;
      }
    }
    return null;
  }

  Future<void> markDeleted(String collection, String id) async {
    if (kIsWeb) {
      final row = _memory[collection]?[id];
      if (row != null) {
        row['_deleted'] = 1;
        row['deleted_at'] = DateTime.now().toUtc().toIso8601String();
      }
      return;
    }
    final db = await instance;
    final existing = await db.query('kv', where: 'collection = ? AND id = ?', whereArgs: [collection, id]);
    if (existing.isEmpty) {
      return;
    }
    final json = jsonDecode(existing.first['json'] as String) as Map<String, dynamic>;
    json['deleted_at'] = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'kv',
      {'json': jsonEncode(json), 'deleted': 1},
      where: 'collection = ? AND id = ?',
      whereArgs: [collection, id],
    );
  }

  Future<void> enqueueChange({
    required String clientChangeId,
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    int? baseVersion,
  }) async {
    final row = {
      'client_change_id': clientChangeId,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload': payload,
      'base_version': baseVersion,
      'attempt_count': 0,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (kIsWeb) {
      _pending[clientChangeId] = row;
      return;
    }
    final db = await instance;
    await db.insert(
      'pending_changes',
      {
        ...row,
        'payload': jsonEncode(payload),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> pendingChanges() async {
    if (kIsWeb) {
      return _pending.values
          .where((row) => row['status'] == 'pending' || row['status'] == 'failed' || row['status'] == 'syncing')
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    final db = await instance;
    final rows = await db.query(
      'pending_changes',
      where: "status IN ('pending', 'failed', 'syncing')",
      orderBy: 'created_at ASC',
    );
    return [
      for (final row in rows)
        {
          ...row,
          'payload': jsonDecode(row['payload'] as String),
        },
    ];
  }

  Future<void> setPendingStatus(String clientChangeId, String status) async {
    if (kIsWeb) {
      final row = _pending[clientChangeId];
      if (row != null) {
        row['status'] = status;
        row['attempt_count'] = (row['attempt_count'] as int? ?? 0) + 1;
      }
      return;
    }
    final db = await instance;
    await db.update(
      'pending_changes',
      {'status': status, 'attempt_count': 1},
      where: 'client_change_id = ?',
      whereArgs: [clientChangeId],
    );
  }

  Future<void> removePending(String clientChangeId) async {
    if (kIsWeb) {
      _pending.remove(clientChangeId);
      return;
    }
    final db = await instance;
    await db.delete('pending_changes', where: 'client_change_id = ?', whereArgs: [clientChangeId]);
  }

  Future<int> pendingCount() async {
    return (await pendingChanges()).length;
  }

  Future<int> conflictCount() async {
    return (await list('conflicts')).length;
  }

  Future<String?> meta(String key) async {
    final row = await get('_meta', key);
    return row?['value']?.toString();
  }

  Future<void> setMeta(String key, String value) {
    return upsert('_meta', {'id': key, 'value': value});
  }
}
