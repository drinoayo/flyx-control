import 'dart:async';
import 'dart:math';

import '../models/models.dart';
import 'router_repository.dart';

class MockRouterRepository implements RouterRepository {
  final Random _random = Random(4);
  int _tick = 0;
  bool _wifiOptimization = false;
  WifiBandSettings _wifi24 = const WifiBandSettings(
    band: WifiBand.twoFourGhz,
    ssid: 'FlyX-2.4G',
    enabled: true,
    broadcast: true,
    channel: '6',
    bandwidthCode: '2',
    txPowerPercent: 100,
    maxClients: 32,
    wpsEnabled: true,
  );
  WifiBandSettings _wifi5 = const WifiBandSettings(
    band: WifiBand.fiveGhz,
    ssid: 'FlyX-5G',
    enabled: true,
    broadcast: true,
    channel: '157',
    bandwidthCode: '3',
    txPowerPercent: 100,
    maxClients: 32,
    wpsEnabled: true,
  );

  late final List<FlyxDevice> _devices = [
    FlyxDevice(
      id: 'macbook',
      name: 'My Laptop',
      hostname: 'MacBook-Pro',
      mac: '84:32:EA:••:••:91',
      ip: '192.168.0.12',
      kind: DeviceKind.laptop,
      online: true,
      blocked: false,
      rxBytesPerSecond: 1850000,
      txBytesPerSecond: 184000,
      todayBytes: 6438256640,
      weekBytes: 29205777612,
      monthBytes: 88288645120,
      currentSession: const Duration(hours: 5, minutes: 42),
      totalOnlineToday: const Duration(hours: 11, minutes: 8),
      lastSeen: DateTime.now(),
      signalPercent: 92,
      policy: const DevicePolicy(
        dataLimitBytes: 10737418240,
        period: LimitPeriod.daily,
      ),
    ),
    FlyxDevice(
      id: 'phone',
      name: 'My Phone',
      hostname: 'iPhone',
      mac: 'F2:90:1B:••:••:10',
      ip: '192.168.0.14',
      kind: DeviceKind.phone,
      online: true,
      blocked: false,
      rxBytesPerSecond: 480000,
      txBytesPerSecond: 93000,
      todayBytes: 3865470566,
      weekBytes: 16428249907,
      monthBytes: 48855252992,
      currentSession: const Duration(hours: 2, minutes: 36),
      totalOnlineToday: const Duration(hours: 8, minutes: 51),
      lastSeen: DateTime.now(),
      signalPercent: 86,
    ),
    FlyxDevice(
      id: 'tv',
      name: 'Living Room TV',
      hostname: 'Samsung-TV',
      mac: '5C:A6:E6:••:••:2D',
      ip: '192.168.0.20',
      kind: DeviceKind.tv,
      online: true,
      blocked: false,
      rxBytesPerSecond: 2210000,
      txBytesPerSecond: 28000,
      todayBytes: 9126805504,
      weekBytes: 44560379904,
      monthBytes: 137438953472,
      currentSession: const Duration(hours: 3, minutes: 18),
      totalOnlineToday: const Duration(hours: 6, minutes: 44),
      lastSeen: DateTime.now(),
      signalPercent: 74,
      policy: const DevicePolicy(
        dataLimitBytes: 16106127360,
        period: LimitPeriod.daily,
      ),
    ),
    FlyxDevice(
      id: 'tablet',
      name: 'Guest Tablet',
      hostname: 'Galaxy-Tab',
      mac: '20:5E:F7:••:••:03',
      ip: '192.168.0.33',
      kind: DeviceKind.tablet,
      online: false,
      blocked: true,
      rxBytesPerSecond: 0,
      txBytesPerSecond: 0,
      todayBytes: 644245094,
      weekBytes: 4831838208,
      monthBytes: 13958643712,
      currentSession: Duration.zero,
      totalOnlineToday: const Duration(hours: 1, minutes: 12),
      lastSeen: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      signalPercent: 0,
      policy: const DevicePolicy(
        dataLimitBytes: 2147483648,
        period: LimitPeriod.daily,
      ),
    ),
    FlyxDevice(
      id: 'console',
      name: 'PlayStation',
      hostname: 'PS5-6D4',
      mac: '38:53:9C:••:••:A7',
      ip: '192.168.0.29',
      kind: DeviceKind.console,
      online: false,
      blocked: false,
      rxBytesPerSecond: 0,
      txBytesPerSecond: 0,
      todayBytes: 0,
      weekBytes: 9663676416,
      monthBytes: 31138512896,
      currentSession: Duration.zero,
      totalOnlineToday: Duration.zero,
      lastSeen: DateTime.now().subtract(const Duration(hours: 16)),
      signalPercent: 0,
    ),
  ];

