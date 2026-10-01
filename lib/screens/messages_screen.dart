import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

enum _SmsFilter { all, unread, read }

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  Future<RouterSmsPage>? _future;
  final TextEditingController _search = TextEditingController();
  _SmsFilter _filter = _SmsFilter.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _loadAllInbox();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<RouterSmsPage> _loadAllInbox() async {
    final controller = AppScope.of(context);
    final first = await controller.fetchSmsInbox(page: 1);
    final byIndex = <int, RouterSmsMessage>{
      for (final message in first.messages) message.index: message,
    };

    final pages = first.maxPage > 20 ? 20 : first.maxPage;
    var sendFull = first.sendFull;
    var receiveFull = first.receiveFull;
    var flashFull = first.flashFull;
    var maxLength = first.maxLength;

    for (var page = 2; page <= pages; page++) {
      final result = await controller.fetchSmsInbox(page: page);
      sendFull = sendFull || result.sendFull;
      receiveFull = receiveFull || result.receiveFull;
      flashFull = flashFull || result.flashFull;
      if (result.maxLength > 0) maxLength = result.maxLength;
      for (final message in result.messages) {
        byIndex[message.index] = message;
      }
    }

    final messages = byIndex.values.toList()
      ..sort(_compareNewestFirst);

    return RouterSmsPage(
      messages: messages,
      total: first.total,
      page: 1,
      sendFull: sendFull,
      receiveFull: receiveFull,
      flashFull: flashFull,
      maxLength: maxLength,
    );
  }

  int _compareNewestFirst(RouterSmsMessage a, RouterSmsMessage b) {
    final at = _messageTime(a.date);
    final bt = _messageTime(b.date);
    if (at != null && bt != null) {
      final byTime = bt.compareTo(at);
      if (byTime != 0) return byTime;
    } else {
      final byText = b.date.compareTo(a.date);
      if (byText != 0) return byText;
    }
    return b.index.compareTo(a.index);
  }

  DateTime? _messageTime(String value) {
    final normalized = value.trim().replaceFirst(' ', 'T').replaceAll('/', '-');
    return DateTime.tryParse(normalized);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _loadAllInbox();
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

  List<RouterSmsMessage> _visibleMessages(RouterSmsPage data) {
    final query = _search.text.trim().toLowerCase();
    return data.messages.where((message) {
      final matchesStatus = switch (_filter) {
        _SmsFilter.all => true,
        _SmsFilter.unread => message.unread,
        _SmsFilter.read => !message.unread,
      };
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;
      return message.phoneNumber.toLowerCase().contains(query) ||
          message.text.toLowerCase().contains(query) ||
          message.date.toLowerCase().contains(query);
    }).toList(growable: false);
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
          final unreadCount = data.messages.where((m) => m.unread).length;
          final visible = _visibleMessages(data);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
              children: [
                AppTopBar(
                  subtitle: 'ROUTER SMS',
                  title: data.total == 1
                      ? '1 message'
                      : '${data.total} messages',
                ),
                const SizedBox(height: 7),
                Text(
                  unreadCount == 0
                      ? 'All caught up · newest first'
                      : '$unreadCount unread · newest first',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: FlyxColors.mutedFor(context)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search sender or message',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _filter == _SmsFilter.all,
                        onTap: () => setState(() => _filter = _SmsFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Unread ($unreadCount)',
                        selected: _filter == _SmsFilter.unread,
                        onTap: () => setState(() => _filter = _SmsFilter.unread),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Read',
                        selected: _filter == _SmsFilter.read,
                        onTap: () => setState(() => _filter = _SmsFilter.read),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (visible.isEmpty)
                  SurfaceCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Center(
                        child: Text(
                          data.messages.isEmpty
                              ? 'No messages.'
                              : 'No messages match this filter.',
                        ),
                      ),
                    ),
                  )
                else
                  for (final message in visible) ...[
                    SurfaceCard(
                      onTap: () => _open(message),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              message.unread
                                  ? Icons.mark_email_unread_rounded
                                  : Icons.mail_outline_rounded,
                              color: message.unread
                                  ? FlyxColors.accentFor(context)
                                  : FlyxColors.mutedFor(context),
                            ),
                            if (message.unread)
                              Positioned(
                                right: -3,
                                top: -3,
                                child: CircleAvatar(
                                  radius: 4,
                                  backgroundColor:
                                      FlyxColors.accentFor(context),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                message.phoneNumber.isEmpty
                                    ? 'Unknown sender'
                                    : message.phoneNumber,
                                style: TextStyle(
                                  fontWeight: message.unread
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (message.unread)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: FlyxColors.accentFor(context).withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  'UNREAD',
                                  style: TextStyle(
                                    color: FlyxColors.accentFor(context),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${message.text}\n${message.date}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  message.unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
