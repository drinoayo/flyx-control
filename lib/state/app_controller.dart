import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../repositories/router_repository.dart';

class AppController extends ChangeNotifier {
  AppController({required RouterRepository repository}) : _repository = repository;

  RouterRepository _repository;
  Timer? _timer;
  bool loading = true;
  bool busy = false;
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
    _repository = repository;
    network = null;
    devices = const [];
    weeklyUsage = const [];
    capabilities = const RouterCapabilities();
    await refresh();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait<dynamic>([
        _repository.fetchNetwork(),
        _repository.fetchDevices(),
        _repository.fetchWeeklyUsage(),
        _repository.capabilities(),
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
    await _run(() => _repository.setBlocked(id, blocked));
  }

  Future<void> setDeviceName(String id, String name) async {
    await _run(() => _repository.setDeviceName(id, name));
  }

  Future<void> setDevicePolicy(String id, DevicePolicy policy) async {
    await _run(() => _repository.setDevicePolicy(id, policy));
  }

  Future<void> reboot() async {
    await _run(_repository.reboot);
  }

  Future<void> _run(Future<void> Function() task) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await task();
      await refresh(silent: true);
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