  @override
  Future<NetworkSnapshot> fetchNetwork() async {
    await Future<void>.delayed(const Duration(milliseconds: 130));
    _tick++;
    final wave = sin(_tick / 2.8);
    return NetworkSnapshot(
      connected: true,
      networkType: '5G NSA',
      carrier: 'MTN-NG',
      rsrp: -97 + (wave * 3).round(),
      rsrq: -11,
      sinr: 18 + (wave * 2).round(),
      rssi: -72,
      pci: 284,
      lteBand: 'B3',
      nrBand: 'n78',
      downloadBytesPerSecond: 3800000 + (wave * 1150000) + _random.nextInt(220000),
      uploadBytesPerSecond: 420000 + (wave * 110000) + _random.nextInt(60000),
      routerUptime: Duration(days: 6, hours: 14, minutes: 28 + _tick),
      internetUptimePercent: 99.2,
      todayBytes: 19756849561 + (_tick * 17500000),
      monthBytes: 128849018880 + (_tick * 17500000),
      outagesToday: 2,
      latencyMs: 38 + _random.nextInt(6),
      packetLossPercent: .2,
    );
  }

  @override
  Future<List<FlyxDevice>> fetchDevices() async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    for (var i = 0; i < _devices.length; i++) {
      final d = _devices[i];
      if (!d.online || d.blocked) continue;
      final factor = .85 + _random.nextDouble() * .3;
      _devices[i] = d.copyWith(
        rxBytesPerSecond: d.rxBytesPerSecond * factor,
        txBytesPerSecond: d.txBytesPerSecond * factor,
        todayBytes: d.todayBytes + (d.totalRate * 2).round(),
        currentSession: d.currentSession + const Duration(seconds: 2),
        totalOnlineToday: d.totalOnlineToday + const Duration(seconds: 2),
        lastSeen: DateTime.now(),
      );
    }
    return List.unmodifiable(_devices);
  }

  @override
  Future<List<UsagePoint>> fetchWeeklyUsage() async => const [
        UsagePoint('Mon', 7945689498),
        UsagePoint('Tue', 10952166605),
        UsagePoint('Wed', 5153960755),
        UsagePoint('Thu', 12992276070),
        UsagePoint('Fri', 4187593113),
        UsagePoint('Sat', 15676630630),
        UsagePoint('Sun', 6764573491),
      ];

  @override
  Future<WifiSettingsSnapshot> fetchWifiSettings() async =>
      WifiSettingsSnapshot(
        twoFourGhz: _wifi24,
        fiveGhz: _wifi5,
        optimizationEnabled: _wifiOptimization,
      );

  @override
  Future<WifiUpdateResult> updateWifiPrimary(
    WifiBand band, {
    String? ssid,
    String? password,
    bool? enabled,
    bool? broadcast,
    String? authenticationType,
  }) async {
    final current = band == WifiBand.twoFourGhz ? _wifi24 : _wifi5;
    final next = _copyWifi(
      current,
      ssid: ssid,
      enabled: enabled,
      broadcast: broadcast,
      authenticationType: authenticationType,
    );
    _setMockWifi(band, next);
    return WifiUpdateResult(
      reconnectExpected:
          ssid != null ||
          (password?.isNotEmpty ?? false) ||
          enabled != null ||
          authenticationType != null,
    );
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
    final current = band == WifiBand.twoFourGhz ? _wifi24 : _wifi5;
    _setMockWifi(
      band,
      _copyWifi(
        current,
        channel: channel,
        wifiModeCode: wifiModeCode,
        bandwidthCode: bandwidthCode,
        txPowerPercent: txPowerPercent,
        maxClients: maxClients,
        dfsEnabled: dfsEnabled,
      ),
    );
    return const WifiUpdateResult();
  }

  @override
  Future<void> setWifiWps(WifiBand band, bool enabled) async {
    final current = band == WifiBand.twoFourGhz ? _wifi24 : _wifi5;
    _setMockWifi(band, _copyWifi(current, wpsEnabled: enabled));
  }

  @override
  Future<WifiUpdateResult> setWifiOptimization(bool enabled) async {
    _wifiOptimization = enabled;
    return WifiUpdateResult(reconnectExpected: enabled);
  }

  void _setMockWifi(WifiBand band, WifiBandSettings value) {
    if (band == WifiBand.twoFourGhz) {
      _wifi24 = value;
    } else {
      _wifi5 = value;
    }
  }

  WifiBandSettings _copyWifi(
    WifiBandSettings current, {
    String? ssid,
    bool? enabled,
    bool? broadcast,
    String? channel,
    String? bandwidthCode,
    double? txPowerPercent,
    int? maxClients,
    bool? wpsEnabled,
    String? authenticationType,
    String? wifiModeCode,
    bool? dfsEnabled,
  }) {
    return WifiBandSettings(
      band: current.band,
      ssid: ssid ?? current.ssid,
      enabled: enabled ?? current.enabled,
      broadcast: broadcast ?? current.broadcast,
      channel: channel ?? current.channel,
      bandwidthCode: bandwidthCode ?? current.bandwidthCode,
      txPowerPercent: txPowerPercent ?? current.txPowerPercent,
      maxClients: maxClients ?? current.maxClients,
      wpsEnabled: wpsEnabled ?? current.wpsEnabled,
      authenticationType:
          authenticationType ?? current.authenticationType,
      wifiModeCode: wifiModeCode ?? current.wifiModeCode,
      countryCode: current.countryCode,
      maxClientsLimit: current.maxClientsLimit,
      dfsEnabled: dfsEnabled ?? current.dfsEnabled,
    );
  }

  @override
  Future<RouterCapabilities> capabilities() async => const RouterCapabilities(
        signal: true,
        stationList: true,
        blocking: true,
        scheduling: true,
        sms: true,
        ussd: true,
        wifiSettings: true,
        reboot: true,
        perDeviceTraffic: true,
        qos: false,
        networkMode: true,
      );

  @override
  Future<void> setBlocked(String deviceId, bool blocked) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;
    _devices[index] = _devices[index].copyWith(
      blocked: blocked,
      online: blocked ? false : _devices[index].online,
      rxBytesPerSecond: blocked ? 0 : null,
      txBytesPerSecond: blocked ? 0 : null,
    );
  }

  @override
  Future<void> setDeviceName(String deviceId, String name) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;
    _devices[index] = _devices[index].copyWith(name: name);
  }

  @override
  Future<void> setDevicePolicy(String deviceId, DevicePolicy policy) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;
    _devices[index] = _devices[index].copyWith(policy: policy);
  }

  @override
  Future<void> setParentControlSchedule(
    String deviceId,
    ParentControlSchedule schedule,
  ) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;
    _devices[index] = _devices[index].copyWith(
      parentControlSchedule: schedule,
      blocked: schedule.isActiveAt(DateTime.now()),
    );
  }

  @override
  Future<void> deleteParentControlSchedule(String deviceId) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;
    _devices[index] = _devices[index].copyWith(
      clearParentControlSchedule: true,
      blocked: false,
    );
  }

  @override
  Future<void> reboot() async {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}
