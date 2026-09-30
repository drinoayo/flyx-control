import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../repositories/zlt_router_repository.dart';
import '../services/secure_store.dart';
import '../services/zlt_client.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

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
          const SizedBox(height: 18),
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

  Future<void> _connect() async {
    if (password.text.isEmpty) {
      setState(
        () => status = 'Enter the admin password you use at 192.168.0.1.',
      );
      return;
    }

    setState(() {
      loading = true;
      status = 'Running a safe capability check…';
    });

    try {
      final config = RouterConnectionConfig(
        host: host.text.trim(),
        username: username.text.trim().isEmpty ? 'admin' : username.text.trim(),
        password: password.text,
      );

      final client = ZltClient(host: config.host);
      await client.login(
        username: config.username,
        password: config.password,
      );
      final report = await client.discover();

      final repository = ZltRouterRepository(
        client: client,
        username: config.username,
        password: config.password,
      );

      await const SecureRouterStore().save(config);
      if (!mounted) return;

      await AppScope.of(context).replaceRepository(repository);
      if (!mounted) return;

      setState(() {
        status =
            'Connected. ${report.verifiedCommands.length} X17U commands verified.';
        loading = false;
      });

      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.of(context).pop();
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
