import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'config.dart';

class Db {
  Db._();
  static final Db instance = Db._();
  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'species_check.db');
    return openDatabase(path, version: 1, onOpen: _addTestTrees, onCreate: (d, v) async {
      await d.execute(
          'CREATE TABLE trees (barcode TEXT PRIMARY KEY, species TEXT, plot TEXT)');
      await d.execute('CREATE TABLE checks ('
          'barcode TEXT PRIMARY KEY, plot TEXT, recorded TEXT, confirmed TEXT, '
          'status TEXT, checked_at TEXT, handset TEXT, '
          'synced INTEGER NOT NULL DEFAULT 0, airtable_id TEXT)');
      // Settings live here, not in shared_preferences. shared_preferences pulls in
      // androidx.datastore, which crashes on start on the Nautiz X41.
      await d.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    });
  }

  Future<String> getSetting(String key) async {
    final d = await db;
    final rows = await d.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? '' : (rows.first['value'] as String? ?? '');
  }

  Future<void> setSetting(String key, String value) async {
    final d = await db;
    await d.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> replaceTrees(List<Map<String, String>> trees) async {
    final d = await db;
    await d.transaction((t) async {
      await t.delete('trees');
      final batch = t.batch();
      for (final r in trees) {
        batch.insert('trees', r, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      await _addTestTrees(t);
    });
  }

  /// Put the test trees from Config into the tree list, if they are not there.
  static Future<void> _addTestTrees(DatabaseExecutor d) async {
    for (final e in Config.testTrees.entries) {
      await d.insert(
        'trees',
        {'barcode': e.key, 'species': e.value, 'plot': e.key.substring(0, 2)},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<int> treeCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM trees')) ?? 0;
  }

  Future<Map<String, Object?>?> getTree(String barcode) async {
    final d = await db;
    final rows = await d.query('trees', where: 'barcode = ?', whereArgs: [barcode]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> getCheck(String barcode) async {
    final d = await db;
    final rows = await d.query('checks', where: 'barcode = ?', whereArgs: [barcode]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveCheck({
    required String barcode,
    required String plot,
    required String recorded,
    required String confirmed,
    required String handset,
  }) async {
    final d = await db;
    final old = await getCheck(barcode);
    await d.insert(
      'checks',
      {
        'barcode': barcode,
        'plot': plot,
        'recorded': recorded,
        'confirmed': confirmed,
        'status': confirmed == recorded ? 'Confirmed' : 'Changed',
        'checked_at': DateTime.now().toUtc().toIso8601String(),
        'handset': handset,
        'synced': 0,
        'airtable_id': old?['airtable_id'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> unsyncedChecks() async {
    final d = await db;
    return d.query('checks', where: 'synced = 0', orderBy: 'checked_at');
  }

  Future<void> markSynced(String barcode, String airtableId) async {
    final d = await db;
    await d.update('checks', {'synced': 1, 'airtable_id': airtableId},
        where: 'barcode = ?', whereArgs: [barcode]);
  }

  Future<Map<String, int>> counts() async {
    final d = await db;
    int q(Object? v) => (v as int?) ?? 0;
    final total = await treeCount();
    final checked = q(Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM checks')));
    final changed = q(Sqflite.firstIntValue(
        await d.rawQuery("SELECT COUNT(*) FROM checks WHERE status = 'Changed'")));
    final pending = q(Sqflite.firstIntValue(
        await d.rawQuery('SELECT COUNT(*) FROM checks WHERE synced = 0')));
    return {'total': total, 'checked': checked, 'changed': changed, 'pending': pending};
  }
}
