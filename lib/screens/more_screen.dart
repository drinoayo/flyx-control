import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'connect_router_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final c = controller.capabilities;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          const AppTopBar(subtitle: 'TOOLS & ROUTER CONTROLS', title: 'More'),
          const SizedBox(height: 22),
          SurfaceCard(
            emphasized: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectRouterScreen())),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: FlyxColors.yellow, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.router_rounded, color: FlyxColors.ink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Connect your real FlyX', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('192.168.0.1 · ZLT X17U capability scan', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Everyday controls'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                _FeatureRow(icon: Icons.wifi_rounded, title: 'Wi-Fi', subtitle: 'SSID, password, QR sharing', enabled: c.wifiSettings),
                const Divider(height: 24, indent: 46),
                _FeatureRow(icon: Icons.sms_outlined, title: 'Messages', subtitle: 'A proper inbox for router SMS', enabled: c.sms),
                const Divider(height: 24, indent: 46),
                _FeatureRow(icon: Icons.dialpad_rounded, title: 'USSD', subtitle: 'Quick actions and custom codes', enabled: c.ussd),
                const Divider(height: 24, indent: 46),
                _FeatureRow(icon: Icons.shield_outlined, title: 'Blocked devices', subtitle: 'See and restore denied devices', enabled: c.blocking),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Router'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                _FeatureRow(icon: Icons.radar_rounded, title: 'Capability scan', subtitle: '${c.discoveredActions.length} actions discovered', enabled: true),
                const Divider(height: 24, indent: 46),
                _FeatureRow(icon: Icons.data_usage_rounded, title: 'Usage history', subtitle: c.perDeviceTraffic ? 'Per-device counters available' : 'Local history engine ready', enabled: true),
                const Divider(height: 24, indent: 46),
                _FeatureRow(icon: Icons.restart_alt_rounded, title: 'Restart FlyX', subtitle: 'Reboot the router safely', enabled: c.reboot, onTap: c.reboot ? () => _reboot(context) : null),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Capability status'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Capability(label: 'Devices', active: c.stationList),
                _Capability(label: 'Block', active: c.blocking),
                _Capability(label: 'Traffic', active: c.perDeviceTraffic),
                _Capability(label: 'SMS', active: c.sms),
                _Capability(label: 'USSD', active: c.ussd),
                _Capability(label: 'Wi-Fi', active: c.wifiSettings),
                _Capability(label: 'Network mode', active: c.networkMode),
                _Capability(label: 'QoS', active: c.qos),
              ],
            ),
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 18),
            SurfaceCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: FlyxColors.warning),
                  const SizedBox(width: 12),
                  Expanded(child: Text(controller.error!, style: Theme.of(context).textTheme.bodyMedium)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reboot(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart FlyX?'),
        content: const Text('Everyone will briefly lose internet access while the router restarts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restart')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await AppScope.of(context).reboot();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.subtitle, required this.enabled, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
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
          Icon(enabled ? Icons.chevron_right_rounded : Icons.lock_outline_rounded, color: FlyxColors.muted, size: 20),
        ],
      ),
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: (active ? FlyxColors.success : FlyxColors.muted).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: (active ? FlyxColors.success : FlyxColors.muted).withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? Icons.check_circle_rounded : Icons.pending_outlined, size: 14, color: active ? FlyxColors.success : FlyxColors.muted),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: active ? FlyxColors.success : FlyxColors.muted)),
        ],
      ),
    );
  }
}
