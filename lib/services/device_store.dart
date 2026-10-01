import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class StoredDeviceProfile {
  const StoredDeviceProfile({
    required this.mac,
    required this.hostname,
    required this.lastIp,
    required this.firstSeen,
    required this.lastSeen,
    this.friendlyName,
  });

  final String mac;
  final String hostname;
  final String lastIp;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final String? friendlyName;

  String get displayName {
    final friendly = friendlyName?.trim() ?? '';
    if (friendly.isNotEmpty) return friendly;
    final host = hostname.trim();
    return host.isEmpty || host == '*' ? 'Unknown device' : host;
  }
}

class DeviceSessionStats {
  const DeviceSessionStats({
    required this.currentSession,
    required this.totalOnlineToday,
  });

  final Duration currentSession;
  final Duration totalOnlineToday;
}

class DeviceObservation {
  const DeviceObservation({
    required this.mac,
    required this.hostname,
    required this.ip,
  });

  final String mac;
  final String hostname;
  final String ip;
}

/// Local device identity/history store.
///
/// The X17U exposes only currently connected clients. FlyX Control keeps a
/// small local directory keyed by MAC so friendly names and last-seen history
/// survive DHCP changes, router reboots and app restarts.
class DeviceStore {
  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;

    final root = await getDatabasesPath();
    final path = p.join(root, 'flyx_devices.db');

    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          '''
          CREATE TABLE device_profiles (
            mac TEXT PRIMARY KEY,
            friendly_name TEXT,
            hostname TEXT NOT NULL,
            last_ip TEXT NOT NULL,
            first_seen INTEGER NOT NULL,
            last_seen INTEGER NOT NULL
          )
          ''',
        );
        await db.execute(
          'CREATE INDEX device_profiles_last_seen_idx '
          'ON device_profiles(last_seen DESC)',
        );
        await _createSessionTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSessionTables(db);
        }
      },
    );

    return _db!;
  }


  static Future<void> _createSessionTables(DatabaseExecutor db) async {
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS device_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mac TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        ended_at INTEGER
      )
      ''',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS device_sessions_mac_idx '
      'ON device_sessions(mac, started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS device_sessions_open_idx '
      'ON device_sessions(ended_at)',
    );
  }

  Future<void> recordObservations(
    Iterable<DeviceObservation> observations, {
    required DateTime seenAt,
  }) async {
    final rows = observations.toList(growable: false);
    final db = await _database();
    final seenMs = seenAt.millisecondsSinceEpoch;
    final onlineMacs = rows.map((row) => row.mac).toSet();

    await db.transaction((txn) async {
      final openSessions = await txn.query(
        'device_sessions',
        where: 'ended_at IS NULL',
      );

      for (final session in openSessions) {
        final mac = '${session['mac']}';
        final lastSeen = (session['last_seen'] as num).toInt();
        if (!onlineMacs.contains(mac)) {
          await txn.update(
            'device_sessions',
            {'ended_at': lastSeen},
            where: 'id = ?',
            whereArgs: [session['id']],
          );
        }
      }

      for (final observation in rows) {
        final existing = await txn.query(
          'device_profiles',
          columns: const ['first_seen'],
          where: 'mac = ?',
          whereArgs: [observation.mac],
          limit: 1,
        );

        final firstSeen = existing.isEmpty
            ? seenMs
            : (existing.first['first_seen'] as num).toInt();

        await txn.insert(
          'device_profiles',
          {
            'mac': observation.mac,
            'hostname': observation.hostname,
            'last_ip': observation.ip,
            'first_seen': firstSeen,
            'last_seen': seenMs,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        await txn.update(
          'device_profiles',
          {
            'hostname': observation.hostname,
            'last_ip': observation.ip,
            'last_seen': seenMs,
          },
          where: 'mac = ?',
          whereArgs: [observation.mac],
        );

        final open = await txn.query(
          'device_sessions',
          where: 'mac = ? AND ended_at IS NULL',
          whereArgs: [observation.mac],
          orderBy: 'started_at DESC',
          limit: 1,
        );

        if (open.isEmpty) {
          await txn.insert(
            'device_sessions',
            {
              'mac': observation.mac,
              'started_at': seenMs,
              'last_seen': seenMs,
              'ended_at': null,
            },
          );
        } else {
          final session = open.first;
          final lastSeen = (session['last_seen'] as num).toInt();
          const maxResumeGapMs = 90 * 1000;

          if (seenMs - lastSeen > maxResumeGapMs) {
            await txn.update(
              'device_sessions',
              {'ended_at': lastSeen},
              where: 'id = ?',
              whereArgs: [session['id']],
            );
            await txn.insert(
              'device_sessions',
              {
                'mac': observation.mac,
                'started_at': seenMs,
                'last_seen': seenMs,
                'ended_at': null,
              },
            );
          } else {
            await txn.update(
              'device_sessions',
              {'last_seen': seenMs},
              where: 'id = ?',
              whereArgs: [session['id']],
            );
          }
        }
      }
    });
  }


  Future<Map<String, DeviceSessionStats>> sessionStatsByMac({
    required DateTime now,
  }) async {
    final db = await _database();
    final nowMs = now.millisecondsSinceEpoch;
    final dayStart = DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch;

    final rows = await db.query(
      'device_sessions',
      where: 'last_seen >= ? OR ended_at IS NULL',
      whereArgs: [dayStart],
      orderBy: 'started_at ASC',
    );

    final todayMs = <String, int>{};
    final current = <String, Duration>{};

    for (final row in rows) {
      final mac = '${row['mac']}';
      final start = (row['started_at'] as num).toInt();
      final lastSeen = (row['last_seen'] as num).toInt();
      final endedRaw = row['ended_at'];
      final ended = endedRaw == null ? null : (endedRaw as num).toInt();

      final effectiveStart = start < dayStart ? dayStart : start;
      final effectiveEnd = ended ?? nowMs;
      if (effectiveEnd > effectiveStart) {
        todayMs[mac] = (todayMs[mac] ?? 0) + (effectiveEnd - effectiveStart);
      }

      if (ended == null && nowMs - lastSeen <= 90 * 1000) {
        current[mac] = Duration(
          milliseconds: nowMs - start,
        );
      }
    }

    final macs = {...todayMs.keys, ...current.keys};
    return {
      for (final mac in macs)
        mac: DeviceSessionStats(
          currentSession: current[mac] ?? Duration.zero,
          totalOnlineToday: Duration(
            milliseconds: todayMs[mac] ?? 0,
          ),
        ),
    };
  }

  Future<void> setFriendlyName(String mac, String? name) async {
    final db = await _database();
    final trimmed = name?.trim() ?? '';

    await db.update(
      'device_profiles',
      {'friendly_name': trimmed.isEmpty ? null : trimmed},
      where: 'mac = ?',
      whereArgs: [mac],
    );
  }

  Future<Map<String, StoredDeviceProfile>> profilesByMac() async {
    final db = await _database();
    final rows = await db.query(
      'device_profiles',
      orderBy: 'last_seen DESC',
    );

    return {
      for (final row in rows)
        '${row['mac']}': StoredDeviceProfile(
          mac: '${row['mac']}',
          friendlyName: row['friendly_name'] as String?,
          hostname: '${row['hostname'] ?? ''}',
          lastIp: '${row['last_ip'] ?? ''}',
          firstSeen: DateTime.fromMillisecondsSinceEpoch(
            (row['first_seen'] as num).toInt(),
          ),
          lastSeen: DateTime.fromMillisecondsSinceEpoch(
            (row['last_seen'] as num).toInt(),
          ),
        ),
    };
  }
}
