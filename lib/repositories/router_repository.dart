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
    bool? enabled,
    bool? broadcast,
    String? authenticationType,
  });
  Future<WifiUpdateResult> updateWifiRadio(
    WifiBand band, {
    String? channel,
    String? wifiModeCode,
    String? bandwidthCode,
    double? txPowerPercent,
    int? maxClients,
    bool? dfsEnabled,
  });
  Future<void> setWifiWps(WifiBand band, bool enabled);
  Future<WifiUpdateResult> setWifiOptimization(bool enabled);
  Future<RouterSmsPage> fetchSmsInbox({int page = 1});
  Future<void> sendSms(String phoneNumber, String content);
  Future<void> markSmsRead(int index);
  Future<void> deleteSms(List<int> indexes);
  Future<UssdResult> sendUssd(String code);
  Future<void> cancelUssd();
  Future<RouterNetworkModeSnapshot> fetchNetworkMode();
  Future<void> setFlightMode(bool enabled);
  Future<void> setMobileData(bool enabled);
  Future<void> setDataRoaming(bool enabled);
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
