import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  Future<RouterSmsPage>? _future;
  int _page = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).fetchSmsInbox(page: _page);
  }

  void _reload([int? page]) {
    if (!mounted) return;
    setState(() {
      if (page != null) _page = page;
      _future = AppScope.of(context).fetchSmsInbox(page: _page);
    });
  }

  Future<void> _compose({String phoneNumber = ''}) async {
    final phone = TextEditingController(text: phoneNumber.trim());
    final message = TextEditingController();

    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(phoneNumber.isEmpty ? 'New SMS' : 'Reply'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (send == true && mounted) {
      try {
        await AppScope.of(context).sendSms(phone.text, message.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS sent.')),
          );
          _reload();
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
      }
    }

    phone.dispose();
    message.dispose();
  }

  Future<void> _open(RouterSmsMessage message) async {
    if (message.unread) {
      try {
        await AppScope.of(context).markSmsRead(message.index);
      } catch (_) {}
    }
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.phoneNumber.isEmpty ? 'Message' : message.phoneNumber),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.date),
              const SizedBox(height: 12),
              SelectableText(message.text),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'reply'),
            child: const Text('Reply'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'close'),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'reply') {
      await _compose(phoneNumber: message.phoneNumber);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete message?'),
          content: const Text('This removes the SMS from the router inbox.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        try {
          await AppScope.of(context).deleteSms([message.index]);
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error.toString())),
            );
          }
        }
      }
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('New SMS'),
      ),
      body: FutureBuilder<RouterSmsPage>(
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
                  subtitle: 'ROUTER SMS',
                  title: 'Could not load messages',
                ),
                const SizedBox(height: 16),
                SurfaceCard(child: Text(snapshot.error.toString())),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('Try again'),
                ),
              ],
            );
          }

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
              children: [
                AppTopBar(
                  subtitle: 'ROUTER SMS',
                  title: data.total == 1
                      ? '1 message'
                      : data.total.toString() + ' messages',
                ),
                const SizedBox(height: 18),
                if (data.messages.isEmpty)
                  const SurfaceCard(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Center(child: Text('No messages on this page.')),
                    ),
                  )
                else
                  for (final message in data.messages) ...[
                    SurfaceCard(
                      onTap: () => _open(message),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          message.unread
                              ? Icons.mark_email_unread_rounded
                              : Icons.mail_outline_rounded,
                        ),
                        title: Text(
                          message.phoneNumber.isEmpty
                              ? 'Unknown sender'
                              : message.phoneNumber,
                          style: TextStyle(
                            fontWeight: message.unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          message.text + '\n' + message.date,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                if (data.maxPage > 1) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: _page > 1 ? () => _reload(_page - 1) : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Page ' +
                                _page.toString() +
                                ' of ' +
                                data.maxPage.toString(),
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: _page < data.maxPage
                            ? () => _reload(_page + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
