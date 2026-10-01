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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).fetchNetworkMode();
  }

  void _reload() {
    setState(() {
      _future = AppScope.of(context).fetchNetworkMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network mode')),
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
                  title: 'Could not read network mode',
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
                  title: 'Network mode',
                ),
                const SizedBox(height: 18),
                SurfaceCard(
                  emphasized: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Router mode code',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: FlyxColors.muted),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        data.displayMode,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (liveType.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Current connection: $liveType',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: FlyxColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: FlyxColors.yellow,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Read-only verification',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The X17U is returning networkMode directly. Your current raw value is shown above. Changing it stays locked until the firmware’s exact value mapping is captured, so FlyX Control does not guess what codes such as E mean.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: FlyxColors.muted),
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
                                        ?.copyWith(color: FlyxColors.muted),
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
