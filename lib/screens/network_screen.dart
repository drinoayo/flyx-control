import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'network_mode_screen.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final List<double> signalHistory = [];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final n = controller.network;
    if (n != null) {
      signalHistory.add(n.rsrp.toDouble());
      if (signalHistory.length > 28) signalHistory.removeAt(0);
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          AppTopBar(
            subtitle: 'LIVE RADIO + INTERNET HEALTH',
            title: 'Network',
            trailing: n == null ? null : StatusDot(online: n.connected, label: n.networkType),
          ),
          const SizedBox(height: 22),
          SurfaceCard(
            emphasized: true,
            child: n == null
                ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${n.rsrp}', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 48)),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7, left: 5),
                            child: Text('dBm RSRP', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.mutedFor(context))),
                          ),
                          const Spacer(),
                          Text(n.gradeLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: n.gradeColor)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LiveSparkline(values: signalHistory),
                      const SizedBox(height: 18),
                      Text(
                        'Move or reposition the router and watch the live RSRP graph to compare signal quality.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: FlyxColors.mutedFor(context)),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Radio details'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: n == null
                ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: MetricLabel(label: 'RSRP', value: '${n.rsrp} dBm')),
                          Expanded(child: MetricLabel(label: 'RSRQ', value: '${n.rsrq} dB')),
                          Expanded(child: MetricLabel(label: 'SINR', value: '${n.sinr} dB')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(child: MetricLabel(label: 'PCI', value: '${n.pci}')),
                          Expanded(child: MetricLabel(label: 'LTE BAND', value: n.lteBand)),
                          Expanded(child: MetricLabel(label: '5G BAND', value: n.nrBand)),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Data usage'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: n == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: MetricLabel(
                              label: 'TODAY',
                              value: formatBytes(n.todayBytes),
                            ),
                          ),
                          Expanded(
                            child: MetricLabel(
                              label: 'THIS MONTH',
                              value: formatBytes(n.monthBytes),
                            ),
                          ),
                        ],
                      ),
                      if (n.monthDownloadBytes > 0 ||
                          n.monthUploadBytes > 0) ...[
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: MetricLabel(
                                label: 'MONTH DOWNLOAD',
                                value: formatBytes(n.monthDownloadBytes),
                              ),
                            ),
                            Expanded(
                              child: MetricLabel(
                                label: 'MONTH UPLOAD',
                                value: formatBytes(n.monthUploadBytes),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Monthly totals come from FlyX. Daily history is derived locally from verified WAN counters.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: FlyxColors.mutedFor(context),
                              ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Connection health'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: n == null
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      _HealthRow(
                        icon: Icons.speed_rounded,
                        title: 'Latency',
                        value: n.latencyMs == 0 ? 'Collecting' : '${n.latencyMs} ms',
                        valueColor: n.latencyMs == 0 ? FlyxColors.mutedFor(context) : FlyxColors.successFor(context),
                      ),
                      const Divider(height: 24, indent: 46),
                      _HealthRow(
                        icon: Icons.waterfall_chart_rounded,
                        title: 'Packet loss',
                        value: n.packetLossPercent == 0 ? 'Collecting' : '${n.packetLossPercent.toStringAsFixed(1)}%',
                        valueColor: n.packetLossPercent == 0
                            ? FlyxColors.mutedFor(context)
                            : n.packetLossPercent <= .5
                                ? FlyxColors.successFor(context)
                                : FlyxColors.warningFor(context),
                      ),
                      const Divider(height: 24, indent: 46),
                      _HealthRow(
                        icon: Icons.restart_alt_rounded,
                        title: 'Router uptime',
                        value: n.routerUptime == Duration.zero
                            ? 'Waiting for router field'
                            : formatDuration(n.routerUptime),
                      ),
                      const Divider(height: 24, indent: 46),
                      _HealthRow(
                        icon: Icons.public_rounded,
                        title: 'Observed internet uptime',
                        value: n.internetObservationDuration == Duration.zero
                            ? 'Collecting'
                            : '${n.internetUptimePercent.toStringAsFixed(1)}%',
                        valueColor:
                            n.internetObservationDuration == Duration.zero
                                ? FlyxColors.mutedFor(context)
                                : FlyxColors.successFor(context),
                      ),
                      const Divider(height: 24, indent: 46),
                      _HealthRow(
                        icon: Icons.history_toggle_off_rounded,
                        title: 'Observed outages today',
                        value: n.internetObservationDuration == Duration.zero
                            ? 'Collecting'
                            : '${n.outagesToday}',
                        valueColor:
                            n.internetObservationDuration == Duration.zero
                                ? FlyxColors.mutedFor(context)
                                : n.outagesToday == 0
                                    ? FlyxColors.successFor(context)
                                    : FlyxColors.warningFor(context),
                      ),
                      const Divider(height: 24, indent: 46),
                      _HealthRow(
                        icon: Icons.bolt_rounded,
                        title: 'Current traffic',
                        value: '↓ ${formatRate(n.downloadBytesPerSecond)}  ↑ ${formatRate(n.uploadBytesPerSecond)}',
                      ),
                    ],
                  ),
          ),
          if (n != null && n.recentOutages.isNotEmpty) ...[
            const SizedBox(height: 26),
            const SectionTitle(title: 'Recent observed outages'),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Column(
                children: [
                  for (var i = 0; i < n.recentOutages.length; i++) ...[
                    _OutageRow(outage: n.recentOutages[i]),
                    if (i + 1 < n.recentOutages.length)
                      const Divider(height: 22, indent: 42),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'These are only outages FlyX Control continuously observed. Monitoring gaps are excluded.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: FlyxColors.mutedFor(context),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (n != null &&
              (n.routerCpuPercent != null ||
                  n.routerTemperatureC != null ||
                  n.routerMemoryFreeBytes != null ||
                  n.firmwareVersion.isNotEmpty)) ...[
            const SizedBox(height: 26),
            const SectionTitle(title: 'Router health'),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Column(
                children: [
                  if (n.routerCpuPercent != null)
                    _HealthRow(
                      icon: Icons.memory_rounded,
                      title: 'CPU usage',
                      value: '${n.routerCpuPercent!.toStringAsFixed(1)}%',
                    ),
                  if (n.routerCpuPercent != null &&
                      n.routerTemperatureC != null)
                    const Divider(height: 24, indent: 46),
                  if (n.routerTemperatureC != null)
                    _HealthRow(
                      icon: Icons.device_thermostat_rounded,
                      title: 'Temperature',
                      value: '${n.routerTemperatureC!.toStringAsFixed(0)} °C',
                      valueColor: n.routerTemperatureC! >= 70
                          ? FlyxColors.warningFor(context)
                          : FlyxColors.successFor(context),
                    ),
                  if (n.routerTemperatureC != null &&
                      n.routerMemoryFreeBytes != null)
                    const Divider(height: 24, indent: 46),
                  if (n.routerMemoryFreeBytes != null)
                    _HealthRow(
                      icon: Icons.storage_rounded,
                      title: 'Free memory',
                      value: formatBytes(n.routerMemoryFreeBytes!),
                    ),
                  if (n.firmwareVersion.isNotEmpty) ...[
                    const Divider(height: 24, indent: 46),
                    _HealthRow(
                      icon: Icons.system_update_alt_rounded,
                      title: 'Firmware',
                      value: n.firmwareVersion,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (controller.capabilities.networkMode) ...[
            const SizedBox(height: 26),
            const SectionTitle(title: 'Mobile network'),
            const SizedBox(height: 10),
            SurfaceCard(
              child: _ControlRow(
                icon: Icons.tune_rounded,
                title: 'Network settings',
                subtitle: 'Automatic mode, mobile data, roaming and Flight Mode',
                enabled: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NetworkModeScreen(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OutageRow extends StatelessWidget {
  const _OutageRow({required this.outage});

  final ObservedOutage outage;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final duration = outage.durationAt(now);
    final restored = outage.restoredAt;
    final subtitle = restored == null
        ? 'Ongoing · ${formatDuration(duration)} observed'
        : '${_formatOutageClock(outage.startedAt)}–${_formatOutageClock(restored)} · ${formatDuration(duration)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          restored == null ? Icons.cloud_off_rounded : Icons.history_rounded,
          color: restored == null ? FlyxColors.warningFor(context) : FlyxColors.mutedFor(context),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_formatOutageDate(outage.startedAt)} outage',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: FlyxColors.mutedFor(context),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatOutageDate(DateTime value) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}';
}

String _formatOutageClock(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final suffix = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.icon, required this.title, required this.value, this.valueColor});
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: FlyxColors.accentFor(context), size: 22),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        Text(value, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: valueColor)),
      ],
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          Icon(
            icon,
            color: enabled ? FlyxColors.accentFor(context) : FlyxColors.mutedFor(context),
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: FlyxColors.mutedFor(context),
                      ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: FlyxColors.mutedFor(context),
            ),
        ],
      ),
    );
  }
}
