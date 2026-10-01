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
      version: 1,
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
      },
    );

    return _db!;
  }

  Future<void> recordObservations(
    Iterable<DeviceObservation> observations, {
    required DateTime seenAt,
  }) async {
    final rows = observations.toList(growable: false);
    if (rows.isEmpty) return;

    final db = await _database();
    final seenMs = seenAt.millisecondsSinceEpoch;

    await db.transaction((txn) async {
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
      }
    });
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
