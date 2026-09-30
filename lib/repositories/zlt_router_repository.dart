import '../models/models.dart';
import '../services/zlt_client.dart';
import 'router_repository.dart';

/// Live adapter for the MTN FlyX / Tozed ZLT X17U.
///
/// Routine monitoring uses the X17U's native JSON commands. Potentially
/// disruptive controls remain capability-gated and are never guessed.
class ZltRouterRepository implements RouterRepository {
  ZltRouterRepository({
    required this.client,
    required this.username,
    required this.password,
  });

  final ZltClient client;
  final String username;
  final String password;

  bool _loggedIn = false;
  Future<void>? _loginFuture;
  ZltDiscoveryReport? _discovery;

  int _networkPoll = 0;
  Map<String, dynamic> _rfCache = const {};

  double? _lastRx;
  double? _lastTx;
  double? _lastUptime;
  DateTime? _lastCounterAt;
  double _rxRate = 0;
  double _txRate = 0;

  Set<String> _blockedMacs = <String>{};
  Map<String, String> _blockedLabels = <String, String>{};
  int _devicePoll = 0;

  Future<void> _ensureLogin() async {
    if (_loggedIn) return;
    _loginFuture ??= client.login(username: username, password: password);
    try {
      await _loginFuture;
      _loggedIn = true;
    } catch (_) {
      _loginFuture = null;
      rethrow;
    }
  }

  Future<ZltDiscoveryReport> _ensureDiscovery() async {
    if (_discovery != null) return _discovery!;
    await _ensureLogin();
    _discovery = await client.discover();
    return _discovery!;
  }

  @override
  Future<NetworkSnapshot> fetchNetwork() async {
    final wan = await client.command(133);

    _networkPoll++;
    if (_networkPoll == 1 || _networkPoll % 6 == 1) {
      try {
        _rfCache = await client.command(205);
      } catch (_) {
        // The WAN read is enough to keep the dashboard useful.
      }
    }

    final uptime = _number(wan['uptime']);
    _updateRates(
      rx: _number(wan['wan_rx_bytes']),
      tx: _number(wan['wan_tx_bytes']),
      uptime: uptime,
    );

    final monthMib = _number(_rfCache['mon_total_flow']) ?? 0;
    final rsrp5g = _int(wan['RSRP_5G'], 0);
    final rsrp4g = _int(wan['RSRP'], -120);
    final rsrq5g = _int(wan['RSRQ_5G'], 0);
    final rsrq4g = _int(wan['RSRQ'], -20);
    final sinr5g = _int(wan['SINR_5G'], 0);
    final sinr4g = _int(wan['SINR'], 0);
    final rssi5g = _int(wan['RSSI_5G'], 0);
    final rssi4g = _int(wan['RSSI'], -120);
    final pci5g = _int(wan['PCI_5G'], 0);
    final pci4g = _firstInt(wan['PCI'], 0);

    return NetworkSnapshot(
      connected: _text(wan['wan_ip']).isNotEmpty,
      networkType: _text(wan['network_type_str']).isEmpty
          ? 'Unknown'
          : _text(wan['network_type_str']),
      carrier: _text(_rfCache['network_operator']).isEmpty
          ? 'MTN-NG'
          : _text(_rfCache['network_operator']),
      rsrp: rsrp5g != 0 ? rsrp5g : rsrp4g,
      rsrq: rsrq5g != 0 ? rsrq5g : rsrq4g,
      sinr: sinr5g != 0 ? sinr5g : sinr4g,
      rssi: rssi5g != 0 ? rssi5g : rssi4g,
      pci: pci5g != 0 ? pci5g : pci4g,
      lteBand: _text(wan['currentband']).isEmpty
          ? '—'
          : _text(wan['currentband']),
      nrBand: _text(_rfCache['currentband_5g']).isEmpty
          ? '—'
          : _text(_rfCache['currentband_5g']),
      downloadBytesPerSecond: _rxRate,
      uploadBytesPerSecond: _txRate,
      routerUptime: Duration(seconds: uptime.round()),
      internetUptimePercent: 0,
      todayBytes: 0,
      monthBytes: (monthMib * 1024 * 1024).round(),
      outagesToday: 0,
      latencyMs: 0,
      packetLossPercent: 0,
    );
  }

