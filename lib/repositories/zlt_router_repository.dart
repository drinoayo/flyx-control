import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import '../services/device_store.dart';
import '../services/usage_store.dart';
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
    UsageStore? usageStore,
    DeviceStore? deviceStore,
  })  : usageStore = usageStore ?? UsageStore(),
        deviceStore = deviceStore ?? DeviceStore();

  final ZltClient client;
  final String username;
  final String password;
  final UsageStore usageStore;
  final DeviceStore deviceStore;

  Future<void>? _loginFuture;
  ZltDiscoveryReport? _discovery;

  int _networkPoll = 0;
  Map<String, dynamic> _rfCache = const {};
  Map<String, dynamic> _trafficCache = const {};
  Map<String, dynamic> _systemCache = const {};
  DateTime? _lastUsagePersistAt;
  int _todayBytesCache = 0;

  double? _lastRx;
  double? _lastTx;
  double? _lastUptime;
  DateTime? _lastCounterAt;
  double _rxRate = 0;
  double _txRate = 0;

  Set<String> _blockedMacs = <String>{};
  Map<String, String> _blockedLabels = <String, String>{};
  List<Map<String, dynamic>> _parentRules = const [];
  int _devicePoll = 0;
  DateTime? _routerClockBase;
  DateTime? _routerClockReadAt;

  Future<void> _ensureLogin() async {
    if (client.isAuthenticated) {
      return;
    }

    final existing = _loginFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final future = client.login(username: username, password: password);
    _loginFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loginFuture, future)) {
        _loginFuture = null;
      }
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
    await _ensureLogin();

    final wan = await client.command(133);
    final flow = await _safeCommand(18);

    _networkPoll++;
    if (_networkPoll == 1 || _networkPoll % 6 == 1) {
      try {
        _rfCache = await client.command(205);
      } catch (_) {
        // Core radio fields are still available from cmd 133.
      }
    }

    if (_networkPoll == 1 || _networkPoll % 10 == 1) {
      final slow = await Future.wait<Map<String, dynamic>>([
        _safeCommand(337),
        _safeCommand(207),
      ]);
      if (slow[0].isNotEmpty) _trafficCache = slow[0];
      if (slow[1].isNotEmpty) _systemCache = slow[1];
    }

    final rx = _nullableNumber(flow['rxBytes']) ??
        _nullableNumber(wan['wan_rx_bytes']);
    final tx = _nullableNumber(flow['txBytes']) ??
        _nullableNumber(wan['wan_tx_bytes']);
    final uptime = _nullableNumber(flow['uptime']) ??
        _nullableNumber(wan['uptime']) ??
        0;

    _updateRates(
      rx: rx,
      tx: tx,
      uptime: uptime,
    );

    final now = DateTime.now();
    final connected = _text(wan['wan_ip']).isNotEmpty;
    await usageStore.recordNetworkState(
      timestamp: now,
      connected: connected,
    );
    final reliability = await usageStore.reliabilityToday(now);
    final recentOutages = await usageStore.recentObservedOutages(now: now);

    final shouldPersist = _lastUsagePersistAt == null ||
        now.difference(_lastUsagePersistAt!) >= const Duration(seconds: 10);

    if (rx != null && tx != null && uptime >= 0 && shouldPersist) {
      await usageStore.recordWanSample(
        timestamp: now,
        totalBytes: (rx + tx).round(),
        uptimeSeconds: uptime.round(),
      );
      _lastUsagePersistAt = now;
      _todayBytesCache = await usageStore.todayBytes();
    }

    final monthTotalMib =
        _nullableNumber(_trafficCache['mon_download_flow']) ??
            _nullableNumber(_rfCache['mon_total_flow']) ??
            0;
    final monthDownMib =
        _nullableNumber(_trafficCache['dl_mon_flow']) ?? 0;
    final monthUpMib =
        _nullableNumber(_trafficCache['ul_mon_flow']) ?? 0;

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
      connected: connected,
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
      internetUptimePercent: reliability.uptimePercent,
      internetObservationDuration: reliability.observedDuration,
      todayBytes: _todayBytesCache,
      monthBytes: (monthTotalMib * 1024 * 1024).round(),
      monthDownloadBytes: (monthDownMib * 1024 * 1024).round(),
      monthUploadBytes: (monthUpMib * 1024 * 1024).round(),
      outagesToday: reliability.outages,
      latencyMs: 0,
      packetLossPercent: 0,
      recentOutages: recentOutages,
      routerCpuPercent: _nullableNumber(_systemCache['cpu_usage']),
      routerTemperatureC:
          _nullableNumber(_systemCache['device_temperature']),
      routerMemoryFreeBytes:
          _kilobytesToBytes(_systemCache['memoryFree']),
      firmwareVersion: _text(_systemCache['real_fwversion']),
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
      final seconds = now.difference(previousAt).inMilliseconds / 1000.0;
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

    final result223 = await client.command(223, authenticated: true);
    dynamic rows = result223['dhcp_list_info'];
    if (rows is! List) {
      try {
        final result402 = await client.command(402, authenticated: true);
        rows = result402['dhcp_list_info'];
      } catch (_) {
        // cmd 223 is already confirmed on the MTN X17U.
      }
    }

    final deviceSnapshotReliable = rows is List;

    final wifiResults = await Future.wait<Map<String, dynamic>>([
      _safeCommand(224),
      _safeCommand(225),
    ]);
    final wifiByMac = <String, Map<String, dynamic>>{};
    final wifiByIp = <String, Map<String, dynamic>>{};

    void indexWifi(dynamic list, String band) {
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map) continue;
        final map = item.map((key, value) => MapEntry('$key', value));
        map['__band'] = band;
        final mac = _normaliseMac(_text(map['mac']));
        final ip = _text(map['ip']);
        if (mac.isNotEmpty) wifiByMac[mac] = map;
        if (ip.isNotEmpty) wifiByIp[ip] = map;
      }
    }

    indexWifi(wifiResults[0]['wlan24g_wifi_info'], '2.4 GHz');
    indexWifi(wifiResults[1]['wlan5g_wifi_info'], '5 GHz');

    _devicePoll++;
    if (_devicePoll == 1 || _devicePoll % 3 == 1) {
      await _refreshBlocked();
      await _refreshParentControl();
    }

    final observedAt = DateTime.now();
    final scheduleNow = await _routerScheduleTime(observedAt);
    final devices = <FlyxDevice>[];
    final observations = <DeviceObservation>[];
    final onlineMacs = <String>{};

    if (rows is List) {
      for (final entry in rows) {
        if (entry is! Map) continue;
        final map = entry.map((key, value) => MapEntry('$key', value));
        final mac = _normaliseMac(_text(map['mac']));
        if (mac.isEmpty) continue;
        onlineMacs.add(mac);

        final hostname = _text(map['hostname']);
        final name = hostname.isEmpty || hostname == '*'
            ? 'Unknown device'
            : hostname;
        final ip = _text(map['ip']);
        observations.add(
          DeviceObservation(
            mac: mac,
            hostname: name,
            ip: ip,
          ),
        );
        final wifi = wifiByMac[mac] ?? wifiByIp[ip] ?? const <String, dynamic>{};

        final rssi = _nullableInt(wifi['rssi']);
        final signalPercent = rssi == null ? 0 : _wifiSignalPercent(rssi);
        final txLink = _positiveNumber(wifi['txrate']);
        final rxLink = _positiveNumber(wifi['rxrate']);
        final expires = _dateFromEpoch(map['expires']);
        final schedule = _parentScheduleForIp(ip);
        final scheduleActive = schedule?.isActiveAt(scheduleNow) ?? false;

        devices.add(
          FlyxDevice(
            id: mac,
            name: name,
            hostname: name,
            mac: mac,
            ip: ip.isEmpty ? '—' : ip,
            kind: _inferKind(name),
            online: true,
            blocked: _blockedMacs.contains(mac) || scheduleActive,
            rxBytesPerSecond: 0,
            txBytesPerSecond: 0,
            todayBytes: 0,
            weekBytes: 0,
            monthBytes: 0,
            currentSession: Duration.zero,
            totalOnlineToday: Duration.zero,
            lastSeen: observedAt,
            signalPercent: signalPercent,
            wifiBand: _text(wifi['__band']),
            wifiRssiDbm: rssi,
            wifiTxLinkMbps: txLink,
            wifiRxLinkMbps: rxLink,
            dhcpLeaseExpires: expires,
            parentControlSchedule: schedule,
            parentControlActive: scheduleActive,
          ),
        );
      }
    }

    if (deviceSnapshotReliable) {
      await deviceStore.recordObservations(observations, seenAt: observedAt);
    }
    final profiles = await deviceStore.profilesByMac();
    final sessionStats =
        await deviceStore.sessionStatsByMac(now: observedAt);
    final recentSessions = await deviceStore.recentSessionsByMac();

    for (var i = 0; i < devices.length; i++) {
      final profile = profiles[devices[i].mac];
      final stats = sessionStats[devices[i].mac];
      devices[i] = devices[i].copyWith(
        name: profile?.displayName ?? devices[i].name,
        firstSeen: profile?.firstSeen,
        currentSession: stats?.currentSession ?? Duration.zero,
        totalOnlineToday: stats?.totalOnlineToday ?? Duration.zero,
        recentSessions: recentSessions[devices[i].mac] ?? const [],
      );
    }

    // A blocked client normally disappears from active association lists. If
    // future firmware mapping exposes readable filter rules, keep it visible.
    for (final mac in _blockedMacs) {
      if (onlineMacs.contains(mac)) continue;
      final label = _blockedLabels[mac] ?? '';
      final profile = profiles[mac];
      final name = profile?.displayName ??
          (label.isEmpty ? 'Blocked device' : label);
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
          currentSession:
              sessionStats[mac]?.currentSession ?? Duration.zero,
          totalOnlineToday:
              sessionStats[mac]?.totalOnlineToday ?? Duration.zero,
          lastSeen: profile?.lastSeen ?? observedAt,
          signalPercent: 0,
          firstSeen: profile?.firstSeen,
          recentSessions: recentSessions[mac] ?? const [],
        ),
      );
    }

    final existingIds = devices.map((device) => device.id).toSet();
    for (final profile in profiles.values) {
      if (existingIds.contains(profile.mac)) continue;
      devices.add(
        FlyxDevice(
          id: profile.mac,
          name: profile.displayName,
          hostname: profile.hostname.isEmpty
              ? 'Unknown device'
              : profile.hostname,
          mac: profile.mac,
          ip: profile.lastIp.isEmpty ? '—' : profile.lastIp,
          kind: _inferKind(profile.hostname),
          online: false,
          blocked: false,
          rxBytesPerSecond: 0,
          txBytesPerSecond: 0,
          todayBytes: 0,
          weekBytes: 0,
          monthBytes: 0,
          currentSession:
              sessionStats[profile.mac]?.currentSession ?? Duration.zero,
          totalOnlineToday:
              sessionStats[profile.mac]?.totalOnlineToday ?? Duration.zero,
          lastSeen: profile.lastSeen,
          signalPercent: 0,
          firstSeen: profile.firstSeen,
          recentSessions: recentSessions[profile.mac] ?? const [],
        ),
      );
    }

    return devices;
  }

  Future<Map<String, dynamic>> _safeCommand(int cmd) async {
    try {
      return await client.command(cmd, authenticated: true);
    } catch (_) {
      return const {};
    }
  }

  Future<DateTime> _routerScheduleTime(DateTime fallback) async {
    final base = _routerClockBase;
    final readAt = _routerClockReadAt;
    if (base != null && readAt != null) {
      final age = fallback.difference(readAt);
      if (!age.isNegative && age <= const Duration(seconds: 30)) {
        return base.add(age);
      }
    }

    final response = await _safeCommand(11);
    final parsed = _parseRouterSystemTime(_text(response['systime']));
    if (parsed != null) {
      _routerClockBase = parsed;
      _routerClockReadAt = fallback;
      return parsed;
    }
    return fallback;
  }

  DateTime? _parseRouterSystemTime(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(value.trim());
    if (match == null) return null;

    final parts = <int>[];
    for (var i = 1; i <= 6; i++) {
      final parsed = int.tryParse(match.group(i)!);
      if (parsed == null) return null;
      parts.add(parsed);
    }

    try {
      return DateTime(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
      );
    } catch (_) {
      return null;
    }
  }
  Future<void> _refreshBlocked() async {
    try {
      final blocked = <String>{};
      for (final subcmd in const ['0', '1']) {
        final state = await _wirelessFilterState(subcmd);
        if (_text(state['macfilter']) != 'deny') continue;
        final rows = state['maclist'];
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          final mac = _normaliseMac(_text(row['mac']));
          if (mac.isNotEmpty) blocked.add(mac);
        }
      }
      _blockedMacs = blocked;
      _blockedLabels = const {};
      return;
    } catch (_) {
      // Fall back to the generic filter table on firmware that exposes it.
    }

    try {
      final rules = await _filterRules();
      final blocked = <String>{};
      final labels = <String, String>{};

      for (final rule in rules) {
        if (rule['enableRule'] != true) continue;
        final mac = _normaliseMac(_text(rule['mac']));
        if (mac.isEmpty) continue;
        blocked.add(mac);
        final label = _text(rule['remark']);
        if (label.isNotEmpty) labels[mac] = label;
      }

      _blockedMacs = blocked;
      _blockedLabels = labels;
    } catch (_) {
      // Block state remains unchanged if neither filter source is readable.
    }
  }

  Future<Map<String, dynamic>> _wirelessFilterState(String subcmd) async {
    final raw = await client.readWirelessMacFilter(subcmd);
    if (raw == null) {
      return <String, dynamic>{
        'macfilter': 'close',
        'maclist': <Map<String, dynamic>>[],
      };
    }

    final mode = _text(raw['macfilter']);
    final rows = raw['maclist'];
    if (!const {'close', 'deny', 'allow'}.contains(mode) || rows is! List) {
      throw RouterFeatureUnavailable(
        'The router returned an unexpected Wi-Fi MAC-filter state.',
      );
    }

    return <String, dynamic>{
      ...raw,
      'macfilter': mode,
      'maclist': [
        for (final row in rows)
          if (row is Map)
            row.map((key, value) => MapEntry('$key', value)),
      ],
    };
  }

  Future<List<Map<String, dynamic>>> _filterRules() async {
    final payload = await client.command(
      23,
      authenticated: true,
      fields: const {'getfun': true},
    );
    final rows = payload['datas'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry('$key', value)))
        .toList(growable: false);
  }

  Future<void> _refreshParentControl() async {
    try {
      _parentRules = await client.readParentControlRules();
    } catch (_) {
      // Capability discovery decides whether schedules are exposed.
    }
  }

  ParentControlSchedule? _parentScheduleForIp(String ip) {
    if (ip.isEmpty) return null;
    for (final rule in _parentRules) {
      if (_text(rule['ip']) != ip) continue;
      final start = _text(rule['startTime']);
      final end = _text(rule['endTime']);
      final days = _parseScheduleDays(rule['scheduleDays']);
      if (start.isEmpty || end.isEmpty || days.isEmpty) return null;
      return ParentControlSchedule(
        enabled: rule['enableRule'] == true ||
            _text(rule['enableRule']).toLowerCase() == 'true' ||
            _text(rule['enableRule']) == '1',
        startTime: start,
        endTime: end,
        days: days,
      );
    }
    return null;
  }

  @override
  Future<WifiSettingsSnapshot> fetchWifiSettings() async {
    await _ensureLogin();
    final results = await Future.wait<Map<String, dynamic>>([
      client.command(
        2,
        authenticated: true,
        fields: const {'subcmd': 0},
      ),
      client.command(
        211,
        authenticated: true,
        fields: const {'subcmd': 0},
      ),
      client.command(
        230,
        authenticated: true,
        fields: const {'subcmd': '0'},
      ),
      client.command(
        231,
        authenticated: true,
        fields: const {'subcmd': '0'},
      ),
      client.command(
        132,
        authenticated: true,
        fields: const {'subcmd': '0'},
      ),
      client.command(
        132,
        authenticated: true,
        fields: const {'subcmd': '1'},
      ),
    ]);

    return WifiSettingsSnapshot(
      optimizationEnabled: _text(results[0]['wifiSames']) == '1',
      twoFourGhz: _wifiBandSettings(
        WifiBand.twoFourGhz,
        primary: results[0],
        radio: results[2],
        wps: results[4],
      ),
      fiveGhz: _wifiBandSettings(
        WifiBand.fiveGhz,
        primary: results[1],
        radio: results[3],
        wps: results[5],
      ),
    );
  }

  WifiBandSettings _wifiBandSettings(
    WifiBand band, {
    required Map<String, dynamic> primary,
    required Map<String, dynamic> radio,
    required Map<String, dynamic> wps,
  }) {
    final fallbackChannel = band == WifiBand.twoFourGhz
        ? _text(primary['wifi24Channel'])
        : _text(primary['wifi5Channel']);
    final radioChannel = _text(radio['channel']);
    final wpsKey = band == WifiBand.twoFourGhz
        ? 'wlan2g_wps_switch'
        : 'wlan5g_wps_switch';

    return WifiBandSettings(
      band: band,
      ssid: _decodeWifiSsid(_text(primary['ssid'])),
      enabled: _text(primary['wifiOpen']) == '1',
      broadcast: _text(primary['broadcast']) == '1',
      channel: radioChannel.isEmpty ? fallbackChannel : radioChannel,
      bandwidthCode: _text(radio['bandWidth']),
      txPowerPercent: _number(radio['txPower']),
      maxClients: _int(radio['maxNum']),
      wpsEnabled: _text(wps[wpsKey]) == '1',
      authenticationType: _text(primary['authenticationType']),
      wifiModeCode: _text(radio['wifiWorkMode']),
      countryCode: _text(radio['countryCode']),
      maxClientsLimit: _int(
        radio[
          band == WifiBand.twoFourGhz
              ? 'maxStaLimitCap24'
              : 'maxStaLimitCap5'
        ],
        32,
      ),
      dfsEnabled: band == WifiBand.fiveGhz
          ? _text(radio['dfsSwitch']) == '1'
          : null,
    );
  }

  @override
  Future<WifiUpdateResult> updateWifiPrimary(
    WifiBand band, {
    String? ssid,
    String? password,
    bool? enabled,
    bool? broadcast,
    String? authenticationType,
  }) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    final cmd = band == WifiBand.twoFourGhz ? 2 : 211;
    final otherCmd = band == WifiBand.twoFourGhz ? 211 : 2;
    if (!report.supportsCommand(cmd)) {
      throw RouterFeatureUnavailable(
        'This Wi-Fi band is not readable on the connected router.',
      );
    }

    final current = await client.command(
      cmd,
      authenticated: true,
      fields: const {'subcmd': 0},
    );
    final original = _wifiPrimaryForm(current);
    if (_text(original['wifiSames']) == '1') {
      throw RouterFeatureUnavailable(
        '5G Optimization is enabled. Turn it off before changing an individual Wi-Fi band.',
      );
    }
    final updated = Map<String, dynamic>.from(original);

    final requestedSsid = ssid?.trim();
    if (ssid != null) {
      if (requestedSsid == null || requestedSsid.isEmpty) {
        throw RouterFeatureUnavailable('Wi-Fi name cannot be empty.');
      }
      final bytes = utf8.encode(requestedSsid);
      if (bytes.length > 31 ||
          requestedSsid.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
        throw RouterFeatureUnavailable(
          'Wi-Fi name must be 31 bytes or fewer and cannot contain control characters.',
        );
      }
      updated['ssid'] = base64Encode(bytes);
    }

    if (enabled != null) {
      if (!enabled) {
        final other = await client.command(
          otherCmd,
          authenticated: true,
          fields: const {'subcmd': 0},
        );
        if (_text(other['wifiOpen']) != '1') {
          throw RouterFeatureUnavailable(
            'FlyX Control will not turn off the last enabled Wi-Fi band.',
          );
        }
      }
      updated['wifiOpen'] = enabled ? '1' : '0';
    }

    if (broadcast != null) {
      updated['broadcast'] = broadcast ? '1' : '0';
    }

    const securityModes = {'0', '2', '3', '4', '5'};
    if (authenticationType != null) {
      if (!securityModes.contains(authenticationType)) {
        throw RouterFeatureUnavailable('Unsupported Wi-Fi security mode.');
      }
      updated['authenticationType'] = authenticationType;
      if (authenticationType == '0') {
        updated['key'] = '';
      }
    }

    final targetSecurity = _text(updated['authenticationType']);
    if (password != null && password.isNotEmpty) {
      if (targetSecurity == '0') {
        throw RouterFeatureUnavailable(
          'An open Wi-Fi network does not use a password.',
        );
      }
      _validateWifiPassword(password);
      updated['key'] = password;
    }

    if (targetSecurity != '0' && _text(updated['key']).isEmpty) {
      throw RouterFeatureUnavailable(
        'Enter a Wi-Fi password before enabling a protected security mode.',
      );
    }

    final changed = !_sameJson(updated, original);
    if (!changed) return const WifiUpdateResult();

    final disruptive =
        _text(updated['ssid']) != _text(original['ssid']) ||
            _text(updated['key']) != _text(original['key']) ||
            _text(updated['wifiOpen']) != _text(original['wifiOpen']) ||
            _text(updated['authenticationType']) !=
                _text(original['authenticationType']);
    final localBand = disruptive ? await _localWifiBand() : null;
    final reconnectExpected =
        disruptive && (localBand == null || localBand == band);

    Object? primaryError;
    try {
      await client.writeExact(
        cmd,
        {
          ...updated,
          'subcmd': 0,
        },
      );

      if (reconnectExpected) {
        return const WifiUpdateResult(reconnectExpected: true);
      }

      final readback = await client.command(
        cmd,
        authenticated: true,
        fields: const {'subcmd': 0},
      );
      if (!_wifiPrimaryMatches(
        readback,
        updated,
        checkKey: (password?.isNotEmpty ?? false) || targetSecurity == '0',
      )) {
        throw RouterFeatureUnavailable(
          'The router did not confirm the Wi-Fi change.',
        );
      }
      return const WifiUpdateResult();
    } catch (error) {
      primaryError = error;
    }

    try {
      await client.writeExact(
        cmd,
        {
          ...original,
          'subcmd': 0,
        },
      );
      final restored = await client.command(
        cmd,
        authenticated: true,
        fields: const {'subcmd': 0},
      );
      if (!_wifiPrimaryMatches(restored, original, checkKey: false)) {
        throw RouterFeatureUnavailable(
          'The router did not confirm an exact Wi-Fi rollback.',
        );
      }
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The Wi-Fi change failed and rollback could not be verified. Check the MTN Wi-Fi page before trying another change. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The Wi-Fi change was not saved. The previous settings were restored. $primaryError',
    );
  }

  void _validateWifiPassword(String password) {
    final invalidPassword = password.length < 8 ||
        password.length > 31 ||
        password.contains(RegExp(r'\s')) ||
        password.contains(RegExp(r'''[\\'";]''')) ||
        password.codeUnits.any((unit) => unit > 0x7f);
    if (invalidPassword) {
      throw RouterFeatureUnavailable(
        'Wi-Fi password must be 8–31 ASCII characters with no spaces, backslashes, quotes or semicolons.',
      );
    }
  }

  @override
  Future<WifiUpdateResult> updateWifiRadio(
    WifiBand band, {
    String? channel,
    String? wifiModeCode,
    String? bandwidthCode,
    double? txPowerPercent,
    int? maxClients,
    bool? dfsEnabled,
  }) async {
    await _ensureLogin();
    final cmd = band == WifiBand.twoFourGhz ? 230 : 231;
    final primaryCmd = band == WifiBand.twoFourGhz ? 2 : 211;
    final currentPrimary = await client.command(
      primaryCmd,
      authenticated: true,
      fields: const {'subcmd': 0},
    );
    if (_text(currentPrimary['wifiSames']) == '1') {
      throw RouterFeatureUnavailable(
        '5G Optimization is enabled. Turn it off before changing advanced settings for one band.',
      );
    }

    final current = await client.command(
      cmd,
      authenticated: true,
      fields: const {'subcmd': '0'},
    );
    final original = _wifiRadioForm(band, current);
    final updated = Map<String, dynamic>.from(original);

    if (channel != null) {
      final value = channel.trim().toLowerCase();
      if (value != 'auto') {
        final parsed = int.tryParse(value);
        if (parsed == null || parsed < 1 || parsed > 196) {
          throw RouterFeatureUnavailable(
            'Channel must be Auto or a numeric channel supported by the router.',
          );
        }
      }
      updated['channel'] = value == 'auto' ? 'auto' : value;
    }

    if (wifiModeCode != null) {
      final allowed = band == WifiBand.twoFourGhz
          ? const {'0', '1', '2', '3', '4', '5', '6', '16'}
          : <String>{
              '7',
              '8',
              '9',
              '10',
              '11',
              '13',
              '17',
              _text(original['wifi_workMode']),
            };
      if (!allowed.contains(wifiModeCode)) {
        throw RouterFeatureUnavailable(
          'That Wi-Fi mode is not exposed by the stock MTN settings for this band.',
        );
      }
      updated['wifi_workMode'] = wifiModeCode;
      updated['wifiWorkMode'] = wifiModeCode;
    }

    if (bandwidthCode != null) {
      _validateWifiBandwidth(
        band,
        mode: _text(updated['wifi_workMode']),
        channel: _text(updated['channel']),
        bandwidth: bandwidthCode,
      );
      updated['bandWidth'] = bandwidthCode;
    } else {
      _validateWifiBandwidth(
        band,
        mode: _text(updated['wifi_workMode']),
        channel: _text(updated['channel']),
        bandwidth: _text(updated['bandWidth']),
      );
    }

    if (txPowerPercent != null) {
      const allowedPower = [100.0, 75.0, 50.0, 25.0, 12.5];
      if (!allowedPower.contains(txPowerPercent)) {
        throw RouterFeatureUnavailable(
          'Choose a transmit-power level exposed by the MTN Wi-Fi page.',
        );
      }
      updated['txPower'] = _formatWifiNumber(txPowerPercent);
    }

    if (maxClients != null) {
      final limit = band == WifiBand.twoFourGhz
          ? _int(current['maxStaLimitCap24'], 32)
          : _int(current['maxStaLimitCap5'], 32);
      if (maxClients < 1 || maxClients > limit) {
        throw RouterFeatureUnavailable(
          'Maximum clients must be between 1 and $limit.',
        );
      }
      updated['maxNum'] = '$maxClients';
    }

    if (dfsEnabled != null && band == WifiBand.fiveGhz) {
      updated['dfsSwitch'] = dfsEnabled ? '1' : '0';
    }

    final changed = !_sameWifiRadioState(original, updated, band);
    if (!changed) return const WifiUpdateResult();

    final localBand = await _localWifiBand();
    final reconnectExpected = localBand == null || localBand == band;

    Object? primaryError;
    try {
      await client.writeExact(cmd, updated);
      if (reconnectExpected) {
        return const WifiUpdateResult(reconnectExpected: true);
      }

      final readback = await client.command(
        cmd,
        authenticated: true,
        fields: const {'subcmd': '0'},
      );
      if (!_wifiRadioMatches(readback, updated, band)) {
        throw RouterFeatureUnavailable(
          'The router did not confirm the advanced Wi-Fi change.',
        );
      }
      return const WifiUpdateResult();
    } catch (error) {
      primaryError = error;
    }

    try {
      await client.writeExact(cmd, original);
      final restored = await client.command(
        cmd,
        authenticated: true,
        fields: const {'subcmd': '0'},
      );
      if (!_wifiRadioMatches(restored, original, band)) {
        throw RouterFeatureUnavailable(
          'The router did not confirm the advanced Wi-Fi rollback.',
        );
      }
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The advanced Wi-Fi change failed and rollback could not be verified. Check the MTN Wi-Fi page before trying again. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The advanced Wi-Fi change was not saved. The previous settings were restored. $primaryError',
    );
  }

  @override
  Future<void> setWifiWps(WifiBand band, bool enabled) async {
    await _ensureLogin();
    final primaryCmd = band == WifiBand.twoFourGhz ? 2 : 211;
    final subcmd = band == WifiBand.twoFourGhz ? '0' : '1';
    final key = band == WifiBand.twoFourGhz
        ? 'wlan2g_wps_switch'
        : 'wlan5g_wps_switch';

    final primary = await client.command(
      primaryCmd,
      authenticated: true,
      fields: const {'subcmd': 0},
    );
    if (enabled) {
      if (_text(primary['wifiOpen']) != '1') {
        throw RouterFeatureUnavailable(
          'Turn this Wi-Fi band on before enabling WPS.',
        );
      }
      if (_text(primary['broadcast']) != '1') {
        throw RouterFeatureUnavailable(
          'Enable SSID broadcast before enabling WPS.',
        );
      }
      final auth = _text(primary['authenticationType']);
      if (auth == '0' || auth == '4') {
        throw RouterFeatureUnavailable(
          auth == '4'
              ? 'The stock router disables WPS while WPA3-PSK is selected.'
              : 'WPS cannot be enabled on an open Wi-Fi network.',
        );
      }
    }

    final before = await client.command(
      132,
      authenticated: true,
      fields: {'subcmd': subcmd},
    );
    final original = _text(before[key]) == '1';

    try {
      await client.writeExact(
        132,
        {
          key: enabled ? '1' : '0',
          'subcmd': int.parse(subcmd),
        },
      );
      final readback = await client.command(
        132,
        authenticated: true,
        fields: {'subcmd': subcmd},
      );
      if ((_text(readback[key]) == '1') != enabled) {
        throw RouterFeatureUnavailable(
          'The router did not confirm the WPS change.',
        );
      }
    } catch (error) {
      try {
        await client.writeExact(
          132,
          {
            key: original ? '1' : '0',
            'subcmd': int.parse(subcmd),
          },
        );
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<WifiUpdateResult> setWifiOptimization(bool enabled) async {
    await _ensureLogin();
    final current24 = await client.command(
      2,
      authenticated: true,
      fields: const {'subcmd': 0},
    );
    final current5 = await client.command(
      211,
      authenticated: true,
      fields: const {'subcmd': 0},
    );

    if (enabled &&
        (_text(current24['wifiOpen']) != '1' ||
            _text(current5['wifiOpen']) != '1')) {
      throw RouterFeatureUnavailable(
        'Both Wi-Fi bands must be enabled before turning on 5G Optimization.',
      );
    }

    final original = _wifiPrimaryForm(current24);
    final updated = Map<String, dynamic>.from(original)
      ..['wifiSames'] = enabled ? '1' : '0';

    if (_text(original['wifiSames']) == _text(updated['wifiSames'])) {
      return const WifiUpdateResult();
    }

    Object? primaryError;
    try {
      await client.writeExact(
        2,
        {
          ...updated,
          'subcmd': 0,
        },
      );
      if (enabled) {
        return const WifiUpdateResult(reconnectExpected: true);
      }
      final readback = await client.command(
        2,
        authenticated: true,
        fields: const {'subcmd': 0},
      );
      if (_text(readback['wifiSames']) != '0') {
        throw RouterFeatureUnavailable(
          'The router did not confirm that 5G Optimization was disabled.',
        );
      }
      return const WifiUpdateResult();
    } catch (error) {
      primaryError = error;
    }

    try {
      await client.writeExact(
        2,
        {
          ...original,
          'subcmd': 0,
        },
      );
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The 5G Optimization change failed and rollback could not be verified. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }
    throw RouterFeatureUnavailable(
      'The 5G Optimization change was not saved. $primaryError',
    );
  }

  Map<String, dynamic> _wifiRadioForm(
    WifiBand band,
    Map<String, dynamic> raw,
  ) {
    final form = <String, dynamic>{
      'countryCode': raw['countryCode'] ?? '',
      'txPower': raw['txPower'] ?? '',
      'channel': raw['channel'] ?? 'auto',
      'wifi_workMode': raw['wifiWorkMode'] ?? '',
      'wifiWorkMode': raw['wifiWorkMode'] ?? '',
      'bandWidth': raw['bandWidth'] ?? '',
      'maxNum': '${raw['maxNum'] ?? ''}',
      'eliminateNum': raw['eliminateNum'] ?? 0,
      'connectNum': raw['connectNum'] ?? 0,
      'wifiOpen': raw['wifiOpen'] ?? '',
    };
    if (band == WifiBand.fiveGhz) {
      form['dfsSwitch'] = raw['dfsSwitch'] ?? '1';
    }
    return form;
  }

  bool _sameWifiRadioState(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    WifiBand band,
  ) {
    const base = {
      'countryCode',
      'txPower',
      'channel',
      'wifiWorkMode',
      'bandWidth',
      'maxNum',
      'wifiOpen',
    };
    final keys = <String>{...base};
    if (band == WifiBand.fiveGhz) keys.add('dfsSwitch');
    return keys.every((key) => _text(a[key]) == _text(b[key]));
  }

  bool _wifiRadioMatches(
    Map<String, dynamic> readback,
    Map<String, dynamic> expected,
    WifiBand band,
  ) {
    final normalized = _wifiRadioForm(band, readback);
    return _sameWifiRadioState(normalized, expected, band);
  }

  void _validateWifiBandwidth(
    WifiBand band, {
    required String mode,
    required String channel,
    required String bandwidth,
  }) {
    if (band == WifiBand.twoFourGhz) {
      final allowed = {'0', '1', '2'};
      if (!allowed.contains(bandwidth)) {
        throw RouterFeatureUnavailable('Unsupported 2.4 GHz bandwidth.');
      }
      if (const {'0', '1', '3'}.contains(mode) && bandwidth != '0') {
        throw RouterFeatureUnavailable(
          'This 2.4 GHz Wi-Fi mode only supports 20 MHz on the stock router page.',
        );
      }
      return;
    }

    final allowed = {'0', '1', '3'};
    if (!allowed.contains(bandwidth)) {
      throw RouterFeatureUnavailable('Unsupported 5 GHz bandwidth.');
    }
    if ((mode == '7' || channel == '165') && bandwidth != '0') {
      throw RouterFeatureUnavailable(
        'This 5 GHz mode/channel only supports 20 MHz.',
      );
    }
    if (const {'8', '10'}.contains(mode) && bandwidth == '3') {
      throw RouterFeatureUnavailable(
        'This 5 GHz Wi-Fi mode does not expose 80 MHz on the stock router page.',
      );
    }
  }

  String _formatWifiNumber(double value) {
    return value == value.roundToDouble()
        ? '${value.toInt()}'
        : '$value';
  }

  Future<WifiBand?> _localWifiBand() async {
    final localIp = await _localLanIp();
    if (localIp == null || localIp.isEmpty) return null;

    final responses = await Future.wait<Map<String, dynamic>>([
      _safeCommand(224),
      _safeCommand(225),
    ]);
    final candidates = <(WifiBand, dynamic)>[
      (WifiBand.twoFourGhz, responses[0]['wlan24g_wifi_info']),
      (WifiBand.fiveGhz, responses[1]['wlan5g_wifi_info']),
    ];

    for (final candidate in candidates) {
      final rows = candidate.$2;
      if (rows is! List) continue;
      for (final row in rows) {
        if (row is! Map) continue;
        if (_text(row['ip']) == localIp) return candidate.$1;
      }
    }
    return null;
  }

  Map<String, dynamic> _wifiPrimaryForm(Map<String, dynamic> raw) {
    const keys = [
      'wifiSames',
      'wifiOpen',
      'broadcast',
      'wifiwmm',
      'ssid',
      'authenticationType',
      'key',
    ];
    return {for (final key in keys) key: raw[key] ?? ''};
  }

  bool _wifiPrimaryMatches(
    Map<String, dynamic> readback,
    Map<String, dynamic> expected, {
    required bool checkKey,
  }) {
    const keys = [
      'wifiSames',
      'wifiOpen',
      'broadcast',
      'wifiwmm',
      'ssid',
      'authenticationType',
    ];
    for (final key in keys) {
      if (_text(readback[key]) != _text(expected[key])) return false;
    }
    if (checkKey && _text(readback['key']) != _text(expected['key'])) {
      return false;
    }
    return true;
  }

  String _decodeWifiSsid(String value) {
    if (value.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(value));
    } catch (_) {
      return value;
    }
  }
  @override
  Future<RouterSmsPage> fetchSmsInbox({int page = 1}) async {
    await _ensureLogin();
    if (page < 1) page = 1;

    final results = await Future.wait<Map<String, dynamic>>([
      client.command(
        12,
        authenticated: true,
        fields: {'page_num': page, 'subcmd': 0},
      ),
      _safeCommand(16),
    ]);
    final raw = results[0];
    final settings = results[1];
    final messages = <RouterSmsMessage>[];
    final encodedList = _text(raw['sms_list']);

    if (encodedList.isNotEmpty) {
      for (final encoded in encodedList.split(',')) {
        final decoded = _decodeSmsValue(encoded);
        if (decoded.isEmpty) continue;
        final parts = decoded.split(' ');
        if (parts.length < 6) continue;
        final index = int.tryParse(parts[0]);
        if (index == null) continue;
        messages.add(
          RouterSmsMessage(
            index: index,
            unread: parts[1] == '0',
            phoneNumber: parts[2].replaceAll(r'
    final report = await _ensureDiscovery();
    return RouterCapabilities(
      signal: report.supportsCommand(133),
      stationList: report.hasStationList,
      blocking: report.canBlock,
      scheduling: report.canSchedule,
      sms: report.supportsCommand(12) && report.supportsCommand(16),
      ussd: report.supportsCommand(207),
      wifiSettings: report.supportsCommand(2) && report.supportsCommand(211),
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
        'Instant Block / Unblock is staged but still locked until the direct Wi-Fi blacklist write path passes its reversible live-router verification.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    if (blocked) {
      final targetIp = await _currentIpForMacOrNull(mac);
      final localIp = await _localLanIp();
      if (targetIp != null && localIp != null && targetIp == localIp) {
        throw RouterFeatureUnavailable(
          'FlyX Control will not block the phone currently being used to manage the router.',
        );
      }
    }

    final originals = <String, Map<String, dynamic>>{};
    final updated = <String, Map<String, dynamic>>{};

    for (final subcmd in const ['0', '1']) {
      final state = await _wirelessFilterState(subcmd);
      originals[subcmd] = _deepMapCopy(state);

      final mode = _text(state['macfilter']);
      if (mode == 'allow') {
        throw RouterFeatureUnavailable(
          'This router is using Wi-Fi whitelist mode. FlyX Control will not change that policy automatically.',
        );
      }

      final rows = <Map<String, dynamic>>[
        for (final row in state['maclist'] as List)
          if (row is Map)
            row.map((key, value) => MapEntry('$key', value)),
      ]..removeWhere(
          (row) => _normaliseMac(_text(row['mac'])) == mac,
        );

      if (blocked) {
        if (rows.length >= 32) {
          throw RouterFeatureUnavailable(
            'This Wi-Fi blacklist already contains the maximum supported number of entries.',
          );
        }
        rows.add({'mac': mac});
      }

      updated[subcmd] = <String, dynamic>{
        ...state,
        'macfilter': blocked
            ? 'deny'
            : rows.isEmpty && mode == 'deny'
                ? 'close'
                : mode,
        'maclist': rows,
      };
    }

    Object? primaryError;
    try {
      for (final subcmd in const ['0', '1']) {
        await client.saveWirelessMacFilter(subcmd, updated[subcmd]!);
      }

      for (final subcmd in const ['0', '1']) {
        final readback = await _wirelessFilterState(subcmd);
        final rows = readback['maclist'] as List;
        final present = rows.any(
          (row) =>
              row is Map &&
              _normaliseMac(_text(row['mac'])) == mac,
        );

        if (blocked) {
          if (_text(readback['macfilter']) != 'deny' || !present) {
            throw RouterFeatureUnavailable(
              'The router did not confirm the block on both Wi-Fi bands.',
            );
          }
        } else if (present) {
          throw RouterFeatureUnavailable(
            'The router still reports this device in a Wi-Fi MAC-filter list.',
          );
        }
      }

      await _refreshBlocked();
      return;
    } catch (error) {
      primaryError = error;
    }

    try {
      for (final subcmd in const ['0', '1']) {
        await client.saveWirelessMacFilter(subcmd, originals[subcmd]!);
      }
      for (final subcmd in const ['0', '1']) {
        final restored = await _wirelessFilterState(subcmd);
        if (!_sameJson(restored, originals[subcmd]!)) {
          throw RouterFeatureUnavailable(
            'The router did not confirm an exact Wi-Fi filter rollback.',
          );
        }
      }
      await _refreshBlocked();
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The block change failed and automatic rollback could not be verified. Check Wi-Fi Black/White List in the MTN interface before another block attempt. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The block change was not saved. The previous Wi-Fi filter state was restored. $primaryError',
    );
  }

  Future<String?> _currentIpForMacOrNull(String mac) async {
    final response = await client.command(223, authenticated: true);
    final rows = response['dhcp_list_info'];
    if (rows is! List) return null;
    for (final row in rows) {
      if (row is! Map) continue;
      if (_normaliseMac(_text(row['mac'])) != mac) continue;
      final ip = _text(row['ip']);
      return ip.isEmpty ? null : ip;
    }
    return null;
  }

  Future<String?> _localLanIp() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        client.host,
        80,
        timeout: const Duration(seconds: 2),
      );
      return socket.address.address;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Map<String, dynamic> _deepMapCopy(Map<String, dynamic> value) {
    return (jsonDecode(jsonEncode(value)) as Map).map(
      (key, item) => MapEntry('$key', item),
    );
  }

  bool _sameJson(dynamic a, dynamic b) {
    return jsonEncode(_stableJson(a)) == jsonEncode(_stableJson(b));
  }

  @override
  Future<void> setDeviceName(String deviceId, String name) async {
    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    final trimmed = name.trim();
    if (trimmed.length > 48 || trimmed.contains('\n') || trimmed.contains('\r')) {
      throw RouterFeatureUnavailable(
        'Device names must be 48 characters or fewer and use a single line.',
      );
    }

    await deviceStore.setFriendlyName(
      mac,
      trimmed.isEmpty ? null : trimmed,
    );
  }

  @override
  Future<void> setDevicePolicy(String deviceId, DevicePolicy policy) async {
    throw RouterFeatureUnavailable(
      'Quota storage is ready, but automatic enforcement needs verified per-device accounting and a safe block path.',
    );
  }

  @override
  Future<void> setParentControlSchedule(
    String deviceId,
    ParentControlSchedule schedule,
  ) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.canSchedule) {
      throw RouterFeatureUnavailable(
        'Parent Control is not readable on this router yet, so FlyX Control will not replace its rule list.',
      );
    }
    _validateSchedule(schedule);

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }
    final ip = await _currentIpForMac(mac);
    final original = await client.readParentControlRules();
    final updated = original
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();

    final matching = <int>[];
    for (var i = 0; i < updated.length; i++) {
      if (_text(updated[i]['ip']) == ip) matching.add(i);
    }
    if (matching.length > 1) {
      throw RouterFeatureUnavailable(
        'The router returned more than one Parent Control rule for this device IP. FlyX Control will not guess which one to replace.',
      );
    }

    final rule = matching.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(updated[matching.single]);
    rule
      ..['enableRule'] = schedule.enabled
      ..['ip'] = ip
      ..['startTime'] = schedule.startTime
      ..['endTime'] = schedule.endTime
      ..['scheduleDays'] = _serializeScheduleDays(schedule.days);

    if (matching.isEmpty) {
      updated.add(rule);
    } else {
      updated[matching.single] = rule;
    }

    await _saveParentRulesSafely(
      original: original,
      updated: updated,
      verify: (readback) {
        for (final item in readback) {
          if (_text(item['ip']) != ip) continue;
          final enabled = item['enableRule'] == true ||
              _text(item['enableRule']).toLowerCase() == 'true' ||
              _text(item['enableRule']) == '1';
          return enabled == schedule.enabled &&
              _text(item['startTime']) == schedule.startTime &&
              _text(item['endTime']) == schedule.endTime &&
              _text(item['scheduleDays']) ==
                  _serializeScheduleDays(schedule.days);
        }
        return false;
      },
    );
  }

  @override
  Future<void> deleteParentControlSchedule(String deviceId) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.canSchedule) {
      throw RouterFeatureUnavailable(
        'Parent Control is not readable on this router yet.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }
    final ip = await _currentIpForMac(mac);
    final original = await client.readParentControlRules();
    final updated = original
        .where((rule) => _text(rule['ip']) != ip)
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();

    if (updated.length == original.length) {
      _parentRules = original;
      return;
    }

    await _saveParentRulesSafely(
      original: original,
      updated: updated,
      deletion: true,
      verify: (readback) =>
          !readback.any((rule) => _text(rule['ip']) == ip),
    );
  }

  Future<String> _currentIpForMac(String mac) async {
    final response = await client.command(223, authenticated: true);
    final rows = response['dhcp_list_info'];
    if (rows is! List) {
      throw RouterFeatureUnavailable(
        'The router did not return the connected-device list.',
      );
    }
    for (final row in rows) {
      if (row is! Map) continue;
      final normalized = row.map((key, value) => MapEntry('$key', value));
      if (_normaliseMac(_text(normalized['mac'])) != mac) continue;
      final ip = _text(normalized['ip']);
      if (ip.isNotEmpty) return ip;
    }
    throw RouterFeatureUnavailable(
      'This device is not currently connected. Because MTN Parent Control rules are IP-based, reconnect it before changing its schedule.',
    );
  }

  Future<void> _saveParentRulesSafely({
    required List<Map<String, dynamic>> original,
    required List<Map<String, dynamic>> updated,
    required bool Function(List<Map<String, dynamic>>) verify,
    bool deletion = false,
  }) async {
    Object? primaryError;
    try {
      await client.saveParentControlRules(updated, deletion: deletion);
      final readback = await client.readParentControlRules();
      if (!verify(readback)) {
        throw RouterFeatureUnavailable(
          'The router did not return the expected Parent Control state after saving.',
        );
      }
      _parentRules = readback;
      return;
    } catch (error) {
      primaryError = error;
    }

    try {
      await client.saveParentControlRules(original, deletion: true);
      final restored = await client.readParentControlRules();
      _parentRules = restored;
      if (!_sameParentRules(restored, original)) {
        throw RouterFeatureUnavailable(
          'The schedule write failed and the router did not confirm an exact rollback.',
        );
      }
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The schedule write failed and automatic rollback could not be verified. Open the MTN Parent Control page before making another change. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The schedule change was not saved. The previous Parent Control rules were restored. $primaryError',
    );
  }

  bool _sameParentRules(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    return jsonEncode(_stableJson(a)) == jsonEncode(_stableJson(b));
  }

  dynamic _stableJson(dynamic value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return {
        for (final entry in entries)
          '${entry.key}': _stableJson(entry.value),
      };
    }
    if (value is List) {
      return value.map(_stableJson).toList(growable: false);
    }
    return value;
  }

  void _validateSchedule(ParentControlSchedule schedule) {
    if (schedule.days.isEmpty ||
        schedule.days.any((day) => day < 0 || day > 6)) {
      throw RouterFeatureUnavailable('Choose at least one valid day.');
    }
    final start = _timeMinutes(schedule.startTime);
    final end = _timeMinutes(schedule.endTime);
    if (start == null || end == null || end <= start) {
      throw RouterFeatureUnavailable(
        'Choose a valid schedule where the end time is later than the start time.',
      );
    }
  }

  Set<int> _parseScheduleDays(dynamic value) {
    return _text(value)
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .where((day) => day >= 0 && day <= 6)
        .toSet();
  }

  String _serializeScheduleDays(Set<int> days) {
    final ordered = days.toList()..sort();
    return ordered.join(',');
  }

  int? _timeMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 24 || minute < 0 || minute > 59) return null;
    if (hour == 24 && minute != 0) return null;
    return hour * 60 + minute;
  }

  @override
  Future<List<UsagePoint>> fetchWeeklyUsage() => usageStore.lastSevenDays();

  @override
  Future<void> reboot() async {
    throw RouterFeatureUnavailable(
      'Reboot is intentionally disabled until its X17U write command is verified on this firmware.',
    );
  }

  DeviceKind _inferKind(String hostname) {
    final value = hostname.toLowerCase();
    if (RegExp(r'pixel|iphone|galaxy|android|redmi|xiaomi|oppo|vivo|realme|oneplus|tecno|infinix').hasMatch(value)) {
      return DeviceKind.phone;
    }
    if (RegExp(r'ipad|tablet|tab').hasMatch(value)) return DeviceKind.tablet;
    if (RegExp(r'macbook|laptop|thinkpad|desktop|surface|lenovo|dell|acer|asus|hp-').hasMatch(value)) {
      return DeviceKind.laptop;
    }
    if (RegExp(r'tv|bravia|webos|tizen|chromecast|firetv|roku').hasMatch(value)) {
      return DeviceKind.tv;
    }
    if (RegExp(r'playstation|ps5|ps4|xbox|nintendo|switch').hasMatch(value)) {
      return DeviceKind.console;
    }
    return DeviceKind.unknown;
  }

  int _wifiSignalPercent(int rssi) {
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 2).clamp(0, 100).toInt();
  }

  DateTime? _dateFromEpoch(dynamic value) {
    final seconds = int.tryParse(_text(value));
    if (seconds == null || seconds <= 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    } catch (_) {
      return null;
    }
  }

  double _number(dynamic value, [double fallback = 0]) {
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? fallback;
  }

  double? _nullableNumber(dynamic value) {
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double? _positiveNumber(dynamic value) {
    final number = _nullableNumber(value);
    if (number == null || number <= 0) return null;
    return number;
  }

  int? _kilobytesToBytes(dynamic value) {
    final kb = _nullableNumber(value);
    if (kb == null || kb < 0) return null;
    return (kb * 1024).round();
  }

  int _int(dynamic value, [int fallback = 0]) {
    return _number(value, fallback.toDouble()).round();
  }

  int? _nullableInt(dynamic value) {
    final number = _nullableNumber(value);
    return number?.round();
  }

  int _firstInt(dynamic value, [int fallback = 0]) {
    final text = _text(value);
    if (text.isEmpty) return fallback;
    final first = RegExp(r'-?\d+').firstMatch(text)?.group(0);
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
, ' '),
            date: '${parts[3]} ${parts[4]}',
            text: parts.sublist(5).join(' '),
          ),
        );
      }
    }

    return RouterSmsPage(
      messages: messages,
      total: _int(raw['sms_total'], messages.length),
      page: page,
      sendFull: _text(raw['send_full']) == '1',
      receiveFull: _text(raw['receive_full']) == '1',
      flashFull: _text(raw['sms_flash_full']) == '1',
      maxLength: _int(settings['maxLen'], 160),
    );
  }

  @override
  Future<void> sendSms(String phoneNumber, String content) async {
    await _ensureLogin();
    final phone = phoneNumber.trim();
    final message = content.trim();
    if (phone.isEmpty) {
      throw RouterFeatureUnavailable('Enter a phone number.');
    }
    if (message.isEmpty) {
      throw RouterFeatureUnavailable('Enter a message.');
    }
    if (message.runes.any((rune) => rune > 0xffff)) {
      throw RouterFeatureUnavailable(
        'The MTN router SMS interface does not support emoji characters.',
      );
    }

    final settings = await _safeCommand(16);
    if (_text(settings['smsSw']) == '0') {
      throw RouterFeatureUnavailable(
        'SMS is disabled in the router settings. Enable the router SMS function first.',
      );
    }
    final maxLength = _int(settings['maxLen'], 160);
    if (message.length > maxLength) {
      throw RouterFeatureUnavailable(
        'This router allows up to $maxLength characters per message.',
      );
    }

    await client.writeExact(
      13,
      {
        'phoneNo': phone,
        'content': base64Encode(utf8.encode(message)),
      },
    );
  }

  @override
  Future<void> markSmsRead(int index) async {
    await _ensureLogin();
    await client.writeExact(12, {'index': index});
  }

  @override
  Future<void> deleteSms(List<int> indexes) async {
    await _ensureLogin();
    if (indexes.isEmpty) return;
    await client.writeExact(
      14,
      {
        'index': indexes.join(','),
        'subcmd': 0,
      },
    );
  }

  @override
  Future<UssdResult> sendUssd(String code) async {
    await _ensureLogin();
    final value = code.trim();
    if (value.isEmpty || !RegExp(r'^[0-9*#]+
    final report = await _ensureDiscovery();
    return RouterCapabilities(
      signal: report.supportsCommand(133),
      stationList: report.hasStationList,
      blocking: report.canBlock,
      scheduling: report.canSchedule,
      sms: false,
      ussd: false,
      wifiSettings: report.supportsCommand(2) && report.supportsCommand(211),
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
        'Instant Block / Unblock is staged but still locked until the direct Wi-Fi blacklist write path passes its reversible live-router verification.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    if (blocked) {
      final targetIp = await _currentIpForMacOrNull(mac);
      final localIp = await _localLanIp();
      if (targetIp != null && localIp != null && targetIp == localIp) {
        throw RouterFeatureUnavailable(
          'FlyX Control will not block the phone currently being used to manage the router.',
        );
      }
    }

    final originals = <String, Map<String, dynamic>>{};
    final updated = <String, Map<String, dynamic>>{};

    for (final subcmd in const ['0', '1']) {
      final state = await _wirelessFilterState(subcmd);
      originals[subcmd] = _deepMapCopy(state);

      final mode = _text(state['macfilter']);
      if (mode == 'allow') {
        throw RouterFeatureUnavailable(
          'This router is using Wi-Fi whitelist mode. FlyX Control will not change that policy automatically.',
        );
      }

      final rows = <Map<String, dynamic>>[
        for (final row in state['maclist'] as List)
          if (row is Map)
            row.map((key, value) => MapEntry('$key', value)),
      ]..removeWhere(
          (row) => _normaliseMac(_text(row['mac'])) == mac,
        );

      if (blocked) {
        if (rows.length >= 32) {
          throw RouterFeatureUnavailable(
            'This Wi-Fi blacklist already contains the maximum supported number of entries.',
          );
        }
        rows.add({'mac': mac});
      }

      updated[subcmd] = <String, dynamic>{
        ...state,
        'macfilter': blocked
            ? 'deny'
            : rows.isEmpty && mode == 'deny'
                ? 'close'
                : mode,
        'maclist': rows,
      };
    }

    Object? primaryError;
    try {
      for (final subcmd in const ['0', '1']) {
        await client.saveWirelessMacFilter(subcmd, updated[subcmd]!);
      }

      for (final subcmd in const ['0', '1']) {
        final readback = await _wirelessFilterState(subcmd);
        final rows = readback['maclist'] as List;
        final present = rows.any(
          (row) =>
              row is Map &&
              _normaliseMac(_text(row['mac'])) == mac,
        );

        if (blocked) {
          if (_text(readback['macfilter']) != 'deny' || !present) {
            throw RouterFeatureUnavailable(
              'The router did not confirm the block on both Wi-Fi bands.',
            );
          }
        } else if (present) {
          throw RouterFeatureUnavailable(
            'The router still reports this device in a Wi-Fi MAC-filter list.',
          );
        }
      }

      await _refreshBlocked();
      return;
    } catch (error) {
      primaryError = error;
    }

    try {
      for (final subcmd in const ['0', '1']) {
        await client.saveWirelessMacFilter(subcmd, originals[subcmd]!);
      }
      for (final subcmd in const ['0', '1']) {
        final restored = await _wirelessFilterState(subcmd);
        if (!_sameJson(restored, originals[subcmd]!)) {
          throw RouterFeatureUnavailable(
            'The router did not confirm an exact Wi-Fi filter rollback.',
          );
        }
      }
      await _refreshBlocked();
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The block change failed and automatic rollback could not be verified. Check Wi-Fi Black/White List in the MTN interface before another block attempt. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The block change was not saved. The previous Wi-Fi filter state was restored. $primaryError',
    );
  }

  Future<String?> _currentIpForMacOrNull(String mac) async {
    final response = await client.command(223, authenticated: true);
    final rows = response['dhcp_list_info'];
    if (rows is! List) return null;
    for (final row in rows) {
      if (row is! Map) continue;
      if (_normaliseMac(_text(row['mac'])) != mac) continue;
      final ip = _text(row['ip']);
      return ip.isEmpty ? null : ip;
    }
    return null;
  }

  Future<String?> _localLanIp() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        client.host,
        80,
        timeout: const Duration(seconds: 2),
      );
      return socket.address.address;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Map<String, dynamic> _deepMapCopy(Map<String, dynamic> value) {
    return (jsonDecode(jsonEncode(value)) as Map).map(
      (key, item) => MapEntry('$key', item),
    );
  }

  bool _sameJson(dynamic a, dynamic b) {
    return jsonEncode(_stableJson(a)) == jsonEncode(_stableJson(b));
  }

  @override
  Future<void> setDeviceName(String deviceId, String name) async {
    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    final trimmed = name.trim();
    if (trimmed.length > 48 || trimmed.contains('\n') || trimmed.contains('\r')) {
      throw RouterFeatureUnavailable(
        'Device names must be 48 characters or fewer and use a single line.',
      );
    }

    await deviceStore.setFriendlyName(
      mac,
      trimmed.isEmpty ? null : trimmed,
    );
  }

  @override
  Future<void> setDevicePolicy(String deviceId, DevicePolicy policy) async {
    throw RouterFeatureUnavailable(
      'Quota storage is ready, but automatic enforcement needs verified per-device accounting and a safe block path.',
    );
  }

  @override
  Future<void> setParentControlSchedule(
    String deviceId,
    ParentControlSchedule schedule,
  ) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.canSchedule) {
      throw RouterFeatureUnavailable(
        'Parent Control is not readable on this router yet, so FlyX Control will not replace its rule list.',
      );
    }
    _validateSchedule(schedule);

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }
    final ip = await _currentIpForMac(mac);
    final original = await client.readParentControlRules();
    final updated = original
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();

    final matching = <int>[];
    for (var i = 0; i < updated.length; i++) {
      if (_text(updated[i]['ip']) == ip) matching.add(i);
    }
    if (matching.length > 1) {
      throw RouterFeatureUnavailable(
        'The router returned more than one Parent Control rule for this device IP. FlyX Control will not guess which one to replace.',
      );
    }

    final rule = matching.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(updated[matching.single]);
    rule
      ..['enableRule'] = schedule.enabled
      ..['ip'] = ip
      ..['startTime'] = schedule.startTime
      ..['endTime'] = schedule.endTime
      ..['scheduleDays'] = _serializeScheduleDays(schedule.days);

    if (matching.isEmpty) {
      updated.add(rule);
    } else {
      updated[matching.single] = rule;
    }

    await _saveParentRulesSafely(
      original: original,
      updated: updated,
      verify: (readback) {
        for (final item in readback) {
          if (_text(item['ip']) != ip) continue;
          final enabled = item['enableRule'] == true ||
              _text(item['enableRule']).toLowerCase() == 'true' ||
              _text(item['enableRule']) == '1';
          return enabled == schedule.enabled &&
              _text(item['startTime']) == schedule.startTime &&
              _text(item['endTime']) == schedule.endTime &&
              _text(item['scheduleDays']) ==
                  _serializeScheduleDays(schedule.days);
        }
        return false;
      },
    );
  }

  @override
  Future<void> deleteParentControlSchedule(String deviceId) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.canSchedule) {
      throw RouterFeatureUnavailable(
        'Parent Control is not readable on this router yet.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }
    final ip = await _currentIpForMac(mac);
    final original = await client.readParentControlRules();
    final updated = original
        .where((rule) => _text(rule['ip']) != ip)
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();

    if (updated.length == original.length) {
      _parentRules = original;
      return;
    }

    await _saveParentRulesSafely(
      original: original,
      updated: updated,
      deletion: true,
      verify: (readback) =>
          !readback.any((rule) => _text(rule['ip']) == ip),
    );
  }

  Future<String> _currentIpForMac(String mac) async {
    final response = await client.command(223, authenticated: true);
    final rows = response['dhcp_list_info'];
    if (rows is! List) {
      throw RouterFeatureUnavailable(
        'The router did not return the connected-device list.',
      );
    }
    for (final row in rows) {
      if (row is! Map) continue;
      final normalized = row.map((key, value) => MapEntry('$key', value));
      if (_normaliseMac(_text(normalized['mac'])) != mac) continue;
      final ip = _text(normalized['ip']);
      if (ip.isNotEmpty) return ip;
    }
    throw RouterFeatureUnavailable(
      'This device is not currently connected. Because MTN Parent Control rules are IP-based, reconnect it before changing its schedule.',
    );
  }

  Future<void> _saveParentRulesSafely({
    required List<Map<String, dynamic>> original,
    required List<Map<String, dynamic>> updated,
    required bool Function(List<Map<String, dynamic>>) verify,
    bool deletion = false,
  }) async {
    Object? primaryError;
    try {
      await client.saveParentControlRules(updated, deletion: deletion);
      final readback = await client.readParentControlRules();
      if (!verify(readback)) {
        throw RouterFeatureUnavailable(
          'The router did not return the expected Parent Control state after saving.',
        );
      }
      _parentRules = readback;
      return;
    } catch (error) {
      primaryError = error;
    }

    try {
      await client.saveParentControlRules(original, deletion: true);
      final restored = await client.readParentControlRules();
      _parentRules = restored;
      if (!_sameParentRules(restored, original)) {
        throw RouterFeatureUnavailable(
          'The schedule write failed and the router did not confirm an exact rollback.',
        );
      }
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The schedule write failed and automatic rollback could not be verified. Open the MTN Parent Control page before making another change. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The schedule change was not saved. The previous Parent Control rules were restored. $primaryError',
    );
  }

  bool _sameParentRules(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    return jsonEncode(_stableJson(a)) == jsonEncode(_stableJson(b));
  }

  dynamic _stableJson(dynamic value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return {
        for (final entry in entries)
          '${entry.key}': _stableJson(entry.value),
      };
    }
    if (value is List) {
      return value.map(_stableJson).toList(growable: false);
    }
    return value;
  }

  void _validateSchedule(ParentControlSchedule schedule) {
    if (schedule.days.isEmpty ||
        schedule.days.any((day) => day < 0 || day > 6)) {
      throw RouterFeatureUnavailable('Choose at least one valid day.');
    }
    final start = _timeMinutes(schedule.startTime);
    final end = _timeMinutes(schedule.endTime);
    if (start == null || end == null || end <= start) {
      throw RouterFeatureUnavailable(
        'Choose a valid schedule where the end time is later than the start time.',
      );
    }
  }

  Set<int> _parseScheduleDays(dynamic value) {
    return _text(value)
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .where((day) => day >= 0 && day <= 6)
        .toSet();
  }

  String _serializeScheduleDays(Set<int> days) {
    final ordered = days.toList()..sort();
    return ordered.join(',');
  }

  int? _timeMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 24 || minute < 0 || minute > 59) return null;
    if (hour == 24 && minute != 0) return null;
    return hour * 60 + minute;
  }

  @override
  Future<List<UsagePoint>> fetchWeeklyUsage() => usageStore.lastSevenDays();

  @override
  Future<void> reboot() async {
    throw RouterFeatureUnavailable(
      'Reboot is intentionally disabled until its X17U write command is verified on this firmware.',
    );
  }

  DeviceKind _inferKind(String hostname) {
    final value = hostname.toLowerCase();
    if (RegExp(r'pixel|iphone|galaxy|android|redmi|xiaomi|oppo|vivo|realme|oneplus|tecno|infinix').hasMatch(value)) {
      return DeviceKind.phone;
    }
    if (RegExp(r'ipad|tablet|tab').hasMatch(value)) return DeviceKind.tablet;
    if (RegExp(r'macbook|laptop|thinkpad|desktop|surface|lenovo|dell|acer|asus|hp-').hasMatch(value)) {
      return DeviceKind.laptop;
    }
    if (RegExp(r'tv|bravia|webos|tizen|chromecast|firetv|roku').hasMatch(value)) {
      return DeviceKind.tv;
    }
    if (RegExp(r'playstation|ps5|ps4|xbox|nintendo|switch').hasMatch(value)) {
      return DeviceKind.console;
    }
    return DeviceKind.unknown;
  }

  int _wifiSignalPercent(int rssi) {
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 2).clamp(0, 100).toInt();
  }

  DateTime? _dateFromEpoch(dynamic value) {
    final seconds = int.tryParse(_text(value));
    if (seconds == null || seconds <= 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    } catch (_) {
      return null;
    }
  }

  double _number(dynamic value, [double fallback = 0]) {
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? fallback;
  }

  double? _nullableNumber(dynamic value) {
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double? _positiveNumber(dynamic value) {
    final number = _nullableNumber(value);
    if (number == null || number <= 0) return null;
    return number;
  }

  int? _kilobytesToBytes(dynamic value) {
    final kb = _nullableNumber(value);
    if (kb == null || kb < 0) return null;
    return (kb * 1024).round();
  }

  int _int(dynamic value, [int fallback = 0]) {
    return _number(value, fallback.toDouble()).round();
  }

  int? _nullableInt(dynamic value) {
    final number = _nullableNumber(value);
    return number?.round();
  }

  int _firstInt(dynamic value, [int fallback = 0]) {
    final text = _text(value);
    if (text.isEmpty) return fallback;
    final first = RegExp(r'-?\d+').firstMatch(text)?.group(0);
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
).hasMatch(value)) {
      throw RouterFeatureUnavailable(
        'Enter a valid USSD code or reply using digits, * and #.',
      );
    }
    if (value.length > 99) {
      throw RouterFeatureUnavailable('USSD input cannot exceed 99 characters.');
    }

    final answer = await client.writeExact(
      561,
      {
        'subcmd': '0',
        'ussd_code': value,
      },
      receiveTimeout: const Duration(seconds: 17),
      validateMessage: false,
    );

    final ret = _text(answer['ret']);
    if (ret.isNotEmpty && ret != '0') {
      const errors = {
        '500': 'An error occurred.',
        '503': 'Invalid USSD parameter.',
        '504': 'The current network state does not support this operation.',
        '505': 'Invalid PIN or PUK.',
        '507': 'The USSD operation timed out.',
      };
      throw RouterFeatureUnavailable(errors[ret] ?? 'USSD was not supported by the network.');
    }

    final status = _text(answer['ussd_st']);
    if (status.isNotEmpty && !const {'0', '1', '2'}.contains(status)) {
      const statusErrors = {
        '3': 'Another local client already responded to this USSD session.',
        '4': 'This USSD operation is not supported.',
        '5': 'The USSD network request timed out.',
      };
      throw RouterFeatureUnavailable(
        statusErrors[status] ?? 'The network returned an unknown USSD state.',
      );
    }

    final message = _decodeUssdHex(_text(answer['message']));
    return UssdResult(
      message: message.isEmpty && status != '1'
          ? 'USSD session ended.'
          : message,
      needsReply: status == '1',
      status: status,
    );
  }

  @override
  Future<void> cancelUssd() async {
    await _ensureLogin();
    await client.writeExact(
      561,
      const {'subcmd': '1'},
      receiveTimeout: const Duration(seconds: 17),
      validateMessage: false,
    );
  }

  String _decodeSmsValue(String value) {
    if (value.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(value), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  String _decodeUssdHex(String value) {
    if (value.isEmpty) return '';
    final buffer = StringBuffer();
    final chunks = RegExp(r'[A-Fa-f0-9]{1,4}').allMatches(value);
    for (final match in chunks) {
      final part = match.group(0)!;
      if (part == '0009' || part == '0000') continue;
      final code = int.tryParse(part, radix: 16);
      if (code != null) buffer.write(String.fromCharCode(code));
    }
    return buffer.toString();
  }

  @override
  Future<RouterCapabilities> capabilities() async {
    final report = await _ensureDiscovery();
    return RouterCapabilities(
      signal: report.supportsCommand(133),
      stationList: report.hasStationList,
      blocking: report.canBlock,
      scheduling: report.canSchedule,
      sms: false,
      ussd: false,
      wifiSettings: report.supportsCommand(2) && report.supportsCommand(211),
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
        'Instant Block / Unblock is staged but still locked until the direct Wi-Fi blacklist write path passes its reversible live-router verification.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    if (blocked) {
      final targetIp = await _currentIpForMacOrNull(mac);
      final localIp = await _localLanIp();
      if (targetIp != null && localIp != null && targetIp == localIp) {
        throw RouterFeatureUnavailable(
          'FlyX Control will not block the phone currently being used to manage the router.',
        );
      }
    }

    final originals = <String, Map<String, dynamic>>{};
    final updated = <String, Map<String, dynamic>>{};

    for (final subcmd in const ['0', '1']) {
      final state = await _wirelessFilterState(subcmd);
      originals[subcmd] = _deepMapCopy(state);

      final mode = _text(state['macfilter']);
      if (mode == 'allow') {
        throw RouterFeatureUnavailable(
          'This router is using Wi-Fi whitelist mode. FlyX Control will not change that policy automatically.',
        );
      }

      final rows = <Map<String, dynamic>>[
        for (final row in state['maclist'] as List)
          if (row is Map)
            row.map((key, value) => MapEntry('$key', value)),
      ]..removeWhere(
          (row) => _normaliseMac(_text(row['mac'])) == mac,
        );

      if (blocked) {
        if (rows.length >= 32) {
          throw RouterFeatureUnavailable(
            'This Wi-Fi blacklist already contains the maximum supported number of entries.',
          );
        }
        rows.add({'mac': mac});
      }

      updated[subcmd] = <String, dynamic>{
        ...state,
        'macfilter': blocked
            ? 'deny'
            : rows.isEmpty && mode == 'deny'
                ? 'close'
                : mode,
        'maclist': rows,
      };
    }

    Object? primaryError;
    try {
      for (final subcmd in const ['0', '1']) {
        await client.saveWirelessMacFilter(subcmd, updated[subcmd]!);
      }

      for (final subcmd in const ['0', '1']) {
        final readback = await _wirelessFilterState(subcmd);
        final rows = readback['maclist'] as List;
        final present = rows.any(
          (row) =>
              row is Map &&
              _normaliseMac(_text(row['mac'])) == mac,
        );

        if (blocked) {
          if (_text(readback['macfilter']) != 'deny' || !present) {
            throw RouterFeatureUnavailable(
              'The router did not confirm the block on both Wi-Fi bands.',
            );
          }
        } else if (present) {
          throw RouterFeatureUnavailable(
            'The router still reports this device in a Wi-Fi MAC-filter list.',
          );
        }
      }

      await _refreshBlocked();
      return;
    } catch (error) {
      primaryError = error;
    }

    try {
      for (final subcmd in const ['0', '1']) {
        await client.saveWirelessMacFilter(subcmd, originals[subcmd]!);
      }
      for (final subcmd in const ['0', '1']) {
        final restored = await _wirelessFilterState(subcmd);
        if (!_sameJson(restored, originals[subcmd]!)) {
          throw RouterFeatureUnavailable(
            'The router did not confirm an exact Wi-Fi filter rollback.',
          );
        }
      }
      await _refreshBlocked();
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The block change failed and automatic rollback could not be verified. Check Wi-Fi Black/White List in the MTN interface before another block attempt. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The block change was not saved. The previous Wi-Fi filter state was restored. $primaryError',
    );
  }

  Future<String?> _currentIpForMacOrNull(String mac) async {
    final response = await client.command(223, authenticated: true);
    final rows = response['dhcp_list_info'];
    if (rows is! List) return null;
    for (final row in rows) {
      if (row is! Map) continue;
      if (_normaliseMac(_text(row['mac'])) != mac) continue;
      final ip = _text(row['ip']);
      return ip.isEmpty ? null : ip;
    }
    return null;
  }

  Future<String?> _localLanIp() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        client.host,
        80,
        timeout: const Duration(seconds: 2),
      );
      return socket.address.address;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Map<String, dynamic> _deepMapCopy(Map<String, dynamic> value) {
    return (jsonDecode(jsonEncode(value)) as Map).map(
      (key, item) => MapEntry('$key', item),
    );
  }

  bool _sameJson(dynamic a, dynamic b) {
    return jsonEncode(_stableJson(a)) == jsonEncode(_stableJson(b));
  }

  @override
  Future<void> setDeviceName(String deviceId, String name) async {
    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    final trimmed = name.trim();
    if (trimmed.length > 48 || trimmed.contains('\n') || trimmed.contains('\r')) {
      throw RouterFeatureUnavailable(
        'Device names must be 48 characters or fewer and use a single line.',
      );
    }

    await deviceStore.setFriendlyName(
      mac,
      trimmed.isEmpty ? null : trimmed,
    );
  }

  @override
  Future<void> setDevicePolicy(String deviceId, DevicePolicy policy) async {
    throw RouterFeatureUnavailable(
      'Quota storage is ready, but automatic enforcement needs verified per-device accounting and a safe block path.',
    );
  }

  @override
  Future<void> setParentControlSchedule(
    String deviceId,
    ParentControlSchedule schedule,
  ) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.canSchedule) {
      throw RouterFeatureUnavailable(
        'Parent Control is not readable on this router yet, so FlyX Control will not replace its rule list.',
      );
    }
    _validateSchedule(schedule);

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }
    final ip = await _currentIpForMac(mac);
    final original = await client.readParentControlRules();
    final updated = original
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();

    final matching = <int>[];
    for (var i = 0; i < updated.length; i++) {
      if (_text(updated[i]['ip']) == ip) matching.add(i);
    }
    if (matching.length > 1) {
      throw RouterFeatureUnavailable(
        'The router returned more than one Parent Control rule for this device IP. FlyX Control will not guess which one to replace.',
      );
    }

    final rule = matching.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(updated[matching.single]);
    rule
      ..['enableRule'] = schedule.enabled
      ..['ip'] = ip
      ..['startTime'] = schedule.startTime
      ..['endTime'] = schedule.endTime
      ..['scheduleDays'] = _serializeScheduleDays(schedule.days);

    if (matching.isEmpty) {
      updated.add(rule);
    } else {
      updated[matching.single] = rule;
    }

    await _saveParentRulesSafely(
      original: original,
      updated: updated,
      verify: (readback) {
        for (final item in readback) {
          if (_text(item['ip']) != ip) continue;
          final enabled = item['enableRule'] == true ||
              _text(item['enableRule']).toLowerCase() == 'true' ||
              _text(item['enableRule']) == '1';
          return enabled == schedule.enabled &&
              _text(item['startTime']) == schedule.startTime &&
              _text(item['endTime']) == schedule.endTime &&
              _text(item['scheduleDays']) ==
                  _serializeScheduleDays(schedule.days);
        }
        return false;
      },
    );
  }

  @override
  Future<void> deleteParentControlSchedule(String deviceId) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.canSchedule) {
      throw RouterFeatureUnavailable(
        'Parent Control is not readable on this router yet.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }
    final ip = await _currentIpForMac(mac);
    final original = await client.readParentControlRules();
    final updated = original
        .where((rule) => _text(rule['ip']) != ip)
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();

    if (updated.length == original.length) {
      _parentRules = original;
      return;
    }

    await _saveParentRulesSafely(
      original: original,
      updated: updated,
      deletion: true,
      verify: (readback) =>
          !readback.any((rule) => _text(rule['ip']) == ip),
    );
  }

  Future<String> _currentIpForMac(String mac) async {
    final response = await client.command(223, authenticated: true);
    final rows = response['dhcp_list_info'];
    if (rows is! List) {
      throw RouterFeatureUnavailable(
        'The router did not return the connected-device list.',
      );
    }
    for (final row in rows) {
      if (row is! Map) continue;
      final normalized = row.map((key, value) => MapEntry('$key', value));
      if (_normaliseMac(_text(normalized['mac'])) != mac) continue;
      final ip = _text(normalized['ip']);
      if (ip.isNotEmpty) return ip;
    }
    throw RouterFeatureUnavailable(
      'This device is not currently connected. Because MTN Parent Control rules are IP-based, reconnect it before changing its schedule.',
    );
  }

  Future<void> _saveParentRulesSafely({
    required List<Map<String, dynamic>> original,
    required List<Map<String, dynamic>> updated,
    required bool Function(List<Map<String, dynamic>>) verify,
    bool deletion = false,
  }) async {
    Object? primaryError;
    try {
      await client.saveParentControlRules(updated, deletion: deletion);
      final readback = await client.readParentControlRules();
      if (!verify(readback)) {
        throw RouterFeatureUnavailable(
          'The router did not return the expected Parent Control state after saving.',
        );
      }
      _parentRules = readback;
      return;
    } catch (error) {
      primaryError = error;
    }

    try {
      await client.saveParentControlRules(original, deletion: true);
      final restored = await client.readParentControlRules();
      _parentRules = restored;
      if (!_sameParentRules(restored, original)) {
        throw RouterFeatureUnavailable(
          'The schedule write failed and the router did not confirm an exact rollback.',
        );
      }
    } catch (rollbackError) {
      throw RouterFeatureUnavailable(
        'The schedule write failed and automatic rollback could not be verified. Open the MTN Parent Control page before making another change. Original error: $primaryError. Rollback error: $rollbackError',
      );
    }

    throw RouterFeatureUnavailable(
      'The schedule change was not saved. The previous Parent Control rules were restored. $primaryError',
    );
  }

  bool _sameParentRules(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    return jsonEncode(_stableJson(a)) == jsonEncode(_stableJson(b));
  }

  dynamic _stableJson(dynamic value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return {
        for (final entry in entries)
          '${entry.key}': _stableJson(entry.value),
      };
    }
    if (value is List) {
      return value.map(_stableJson).toList(growable: false);
    }
    return value;
  }

  void _validateSchedule(ParentControlSchedule schedule) {
    if (schedule.days.isEmpty ||
        schedule.days.any((day) => day < 0 || day > 6)) {
      throw RouterFeatureUnavailable('Choose at least one valid day.');
    }
    final start = _timeMinutes(schedule.startTime);
    final end = _timeMinutes(schedule.endTime);
    if (start == null || end == null || end <= start) {
      throw RouterFeatureUnavailable(
        'Choose a valid schedule where the end time is later than the start time.',
      );
    }
  }

  Set<int> _parseScheduleDays(dynamic value) {
    return _text(value)
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .where((day) => day >= 0 && day <= 6)
        .toSet();
  }

  String _serializeScheduleDays(Set<int> days) {
    final ordered = days.toList()..sort();
    return ordered.join(',');
  }

  int? _timeMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 24 || minute < 0 || minute > 59) return null;
    if (hour == 24 && minute != 0) return null;
    return hour * 60 + minute;
  }

  @override
  Future<List<UsagePoint>> fetchWeeklyUsage() => usageStore.lastSevenDays();

  @override
  Future<void> reboot() async {
    throw RouterFeatureUnavailable(
      'Reboot is intentionally disabled until its X17U write command is verified on this firmware.',
    );
  }

  DeviceKind _inferKind(String hostname) {
    final value = hostname.toLowerCase();
    if (RegExp(r'pixel|iphone|galaxy|android|redmi|xiaomi|oppo|vivo|realme|oneplus|tecno|infinix').hasMatch(value)) {
      return DeviceKind.phone;
    }
    if (RegExp(r'ipad|tablet|tab').hasMatch(value)) return DeviceKind.tablet;
    if (RegExp(r'macbook|laptop|thinkpad|desktop|surface|lenovo|dell|acer|asus|hp-').hasMatch(value)) {
      return DeviceKind.laptop;
    }
    if (RegExp(r'tv|bravia|webos|tizen|chromecast|firetv|roku').hasMatch(value)) {
      return DeviceKind.tv;
    }
    if (RegExp(r'playstation|ps5|ps4|xbox|nintendo|switch').hasMatch(value)) {
      return DeviceKind.console;
    }
    return DeviceKind.unknown;
  }

  int _wifiSignalPercent(int rssi) {
    if (rssi >= -50) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 2).clamp(0, 100).toInt();
  }

  DateTime? _dateFromEpoch(dynamic value) {
    final seconds = int.tryParse(_text(value));
    if (seconds == null || seconds <= 0) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    } catch (_) {
      return null;
    }
  }

  double _number(dynamic value, [double fallback = 0]) {
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? fallback;
  }

  double? _nullableNumber(dynamic value) {
    final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double? _positiveNumber(dynamic value) {
    final number = _nullableNumber(value);
    if (number == null || number <= 0) return null;
    return number;
  }

  int? _kilobytesToBytes(dynamic value) {
    final kb = _nullableNumber(value);
    if (kb == null || kb < 0) return null;
    return (kb * 1024).round();
  }

  int _int(dynamic value, [int fallback = 0]) {
    return _number(value, fallback.toDouble()).round();
  }

  int? _nullableInt(dynamic value) {
    final number = _nullableNumber(value);
    return number?.round();
  }

  int _firstInt(dynamic value, [int fallback = 0]) {
    final text = _text(value);
    if (text.isEmpty) return fallback;
    final first = RegExp(r'-?\d+').firstMatch(text)?.group(0);
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
