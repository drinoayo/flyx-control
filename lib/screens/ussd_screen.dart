import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class UssdScreen extends StatefulWidget {
  const UssdScreen({super.key});

  @override
  State<UssdScreen> createState() => _UssdScreenState();
}

class _UssdScreenState extends State<UssdScreen> {
  final TextEditingController _input = TextEditingController();
  final List<_UssdEntry> _history = [];
  bool _busy = false;
  bool _needsReply = false;
  bool _sessionActive = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final value = _input.text.trim();
    if (value.isEmpty) return;

    setState(() => _busy = true);
    try {
      final result = await AppScope.of(context).sendUssd(value);
      if (!mounted) return;
      setState(() {
        _history.add(_UssdEntry(value: value, outgoing: true));
        if (result.message.isNotEmpty) {
          _history.add(_UssdEntry(value: result.message, outgoing: false));
        }
        _needsReply = result.needsReply;
        _sessionActive = result.needsReply;
        _input.clear();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy || !_sessionActive) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).cancelUssd();
      if (!mounted) return;
      setState(() {
        _sessionActive = false;
        _needsReply = false;
        _history.add(
          const _UssdEntry(value: 'USSD session cancelled.', outgoing: false),
        );
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('USSD')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            const AppTopBar(
              subtitle: 'ROUTER USSD',
              title: 'Dial through the FlyX SIM',
            ),
            const SizedBox(height: 8),
            Text(
              'Enter a USSD code such as a balance or service code. Network replies can take several seconds.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: FlyxColors.muted),
            ),
            const SizedBox(height: 18),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _input,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    maxLength: 99,
                    decoration: InputDecoration(
                      labelText: _needsReply ? 'Reply' : 'USSD code',
                      hintText: _needsReply ? 'Enter your reply' : '*123#',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _send,
                          icon: const Icon(Icons.dialpad_rounded),
                          label: Text(
                            _busy
                                ? 'Waiting…'
                                : (_needsReply ? 'Send reply' : 'Send'),
                          ),
                        ),
                      ),
                      if (_sessionActive) ...[
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: _busy ? null : _cancel,
                          child: const Text('Cancel session'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionTitle(title: 'Session'),
              const SizedBox(height: 10),
              for (final entry in _history) ...[
                Align(
                  alignment: entry.outgoing
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 330),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: entry.outgoing
                          ? FlyxColors.yellow.withValues(alpha: .12)
                          : FlyxColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: FlyxColors.muted.withValues(alpha: .12),
                      ),
                    ),
                    child: SelectableText(entry.value),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _UssdEntry {
  const _UssdEntry({required this.value, required this.outgoing});

  final String value;
  final bool outgoing;
}
