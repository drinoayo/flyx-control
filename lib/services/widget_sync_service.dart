import 'dart:io';

import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../models/models.dart';

class WidgetSyncService {
  WidgetSyncService._();

  static const MethodChannel _channel = MethodChannel(
    'com.flyxcontrol.flyx_control/widgets',
  );

  static Future<void> sync({
    required NetworkSnapshot network,
    required List<FlyxDevice> devices,
    required int messageCount,
  }) async {
    if (!Platform.isAndroid) return;

    final connectedDevices = devices
        .where((device) => device.online && !device.blocked)
        .length;

    try {
      await _channel.invokeMethod<void>('sync', {
        'connected': network.connected,
        'download': formatRate(network.downloadBytesPerSecond),
        'upload': formatRate(network.uploadBytesPerSecond),
        'devices': '$connectedDevices',
        'uptime': formatDuration(network.routerUptime),
        'messages': '$messageCount',
        'today': formatBytes(network.todayBytes),
        'month': formatBytes(network.monthBytes),
      });
    } on MissingPluginException {
      // The native bridge only exists on Android builds.
    } on PlatformException {
      // Widgets are optional. Never let a launcher/widget error interfere
      // with the router controller itself.
    }
  }

  static Future<bool> requestPinWidget() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPinWidget') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
