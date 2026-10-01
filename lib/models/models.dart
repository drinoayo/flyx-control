import 'package:flutter/material.dart';

enum DeviceKind { phone, laptop, tv, tablet, desktop, console, unknown }
enum LimitPeriod { daily, weekly, monthly }
enum ConnectionGrade { excellent, good, fair, poor }
enum WifiBand { twoFourGhz, fiveGhz }

class WifiBandSettings {
  const WifiBandSettings({
    required this.band,
    required this.ssid,
    required this.enabled,
    required this.broadcast,
    required this.channel,
    required this.bandwidthCode,
    required this.txPowerPercent,
    required this.maxClients,
    required this.wpsEnabled,
    this.authenticationType = '2',
    this.wifiModeCode = '',
    this.countryCode = '',
    this.maxClientsLimit = 32,
    this.dfsEnabled,
  });

  final WifiBand band;
  final String ssid;
  final bool enabled;
  final bool broadcast;
  final String channel;
  final String bandwidthCode;
  final double txPowerPercent;
  final int maxClients;
  final bool wpsEnabled;
  final String authenticationType;
  final String wifiModeCode;
  final String countryCode;
  final int maxClientsLimit;
  final bool? dfsEnabled;

  String get label => band == WifiBand.twoFourGhz ? '2.4 GHz' : '5 GHz';
}

class WifiSettingsSnapshot {
  const WifiSettingsSnapshot({
    required this.twoFourGhz,
    required this.fiveGhz,
    this.optimizationEnabled = false,
  });

  final WifiBandSettings twoFourGhz;
  final WifiBandSettings fiveGhz;

  /// Stock X17U "5G Optimization" / shared-band setting.
  final bool optimizationEnabled;
}

class WifiUpdateResult {
  const WifiUpdateResult({this.reconnectExpected = false});

  final bool reconnectExpected;
}


class RouterSmsMessage {
  const RouterSmsMessage({
    required this.index,
    required this.unread,
    required this.phoneNumber,
    required this.date,
    required this.text,
  });

  final int index;
  final bool unread;
  final String phoneNumber;
  final String date;
  final String text;

  RouterSmsMessage copyWith({bool? unread}) {
    return RouterSmsMessage(
      index: index,
      unread: unread ?? this.unread,
      phoneNumber: phoneNumber,
      date: date,
      text: text,
    );
  }
}

class RouterSmsPage {
  const RouterSmsPage({
    required this.messages,
    required this.total,
    required this.page,
    this.sendFull = false,
    this.receiveFull = false,
    this.flashFull = false,
    this.maxLength = 160,
  });

  final List<RouterSmsMessage> messages;
  final int total;
  final int page;
  final bool sendFull;
  final bool receiveFull;
  final bool flashFull;
  final int maxLength;

  int get maxPage => total <= 0 ? 1 : ((total + 9) ~/ 10);
}

class UssdResult {
  const UssdResult({
    required this.message,
    required this.needsReply,
    required this.status,
  });

  final String message;
  final bool needsReply;
  final String status;
}

class ParentControlSchedule {
  const ParentControlSchedule({
    required this.enabled,
    required this.startTime,
    required this.endTime,
    required this.days,
  });

  final bool enabled;
  final String startTime;
  final String endTime;

  /// X17U weekday values: Sunday=0, Monday=1 ... Saturday=6.
  final Set<int> days;

  ParentControlSchedule copyWith({
    bool? enabled,
    String? startTime,
    String? endTime,
    Set<int>? days,
  }) {
    return ParentControlSchedule(
      enabled: enabled ?? this.enabled,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      days: days ?? this.days,
    );
  }

  bool isActiveAt(DateTime value) {
    if (!enabled || days.isEmpty) return false;
    final routerDay = value.weekday == DateTime.sunday ? 0 : value.weekday;
    if (!days.contains(routerDay)) return false;

    final start = _minutes(startTime);
    final end = _minutes(endTime);
    if (start == null || end == null || end <= start) return false;

    final current = value.hour * 60 + value.minute;
    return current >= start && current < end;
  }

  String get dayLabel {
    if (days.length == 7) return 'Every day';
    const labels = {
      0: 'Sun',
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
    };
    final ordered = <int>[1, 2, 3, 4, 5, 6, 0]
        .where(days.contains)
        .map((day) => labels[day]!)
        .toList();
    return ordered.join(', ');
  }