  void _updateRates({
    required double? rx,
    required double? tx,
    required double uptime,
  }) {
    final now = DateTime.now();
    final previousAt = _lastCounterAt;

    if (rx != null &&
        tx != null &&
        _lastRx != null &&
        _lastTx != null &&
        _lastUptime != null &&
        previousAt != null) {
      final seconds =
          now.difference(previousAt).inMilliseconds / 1000.0;
      final uptimeRewound = uptime < _lastUptime!;
      final rxRewound = rx < _lastRx!;
      final txRewound = tx < _lastTx!;

      if (seconds > 0 && !uptimeRewound && !rxRewound && !txRewound) {
        _rxRate = (rx - _lastRx!) / seconds;
        _txRate = (tx - _lastTx!) / seconds;
      } else {
        _rxRate = 0;
        _txRate = 0;
      }
    }

    _lastRx = rx;
    _lastTx = tx;
    _lastUptime = uptime;
    _lastCounterAt = now;
  }

  @override
  Future<List<FlyxDevice>> fetchDevices() async {
    await _ensureLogin();
    final result = await client.command(223, authenticated: true);
    final rows = result['dhcp_list_info'];

    _devicePoll++;
    if (_devicePoll == 1 || _devicePoll % 3 == 1) {
      await _refreshBlocked();
    }

    final devices = <FlyxDevice>[];
    final onlineMacs = <String>{};

    if (rows is List) {
      for (final entry in rows) {
        if (entry is! Map) continue;
        final map = entry.map((key, value) => MapEntry('$key', value));
        final mac = _normaliseMac('${map['mac'] ?? ''}');
        if (mac.isEmpty) continue;
        onlineMacs.add(mac);

        final hostname = _text(map['hostname']);
        final name = hostname.isEmpty ? 'Unknown device' : hostname;
        final connectSeconds = _int(
          map['connect_time'] ?? map['online_time'] ?? map['uptime'],
          0,
        );

        devices.add(
          FlyxDevice(
            id: mac,
            name: name,
            hostname: name,
            mac: mac,
            ip: _text(map['ip']).isEmpty ? '—' : _text(map['ip']),
            kind: DeviceKind.unknown,
            online: true,
            blocked: _blockedMacs.contains(mac),
            rxBytesPerSecond: 0,
            txBytesPerSecond: 0,
            todayBytes: 0,
            weekBytes: 0,
            monthBytes: 0,
            currentSession: Duration(seconds: connectSeconds),
            totalOnlineToday: Duration(seconds: connectSeconds),
            lastSeen: DateTime.now(),
            signalPercent: 0,
          ),
        );
      }
    }

    // A blocked client normally disappears from DHCP/association lists. Keep it
    // visible in FlyX Control so the Blocked tab remains useful.
    for (final mac in _blockedMacs) {
      if (onlineMacs.contains(mac)) continue;
      final label = _blockedLabels[mac] ?? '';
      final name = label.isEmpty ? 'Blocked device' : label;
      devices.add(
        FlyxDevice(
          id: mac,
          name: name,
          hostname: name,
          mac: mac,
          ip: '—',
          kind: DeviceKind.unknown,
          online: false,
          blocked: true,
          rxBytesPerSecond: 0,
          txBytesPerSecond: 0,
          todayBytes: 0,
          weekBytes: 0,
          monthBytes: 0,
          currentSession: Duration.zero,
          totalOnlineToday: Duration.zero,
          lastSeen: DateTime.now(),
          signalPercent: 0,
        ),
      );
    }

    return devices;
  }

