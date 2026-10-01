import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../repositories/router_repository.dart';
import '../services/widget_sync_service.dart';

class AppController extends ChangeNotifier {
  AppController({required this.repository});

  RouterRepository repository;
  Timer? _timer;
  bool loading = true;
  bool busy = false;
  bool _refreshing = false;
  int _pollTick = 0;
  int _messageCount = 0;
  DateTime? _lastWidgetSyncAt;
  String? error;
  NetworkSnapshot? network;
  List<FlyxDevice> devices = const [];
  List<UsagePoint> weeklyUsage = const [];
  RouterCapabilities capabilities = const RouterCapabilities();

  Future<void> start() async {
    await refresh();
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    if (_refreshing || busy) return;
    _refreshing = true;
    _pollTick++;

    try {
      final fetchDevices = _pollTick % 3 == 0;
      final fetchHistory = _pollTick % 15 == 0;
      final fetchMessages = capabilities.sms && _pollTick % 15 == 0;

      final futures = <Future<dynamic>>[
        repository.fetchNetwork(),
        if (fetchDevices) repository.fetchDevices(),
        if (fetchHistory) repository.fetchWeeklyUsage(),
        if (fetchMessages) repository.fetchSmsInbox(),
      ];
      final results = await Future.wait<dynamic>(futures);

      var index = 0;
      network = results[index++] as NetworkSnapshot;
      if (fetchDevices) {
        devices = results[index++] as List<FlyxDevice>;
      }
      if (fetchHistory) {
        weeklyUsage = results[index++] as List<UsagePoint>;
      }
      if (fetchMessages) {
        _messageCount = (results[index++] as RouterSmsPage).total;
      }
      error = null;
      await _syncWidgets();
    } catch (e) {
      error = e.toString();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> replaceRepository(RouterRepository repository) async {
    this.repository = repository;
    network = null;
    devices = const [];
    weeklyUsage = const [];
    capabilities = const RouterCapabilities();
    _messageCount = 0;
    _lastWidgetSyncAt = null;
    _pollTick = 0;
    await refresh();
    _startPolling();
  }

  Future<void> refresh({
    bool silent = false,
    bool allowWhileBusy = false,
  }) async {
    if (_refreshing || (busy && !allowWhileBusy)) return;
    _refreshing = true;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait<dynamic>([
        repository.fetchNetwork(),
        repository.fetchDevices(),
        repository.fetchWeeklyUsage(),
        repository.capabilities(),
      ]);
      network = results[0] as NetworkSnapshot;
      devices = results[1] as List<FlyxDevice>;
      weeklyUsage = results[2] as List<UsagePoint>;
      capabilities = results[3] as RouterCapabilities;
      if (capabilities.sms) {
        try {
          _messageCount = (await repository.fetchSmsInbox()).total;
        } catch (_) {
          // Keep the last known count if SMS is temporarily unavailable.
        }
      } else {
        _messageCount = 0;
      }
      error = null;
      await _syncWidgets(force: true);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _syncWidgets({bool force = false}) async {
    final snapshot = network;
    if (snapshot == null) return;

    final now = DateTime.now();
    if (!force &&
        _lastWidgetSyncAt != null &&
        now.difference(_lastWidgetSyncAt!) < const Duration(seconds: 3)) {
      return;
    }

    _lastWidgetSyncAt = now;
    await WidgetSyncService.sync(
      network: snapshot,
      devices: devices,
      messageCount: _messageCount,
    );
  }

  FlyxDevice? deviceById(String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<WifiSettingsSnapshot> fetchWifiSettings() {
    return repository.fetchWifiSettings();
  }

  Future<RouterSmsPage> fetchSmsInbox({int page = 1}) {
    return repository.fetchSmsInbox(page: page);
  }

  Future<void> sendSms(String phoneNumber, String content) {
    return _runAction(() => repository.sendSms(phoneNumber, content));
  }

  Future<void> markSmsRead(int index) {
    return _runAction(() => repository.markSmsRead(index));
  }

  Future<void> deleteSms(List<int> indexes) async {
    await _runAction(() => repository.deleteSms(indexes));
    if (capabilities.sms) {
      try {
        _messageCount = (await repository.fetchSmsInbox()).total;
        await _syncWidgets(force: true);
      } catch (_) {
        // The inbox screen will surface any real SMS error to the user.
      }
    }
  }

  Future<UssdResult> sendUssd(String code) {
    return repository.sendUssd(code);
  }

  Future<void> cancelUssd() {
    return repository.cancelUssd();
  }

  Future<RouterNetworkModeSnapshot> fetchNetworkMode() {
    return repository.fetchNetworkMode();
  }

  Future<void> setFlightMode(bool enabled) {
    return _runAction(() => repository.setFlightMode(enabled));
  }

  Future<void> setMobileData(bool enabled) {
    return _runAction(() => repository.setMobileData(enabled));
  }

  Future<void> setDataRoaming(bool enabled) {
    return _runAction(() => repository.setDataRoaming(enabled));
  }

  Future<WifiUpdateResult> updateWifiPrimary(
    WifiBand band, {
    String? ssid,
    String? password,
    bool? enabled,
    bool? broadcast,
    String? authenticationType,
  }) {
    return _runWifi(
      () => repository.updateWifiPrimary(
        band,
        ssid: ssid,
        password: password,
        enabled: enabled,
        broadcast: broadcast,
        authenticationType: authenticationType,
      ),
    );
  }

  Future<WifiUpdateResult> updateWifiRadio(
    WifiBand band, {
    String? channel,
    String? wifiModeCode,
    String? bandwidthCode,
    double? txPowerPercent,
    int? maxClients,
    bool? dfsEnabled,
  }) {
    return _runWifi(
      () => repository.updateWifiRadio(
        band,
        channel: channel,
        wifiModeCode: wifiModeCode,
        bandwidthCode: bandwidthCode,
        txPowerPercent: txPowerPercent,
        maxClients: maxClients,
        dfsEnabled: dfsEnabled,
      ),
    );
  }

  Future<void> setWifiWps(WifiBand band, bool enabled) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await repository.setWifiWps(band, enabled);
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<WifiUpdateResult> setWifiOptimization(bool enabled) {
    return _runWifi(() => repository.setWifiOptimization(enabled));
  }

  Future<WifiUpdateResult> _runWifi(
    Future<WifiUpdateResult> Function() task,
  ) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await task();
      if (!result.reconnectExpected) {
        await refresh(silent: true, allowWhileBusy: true);
      }
      return result;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setBlocked(String id, bool blocked) async {
    await _run(() => repository.setBlocked(id, blocked));
  }

  Future<void> setDeviceName(String id, String name) async {
    await _run(() => repository.setDeviceName(id, name));
  }

  Future<void> forgetDevice(String id) async {
    await _run(() => repository.forgetDevice(id));
  }

  Future<void> setDevicePolicy(String id, DevicePolicy policy) async {
    await _run(() => repository.setDevicePolicy(id, policy));
  }

  Future<void> setParentControlSchedule(
    String id,
    ParentControlSchedule schedule,
  ) async {
    await _run(() => repository.setParentControlSchedule(id, schedule));
  }

  Future<void> deleteParentControlSchedule(String id) async {
    await _run(() => repository.deleteParentControlSchedule(id));
  }

  Future<void> reboot() async {
    await _runAction(repository.reboot);
  }

  Future<void> _runAction(Future<void> Function() task) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await task();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await task();
      await refresh(silent: true, allowWhileBusy: true);
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
