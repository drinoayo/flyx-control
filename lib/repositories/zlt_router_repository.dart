import 'dart:convert';

import '../models/models.dart';
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
  }) : usageStore = usageStore ?? UsageStore();

  final ZltClient client;
  final String username;
  final String password;
  final UsageStore usageStore;

  bool _loggedIn = false;
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

  final Map<String, DateTime> _continuousOnlineSince = {};
  Set<String> _onlineLastPoll = <String>{};

  Set<String> _blockedMacs = <String>{};
  Map<String, String> _blockedLabels = <String, String>{};
  List<Map<String, dynamic>> _parentRules = const [];
  int _devicePoll = 0;

  Future<void> _ensureLogin() async {
    if (_loggedIn || client.isAuthenticated) {
      _loggedIn = true;
      return;
    }
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
      todayBytes: _todayBytesCache,
      monthBytes: (monthTotalMib * 1024 * 1024).round(),
      monthDownloadBytes: (monthDownMib * 1024 * 1024).round(),
      monthUploadBytes: (monthUpMib * 1024 * 1024).round(),
      outagesToday: 0,
      latencyMs: 0,
      packetLossPercent: 0,
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

    final now = DateTime.now();
    final devices = <FlyxDevice>[];
    final onlineMacs = <String>{};

    if (rows is List) {
      for (final entry in rows) {
        if (entry is! Map) continue;
        final map = entry.map((key, value) => MapEntry('$key', value));
        final mac = _normaliseMac(_text(map['mac']));
        if (mac.isEmpty) continue;
        onlineMacs.add(mac);

        if (!_onlineLastPoll.contains(mac)) {
          _continuousOnlineSince[mac] = now;
        }
        final since = _continuousOnlineSince[mac] ?? now;

        final hostname = _text(map['hostname']);
        final name = hostname.isEmpty || hostname == '*'
            ? 'Unknown device'
            : hostname;
        final ip = _text(map['ip']);
        final wifi = wifiByMac[mac] ?? wifiByIp[ip] ?? const <String, dynamic>{};

        final rssi = _nullableInt(wifi['rssi']);
        final signalPercent = rssi == null ? 0 : _wifiSignalPercent(rssi);
        final txLink = _positiveNumber(wifi['txrate']);
        final rxLink = _positiveNumber(wifi['rxrate']);
        final expires = _dateFromEpoch(map['expires']);
        final schedule = _parentScheduleForIp(ip);
        final scheduleActive = schedule?.isActiveAt(now) ?? false;

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
            currentSession: now.difference(since),
            totalOnlineToday: Duration.zero,
            lastSeen: now,
            signalPercent: signalPercent,
            wifiBand: _text(wifi['__band']),
            wifiRssiDbm: rssi,
            wifiTxLinkMbps: txLink,
            wifiRxLinkMbps: rxLink,
            dhcpLeaseExpires: expires,
            parentControlSchedule: schedule,
          ),
        );
      }
    }

    // Devices that vanished since the previous poll start a new continuous
    // session when they appear again.
    for (final previous in _onlineLastPoll.difference(onlineMacs)) {
      _continuousOnlineSince.remove(previous);
    }
    _onlineLastPoll = onlineMacs;

    // A blocked client normally disappears from active association lists. If
    // future firmware mapping exposes readable filter rules, keep it visible.
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
          lastSeen: now,
          signalPercent: 0,
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

  Future<void> _refreshBlocked() async {
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
      // The user's current MTN firmware returns no readable rules for cmd 23.
    }
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
  Future<RouterCapabilities> capabilities() async {
    final report = await _ensureDiscovery();
    return RouterCapabilities(
      signal: report.supportsCommand(133),
      stationList: report.hasStationList,
      blocking: report.canBlock,
      scheduling: report.canSchedule,
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
        'Blocking is not enabled yet because this MTN firmware accepts the filter commands but does not expose readable filter state. FlyX Control will not risk locking you out.',
      );
    }

    final mac = _normaliseMac(deviceId);
    if (mac.isEmpty) {
      throw RouterFeatureUnavailable('Invalid device MAC address.');
    }

    final rules = (await _filterRules())
        .where((rule) => _normaliseMac(_text(rule['mac'])) != mac)
        .toList();

    if (blocked) {
      final existingAddresses = rules
          .map((rule) => _normaliseMac(_text(rule['mac'])))
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
      'Friendly-name persistence will be stored locally in FlyX Control in the next data-layer pass.',
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
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return {
        for (final key in keys) key: _stableJson(value[key]),
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
