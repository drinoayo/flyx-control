import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class NetworkModeScreen extends StatefulWidget {
  const NetworkModeScreen({super.key});

  @override
  State<NetworkModeScreen> createState() => _NetworkModeScreenState();
}

class _NetworkModeScreenState extends State<NetworkModeScreen> {
  Future<RouterNetworkModeSnapshot>? _future;
  bool _showFields = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).fetchNetworkMode();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = AppScope.of(context).fetchNetworkMode();
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _setFlight(bool enabled) async {
    if (_busy) return;
    if (enabled) {
      final ok = await _confirm(
        title: 'Turn on Flight Mode?',
        body:
            'This disables the mobile-network connection. The FlyX Wi-Fi and local app connection should remain available, but Internet access will stop until Flight Mode is turned off.',
        action: 'Turn on',
      );
      if (!ok || !mounted) return;
    }
    await _runChange(() => AppScope.of(context).setFlightMode(enabled));
  }

  Future<void> _setData(bool enabled) async {
    if (_busy) return;
    if (!enabled) {
      final ok = await _confirm(
        title: 'Turn mobile data off?',
        body:
            'Devices can stay connected to FlyX Wi-Fi, but Internet access through the MTN SIM will stop until mobile data is turned back on.',
        action: 'Turn off',
      );
      if (!ok || !mounted) return;
    }
    await _runChange(() => AppScope.of(context).setMobileData(enabled));
  }

  Future<void> _setRoaming(bool enabled) async {
    if (_busy) return;
    await _runChange(() => AppScope.of(context).setDataRoaming(enabled));
  }

  Future<void> _runChange(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile-network setting saved and verified.')),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mobile network')),
      body: FutureBuilder<RouterNetworkModeSnapshot>(
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
                  subtitle: 'MOBILE NETWORK',
                  title: 'Could not read network settings',
                ),
                const SizedBox(height: 18),
                SurfaceCard(child: Text(snapshot.error.toString())),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('Try again'),
                ),
              ],
            );
          }

          final data = snapshot.data!;
          final liveType = AppScope.of(context).network?.networkType ?? '';
          final entries = data.fields.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              children: [
                const AppTopBar(
                  subtitle: 'MOBILE NETWORK',
                  title: 'Network settings',
                ),
                const SizedBox(height: 18),
                SurfaceCard(
                  emphasized: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Network mode',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: FlyxColors.mutedFor(context)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.displayMode,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Router code: ${data.networkModeCode}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: FlyxColors.mutedFor(context)),
                      ),
                      if (liveType.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Current connection: $liveType',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: FlyxColors.mutedFor(context)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'This MTN X17U firmware exposes Automatic as its supported network-mode option. FlyX Control does not invent 4G-only or 5G-only values that the stock page does not offer.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: FlyxColors.mutedFor(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SurfaceCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: data.flightMode,
                        onChanged: _busy ? null : _setFlight,
                        title: const Text('Flight Mode'),
                        subtitle: const Text(
                          'Disable or restore the cellular connection',
                        ),
                      ),
                      const Divider(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: data.dataEnabled,
                        onChanged:
                            _busy || data.flightMode ? null : _setData,
                        title: const Text('Mobile data'),
                        subtitle: const Text(
                          'Allow Internet access through the MTN SIM',
                        ),
                      ),
                      const Divider(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: data.roamingEnabled,
                        onChanged: _busy ||
                                data.flightMode ||
                                !data.dataEnabled
                            ? null
                            : _setRoaming,
                        title: const Text('Data roaming'),
                        subtitle: const Text(
                          'Allow mobile data while the SIM is roaming',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SurfaceCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: MetricLabel(
                          label: 'LTE CA',
                          value: data.lteCarrierAggregation ? 'On' : 'Off',
                        ),
                      ),
                      Expanded(
                        child: MetricLabel(
                          label: 'NR CA',
                          value: data.nrCarrierAggregation ? 'On' : 'Off',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SurfaceCard(
                  onTap: () => setState(() => _showFields = !_showFields),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Router fields',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          AnimatedRotation(
                            turns: _showFields ? .5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                      if (_showFields) ...[
                        const Divider(height: 24),
                        if (entries.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('No additional fields returned.'),
                          )
                        else
                          for (final entry in entries) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: SelectableText(
                                    entry.key,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: FlyxColors.mutedFor(context)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 6,
                                  child: SelectableText(
                                    entry.value.isEmpty ? '—' : entry.value,
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
