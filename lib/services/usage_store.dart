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
class ObservedReliability {
  const ObservedReliability({
    required this.uptimePercent,
    required this.outages,
    required this.observedDuration,
  });

  final double uptimePercent;
  final int outages;
  final Duration observedDuration;
}

class UsageStore {
  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;

    final root = await getDatabasesPath();
    final path = p.join(root, 'flyx_usage.db');

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await _createV2(db);
        await _createV3(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1 was an unused per-device sample prototype. The X17U has not
          // exposed trustworthy per-device byte counters, so replace it with
          // the verified WAN-delta history schema.
          await db.execute('DROP TABLE IF EXISTS traffic_samples');
          await _createV2(db);
        }
        if (oldVersion < 3) {
          await _createV3(db);
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

  Future<void> _createV3(DatabaseExecutor db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS network_samples (
        ts INTEGER PRIMARY KEY,
        connected INTEGER NOT NULL
      )
      ''',
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

  Future<void> recordNetworkState({
    required DateTime timestamp,
    required bool connected,
  }) async {
    final db = await _database();
    final nowMs = timestamp.millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'network_samples',
        orderBy: 'ts DESC',
        limit: 1,
      );

      var shouldInsert = rows.isEmpty;
      if (rows.isNotEmpty) {
        final previousTs = (rows.first['ts'] as num).toInt();
        final previousConnected = (rows.first['connected'] as num).toInt() == 1;
        final gapMs = nowMs - previousTs;
        shouldInsert = previousConnected != connected ||
            gapMs >= const Duration(seconds: 10).inMilliseconds;
      }

      if (shouldInsert) {
        await txn.insert(
          'network_samples',
          {
            'ts': nowMs,
            'connected': connected ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.delete(
        'network_samples',
        where: 'ts < ?',
        whereArgs: [
          timestamp
              .subtract(const Duration(days: 8))
              .millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<ObservedReliability> reliabilityToday(DateTime now) async {
    final db = await _database();
    final start = DateTime(now.year, now.month, now.day);
    final startMs = start.millisecondsSinceEpoch;
    final nowMs = now.millisecondsSinceEpoch;

    final before = await db.query(
      'network_samples',
      where: 'ts < ?',
      whereArgs: [startMs],
      orderBy: 'ts DESC',
      limit: 1,
    );
    final today = await db.query(
      'network_samples',
      where: 'ts >= ? AND ts <= ?',
      whereArgs: [startMs, nowMs],
      orderBy: 'ts ASC',
    );

    final rows = <Map<String, Object?>>[
      if (before.isNotEmpty) before.first,
      ...today,
    ];
    if (rows.isEmpty) {
      return const ObservedReliability(
        uptimePercent: 0,
        outages: 0,
        observedDuration: Duration.zero,
      );
    }

    const maxObservedGap = Duration(seconds: 15);
    final maxGapMs = maxObservedGap.inMilliseconds;
    var observedMs = 0;
    var connectedMs = 0;
    var outages = 0;

    for (var i = 0; i + 1 < rows.length; i++) {
      final current = rows[i];
      final next = rows[i + 1];
      final currentTs = (current['ts'] as num).toInt();
      final nextTs = (next['ts'] as num).toInt();
      final segmentStart = currentTs < startMs ? startMs : currentTs;
      final segmentEnd = nextTs > nowMs ? nowMs : nextTs;
      final gapMs = nextTs - currentTs;

      if (gapMs > 0 &&
          gapMs <= maxGapMs &&
          segmentEnd > segmentStart) {
        final duration = segmentEnd - segmentStart;
        observedMs += duration;
        if ((current['connected'] as num).toInt() == 1) {
          connectedMs += duration;
        }
      }

      if (gapMs > 0 &&
          gapMs <= maxGapMs &&
          (current['connected'] as num).toInt() == 1 &&
          (next['connected'] as num).toInt() == 0 &&
          nextTs >= startMs) {
        outages++;
      }
    }

    final last = rows.last;
    final lastTs = (last['ts'] as num).toInt();
    final tailMs = nowMs - lastTs;
    if (tailMs > 0 && tailMs <= maxGapMs && lastTs >= startMs) {
      observedMs += tailMs;
      if ((last['connected'] as num).toInt() == 1) {
        connectedMs += tailMs;
      }
    }

    final uptime = observedMs == 0
        ? 0.0
        : (connectedMs / observedMs) * 100.0;

    return ObservedReliability(
      uptimePercent: uptime.clamp(0.0, 100.0).toDouble(),
      outages: outages,
      observedDuration: Duration(milliseconds: observedMs),
    );
  }

  Future<List<ObservedOutage>> recentObservedOutages({
    required DateTime now,
    int limit = 5,
  }) async {
    final db = await _database();
    final cutoff = now.subtract(const Duration(days: 8)).millisecondsSinceEpoch;
    final rows = await db.query(
      'network_samples',
      where: 'ts >= ?',
      whereArgs: [cutoff],
      orderBy: 'ts ASC',
    );
    if (rows.length < 2) return const [];

    const maxObservedGap = Duration(seconds: 15);
    final maxGapMs = maxObservedGap.inMilliseconds;
    final outages = <ObservedOutage>[];
    DateTime? outageStart;

    for (var i = 0; i + 1 < rows.length; i++) {
      final current = rows[i];
      final next = rows[i + 1];
      final currentTs = (current['ts'] as num).toInt();
      final nextTs = (next['ts'] as num).toInt();
      final gapMs = nextTs - currentTs;

      if (gapMs <= 0 || gapMs > maxGapMs) {
        // Monitoring gaps are unknown time, so never bridge an outage across
        // them or invent a restoration time.
        outageStart = null;
        continue;
      }

      final currentConnected = (current['connected'] as num).toInt() == 1;
      final nextConnected = (next['connected'] as num).toInt() == 1;

      if (currentConnected && !nextConnected) {
        outageStart = DateTime.fromMillisecondsSinceEpoch(nextTs);
      } else if (!currentConnected && nextConnected && outageStart != null) {
        outages.add(
          ObservedOutage(
            startedAt: outageStart,
            restoredAt: DateTime.fromMillisecondsSinceEpoch(nextTs),
          ),
        );
        outageStart = null;
      }
    }

    final last = rows.last;
    final lastTs = (last['ts'] as num).toInt();
    final lastConnected = (last['connected'] as num).toInt() == 1;
    final tailMs = now.millisecondsSinceEpoch - lastTs;
    if (!lastConnected &&
        outageStart != null &&
        tailMs >= 0 &&
        tailMs <= maxGapMs) {
      outages.add(ObservedOutage(startedAt: outageStart));
    }

    outages.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return outages.take(limit).toList(growable: false);
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
