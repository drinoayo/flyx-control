import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'device_schedule_screen.dart';

class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final device = controller.deviceById(deviceId);
    if (device == null) {
      return const Scaffold(
        body: Center(child: Text('Device is no longer available.')),
      );
    }

    final hasTraffic = controller.capabilities.perDeviceTraffic;
    final canBlock = controller.capabilities.blocking &&
        (device.wifiBand.isNotEmpty || device.blocked);
    final canSchedule = controller.capabilities.scheduling;
    final schedule = device.parentControlSchedule;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlyxColors.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(device.name),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
        children: [
          _Header(
            device: device,
            hasTraffic: hasTraffic,
            onRename: () => _renameDevice(context, device),
          ),
          const SizedBox(height: 24),

          const SectionTitle(title: 'Connection'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricLabel(
                        label: 'WI-FI',
                        value: device.wifiBand.isEmpty
                            ? 'Connected'
                            : device.wifiBand,
                      ),
                    ),
                    Expanded(
                      child: MetricLabel(
                        label: 'SIGNAL',
                        value: device.wifiRssiDbm == null
                            ? '—'
                            : '${device.wifiRssiDbm} dBm',
                      ),
                    ),
                    Expanded(
                      child: MetricLabel(
                        label: 'OBSERVED',
                        value: formatDuration(device.currentSession),
                      ),
                    ),
                  ],
                ),
                if (device.wifiTxLinkMbps != null ||
                    device.wifiRxLinkMbps != null) ...[
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: MetricLabel(
                          label: 'WI-FI RX LINK',
                          value: device.wifiRxLinkMbps == null
                              ? '—'
                              : '${_cleanMbps(device.wifiRxLinkMbps!)} Mbps',
                        ),
                      ),
                      Expanded(
                        child: MetricLabel(
                          label: 'WI-FI TX LINK',
                          value: device.wifiTxLinkMbps == null
                              ? '—'
                              : '${_cleanMbps(device.wifiTxLinkMbps!)} Mbps',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Link rate describes the Wi-Fi connection between this device and FlyX. It is not the device’s current internet speed.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: FlyxColors.muted,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          const SectionTitle(title: 'Usage'),
          const SizedBox(height: 10),
          if (hasTraffic)
            SurfaceCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricLabel(
                          label: 'TODAY',
                          value: formatBytes(device.todayBytes),
                        ),
                      ),
                      Expanded(
                        child: MetricLabel(
                          label: 'THIS WEEK',
                          value: formatBytes(device.weekBytes),
                        ),
                      ),
                      Expanded(
                        child: MetricLabel(
                          label: 'THIS MONTH',
                          value: formatBytes(device.monthBytes),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _QuotaProgress(device: device),
                ],
              ),
            )
          else
            SurfaceCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.query_stats_rounded,
                    color: FlyxColors.yellow,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'FlyX exposes this device and its Wi-Fi association, but we have not yet verified per-device byte counters on your MTN firmware. FlyX Control will not label Wi-Fi link speed as data usage.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: FlyxColors.muted,
                          ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),
          const SectionTitle(title: 'Access schedule'),
          const SizedBox(height: 10),
          SurfaceCard(
            onTap: canSchedule
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DeviceScheduleScreen(
                          deviceId: device.id,
                        ),
                      ),
                    )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  schedule?.isActiveAt(DateTime.now()) == true
                      ? Icons.wifi_off_rounded
                      : Icons.schedule_rounded,
                  color: canSchedule ? FlyxColors.yellow : FlyxColors.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        canSchedule
                            ? schedule == null
                                ? 'No schedule'
                                : schedule.enabled
                                    ? schedule.summary
                                    : 'Disabled · ${schedule.summary}'
                            : 'Waiting for router support',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        canSchedule
                            ? schedule == null
                                ? 'Set repeating hours when this device should be disconnected from FlyX.'
                                : schedule.isActiveAt(DateTime.now())
                                    ? 'This device is currently inside its blocked window.'
                                    : 'Manage days, hours, and whether this rule is enabled.'
                            : 'FlyX Control only enables schedules when the router exposes a readable Parent Control rule list.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: FlyxColors.muted,
                            ),
                      ),
                    ],
                  ),
                ),
                if (canSchedule) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: FlyxColors.muted,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          const SectionTitle(title: 'Data limit'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasTraffic && canBlock
                      ? (device.policy.dataLimitBytes == null
                          ? 'No limit'
                          : '${formatBytes(device.policy.dataLimitBytes!)} / ${_period(device.policy.period)}')
                      : 'Waiting for router support',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 7),
                Text(
                  hasTraffic && canBlock
                      ? 'When the quota is reached, FlyX Control can pause this device automatically.'
                      : 'A reliable quota needs both per-device traffic accounting and a verified router-side block action. We have not enabled either prematurely.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: FlyxColors.muted,
                      ),
                ),
                if (hasTraffic && canBlock) ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => _setLimit(context, device),
                    child: const Text('Set data limit'),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          const SectionTitle(title: 'Performance'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: hasTraffic
                ? Row(
                    children: [
                      Expanded(
                        child: MetricLabel(
                          label: 'DOWNLOAD NOW',
                          value: formatRate(device.rxBytesPerSecond),
                        ),
                      ),
                      Expanded(
                        child: MetricLabel(
                          label: 'UPLOAD NOW',
                          value: formatRate(device.txBytesPerSecond),
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Per-device internet throughput is not available yet. The Network screen can still calculate the FlyX connection’s total live download and upload speed from the router’s WAN byte counters.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: FlyxColors.muted,
                        ),
                  ),
          ),

          const SizedBox(height: 24),
          const SectionTitle(title: 'Device info'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                _InfoRow(label: 'Hostname', value: device.hostname),
                const Divider(height: 24),
                _InfoRow(
                  label: device.online ? 'IP address' : 'Last IP address',
                  value: device.ip,
                ),
                const Divider(height: 24),
                _InfoRow(label: 'MAC address', value: device.mac),
                if (device.firstSeen != null) ...[
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'First observed',
                    value: _formatDate(device.firstSeen!),
                  ),
                ],
                if (!device.online) ...[
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'Last observed',
                    value: _formatDate(device.lastSeen),
                  ),
                ],
                if (device.dhcpLeaseExpires != null && device.online) ...[
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'DHCP lease until',
                    value: _formatDate(device.dhcpLeaseExpires!),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          if (canBlock)
            SizedBox(
              height: 54,
              child: device.blocked
                  ? FilledButton.icon(
                      onPressed: () => _toggleBlock(context, device, false),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Unblock device'),
                    )
                  : OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FlyxColors.danger,
                        side: const BorderSide(color: Color(0x55FF6B6B)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => _toggleBlock(context, device, true),
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('Block device'),
                    ),
            )
          else
            SurfaceCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: FlyxColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      controller.capabilities.blocking
                          ? 'Instant Block is available for devices currently identified on FlyX Wi-Fi. This device is not currently associated with a Wi-Fi band.'
                          : 'Block / Unblock is unavailable because the router’s Wi-Fi deny-list path is not available.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: FlyxColors.muted,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _cleanMbps(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)} · '
        '${two(local.day)}/${two(local.month)}';
  }

  static String _period(LimitPeriod period) => switch (period) {
        LimitPeriod.daily => 'day',
        LimitPeriod.weekly => 'week',
        LimitPeriod.monthly => 'month',
      };

  Future<void> _toggleBlock(
    BuildContext context,
    FlyxDevice device,
    bool blocked,
  ) async {
    if (blocked) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Block ${device.name}?'),
          content: const Text(
            'This device will lose internet access until you unblock it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (yes != true || !context.mounted) return;
    }

    try {
      await AppScope.of(context).setBlocked(device.id, blocked);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _renameDevice(
    BuildContext context,
    FlyxDevice device,
  ) async {
    var draft = device.name == device.hostname ? '' : device.name;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: draft,
              autofocus: true,
              maxLength: 48,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (value) => draft = value,
              decoration: InputDecoration(
                labelText: 'Friendly name',
                hintText: device.hostname,
              ),
            ),
            Text(
              'Stored only in FlyX Control. Leave it blank to use the router hostname.',
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: FlyxColors.muted,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || !context.mounted) return;

    try {
      await AppScope.of(context).setDeviceName(device.id, result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _setLimit(
    BuildContext context,
    FlyxDevice device,
  ) async {
    final existingGb = device.policy.dataLimitBytes == null
        ? ''
        : (device.policy.dataLimitBytes! / 1073741824).toStringAsFixed(0);
    final text = TextEditingController(text: existingGb);
    var period = device.policy.period;

    final result = await showModalBottomSheet<DevicePolicy>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlyxColors.surface,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            20,
            18,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set data limit',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Set a quota for this device. Leave the amount blank to remove the limit.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FlyxColors.muted,
                    ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: text,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Allowance in GB',
                  hintText: '10',
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<LimitPeriod>(
                segments: const [
                  ButtonSegment(
                    value: LimitPeriod.daily,
                    label: Text('Daily'),
                  ),
                  ButtonSegment(
                    value: LimitPeriod.weekly,
                    label: Text('Weekly'),
                  ),
                  ButtonSegment(
                    value: LimitPeriod.monthly,
                    label: Text('Monthly'),
                  ),
                ],
                selected: {period},
                onSelectionChanged: (value) =>
                    setModalState(() => period = value.first),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final gb = double.tryParse(text.text.trim());
                  final bytes =
                      gb == null ? null : (gb * 1073741824).round();
                  Navigator.pop(
                    context,
                    DevicePolicy(
                      dataLimitBytes: bytes,
                      period: period,
                      pauseWhenLimitReached: true,
                    ),
                  );
                },
                child: const Text('Save limit'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    try {
      await AppScope.of(context).setDevicePolicy(device.id, result);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.device,
    required this.hasTraffic,
    required this.onRename,
  });

  final FlyxDevice device;
  final bool hasTraffic;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      emphasized: true,
      child: Column(
        children: [
          Row(
            children: [
              DeviceGlyph(
                kind: device.kind,
                blocked: device.blocked,
                size: 58,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Rename device',
                          onPressed: onRename,
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Builder(
                      builder: (context) {
                        final scheduled =
                            device.parentControlSchedule?.isActiveAt(
                                  DateTime.now(),
                                ) ??
                                false;
                        return StatusDot(
                          online: device.online && !device.blocked,
                          label: scheduled
                              ? 'Scheduled block'
                              : device.blocked
                                  ? 'Blocked'
                                  : device.online
                                      ? 'Online'
                                      : 'Offline',
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (device.online && !device.blocked) ...[
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 17),
            Row(
              children: [
                if (hasTraffic) ...[
                  Expanded(
                    child: MetricLabel(
                      label: 'DOWN',
                      value: '↓ ${formatRate(device.rxBytesPerSecond)}',
                    ),
                  ),
                  Expanded(
                    child: MetricLabel(
                      label: 'UP',
                      value: '↑ ${formatRate(device.txBytesPerSecond)}',
                    ),
                  ),
                ] else
                  Expanded(
                    child: MetricLabel(
                      label: 'CONNECTION',
                      value: device.wifiBand.isEmpty
                          ? 'Wi-Fi'
                          : device.wifiBand,
                    ),
                  ),
                MetricLabel(
                  label: 'SIGNAL',
                  value: device.wifiRssiDbm == null
                      ? (device.signalPercent == 0
                          ? '—'
                          : '${device.signalPercent}%')
                      : '${device.wifiRssiDbm} dBm',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuotaProgress extends StatelessWidget {
  const _QuotaProgress({required this.device});
  final FlyxDevice device;

  @override
  Widget build(BuildContext context) {
    final limit = device.policy.dataLimitBytes;
    if (limit == null || limit <= 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No quota set',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: FlyxColors.muted,
              ),
        ),
      );
    }

    final used = switch (device.policy.period) {
      LimitPeriod.daily => device.todayBytes,
      LimitPeriod.weekly => device.weekBytes,
      LimitPeriod.monthly => device.monthBytes,
    };
    final fraction = (used / limit).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${(fraction * 100).toStringAsFixed(0)}% of limit',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Text(
              '${formatBytes(used)} / ${formatBytes(limit)}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: FlyxColors.muted,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 9,
            backgroundColor: FlyxColors.line,
            valueColor: AlwaysStoppedAnimation(
              fraction >= .9 ? FlyxColors.danger : FlyxColors.yellow,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: FlyxColors.muted,
                ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}
