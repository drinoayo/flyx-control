import 'dart:convert';

import '../models/models.dart';
import '../services/zlt_client.dart';
import 'router_repository.dart';

/// Live adapter for ZLT/ZTE reqproc-based firmware.
///
/// The read side is implemented now. Write features are enabled only when the
/// action name is discovered in the router's own JavaScript. This avoids
/// pretending that one carrier firmware is identical to another.
class ZltRouterRepository implements RouterRepository {
  ZltRouterRepository({
    required this.client,
    required this.username,
    required this.password,
  });

  final ZltClient client;
  final String username;
  final String password;
  ZltDiscoveryReport? _discovery;
  bool _loggedIn = false;

  Future<void> _ensureLogin() async {
    if (_loggedIn) return;
    await client.login(username: username, password: password);
    _loggedIn = true;
  }

  Future<ZltDiscoveryReport> _ensureDiscovery() async {
    _discovery ??= await client.discover();
    return _discovery!;
  }

  @override
  Future<NetworkSnapshot> fetchNetwork() async {
    final open = await client.read([
      'network_type',
      'rssi',
      'signalbar',
      'lte_rsrq',
      'lte_pci',
      'ppp_status',
    ]);

    Map<String, dynamic> auth = const {};
    try {
      await _ensureLogin();
      auth = await client.read([
        'lte_rsrp',
        'lte_band',
        'lte_snr',
        'realtime_rx_thrpt',
        'realtime_tx_thrpt',
        'realtime_rx_bytes',
        'realtime_tx_bytes',
        'monthly_rx_bytes',
        'monthly_tx_bytes',
      ]);
    } catch (_) {
      // Signal basics remain useful even if auth-only fields are unavailable.
    }

    int parseInt(dynamic value, [int fallback = 0]) {
      final cleaned = '$value'.replaceAll(RegExp(r'[^0-9\-]'), '');
      return int.tryParse(cleaned) ?? fallback;
    }

    double parseDouble(dynamic value) {
      final cleaned = '$value'.replaceAll(RegExp(r'[^0-9.\-]'), '');
      return double.tryParse(cleaned) ?? 0;
    }

    final monthlyRx = parseInt(auth['monthly_rx_bytes']);
    final monthlyTx = parseInt(auth['monthly_tx_bytes']);
    final liveRx = parseDouble(auth['realtime_rx_thrpt']);
    final liveTx = parseDouble(auth['realtime_tx_thrpt']);

    return NetworkSnapshot(
      connected: '${open['ppp_status'] ?? ''}'.toLowerCase().contains('connect') ||
          '${open['ppp_status'] ?? ''}' == 'ppp_connected',
      networkType: '${open['network_type'] ?? 'Unknown'}',
      carrier: 'MTN-NG',
      rsrp: parseInt(auth['lte_rsrp'], parseInt(open['rssi'], -120)),
      rsrq: parseInt(open['lte_rsrq'], -20),
      sinr: parseInt(auth['lte_snr']),
      rssi: parseInt(open['rssi'], -120),
      pci: parseInt(open['lte_pci']),
      lteBand: '${auth['lte_band'] ?? '—'}',
      nrBand: '—',
      // Firmware varies between bytes/s and bit/s. Until the X17U value is
      // confirmed, keep the raw rate visible through the UI as bytes/s.
      downloadBytesPerSecond: liveRx,
      uploadBytesPerSecond: liveTx,
      routerUptime: Duration.zero,
      internetUptimePercent: 0,
      todayBytes: 0,
      monthBytes: monthlyRx + monthlyTx,
      outagesToday: 0,
      latencyMs: 0,
      packetLossPercent: 0,
    );
  }

