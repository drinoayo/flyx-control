import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../repositories/zlt_router_repository.dart';
import '../services/secure_store.dart';
import '../services/zlt_client.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'app_shell.dart';

class ConnectRouterScreen extends StatefulWidget {
  const ConnectRouterScreen({super.key});

  @override
  State<ConnectRouterScreen> createState() => _ConnectRouterScreenState();
}

class _ConnectRouterScreenState extends State<ConnectRouterScreen> {
  final host = TextEditingController(text: '192.168.0.1');
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  bool obscure = true;
  bool loading = false;
  bool rememberMe = true;
  String? status;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final saved = await const SecureRouterStore().load();
    if (saved == null || !mounted) return;
    host.text = saved.host;
    username.text = saved.username;
    password.text = saved.password;
    setState(() => rememberMe = true);
  }

  @override
  void dispose() {
    host.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlyxColors.ink,
        surfaceTintColor: Colors.transparent,
        title: const Text('Connect to FlyX'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          SurfaceCard(
            emphasized: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: FlyxColors.yellow,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.router_rounded, color: FlyxColors.ink),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ZLT X17U', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 3),
                          Text(
                            'Local connection · no cloud account',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: FlyxColors.muted,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Your router password stays in encrypted device storage. FlyX Control talks directly to the router over your Wi-Fi.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: FlyxColors.muted,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: host,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Router address',
              prefixIcon: Icon(Icons.language_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: username,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Admin password',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: rememberMe,
            onChanged: loading
                ? null
                : (value) => setState(() => rememberMe = value ?? true),
            title: const Text('Remember me'),
            subtitle: Text(
              'Store this router login securely on this phone and reconnect automatically after app or phone restarts.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FlyxColors.muted,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: loading ? null : _connect,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: FlyxColors.ink,
                    ),
                  )
                : const Icon(Icons.link_rounded),
            label: Text(loading ? 'Connecting…' : 'Connect securely'),
          ),
          if (status != null) ...[
            const SizedBox(height: 14),
            Text(
              status!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: status!.startsWith('Connected')
                        ? FlyxColors.success
                        : FlyxColors.danger,
                  ),
            ),
          ],
          const SizedBox(height: 28),
          const SectionTitle(title: 'What happens first'),
          const SizedBox(height: 10),
          const SurfaceCard(
            child: Column(
              children: [
                _Step(
                  index: '01',
                  title: 'Safe read-only scan',
                  text: 'Check liveness, WAN status, signal fields and firmware data.',
                ),
                Divider(height: 26, indent: 46),
                _Step(
                  index: '02',
                  title: 'Capability discovery',
                  text: 'Confirm the authenticated device list and filter controls using read-only commands.',
                ),
                Divider(height: 26, indent: 46),
                _Step(
                  index: '03',
                  title: 'Enable only proven controls',
                  text: 'No fake buttons. Blocking and other controls appear only when the X17U confirms them.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _normaliseRouterHost(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;

    value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    value = value.split('/').first.split('#').first;
    if (value.contains(':')) {
      // X17U uses the default HTTP port. Keep beta networking constrained to
      // a plain local IPv4 address rather than accepting arbitrary endpoints.
      return null;
    }

    final parts = value.split('.');
    if (parts.length != 4) return null;
    final parsed = parts.map(int.tryParse).toList(growable: false);
    if (parsed.any((part) => part == null || part < 0 || part > 255)) {
      return null;
    }
    final octets = parsed.cast<int>();

    final a = octets[0];
    final b = octets[1];
    final isPrivate = a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
    return isPrivate ? value : null;
  }

  Future<void> _connect() async {
    if (password.text.isEmpty) {
      setState(
        () => status = 'Enter the admin password you use at 192.168.0.1.',
      );
      return;
    }

    setState(() {
      loading = true;
      status = 'Signing in to FlyX…';
    });

    try {
      final routerHost = _normaliseRouterHost(host.text);
      if (routerHost == null) {
        setState(() {
          status =
              'Enter a private local router IPv4 address, such as 192.168.0.1.';
          loading = false;
        });
        return;
      }

      final config = RouterConnectionConfig(
        host: routerHost,
        username: username.text.trim().isEmpty ? 'admin' : username.text.trim(),
        password: password.text,
      );

      final client = ZltClient(host: config.host);
      await client.login(
        username: config.username,
        password: config.password,
      );
      if (mounted) {
        setState(() => status = 'Checking router capabilities…');
      }
      final report = await client.discover();

      final repository = ZltRouterRepository(
        client: client,
        username: config.username,
        password: config.password,
        initialDiscovery: report,
      );

      final store = const SecureRouterStore();
      if (rememberMe) {
        await store.save(config);
      } else {
        await store.clear();
      }
      if (!mounted) return;

      setState(() => status = 'Loading dashboard…');
      await AppScope.of(context).replaceRepository(repository);
      if (!mounted) return;

      setState(() {
        status =
            'Connected. ${report.verifiedCommands.length} X17U commands verified.';
        loading = false;
      });

      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const AppShell()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        status = '$e';
        loading = false;
      });
    }
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.title,
    required this.text,
  });

  final String index;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FlyxColors.yellow.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            index,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: FlyxColors.yellow,
                ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FlyxColors.muted,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