  String get summary => '$startTime–$endTime · $dayLabel';

  static int? _minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 24 || minute < 0 || minute > 59) return null;
    if (hour == 24 && minute != 0) return null;
    return hour * 60 + minute;
  }
}

class DevicePolicy {
  const DevicePolicy({
    this.dataLimitBytes,
    this.period = LimitPeriod.daily,
    this.downloadLimitMbps,
    this.uploadLimitMbps,
    this.pauseWhenLimitReached = true,
  });

  final int? dataLimitBytes;
  final LimitPeriod period;
  final double? downloadLimitMbps;
  final double? uploadLimitMbps;
  final bool pauseWhenLimitReached;

  DevicePolicy copyWith({
    int? dataLimitBytes,
    bool clearDataLimit = false,
    LimitPeriod? period,
    double? downloadLimitMbps,
    double? uploadLimitMbps,
    bool? pauseWhenLimitReached,
  }) {
    return DevicePolicy(
      dataLimitBytes: clearDataLimit ? null : dataLimitBytes ?? this.dataLimitBytes,
      period: period ?? this.period,
      downloadLimitMbps: downloadLimitMbps ?? this.downloadLimitMbps,
      uploadLimitMbps: uploadLimitMbps ?? this.uploadLimitMbps,
      pauseWhenLimitReached: pauseWhenLimitReached ?? this.pauseWhenLimitReached,
    );
  }
}

class DeviceSessionRecord {
  const DeviceSessionRecord({
    required this.startedAt,
    required this.lastSeen,
    this.endedAt,
  });

  final DateTime startedAt;
  final DateTime lastSeen;
  final DateTime? endedAt;

  bool get isCurrent => endedAt == null;

  Duration durationAt(DateTime now) {
    final end = endedAt ?? now;
    if (!end.isAfter(startedAt)) return Duration.zero;
    return end.difference(startedAt);
  }
}

class ObservedOutage {
  const ObservedOutage({
    required this.startedAt,
    this.restoredAt,
  });

  final DateTime startedAt;
  final DateTime? restoredAt;

  bool get ongoing => restoredAt == null;

  Duration durationAt(DateTime now) {
    final end = restoredAt ?? now;
    if (!end.isAfter(startedAt)) return Duration.zero;
    return end.difference(startedAt);
  }
}

class FlyxDevice {
  const FlyxDevice({
    required this.id,
    required this.name,
    required this.hostname,
    required this.mac,
    required this.ip,
    required this.kind,
    required this.online,
    required this.blocked,
    required this.rxBytesPerSecond,
    required this.txBytesPerSecond,
    required this.todayBytes,
    required this.weekBytes,
    required this.monthBytes,
    required this.currentSession,
    required this.totalOnlineToday,
    required this.lastSeen,
    required this.signalPercent,
    this.firstSeen,
    this.wifiBand = '',
    this.wifiRssiDbm,
    this.wifiTxLinkMbps,
    this.wifiRxLinkMbps,
    this.dhcpLeaseExpires,
    this.parentControlSchedule,
    this.parentControlActive = false,
    this.recentSessions = const [],
    this.policy = const DevicePolicy(),
  });

  final String id;
  final String name;
  final String hostname;
  final String mac;
  final String ip;
  final DeviceKind kind;
  final bool online;
  final bool blocked;

  /// Actual observed per-device traffic. Keep at zero unless the router exposes
  /// byte counters/throughput for this client; Wi-Fi link rates must not be
  /// presented as internet throughput.
  final double rxBytesPerSecond;
  final double txBytesPerSecond;

  final int todayBytes;
  final int weekBytes;
  final int monthBytes;
  final Duration currentSession;
  final Duration totalOnlineToday;
  final DateTime lastSeen;
  final int signalPercent;
  final DateTime? firstSeen;

  /// Association/link information from X17U Wi-Fi commands 224/225.
  final String wifiBand;
  final int? wifiRssiDbm;
  final double? wifiTxLinkMbps;
  final double? wifiRxLinkMbps;

  /// DHCP lease expiry if exposed. This is not device uptime.
  final DateTime? dhcpLeaseExpires;

  /// Router-side Kids Management rule matched to this device's current LAN IP.
  final ParentControlSchedule? parentControlSchedule;

  /// Whether the router's own clock says the Parent Control window is active.
  final bool parentControlActive;

