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
  bool _optimizationBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).fetchWifiSettings();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = AppScope.of(context).fetchWifiSettings();
    });
  }

  Future<void> _setOptimization(bool current, bool enabled) async {
    if (_optimizationBusy || current == enabled) return;

    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable 5G Optimization?'),
          content: const Text(
            'The router may combine the 2.4 GHz and 5 GHz Wi-Fi settings and reconnect wireless devices. Individual band settings are locked while optimization is enabled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _optimizationBusy = true);
    try {
      final result = await AppScope.of(context).setWifiOptimization(enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.reconnectExpected
                ? '5G Optimization saved. Reconnect to FlyX Wi-Fi if this phone disconnects.'
                : '5G Optimization saved and verified.',
          ),
        ),
      );
      if (!result.reconnectExpected) _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _optimizationBusy = false);
    }
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
                  'Control the Wi-Fi settings exposed by the MTN X17U interface. Potentially disruptive changes warn before saving and use the router\'s own readback whenever the active connection stays available.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: FlyxColors.mutedFor(context)),
                ),
                const SizedBox(height: 22),
                SurfaceCard(
                  emphasized: data.optimizationEnabled,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: data.optimizationEnabled,
                    onChanged: _optimizationBusy
                        ? null
                        : (value) => _setOptimization(
                              data.optimizationEnabled,
                              value,
                            ),
                    title: const Text('5G Optimization'),
                    subtitle: Text(
                      data.optimizationEnabled
                          ? 'Enabled · individual band settings are managed together by the router'
                          : 'Disabled · 2.4 GHz and 5 GHz can be configured separately',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _WifiBandEditor(
                  key: ValueKey(
                    '24-${data.twoFourGhz.ssid}-${data.twoFourGhz.broadcast}-${data.twoFourGhz.channel}-${data.optimizationEnabled}',
                  ),
                  settings: data.twoFourGhz,
                  lockedByOptimization: data.optimizationEnabled,
                  onReload: _reload,
                ),
                const SizedBox(height: 18),
                _WifiBandEditor(
                  key: ValueKey(
                    '5-${data.fiveGhz.ssid}-${data.fiveGhz.broadcast}-${data.fiveGhz.channel}-${data.optimizationEnabled}',
                  ),
                  settings: data.fiveGhz,
                  lockedByOptimization: data.optimizationEnabled,
                  onReload: _reload,
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
    required this.lockedByOptimization,
    required this.onReload,
  });

  final WifiBandSettings settings;
  final bool lockedByOptimization;
  final VoidCallback onReload;

  @override
  State<_WifiBandEditor> createState() => _WifiBandEditorState();
}

class _WifiBandEditorState extends State<_WifiBandEditor> {
  late final TextEditingController _ssid;
  late final TextEditingController _password;
  late final TextEditingController _channel;
  late final TextEditingController _maxClients;

  late bool _enabled;
  late bool _broadcast;
  late String _security;
  late String _wifiMode;
  late String _bandwidth;
  late double _txPower;
  late bool _dfs;
  bool _busy = false;
  bool _expanded = false;

  static const _securityOptions = <String, String>{
    '0': 'Open',
    '2': 'WPA2-PSK',
    '3': 'WPA/WPA2-PSK',
    '4': 'WPA3-PSK',
    '5': 'WPA2/WPA3-PSK',
  };

  static const _mode24 = <String, String>{
    '0': '11b only',
    '1': '11g only',
    '2': '11n only',
    '3': '11b/g',
    '4': '11g/n',
    '5': '11b/n',
    '6': '11b/g/n',
    '16': '11g/n/ax',
  };

