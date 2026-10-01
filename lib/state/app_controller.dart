import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../repositories/router_repository.dart';

class AppController extends ChangeNotifier {
  AppController({required this.repository});

  RouterRepository repository;
  Timer? _timer;
  bool loading = true;
  bool busy = false;
  bool _refreshing = false;
  String? error;
  NetworkSnapshot? network;
  List<FlyxDevice> devices = const [];
  List<UsagePoint> weeklyUsage = const [];
  RouterCapabilities capabilities = const RouterCapabilities();

  Future<void> start() async {
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh(silent: true));
  }

  Future<void> replaceRepository(RouterRepository repository) async {
    this.repository = repository;
    network = null;
    devices = const [];
    weeklyUsage = const [];
    capabilities = const RouterCapabilities();
    await refresh();
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
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      _refreshing = false;
      notifyListeners();
    }
  }

  FlyxDevice? deviceById(String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Future<void> setBlocked(String id, bool blocked) async {
    await _run(() => repository.setBlocked(id, blocked));
  }

  Future<void> setDeviceName(String id, String name) async {
    await _run(() => repository.setDeviceName(id, name));
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
    await _run(repository.reboot);
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
