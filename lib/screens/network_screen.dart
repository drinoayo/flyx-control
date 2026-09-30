import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final List<double> signalHistory = [-98, -98, -97, -96, -97, -95, -96, -94, -96, -97, -95, -96];

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
                            child: Text('dBm RSRP', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted)),
                          ),
                          const Spacer(),
                          Text(n.gradeLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: n.gradeColor)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LiveSparkline(values: signalHistory),
                      const SizedBox(height: 18),
                      Text(
                        'Signal Finder can turn this into a full-screen meter with haptics while you reposition the ODU.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted),
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
                        valueColor: n.latencyMs == 0 ? FlyxColors.muted : FlyxColors.success,
                      ),
                      const Divider(height: 24, indent: 46),
                      _HealthRow(
                        icon: Icons.waterfall_chart_rounded,
                        title: 'Packet loss',
                        value: n.packetLossPercent == 0 ? 'Collecting' : '${n.packetLossPercent.toStringAsFixed(1)}%',
                        valueColor: n.packetLossPercent <= .5 ? FlyxColors.success : FlyxColors.warning,
                      ),
                      const Divider(height: 24, indent: 46),
                      _HealthRow(
                        icon: Icons.restart_alt_rounded,
                        title: 'Router uptime',
                        value: n.routerUptime == Duration.zero ? 'Waiting for router field' : formatDuration(n.routerUptime),
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
          const SizedBox(height: 26),
          const SectionTitle(title: 'Advanced controls'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                _ControlRow(
                  icon: Icons.tune_rounded,
                  title: 'Network mode',
                  subtitle: controller.capabilities.networkMode ? 'Automatic · 4G · 5G options available' : 'Awaiting X17U capability mapping',
                  enabled: controller.capabilities.networkMode,
                ),
                const Divider(height: 24, indent: 46),
                const _ControlRow(
                  icon: Icons.cell_tower_rounded,
                  title: 'Band & cell controls',
                  subtitle: 'Shown only after the firmware exposes supported fields',
                  enabled: false,
                ),
                const Divider(height: 24, indent: 46),
                const _ControlRow(
                  icon: Icons.radar_rounded,
                  title: 'Signal Finder',
                  subtitle: 'Large live meter, haptics and best-position tracking',
                  enabled: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
        Icon(icon, color: FlyxColors.yellow, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        Text(value, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: valueColor)),
      ],
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.icon, required this.title, required this.subtitle, required this.enabled});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: enabled ? FlyxColors.yellow : FlyxColors.muted, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right_rounded, color: enabled ? Colors.white : FlyxColors.muted),
      ],
    );
  }
}
