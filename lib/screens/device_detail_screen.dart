import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final device = controller.deviceById(deviceId);
    if (device == null) {
      return const Scaffold(body: Center(child: Text('Device is no longer available.')));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlyxColors.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(device.name),
        actions: [
          IconButton(
            onPressed: () => _rename(context, device),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
        children: [
          _Header(device: device),
          const SizedBox(height: 24),
          const SectionTitle(title: 'Usage'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: MetricLabel(label: 'TODAY', value: formatBytes(device.todayBytes))),
                    Expanded(child: MetricLabel(label: 'THIS WEEK', value: formatBytes(device.weekBytes))),
                    Expanded(child: MetricLabel(label: 'THIS MONTH', value: formatBytes(device.monthBytes))),
                  ],
                ),
                const SizedBox(height: 20),
                _QuotaProgress(device: device),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.policy.dataLimitBytes == null
                            ? 'No limit'
                            : '${formatBytes(device.policy.dataLimitBytes!)} / ${_period(device.policy.period)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _setLimit(context, device),
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'When the quota is reached, FlyX Control can pause this device automatically when the router exposes a compatible blocking rule.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle(title: 'Performance'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: MetricLabel(label: 'DOWNLOAD NOW', value: formatRate(device.rxBytesPerSecond))),
                    Expanded(child: MetricLabel(label: 'UPLOAD NOW', value: formatRate(device.txBytesPerSecond))),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: MetricLabel(label: 'CURRENT SESSION', value: formatDuration(device.currentSession))),
                    Expanded(child: MetricLabel(label: 'ONLINE TODAY', value: formatDuration(device.totalOnlineToday))),
                  ],
                ),
              ],
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
                _InfoRow(label: 'IP address', value: device.ip),
                const Divider(height: 24),
                _InfoRow(label: 'MAC address', value: device.mac),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _toggleBlock(context, device, true),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Block device'),
                  ),
          ),
        ],
      ),
    );
  }

  static String _period(LimitPeriod period) => switch (period) {
        LimitPeriod.daily => 'day',
        LimitPeriod.weekly => 'week',
        LimitPeriod.monthly => 'month',
      };

  Future<void> _toggleBlock(BuildContext context, FlyxDevice device, bool blocked) async {
    if (blocked) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Block ${device.name}?'),
          content: const Text('This device will lose internet access until you unblock it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block')),
          ],
        ),
      );
      if (yes != true) return;
    }
    try {
      await AppScope.of(context).setBlocked(device.id, blocked);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _rename(BuildContext context, FlyxDevice device) async {
    final text = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(controller: text, autofocus: true, decoration: const InputDecoration(hintText: 'Device name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, text.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await AppScope.of(context).setDeviceName(device.id, name);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _setLimit(BuildContext context, FlyxDevice device) async {
    final existingGb = device.policy.dataLimitBytes == null ? '' : (device.policy.dataLimitBytes! / 1073741824).toStringAsFixed(0);
    final text = TextEditingController(text: existingGb);
    var period = device.policy.period;
    final result = await showModalBottomSheet<DevicePolicy>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlyxColors.surface,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(18, 20, 18, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set data limit', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Set a quota for this device. Leave the amount blank to remove the limit.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted)),
              const SizedBox(height: 18),
              TextField(
                controller: text,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Allowance in GB', hintText: '10'),
              ),
              const SizedBox(height: 14),
              SegmentedButton<LimitPeriod>(
                segments: const [
                  ButtonSegment(value: LimitPeriod.daily, label: Text('Daily')),
                  ButtonSegment(value: LimitPeriod.weekly, label: Text('Weekly')),
                  ButtonSegment(value: LimitPeriod.monthly, label: Text('Monthly')),
                ],
                selected: {period},
                onSelectionChanged: (value) => setModalState(() => period = value.first),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final gb = double.tryParse(text.text.trim());
                  final bytes = gb == null ? null : (gb * 1073741824).round();
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
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.device});
  final FlyxDevice device;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      emphasized: true,
      child: Column(
        children: [
          Row(
            children: [
              DeviceGlyph(kind: device.kind, blocked: device.blocked, size: 58),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 5),
                    StatusDot(
                      online: device.online && !device.blocked,
                      label: device.blocked ? 'Blocked' : device.online ? 'Online' : 'Offline',
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
                Expanded(child: MetricLabel(label: 'DOWN', value: '↓ ${formatRate(device.rxBytesPerSecond)}')),
                Expanded(child: MetricLabel(label: 'UP', value: '↑ ${formatRate(device.txBytesPerSecond)}')),
                MetricLabel(label: 'WI-FI', value: '${device.signalPercent}%'),
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
        child: Text('No quota set', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted)),
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
            Expanded(child: Text('${(fraction * 100).toStringAsFixed(0)}% of limit', style: Theme.of(context).textTheme.labelMedium)),
            Text('${formatBytes(used)} / ${formatBytes(limit)}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: FlyxColors.muted)),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 9,
            backgroundColor: FlyxColors.line,
            valueColor: AlwaysStoppedAnimation(fraction >= .9 ? FlyxColors.danger : FlyxColors.yellow),
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
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted))),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}