  @override
  Future<List<FlyxDevice>> fetchDevices() async {
    await _ensureLogin();
    final result = await client.read(['station_list']);
    dynamic raw = result['station_list'];
    if (raw is String && raw.trim().startsWith('[')) {
      raw = jsonDecode(raw);
    }
    if (raw is! List) return const [];

    return raw.map((entry) {
      final map = entry is Map ? entry : const <String, dynamic>{};
      final mac = '${map['mac_addr'] ?? map['mac'] ?? ''}';
      final hostname = '${map['hostname'] ?? 'Unknown device'}';
      final connectSeconds = int.tryParse('${map['connect_time'] ?? 0}') ?? 0;
      return FlyxDevice(
        id: mac.isEmpty ? hostname : mac,
        name: hostname,
        hostname: hostname,
        mac: mac,
        ip: '${map['ip_addr'] ?? map['ip'] ?? '—'}',
        kind: DeviceKind.unknown,
        online: true,
        blocked: false,
        rxBytesPerSecond: 0,
        txBytesPerSecond: 0,
        todayBytes: 0,
        weekBytes: 0,
        monthBytes: 0,
        currentSession: Duration(seconds: connectSeconds),
        totalOnlineToday: Duration(seconds: connectSeconds),
        lastSeen: DateTime.now(),
        signalPercent: 0,
      );
    }).toList(growable: false);
  }

  @override
  Future<RouterCapabilities> capabilities() async {
    final report = await _ensureDiscovery();
    final actions = report.actions;
    return RouterCapabilities(
      signal: true,
      stationList: report.hasStationList,
      blocking: actions.contains('AIRTEL_SET_TRAFFIC_BLOCK'),
      sms: actions.contains('SEND_SMS'),
      ussd: actions.contains('USSD_PROCESS'),
      wifiSettings: actions.contains('SET_WIFI_SSID1_SETTINGS'),
      reboot: actions.contains('REBOOT_DEVICE'),
      perDeviceTraffic: '${report.status['AIRTEL_GET_DEVICE_INFO_TRAFFIC'] ?? ''}'.isNotEmpty,
      qos: false,
      networkMode: actions.contains('SET_BEARER_PREFERENCE'),
      discoveredActions: actions,
    );
  }

  @override
  Future<void> setBlocked(String deviceId, bool blocked) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.hasAction('AIRTEL_SET_TRAFFIC_BLOCK')) {
      throw RouterFeatureUnavailable(
        'The MTN X17U blocking action has not been mapped yet. Run Capability Scan so we can identify the exact action exposed by your firmware.',
      );
    }
    final result = await client.post('AIRTEL_SET_TRAFFIC_BLOCK', {
      'operate_mac': deviceId,
      'block_flag': blocked ? '1' : '0',
    });
    if ('${result['result'] ?? ''}'.toLowerCase() != 'success') {
      throw RouterFeatureUnavailable('The router did not accept the block request.');
    }
  }

  @override
  Future<void> setDeviceName(String deviceId, String name) async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.hasAction('EDIT_HOSTNAME')) {
      throw RouterFeatureUnavailable('This firmware did not expose EDIT_HOSTNAME.');
    }
    final result = await client.post('EDIT_HOSTNAME', {'mac': deviceId, 'hostname': name});
    if ('${result['result'] ?? ''}'.toLowerCase() != 'success') {
      throw RouterFeatureUnavailable('The router did not accept the rename request.');
    }
  }

  @override
  Future<void> setDevicePolicy(String deviceId, DevicePolicy policy) async {
    throw RouterFeatureUnavailable(
      'Policy storage is ready in the app, but reliable 24/7 enforcement needs the exact X17U parental-control or traffic-control action mapped first.',
    );
  }

  @override
  Future<List<UsagePoint>> fetchWeeklyUsage() async => const [];

  @override
  Future<void> reboot() async {
    await _ensureLogin();
    final report = await _ensureDiscovery();
    if (!report.hasAction('REBOOT_DEVICE')) {
      throw RouterFeatureUnavailable('This firmware did not expose REBOOT_DEVICE.');
    }
    final result = await client.post('REBOOT_DEVICE', const {});
    final value = '${result['result'] ?? ''}'.toLowerCase();
    if (value != 'success' && value != '0') {
      throw RouterFeatureUnavailable('The router did not accept the reboot request.');
    }
  }
}