  /// Recent locally observed association sessions. These are observational,
  /// not reconstructed for periods when FlyX Control was not monitoring.
  final List<DeviceSessionRecord> recentSessions;

  final DevicePolicy policy;

  double get totalRate => rxBytesPerSecond + txBytesPerSecond;

  FlyxDevice copyWith({
    String? name,
    bool? online,
    bool? blocked,
    double? rxBytesPerSecond,
    double? txBytesPerSecond,
    int? todayBytes,
    int? weekBytes,
    int? monthBytes,
    Duration? currentSession,
    Duration? totalOnlineToday,
    DateTime? lastSeen,
    int? signalPercent,
    DateTime? firstSeen,
    String? wifiBand,
    int? wifiRssiDbm,
    double? wifiTxLinkMbps,
    double? wifiRxLinkMbps,
    DateTime? dhcpLeaseExpires,
    ParentControlSchedule? parentControlSchedule,
    bool clearParentControlSchedule = false,
    bool? parentControlActive,
    List<DeviceSessionRecord>? recentSessions,
    DevicePolicy? policy,
  }) {
    return FlyxDevice(
      id: id,
      name: name ?? this.name,
      hostname: hostname,
      mac: mac,
      ip: ip,
      kind: kind,
      online: online ?? this.online,
      blocked: blocked ?? this.blocked,
      rxBytesPerSecond: rxBytesPerSecond ?? this.rxBytesPerSecond,
      txBytesPerSecond: txBytesPerSecond ?? this.txBytesPerSecond,
      todayBytes: todayBytes ?? this.todayBytes,
      weekBytes: weekBytes ?? this.weekBytes,
      monthBytes: monthBytes ?? this.monthBytes,
      currentSession: currentSession ?? this.currentSession,
      totalOnlineToday: totalOnlineToday ?? this.totalOnlineToday,
      lastSeen: lastSeen ?? this.lastSeen,
      signalPercent: signalPercent ?? this.signalPercent,
      firstSeen: firstSeen ?? this.firstSeen,
      wifiBand: wifiBand ?? this.wifiBand,
      wifiRssiDbm: wifiRssiDbm ?? this.wifiRssiDbm,
      wifiTxLinkMbps: wifiTxLinkMbps ?? this.wifiTxLinkMbps,
      wifiRxLinkMbps: wifiRxLinkMbps ?? this.wifiRxLinkMbps,
      dhcpLeaseExpires: dhcpLeaseExpires ?? this.dhcpLeaseExpires,
      parentControlSchedule: clearParentControlSchedule
          ? null
          : parentControlSchedule ?? this.parentControlSchedule,
      parentControlActive:
          parentControlActive ?? this.parentControlActive,
      recentSessions: recentSessions ?? this.recentSessions,
      policy: policy ?? this.policy,
    );
  }
}

class UsagePoint {
  const UsagePoint(this.label, this.bytes);
  final String label;
  final int bytes;
}

class NetworkSnapshot {
  const NetworkSnapshot({
    required this.connected,
    required this.networkType,
    required this.carrier,
    required this.rsrp,
    required this.rsrq,
    required this.sinr,
    required this.rssi,
    required this.pci,
    required this.lteBand,
    required this.nrBand,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
    required this.routerUptime,
    required this.internetUptimePercent,
    this.internetObservationDuration = Duration.zero,
    required this.todayBytes,
    required this.monthBytes,
    required this.outagesToday,
    required this.latencyMs,
    required this.packetLossPercent,
    this.recentOutages = const [],
    this.monthDownloadBytes = 0,
    this.monthUploadBytes = 0,
    this.routerCpuPercent,
    this.routerTemperatureC,
    this.routerMemoryFreeBytes,
    this.firmwareVersion = '',
  });

  final bool connected;
  final String networkType;
  final String carrier;
  final int rsrp;
  final int rsrq;
  final int sinr;
  final int rssi;
  final int pci;
  final String lteBand;
  final String nrBand;
  final double downloadBytesPerSecond;
  final double uploadBytesPerSecond;
  final Duration routerUptime;
  final double internetUptimePercent;
  final Duration internetObservationDuration;
  final int todayBytes;
  final int monthBytes;
  final int outagesToday;
  final int latencyMs;
  final double packetLossPercent;
  final List<ObservedOutage> recentOutages;
  final int monthDownloadBytes;
  final int monthUploadBytes;
  final double? routerCpuPercent;
  final double? routerTemperatureC;
  final int? routerMemoryFreeBytes;
  final String firmwareVersion;