  static const _mode5 = <String, String>{
    '7': '11a only',
    '8': '11n only',
    '9': '11ac only',
    '10': '11a/n',
    '11': '11n/ac',
    '13': '11a/n/ac',
    '17': '11n/ac/ax',
  };

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _ssid = TextEditingController(text: s.ssid);
    _password = TextEditingController();
    _channel = TextEditingController(
      text: s.channel.isEmpty || s.channel == '0' ? 'auto' : s.channel,
    );
    _maxClients = TextEditingController(text: '${s.maxClients}');
    _enabled = s.enabled;
    _broadcast = s.broadcast;
    _security = _securityOptions.containsKey(s.authenticationType)
        ? s.authenticationType
        : '2';
    _wifiMode = s.wifiModeCode;
    _bandwidth = s.bandwidthCode;
    _txPower = s.txPowerPercent;
    _dfs = s.dfsEnabled ?? false;
  }

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    _channel.dispose();
    _maxClients.dispose();
    super.dispose();
  }

  Map<String, String> get _modeOptions {
    final base = widget.settings.band == WifiBand.twoFourGhz
        ? Map<String, String>.from(_mode24)
        : Map<String, String>.from(_mode5);
    if (_wifiMode.isNotEmpty && !base.containsKey(_wifiMode)) {
      base[_wifiMode] = 'Current router mode ($_wifiMode)';
    }
    return base;
  }

  List<MapEntry<String, String>> get _bandwidthOptions {
    if (widget.settings.band == WifiBand.twoFourGhz) {
      if (const {'0', '1', '3'}.contains(_wifiMode)) {
        return const [MapEntry('0', '20 MHz')];
      }
      return const [
        MapEntry('0', '20 MHz'),
        MapEntry('2', '20/40 MHz'),
        MapEntry('1', '40 MHz'),
      ];
    }

    final channel = _channel.text.trim();
    if (_wifiMode == '7' || channel == '165') {
      return const [MapEntry('0', '20 MHz')];
    }
    if (const {'8', '10'}.contains(_wifiMode)) {
      return const [
        MapEntry('0', '20 MHz'),
        MapEntry('1', '40 MHz'),
      ];
    }
    return const [
      MapEntry('0', '20 MHz'),
      MapEntry('1', '40 MHz'),
      MapEntry('3', '80 MHz'),
    ];
  }

  void _normalizeBandwidth() {
    final allowed = _bandwidthOptions.map((e) => e.key).toSet();
    if (!allowed.contains(_bandwidth)) {
      _bandwidth = _bandwidthOptions.first.key;
    }
  }

  Future<bool> _confirmDisruptive(String title, String body) async {
    final confirmed = await showDialog<bool>(
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _saveBasic() async {
    if (_busy || widget.lockedByOptimization) return;
    final s = widget.settings;
    final ssid = _ssid.text.trim();
    final password = _password.text;

    final ssidChanged = ssid != s.ssid;
    final passwordChanged = password.isNotEmpty;
    final enabledChanged = _enabled != s.enabled;
    final broadcastChanged = _broadcast != s.broadcast;
    final securityChanged = _security != s.authenticationType;

    if (!ssidChanged &&
        !passwordChanged &&
        !enabledChanged &&
        !broadcastChanged &&
        !securityChanged) {
      _notice('No basic Wi-Fi changes to save.');
      return;
    }

    if ((_security == '0' || _security == '4') && s.wpsEnabled) {
      _notice(
        _security == '4'
            ? 'Turn WPS off before switching this band to WPA3-PSK.'
            : 'Turn WPS off before making this an open Wi-Fi network.',
      );
      return;
    }

    final disruptive =
        ssidChanged || passwordChanged || enabledChanged || securityChanged;
    if (disruptive) {
      final ok = await _confirmDisruptive(
        'Save ${s.label} Wi-Fi settings?',
        'Changing the Wi-Fi name, password, security mode or radio state can disconnect devices using this band. Reconnect to FlyX Wi-Fi if needed.',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final result = await AppScope.of(context).updateWifiPrimary(
        s.band,
        ssid: ssidChanged ? ssid : null,
        password: passwordChanged ? password : null,
        enabled: enabledChanged ? _enabled : null,
        broadcast: broadcastChanged ? _broadcast : null,
        authenticationType: securityChanged ? _security : null,
      );
      if (!mounted) return;
      _password.clear();
      _notice(
        result.reconnectExpected
            ? 'Basic Wi-Fi settings saved. Reconnect to the updated network if this phone disconnects.'
            : 'Basic Wi-Fi settings saved and verified.',
      );
      if (!result.reconnectExpected) widget.onReload();
    } catch (error) {
      if (mounted) _notice('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAdvanced() async {
    if (_busy || widget.lockedByOptimization) return;
    final s = widget.settings;
    final channel = _channel.text.trim().toLowerCase();
    final maxClients = int.tryParse(_maxClients.text.trim());

    if (channel.isEmpty) {
      _notice('Enter Auto or a channel number.');
      return;
    }
    if (channel != 'auto' && int.tryParse(channel) == null) {
      _notice('Channel must be Auto or a number accepted by the router.');
      return;
    }
    if (maxClients == null ||
        maxClients < 1 ||
        maxClients > s.maxClientsLimit) {
      _notice(
        'Maximum clients must be between 1 and ${s.maxClientsLimit}.',
      );
      return;
    }

    _normalizeBandwidth();

    final channelChanged =
        channel != (s.channel.isEmpty || s.channel == '0'
            ? 'auto'
            : s.channel.toLowerCase());
    final modeChanged = _wifiMode != s.wifiModeCode;
    final bandwidthChanged = _bandwidth != s.bandwidthCode;
    final powerChanged = _txPower != s.txPowerPercent;
    final maxChanged = maxClients != s.maxClients;
    final dfsChanged = s.band == WifiBand.fiveGhz &&
        s.dfsEnabled != null &&
        _dfs != s.dfsEnabled;

    if (!channelChanged &&
        !modeChanged &&
        !bandwidthChanged &&
        !powerChanged &&
        !maxChanged &&
        !dfsChanged) {
      _notice('No advanced Wi-Fi changes to save.');
      return;
    }

    final ok = await _confirmDisruptive(
      'Save ${s.label} advanced settings?',
      'Channel, mode, bandwidth, transmit power or DFS changes can briefly restart this Wi-Fi band. FlyX Control will verify the result when the managing connection remains available.',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await AppScope.of(context).updateWifiRadio(
        s.band,
        channel: channelChanged ? channel : null,
        wifiModeCode: modeChanged ? _wifiMode : null,
        bandwidthCode: bandwidthChanged ? _bandwidth : null,
        txPowerPercent: powerChanged ? _txPower : null,
        maxClients: maxChanged ? maxClients : null,
        dfsEnabled: dfsChanged ? _dfs : null,
      );
      if (!mounted) return;
      _notice(
        result.reconnectExpected
            ? 'Advanced Wi-Fi settings saved. Reconnect if this band restarted.'
            : 'Advanced Wi-Fi settings saved and verified.',
      );
      if (!result.reconnectExpected) widget.onReload();
    } catch (error) {
      if (mounted) _notice('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setWps(bool value) async {
    if (_busy || widget.lockedByOptimization) return;
    final s = widget.settings;

    if (value &&
        (!_enabled ||
            !_broadcast ||
            _security == '0' ||
            _security == '4')) {
      _notice(
        'WPS requires this Wi-Fi band and SSID broadcast to be on, with a compatible protected security mode.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await AppScope.of(context).setWifiWps(s.band, value);
      if (!mounted) return;
      _notice('WPS ${value ? 'enabled' : 'disabled'} and verified.');
      widget.onReload();
    } catch (error) {
      if (mounted) _notice('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final disabled = _busy || widget.lockedByOptimization;
    final modeOptions = _modeOptions;
    final bandwidthOptions = _bandwidthOptions;
    final currentWps = s.wpsEnabled;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: FlyxColors.accentFor(context).withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.wifi_rounded,
                      color: FlyxColors.accentFor(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.label, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 3),
                        Text(
                          widget.lockedByOptimization
                              ? 'Managed by 5G Optimization'
                              : (_enabled ? 'Wi-Fi enabled' : 'Wi-Fi disabled'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: widget.lockedByOptimization
                                    ? FlyxColors.warningFor(context)
                                    : (_enabled
                                        ? FlyxColors.successFor(context)
                                        : FlyxColors.mutedFor(context)),
                              ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _expanded ? .5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: FlyxColors.mutedFor(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
          if (widget.lockedByOptimization) ...[
            const SizedBox(height: 14),
            Text(
              'Turn off 5G Optimization above to edit this band independently.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: FlyxColors.mutedFor(context)),
            ),
          ],
          const SizedBox(height: 22),
          const SectionTitle(title: 'Basic'),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: disabled
                ? null
                : (value) => setState(() => _enabled = value),
            title: const Text('Wi-Fi radio'),
            subtitle: const Text('Turn this wireless band on or off'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ssid,
            enabled: !disabled && _enabled,
            maxLength: 31,
            decoration: const InputDecoration(
              labelText: 'Network name (SSID)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _securityOptions.containsKey(_security)
                ? _security
                : null,
            decoration: const InputDecoration(labelText: 'Security'),
            items: [
              for (final entry in _securityOptions.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
            onChanged: disabled || !_enabled
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _security = value);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !disabled && _enabled && _security != '0',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'New password',
              hintText: _security == '0'
                  ? 'Open network · no password'
                  : 'Leave blank to keep the current password',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _broadcast,
            onChanged: disabled || !_enabled
                ? null
                : (value) => setState(() => _broadcast = value),
            title: const Text('Broadcast network name'),
            subtitle: const Text('Allow nearby devices to see this SSID'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: disabled ? null : _saveBasic,
            child: Text(_busy ? 'Saving…' : 'Save basic settings'),
          ),
          const Divider(height: 36),
          const SectionTitle(title: 'Advanced'),
          const SizedBox(height: 10),
          TextField(
            controller: _channel,
            enabled: !disabled,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              labelText: 'Channel',
              hintText: 'auto',
              helperText:
                  'Use Auto or a channel accepted by the router\'s ${s.countryCode.isEmpty ? 'regional' : s.countryCode} profile.',
            ),
            onChanged: (_) {
              setState(_normalizeBandwidth);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: modeOptions.containsKey(_wifiMode)
                ? _wifiMode
                : null,
            decoration: const InputDecoration(labelText: 'Wi-Fi mode'),
            items: [
              for (final entry in modeOptions.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
            onChanged: disabled
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _wifiMode = value;
                      _normalizeBandwidth();
                    });
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('bw-$_wifiMode-${_channel.text}-$_bandwidth'),
            initialValue: bandwidthOptions.any((e) => e.key == _bandwidth)
                ? _bandwidth
                : bandwidthOptions.first.key,
            decoration: const InputDecoration(labelText: 'Bandwidth'),
            items: [
              for (final entry in bandwidthOptions)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
            onChanged: disabled
                ? null
                : (value) {
                    if (value != null) setState(() => _bandwidth = value);
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<double>(
            initialValue: const [100.0, 75.0, 50.0, 25.0, 12.5]
                    .contains(_txPower)
                ? _txPower
                : 100.0,
            decoration: const InputDecoration(labelText: 'Transmit power'),
            items: const [
              DropdownMenuItem(value: 100.0, child: Text('100%')),
              DropdownMenuItem(value: 75.0, child: Text('75%')),
              DropdownMenuItem(value: 50.0, child: Text('50%')),
              DropdownMenuItem(value: 25.0, child: Text('25%')),
              DropdownMenuItem(value: 12.5, child: Text('12.5%')),
            ],
            onChanged: disabled
                ? null
                : (value) {
                    if (value != null) setState(() => _txPower = value);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxClients,
            enabled: !disabled,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Maximum connected devices',
              helperText: '1–${s.maxClientsLimit}',
            ),
          ),
          if (s.band == WifiBand.fiveGhz && s.dfsEnabled != null) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _dfs,
              onChanged: disabled
                  ? null
                  : (value) => setState(() => _dfs = value),
              title: const Text('DFS'),
              subtitle: const Text(
                'Use the router\'s Dynamic Frequency Selection setting',
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: disabled ? null : _saveAdvanced,
            child: Text(_busy ? 'Saving…' : 'Save advanced settings'),
          ),
          const Divider(height: 36),
          const SectionTitle(title: 'WPS'),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: currentWps,
            onChanged: disabled ? null : _setWps,
            title: const Text('WPS'),
            subtitle: Text(
              currentWps
                  ? 'Enabled on this Wi-Fi band'
                  : 'Disabled on this Wi-Fi band',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'WPS PIN/PBC enrollment is intentionally not started from FlyX Control. The persistent WPS setting itself is controlled here.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: FlyxColors.mutedFor(context)),
          ),
          ],
        ],
      ),
    );
  }
}
