import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class UsageStore {
  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'flyx_usage.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE traffic_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            captured_at INTEGER NOT NULL,
            rx_total INTEGER NOT NULL,
            tx_total INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX traffic_device_time ON traffic_samples(device_id, captured_at)');
      },
    );
    return _db!;
  }

  Future<void> addSample({
    required String deviceId,
    required int rxTotal,
    required int txTotal,
    DateTime? capturedAt,
  }) async {
    final db = await _database();
    await db.insert('traffic_samples', {
      'device_id': deviceId,
      'captured_at': (capturedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'rx_total': rxTotal,
      'tx_total': txTotal,
    });
  }

  Future<int> usageBetween(String deviceId, DateTime start, DateTime end) async {
    final db = await _database();
    final rows = await db.query(
      'traffic_samples',
      where: 'device_id = ? AND captured_at >= ? AND captured_at <= ?',
      whereArgs: [deviceId, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'captured_at ASC',
    );
    if (rows.length < 2) return 0;
    final first = rows.first;
    final last = rows.last;
    final rx = (last['rx_total'] as int) - (first['rx_total'] as int);
    final tx = (last['tx_total'] as int) - (first['tx_total'] as int);
    return (rx + tx).clamp(0, 1 << 62).toInt();
  }
}
