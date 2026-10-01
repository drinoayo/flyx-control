import '../models/models.dart';

abstract class RouterRepository {
  Future<NetworkSnapshot> fetchNetwork();
  Future<List<FlyxDevice>> fetchDevices();
  Future<List<UsagePoint>> fetchWeeklyUsage();
  Future<WifiSettingsSnapshot> fetchWifiSettings();
  Future<WifiUpdateResult> updateWifiPrimary(
    WifiBand band, {
    String? ssid,
    String? password,
    bool? broadcast,
  });
  Future<RouterCapabilities> capabilities();
  Future<void> setBlocked(String deviceId, bool blocked);
  Future<void> setDeviceName(String deviceId, String name);
  Future<void> setDevicePolicy(String deviceId, DevicePolicy policy);
  Future<void> setParentControlSchedule(
    String deviceId,
    ParentControlSchedule schedule,
  );
  Future<void> deleteParentControlSchedule(String deviceId);
  Future<void> reboot();
}

class RouterFeatureUnavailable implements Exception {
  RouterFeatureUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}