  ConnectionGrade get grade {
    if (rsrp >= -85 && sinr >= 20) return ConnectionGrade.excellent;
    if (rsrp >= -100 && sinr >= 10) return ConnectionGrade.good;
    if (rsrp >= -110 && sinr >= 0) return ConnectionGrade.fair;
    return ConnectionGrade.poor;
  }

  String get gradeLabel => switch (grade) {
        ConnectionGrade.excellent => 'Excellent',
        ConnectionGrade.good => 'Good',
        ConnectionGrade.fair => 'Fair',
        ConnectionGrade.poor => 'Poor',
      };

  Color get gradeColor => switch (grade) {
        ConnectionGrade.excellent => const Color(0xFF62D98B),
        ConnectionGrade.good => const Color(0xFF8DDB62),
        ConnectionGrade.fair => const Color(0xFFF6B64D),
        ConnectionGrade.poor => const Color(0xFFFF6B6B),
      };

  NetworkSnapshot copyWith({
    bool? connected,
    String? networkType,
    int? rsrp,
    int? rsrq,
    int? sinr,
    double? downloadBytesPerSecond,
    double? uploadBytesPerSecond,
    Duration? routerUptime,
    double? internetUptimePercent,
    Duration? internetObservationDuration,
    int? todayBytes,
    int? monthBytes,
    int? latencyMs,
    double? packetLossPercent,
    List<ObservedOutage>? recentOutages,
    int? monthDownloadBytes,
    int? monthUploadBytes,
    double? routerCpuPercent,
    double? routerTemperatureC,
    int? routerMemoryFreeBytes,
    String? firmwareVersion,
  }) {
    return NetworkSnapshot(
      connected: connected ?? this.connected,
      networkType: networkType ?? this.networkType,
      carrier: carrier,
      rsrp: rsrp ?? this.rsrp,
      rsrq: rsrq ?? this.rsrq,
      sinr: sinr ?? this.sinr,
      rssi: rssi,
      pci: pci,
      lteBand: lteBand,
      nrBand: nrBand,
      downloadBytesPerSecond: downloadBytesPerSecond ?? this.downloadBytesPerSecond,
      uploadBytesPerSecond: uploadBytesPerSecond ?? this.uploadBytesPerSecond,
      routerUptime: routerUptime ?? this.routerUptime,
      internetUptimePercent:
          internetUptimePercent ?? this.internetUptimePercent,
      internetObservationDuration:
          internetObservationDuration ?? this.internetObservationDuration,
      todayBytes: todayBytes ?? this.todayBytes,
      monthBytes: monthBytes ?? this.monthBytes,
      outagesToday: outagesToday,
      latencyMs: latencyMs ?? this.latencyMs,
      packetLossPercent: packetLossPercent ?? this.packetLossPercent,
      recentOutages: recentOutages ?? this.recentOutages,
      monthDownloadBytes: monthDownloadBytes ?? this.monthDownloadBytes,
      monthUploadBytes: monthUploadBytes ?? this.monthUploadBytes,
      routerCpuPercent: routerCpuPercent ?? this.routerCpuPercent,
      routerTemperatureC:
          routerTemperatureC ?? this.routerTemperatureC,
      routerMemoryFreeBytes:
          routerMemoryFreeBytes ?? this.routerMemoryFreeBytes,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    );
  }
}

class RouterCapabilities {
  const RouterCapabilities({
    this.signal = true,
    this.stationList = false,
    this.blocking = false,
    this.scheduling = false,
    this.sms = false,
    this.ussd = false,
    this.wifiSettings = false,
    this.reboot = false,
    this.perDeviceTraffic = false,
    this.qos = false,
    this.networkMode = false,
    this.discoveredActions = const [],
  });

  final bool signal;
  final bool stationList;
  final bool blocking;
  final bool scheduling;
  final bool sms;
  final bool ussd;
  final bool wifiSettings;
  final bool reboot;
  final bool perDeviceTraffic;
  final bool qos;
  final bool networkMode;
  final List<String> discoveredActions;
}

class RouterConnectionConfig {
  const RouterConnectionConfig({
    this.host = '192.168.0.1',
    this.username = 'admin',
    this.password = '',
  });

  final String host;
  final String username;
  final String password;
}
