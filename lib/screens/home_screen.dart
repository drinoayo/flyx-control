import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'device_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<double> _history = [];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final network = controller.network;
    final online = controller.devices.where((d) => d.online && !d.blocked).toList()
      ..sort((a, b) => b.totalRate.compareTo(a.totalRate));

    if (network != null) {
      _history.add(network.downloadBytesPerSecond / 1000000);
      if (_history.length > 26) _history.removeAt(0);
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        color: FlyxColors.ink,
        backgroundColor: FlyxColors.yellow,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            AppTopBar(
              subtitle: 'MTN FLYX',
              title: 'Your network',
              trailing: StatusDot(online: network?.connected ?? false),
            ),
            const SizedBox(height: 22),
            if (network == null)
              const _LoadingHero()
            else
              _NetworkHero(network: network, history: List.of(_history)),
            const SizedBox(height: 25),
            Row(
              children: [
                QuickAction(
                  icon: Icons.wifi_rounded,
                  label: 'Wi-Fi',
                  onTap: () => _notReady(context, 'Wi-Fi controls'),
                ),
                const SizedBox(width: 10),
                QuickAction(
                  icon: Icons.sms_outlined,
                  label: 'Messages',
                  onTap: () => _notReady(context, 'SMS inbox'),
                ),
                const SizedBox(width: 10),
                QuickAction(
                  icon: Icons.dialpad_rounded,
                  label: 'USSD',
                  onTap: () => _notReady(context, 'USSD'),
                ),
                const SizedBox(width: 10),
                QuickAction(
                  icon: Icons.radar_rounded,
                  label: 'Signal',
                  onTap: () => _notReady(context, 'Signal Finder'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            SectionTitle(
              title: '${online.length} device${online.length == 1 ? '' : 's'} online',
              action: 'View all',
              onAction: () {},
            ),
            const SizedBox(height: 10),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < online.take(3).length; i++) ...[
                    _HomeDeviceRow(
                      device: online[i],
                      hasTraffic: controller.capabilities.perDeviceTraffic,
                    ),
                    if (i < online.take(3).length - 1)
                      const Divider(height: 1, indent: 72, endIndent: 18),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionTitle(title: 'Data usage'),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricLabel(
                          label: 'TODAY',
                          value: network == null
                              ? '—'
                              : formatBytes(network.todayBytes),
                        ),
                      ),
                      Expanded(
                        child: MetricLabel(
                          label: 'THIS MONTH',
                          value: network == null
                              ? '—'
                              : formatBytes(network.monthBytes),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  UsageBars(points: controller.weeklyUsage),
                  const SizedBox(height: 8),
                  Text(
                    'Daily history is calculated locally from the router’s cumulative WAN counters.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: FlyxColors.muted,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionTitle(title: 'Reliability'),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricLabel(
                          label: 'Router uptime',
                          value: network == null
                              ? '—'
                              : formatDuration(network.routerUptime),
                        ),
                      ),
                      Container(width: 1, height: 44, color: FlyxColors.line),
                      const SizedBox(width: 18),
                      Expanded(
                        child: MetricLabel(
                          label: 'Observed internet uptime',
                          value: network == null
                              ? '—'
                              : network.internetObservationDuration ==
                                      Duration.zero
                                  ? 'Collecting'
                                  : '${network.internetUptimePercent.toStringAsFixed(1)}%',
                          valueColor: network != null &&
                                  network.internetObservationDuration !=
                                      Duration.zero
                              ? FlyxColors.success
                              : FlyxColors.muted,
                        ),
                      ),
                    ],
                  ),
                  if (network != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      network.internetObservationDuration == Duration.zero
                          ? 'FlyX Control starts calculating reliability while the app is observing the router.'
                          : 'Tracked while FlyX Control is running · ${network.outagesToday} outage${network.outagesToday == 1 ? '' : 's'} observed today.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: FlyxColors.muted,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _notReady(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is already in the product map and will be wired to the X17U capability scan.')),
    );
  }
}

class _LoadingHero extends StatelessWidget {
  const _LoadingHero();

  @override
  Widget build(BuildContext context) {
    return const SurfaceCard(
      child: SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
    );
  }
}

class _NetworkHero extends StatelessWidget {
  const _NetworkHero({required this.network, required this.history});
  final NetworkSnapshot network;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D2026), Color(0xFF101216)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF323842)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: FlyxColors.yellow,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  network.networkType,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: FlyxColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 9),
              Text(network.carrier, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: FlyxColors.muted)),
              const Spacer(),
              Icon(Icons.signal_cellular_alt_rounded, color: network.gradeColor, size: 20),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${network.rsrp}', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 46)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 5),
                child: Text('dBm', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: network.gradeColor.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  network.gradeLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: network.gradeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LiveSparkline(values: history),
          const SizedBox(height: 17),
          const Divider(height: 1),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: MetricLabel(
                  label: 'DOWNLOAD',
                  value: '↓ ${formatRate(network.downloadBytesPerSecond)}',
                ),
              ),
              Expanded(
                child: MetricLabel(
                  label: 'UPLOAD',
                  value: '↑ ${formatRate(network.uploadBytesPerSecond)}',
                ),
              ),
              MetricLabel(
                label: 'LATENCY',
                value: network.latencyMs <= 0
                    ? '—'
                    : '${network.latencyMs} ms',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeDeviceRow extends StatelessWidget {
  const _HomeDeviceRow({
    required this.device,
    required this.hasTraffic,
  });

  final FlyxDevice device;
  final bool hasTraffic;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DeviceDetailScreen(deviceId: device.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            DeviceGlyph(kind: device.kind, blocked: device.blocked),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(
                    hasTraffic
                        ? '↓ ${formatRate(device.rxBytesPerSecond)}  ·  ${formatBytes(device.todayBytes)} today'
                        : [
                            if (device.wifiBand.isNotEmpty) device.wifiBand,
                            if (device.wifiRssiDbm != null)
                              '${device.wifiRssiDbm} dBm',
                          ].join(' · ').isEmpty
                            ? 'Connected'
                            : [
                                if (device.wifiBand.isNotEmpty)
                                  device.wifiBand,
                                if (device.wifiRssiDbm != null)
                                  '${device.wifiRssiDbm} dBm',
                              ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: FlyxColors.muted,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: FlyxColors.muted),
          ],
        ),
      ),
    );
  }
}
