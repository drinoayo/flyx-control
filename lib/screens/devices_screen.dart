import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'device_detail_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  int filter = 0;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final all = controller.devices;
    final online = all.where((d) => d.online && !d.blocked).toList();
    final blocked = all.where((d) => d.blocked).toList();
    final visible = switch (filter) { 1 => online, 2 => blocked, _ => all };

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: AppTopBar(
              subtitle: 'CONTROL WHO CONNECTS',
              title: 'Devices',
              trailing: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: FlyxColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: FlyxColors.line),
                ),
                child: IconButton(
                  tooltip: 'Refresh',
                  onPressed: controller.refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                _FilterChip(label: 'All ${all.length}', selected: filter == 0, onTap: () => setState(() => filter = 0)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Online ${online.length}', selected: filter == 1, onTap: () => setState(() => filter = 1)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Blocked ${blocked.length}', selected: filter == 2, onTap: () => setState(() => filter = 2)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: visible.isEmpty
                ? _EmptyDevices(filter: filter)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _DeviceCard(device: visible[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? FlyxColors.yellow : FlyxColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? FlyxColors.yellow : FlyxColors.line),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? FlyxColors.ink : Colors.white,
              ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final FlyxDevice device;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DeviceDetailScreen(deviceId: device.id)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              DeviceGlyph(kind: device.kind, blocked: device.blocked, size: 48),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(device.name, style: Theme.of(context).textTheme.titleMedium)),
                        if (device.blocked) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.block_rounded, size: 15, color: FlyxColors.danger),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.blocked
                          ? 'Blocked'
                          : device.online
                              ? '${device.ip} · ${device.signalPercent}% Wi-Fi'
                              : 'Last seen ${_lastSeen(device.lastSeen)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: device.blocked ? FlyxColors.danger : FlyxColors.muted,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: FlyxColors.muted),
            ],
          ),
          if (device.online && !device.blocked) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: MetricLabel(label: 'LIVE', value: '↓ ${formatRate(device.rxBytesPerSecond)}')),
                Expanded(child: MetricLabel(label: 'TODAY', value: formatBytes(device.todayBytes))),
                Expanded(child: MetricLabel(label: 'ONLINE', value: formatDuration(device.currentSession))),
              ],
            ),
          ] else if (device.blocked) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final controller = AppScope.of(context);
                  try {
                    await controller.setBlocked(device.id, false);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Unblock device'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _lastSeen(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.filter});
  final int filter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.devices_other_rounded, color: FlyxColors.muted, size: 42),
            const SizedBox(height: 14),
            Text(filter == 2 ? 'No blocked devices' : 'No devices found', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(
              filter == 2 ? 'Devices you block will stay visible here.' : 'Connect a device to FlyX and it will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
