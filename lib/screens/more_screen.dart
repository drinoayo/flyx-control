import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/app_scope.dart';
import '../state/appearance_scope.dart';
import '../services/widget_sync_service.dart';
import '../widgets/common.dart';
import 'connect_router_screen.dart';
import 'messages_screen.dart';
import 'network_mode_screen.dart';
import 'ussd_screen.dart';
import 'wifi_settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final appearance = AppearanceScope.of(context);
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
                      Text(
                        'Router connection',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage credentials or run a fresh X17U capability scan',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: FlyxColors.mutedFor(context),
                            ),
                      ),
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
                _FeatureRow(
                  icon: Icons.wifi_rounded,
                  title: 'Wi-Fi',
                  subtitle: 'SSID, password and network visibility',
                  enabled: c.wifiSettings,
                  onTap: c.wifiSettings
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WifiSettingsScreen(),
                            ),
                          )
                      : null,
                ),
                const Divider(height: 24, indent: 46),
                _FeatureRow(
                  icon: Icons.sms_outlined,
                  title: 'Messages',
                  subtitle: 'Inbox, replies and new router SMS',
                  enabled: c.sms,
                  onTap: c.sms
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MessagesScreen(),
                            ),
                          )
                      : null,
                ),
                const Divider(height: 24, indent: 46),
                _FeatureRow(
                  icon: Icons.dialpad_rounded,
                  title: 'USSD',
                  subtitle: 'Custom codes and interactive replies',
                  enabled: c.ussd,
                  onTap: c.ussd
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const UssdScreen(),
                            ),
                          )
                      : null,
                ),

              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Home screen'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: _FeatureRow(
              icon: Icons.widgets_rounded,
              title: 'Add FlyX widget',
              subtitle: 'Choose a design, 1–4 details, and light or dark appearance',
              enabled: true,
              onTap: () => _addWidget(context),
            ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Appearance'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                  label: Text('Dark'),
                ),
              ],
              selected: {appearance.value},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  appearance.setMode(selection.first);
                }
              },
            ),
          ),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Router'),
          const SizedBox(height: 10),
          SurfaceCard(
            child: Column(
              children: [
                _FeatureRow(
                  icon: Icons.radar_rounded,
                  title: 'Capabilities',
                  subtitle: '${c.discoveredActions.length} router actions verified',
                  enabled: true,
                ),
                const Divider(height: 24, indent: 46),
                _FeatureRow(
                  icon: Icons.cell_tower_rounded,
                  title: 'Network mode',
                  subtitle: c.networkMode
                      ? 'Read the X17U mobile-network configuration'
                      : 'Network-mode endpoint not detected',
                  enabled: c.networkMode,
                  onTap: c.networkMode
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const NetworkModeScreen(),
                            ),
                          )
                      : null,
                ),
                const Divider(height: 24, indent: 46),
                _FeatureRow(
                  icon: Icons.restart_alt_rounded,
                  title: 'Restart FlyX',
                  subtitle: 'Reboot the router safely',
                  enabled: c.reboot,
                  onTap: c.reboot ? () => _reboot(context) : null,
                ),
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
                _Capability(label: 'Schedules', active: c.scheduling),
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
                  Icon(
                    Icons.info_outline_rounded,
                    color: FlyxColors.warningFor(context),
                  ),
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

  Future<void> _addWidget(BuildContext context) async {
    final requested = await WidgetSyncService.requestPinWidget();
    if (!context.mounted) return;
    if (!requested) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your launcher did not open the widget picker. Long-press the home screen, choose Widgets, then select FlyX Control.',
          ),
        ),
      );
    }
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Restart command sent. FlyX will be unavailable briefly while it boots.',
            ),
          ),
        );
      }
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
          Icon(icon, color: enabled ? FlyxColors.accentFor(context) : FlyxColors.mutedFor(context), size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: FlyxColors.mutedFor(context))),
              ],
            ),
          ),
          if (!enabled)
            Icon(
              Icons.lock_outline_rounded,
              color: FlyxColors.mutedFor(context),
              size: 20,
            )
          else if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              color: FlyxColors.mutedFor(context),
              size: 20,
            )
          else
            Icon(
              Icons.check_circle_outline_rounded,
              color: FlyxColors.successFor(context),
              size: 20,
            ),
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
        color: (active ? FlyxColors.successFor(context) : FlyxColors.mutedFor(context)).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: (active ? FlyxColors.successFor(context) : FlyxColors.mutedFor(context)).withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? Icons.check_circle_rounded : Icons.pending_outlined, size: 14, color: active ? FlyxColors.successFor(context) : FlyxColors.mutedFor(context)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: active ? FlyxColors.successFor(context) : FlyxColors.mutedFor(context))),
        ],
      ),
    );
  }
}
