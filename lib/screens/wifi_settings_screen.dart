import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class WifiSettingsScreen extends StatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  State<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends State<WifiSettingsScreen> {
  Future<WifiSettingsSnapshot>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).fetchWifiSettings();
  }

  void _reload() {
    setState(() {
      _future = AppScope.of(context).fetchWifiSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi')),
      body: SafeArea(
        child: FutureBuilder<WifiSettingsSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const AppTopBar(
                    subtitle: 'ROUTER WI-FI',
                    title: 'Could not load Wi-Fi settings',
                  ),
                  const SizedBox(height: 18),
                  SurfaceCard(
                    child: Text(
                      '${snapshot.error ?? 'The router returned no Wi-Fi settings.'}',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('Try again'),
                  ),
                ],
              );
            }

            final data = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              children: [
                const AppTopBar(
                  subtitle: 'ROUTER WI-FI',
                  title: 'Wireless networks',
                ),
                const SizedBox(height: 8),
                Text(
                  'Change the network name, password or SSID visibility. Channel, transmit power and WPS are shown from the router but remain read-only in this beta.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: FlyxColors.muted),
                ),
                const SizedBox(height: 22),
                _WifiBandEditor(
                  key: ValueKey(
                    '24-${data.twoFourGhz.ssid}-${data.twoFourGhz.broadcast}',
                  ),
                  settings: data.twoFourGhz,
                  onSaved: (result) {
                    if (!result.reconnectExpected) _reload();
                  },
                ),
                const SizedBox(height: 18),
                _WifiBandEditor(
                  key: ValueKey(
                    '5-${data.fiveGhz.ssid}-${data.fiveGhz.broadcast}',
                  ),
                  settings: data.fiveGhz,
                  onSaved: (result) {
                    if (!result.reconnectExpected) _reload();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WifiBandEditor extends StatefulWidget {
  const _WifiBandEditor({
    super.key,
    required this.settings,
    required this.onSaved,
  });

  final WifiBandSettings settings;
  final ValueChanged<WifiUpdateResult> onSaved;

  @override
  State<_WifiBandEditor> createState() => _WifiBandEditorState();
}

class _WifiBandEditorState extends State<_WifiBandEditor> {
  late final TextEditingController _ssid;
  late final TextEditingController _password;
  late bool _broadcast;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ssid = TextEditingController(text: widget.settings.ssid);
    _password = TextEditingController();
    _broadcast = widget.settings.broadcast;
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ssid = _ssid.text.trim();
    final password = _password.text;
    final ssidChanged = ssid != widget.settings.ssid;
    final passwordChanged = password.isNotEmpty;
    final broadcastChanged = _broadcast != widget.settings.broadcast;

    if (!ssidChanged && !passwordChanged && !broadcastChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Wi-Fi changes to save.')),
      );
      return;
    }

    if (ssidChanged || passwordChanged) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save Wi-Fi credentials?'),
          content: Text(
            'Changing the ${widget.settings.label} network name or password may disconnect this phone. If that happens, reconnect to the updated Wi-Fi network before reopening FlyX Control.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final result = await AppScope.of(context).updateWifiPrimary(
        widget.settings.band,
        ssid: ssidChanged ? ssid : null,
        password: passwordChanged ? password : null,
        broadcast: broadcastChanged ? _broadcast : null,
      );
      if (!mounted) return;
      _password.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.reconnectExpected
                ? 'Wi-Fi saved. Reconnect to the updated network if this phone disconnects.'
                : 'Wi-Fi settings saved and verified.',
          ),
        ),
      );
      widget.onSaved(result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final channel =
        settings.channel.toLowerCase() == 'auto' || settings.channel == '0'
            ? 'Auto'
            : settings.channel;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FlyxColors.yellow.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.wifi_rounded,
                  color: FlyxColors.yellow,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      settings.enabled ? 'Wi-Fi enabled' : 'Wi-Fi disabled',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: settings.enabled
                                ? FlyxColors.success
                                : FlyxColors.muted,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ssid,
            enabled: !_saving,
            maxLength: 31,
            decoration: const InputDecoration(
              labelText: 'Network name (SSID)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'New password',
              hintText: 'Leave blank to keep the current password',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _broadcast,
            onChanged: _saving
                ? null
                : (value) => setState(() => _broadcast = value),
            title: const Text('Broadcast network name'),
            subtitle: const Text('Allow nearby devices to see this SSID'),
          ),
          const Divider(height: 26),
          Wrap(
            spacing: 22,
            runSpacing: 14,
            children: [
              _WifiFact(label: 'Channel', value: channel),
              _WifiFact(
                label: 'Transmit power',
                value: '${settings.txPowerPercent}%',
              ),
              _WifiFact(
                label: 'Max clients',
                value: '${settings.maxClients}',
              ),
              _WifiFact(
                label: 'WPS',
                value: settings.wpsEnabled ? 'On' : 'Off',
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save ${settings.label}'),
          ),
        ],
      ),
    );
  }
}

class _WifiFact extends StatelessWidget {
  const _WifiFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: MetricLabel(label: label, value: value),
    );
  }
}
