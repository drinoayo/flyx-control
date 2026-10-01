import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

class DeviceScheduleScreen extends StatelessWidget {
  const DeviceScheduleScreen({
    super.key,
    required this.deviceId,
  });

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final device = controller.deviceById(deviceId);

    if (device == null) {
      return const Scaffold(
        body: Center(child: Text('Device is no longer available.')),
      );
    }

    final schedule = device.parentControlSchedule;
    final active = device.parentControlActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access schedule'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
        children: [
          Text(
            device.name,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 5),
          Text(
            "Schedule repeating hours when this device's network access should be blocked.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: FlyxColors.mutedFor(context),
                ),
          ),
          const SizedBox(height: 22),
          SurfaceCard(
            emphasized: true,
            child: schedule == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        color: FlyxColors.accentFor(context),
                        size: 28,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No schedule',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Add a block window and choose the days it should repeat.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: FlyxColors.mutedFor(context),
                            ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  active
                                      ? 'Blocked by schedule now'
                                      : schedule.enabled
                                          ? 'Schedule enabled'
                                          : 'Schedule disabled',
                                  style:
                                      Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  schedule.summary,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: FlyxColors.mutedFor(context)),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: schedule.enabled,
                            onChanged: controller.busy
                                ? null
                                : (value) => _toggleEnabled(
                                      context,
                                      device,
                                      schedule,
                                      value,
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: FlyxColors.accentFor(context).withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: FlyxColors.accentFor(context).withValues(alpha: .14),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              active
                                  ? Icons.wifi_off_rounded
                                  : Icons.schedule_rounded,
                              color: FlyxColors.yellow,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                active
                                    ? 'This device is inside its scheduled blocked window. Access should recover automatically after the window ends.'
                                    : "During enabled windows, the router blocks this device's access. The router's association list may still show the device, so FlyX Control does not treat disappearance from that list as proof of enforcement.",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: FlyxColors.mutedFor(context)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: FlyxColors.mutedFor(context),
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'MTN Parent Control is IP-based. FlyX Control resolves this device’s current LAN IP again before every save and preserves the router’s full rule list.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: FlyxColors.mutedFor(context),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (schedule == null)
            FilledButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => _edit(context, device, null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add schedule'),
            )
          else ...[
            FilledButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => _edit(context, device, schedule),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text('Edit schedule'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: FlyxColors.dangerFor(context),
                side: const BorderSide(color: Color(0x55FF6B6B)),
              ),
              onPressed:
                  controller.busy ? null : () => _delete(context, device),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete schedule'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleEnabled(
    BuildContext context,
    FlyxDevice device,
    ParentControlSchedule schedule,
    bool enabled,
  ) async {
    if (enabled) {
      final confirmed = await _confirmEnable(context, device);
      if (confirmed != true || !context.mounted) return;
    }

    try {
      await AppScope.of(context).setParentControlSchedule(
        device.id,
        schedule.copyWith(enabled: enabled),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _edit(
    BuildContext context,
    FlyxDevice device,
    ParentControlSchedule? existing,
  ) async {
    final schedule = await showModalBottomSheet<ParentControlSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _ScheduleEditor(existing: existing),
    );
    if (schedule == null || !context.mounted) return;

    if (schedule.enabled) {
      final confirmed = await _confirmEnable(context, device);
      if (confirmed != true || !context.mounted) return;
    }

    try {
      await AppScope.of(context).setParentControlSchedule(device.id, schedule);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<bool?> _confirmEnable(
    BuildContext context,
    FlyxDevice device,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enable schedule for ${device.name}?'),
        content: const Text(
          "During the selected hours this device's network access can be blocked. Make sure you are not relying on this same device to manage the router during the blocked window.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable schedule'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    FlyxDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: Text(
          'The access schedule for ${device.name} will be removed from the router.',
        ),
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
    if (confirmed != true || !context.mounted) return;

    try {
      await AppScope.of(context).deleteParentControlSchedule(device.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.schedule_rounded),
        ),
        child: Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({this.existing});

  final ParentControlSchedule? existing;

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late bool _enabled;
  late String _start;
  late String _end;
  late Set<int> _days;
  String? _error;

  static const _dayOptions = <(int, String)>[
    (1, 'Mon'),
    (2, 'Tue'),
    (3, 'Wed'),
    (4, 'Thu'),
    (5, 'Fri'),
    (6, 'Sat'),
    (0, 'Sun'),
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final now = DateTime.now();
    final routerDay = now.weekday == DateTime.sunday ? 0 : now.weekday;

    _enabled = existing?.enabled ?? true;
    _start = existing?.startTime ?? '22:00';
    _end = existing?.endTime ?? '23:00';
    _days = {...(existing?.days ?? {routerDay})};
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          20,
          18,
          MediaQuery.viewInsetsOf(context).bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'Add schedule' : 'Edit schedule',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                "MTN's own interface only exposes whole hours. FlyX Control can submit exact minutes and verifies the router's readback before keeping the change.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FlyxColors.mutedFor(context),
                    ),
              ),
              const SizedBox(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable this schedule'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'Start',
                      value: _start,
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeField(
                      label: 'End',
                      value: _end,
                      onTap: () => _pickTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Repeat on',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in _dayOptions)
                    FilterChip(
                      label: Text(option.$2),
                      selected: _days.contains(option.$1),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _days.add(option.$1);
                          } else {
                            _days.remove(option.$1);
                          }
                        });
                      },
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: FlyxColors.dangerFor(context),
                      ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save schedule'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = _parseTime(isStart ? _start : _end);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;

    setState(() {
      final value = _formatTime(picked);
      if (isStart) {
        _start = value;
      } else {
        _end = value;
      }
      _error = null;
    });
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return TimeOfDay(
      hour: (hour ?? 0).clamp(0, 23).toInt(),
      minute: (minute ?? 0).clamp(0, 59).toInt(),
    );
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  int? _minutesOfDay(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  void _save() {
    if (_days.isEmpty) {
      setState(() => _error = 'Choose at least one day.');
      return;
    }

    final startMinutes = _minutesOfDay(_start);
    final endMinutes = _minutesOfDay(_end);
    if (startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes) {
      setState(
        () => _error =
            'End time must be later than start time on the same day.',
      );
      return;
    }

    Navigator.pop(
      context,
      ParentControlSchedule(
        enabled: _enabled,
        startTime: _start,
        endTime: _end,
        days: {..._days},
      ),
    );
  }
}
