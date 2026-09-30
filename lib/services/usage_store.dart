import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Persists total WAN counter deltas so FlyX Control can build daily and weekly
/// usage history even though the X17U mainly exposes cumulative totals.
///
/// Counter rewinds are ignored, which prevents false spikes after a reboot.
/// When the app was closed across midnight, the unknown interval is split
/// proportionally across the calendar days it crossed instead of assigning the
/// entire delta to the day the app was reopened.
class UsageStore {
  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;

    final root = await getDatabasesPath();
    final path = p.join(root, 'flyx_usage.db');

    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1 was an unused per-device sample prototype. The X17U has not
          // exposed trustworthy per-device byte counters, so replace it with
          // the verified WAN-delta history schema.
          await db.execute('DROP TABLE IF EXISTS traffic_samples');
          await _createV2(db);
        }
      },
    );

    return _db!;
  }

  Future<void> _createV2(DatabaseExecutor db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS wan_samples (
        ts INTEGER PRIMARY KEY,
        total_bytes INTEGER NOT NULL,
        uptime_seconds INTEGER NOT NULL
      )
      ''',
    );
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS usage_deltas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        bytes INTEGER NOT NULL
      )
      ''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS usage_deltas_ts_idx ON usage_deltas(ts)',
    );
  }

  Future<void> recordWanSample({
    required DateTime timestamp,
    required int totalBytes,
    required int uptimeSeconds,
  }) async {
    if (totalBytes < 0 || uptimeSeconds < 0) return;

    final db = await _database();
    final nowMs = timestamp.millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'wan_samples',
        orderBy: 'ts DESC',
        limit: 1,
      );

      if (rows.isNotEmpty) {
        final previousTs = rows.first['ts'] as int;
        final previousTotal = rows.first['total_bytes'] as int;
        final previousUptime = rows.first['uptime_seconds'] as int;

        final delta = totalBytes - previousTotal;
        final countersMonotonic = delta >= 0;
        final uptimeMonotonic = uptimeSeconds >= previousUptime;
        final timeMovedForward = nowMs > previousTs;

        if (countersMonotonic &&
            uptimeMonotonic &&
            timeMovedForward &&
            delta > 0) {
          await _splitDeltaAcrossDays(
            txn,
            fromMs: previousTs,
            toMs: nowMs,
            bytes: delta,
          );
        }
      }

      await txn.insert(
        'wan_samples',
        {
          'ts': nowMs,
          'total_bytes': totalBytes,
          'uptime_seconds': uptimeSeconds,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'wan_samples',
        where: 'ts < ?',
        whereArgs: [
          timestamp
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
        ],
      );

      await txn.delete(
        'usage_deltas',
        where: 'ts < ?',
        whereArgs: [
          timestamp
              .subtract(const Duration(days: 62))
              .millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<void> _splitDeltaAcrossDays(
    Transaction txn, {
    required int fromMs,
    required int toMs,
    required int bytes,
  }) async {
    if (toMs <= fromMs || bytes <= 0) return;

    final totalMs = toMs - fromMs;
    var cursor = DateTime.fromMillisecondsSinceEpoch(fromMs);
    final end = DateTime.fromMillisecondsSinceEpoch(toMs);
    var assigned = 0;

    while (cursor.isBefore(end)) {
      final nextMidnight = DateTime(
        cursor.year,
        cursor.month,
        cursor.day + 1,
      );
      final segmentEnd =
          nextMidnight.isBefore(end) ? nextMidnight : end;
      final segmentMs = segmentEnd.millisecondsSinceEpoch -
          cursor.millisecondsSinceEpoch;

      final isLast = !segmentEnd.isBefore(end);
      final segmentBytes = isLast
          ? bytes - assigned
          : ((bytes * segmentMs) / totalMs).round();

      if (segmentBytes > 0) {
        await txn.insert(
          'usage_deltas',
          {
            'ts': segmentEnd.millisecondsSinceEpoch - 1,
            'bytes': segmentBytes,
          },
        );
        assigned += segmentBytes;
      }

      cursor = segmentEnd;
    }
  }

  Future<int> usageSince(DateTime start) async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(bytes), 0) AS total '
      'FROM usage_deltas WHERE ts >= ?',
      [start.millisecondsSinceEpoch],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> usageBetween(DateTime start, DateTime end) async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(bytes), 0) AS total '
      'FROM usage_deltas WHERE ts >= ? AND ts < ?',
      [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<int> todayBytes() {
    final now = DateTime.now();
    return usageSince(DateTime(now.year, now.month, now.day));
  }

  Future<List<UsagePoint>> lastSevenDays() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final result = <UsagePoint>[];
    for (var offset = 6; offset >= 0; offset--) {
      final start = today.subtract(Duration(days: offset));
      final end = start.add(const Duration(days: 1));
      final bytes = await usageBetween(start, end);
      result.add(UsagePoint(labels[start.weekday - 1], bytes));
    }
    return result;
  }
}