  Future<void> _refreshBlocked() async {
    try {
      final rules = await _filterRules();
      final blocked = <String>{};
      final labels = <String, String>{};

      for (final rule in rules) {
        if (rule['enableRule'] != true) continue;
        final mac = _normaliseMac('${rule['mac'] ?? ''}');
        if (mac.isEmpty) continue;
        blocked.add(mac);
        final label = _text(rule['remark']);
        if (label.isNotEmpty) labels[mac] = label;
      }

      _blockedMacs = blocked;
      _blockedLabels = labels;
    } catch (_) {
      // Device listing can still work even if this firmware hides filters.
    }
  }

  Future<List<Map<String, dynamic>>> _filterRules() async {
    final payload = await client.command(23, authenticated: true);
    final rows = payload['datas'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => row.map(
            (key, value) => MapEntry('$key', value),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<RouterCapabilities> capabilities() async {
    final report = await _ensureDiscovery();
    return RouterCapabilities(
      signal: report.supportsCommand(133),
      stationList: report.hasStationList,
      blocking: report.canBlock,
      sms: false,
      ussd: false,
      wifiSettings: false,
      reboot: false,
      perDeviceTraffic: false,
      qos: false,
      networkMode: false,
      discoveredActions:
          report.verifiedCommands.map((cmd) => 'cmd:$cmd').toList(),
    );
  }

  @override
  Future<void> setBlocked(String deviceId, bool blocked) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.canBlock) {
      throw RouterFeatureUnavailable(
        'This X17U did not expose the filter controls needed for safe blocking.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    final rules = (await _filterRules())
        .where(
          (rule) => _normaliseMac('${rule['mac'] ?? ''}') != mac,
        )
        .toList();

    if (blocked) {
      final existingAddresses = rules
          .map((rule) => _normaliseMac('${rule['mac'] ?? ''}'))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (existingAddresses.length >= 32) {
        throw RouterFeatureUnavailable(
          'This router already has the maximum number of blocked devices.',
        );
      }

      final mode = {
        'datas': [
          for (final family in const ['IPV4', 'IPV6'])
            {
              'enableRule': true,
              'acceptAll': true,
              'ippro': family,
            },
        ],
      };

      // Explicitly select blacklist semantics before adding a deny rule.
      await client.write(28, mode);
      await client.write(30, mode);

      for (final family in const ['IPV4', 'IPV6']) {
        rules.add({
          'ippro': family,
          'mac': mac,
          'remark': _blockedLabels[mac] ?? '',
          'enableRule': true,
          'enableLink': false,
        });
      }
    }

    await client.write(23, {'datas': rules});
    await client.write(20, const {});
    await _refreshBlocked();
  }

  @override
  Future<void> setDeviceName(String deviceId, String name) async {
    throw RouterFeatureUnavailable(
      'Friendly names are stored locally for now. The X17U rename command has not been verified yet.',
    );
  }

  @override
  Future<void> setDevicePolicy(String deviceId, DevicePolicy policy) async {
    throw RouterFeatureUnavailable(
      'Quota storage is ready, but automatic enforcement will be enabled only after per-device counters are verified on this firmware.',
    );
  }

  @override
  Future<List<UsagePoint>> fetchWeeklyUsage() async => const [];

  @override
  Future<void> reboot() async {
    throw RouterFeatureUnavailable(
      'Reboot is intentionally disabled until its X17U command is verified.',
    );
  }

  double _number(dynamic value, [double fallback = 0]) {
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? fallback;
  }

  int _int(dynamic value, [int fallback = 0]) {
    final number = _number(value, fallback.toDouble());
    return number.round();
  }

  int _firstInt(dynamic value, [int fallback = 0]) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return fallback;
    final first = RegExp(r'-?\\d+').firstMatch(text)?.group(0);
    return int.tryParse(first ?? '') ?? fallback;
  }

  String _text(dynamic value) => '${value ?? ''}'.trim();

  String _normaliseMac(String value) {
    final pairs = RegExp(r'[0-9A-Fa-f]{2}')
        .allMatches(value)
        .map((match) => match.group(0)!)
        .toList();
    if (pairs.length != 6) return '';
    return pairs.map((part) => part.toUpperCase()).join(':');
  }
}
