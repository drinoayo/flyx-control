import 'package:flutter_test/flutter_test.dart';
import 'package:flyx_control/models/models.dart';

void main() {
  group('ParentControlSchedule', () {
    test('maps Sunday to router weekday zero', () {
      const schedule = ParentControlSchedule(
        enabled: true,
        startTime: '04:00',
        endTime: '05:00',
        days: {0},
      );

      final sunday = DateTime(2026, 10, 4, 4, 30);
      expect(schedule.isActiveAt(sunday), isTrue);
    });

    test('uses an end-exclusive blocked window', () {
      const schedule = ParentControlSchedule(
        enabled: true,
        startTime: '22:00',
        endTime: '23:00',
        days: {3},
      );

      expect(schedule.isActiveAt(DateTime(2026, 9, 30, 22, 0)), isTrue);
      expect(schedule.isActiveAt(DateTime(2026, 9, 30, 22, 59)), isTrue);
      expect(schedule.isActiveAt(DateTime(2026, 9, 30, 23, 0)), isFalse);
    });

    test('disabled schedules never report an active block', () {
      const schedule = ParentControlSchedule(
        enabled: false,
        startTime: '22:00',
        endTime: '23:00',
        days: {3},
      );

      expect(schedule.isActiveAt(DateTime(2026, 9, 30, 22, 30)), isFalse);
    });

    test('does not guess cross-midnight schedule semantics', () {
      const schedule = ParentControlSchedule(
        enabled: true,
        startTime: '23:00',
        endTime: '01:00',
        days: {3},
      );

      expect(schedule.isActiveAt(DateTime(2026, 9, 30, 23, 30)), isFalse);
    });

    test('formats weekday labels in Monday to Sunday order', () {
      const schedule = ParentControlSchedule(
        enabled: true,
        startTime: '08:00',
        endTime: '09:00',
        days: {0, 1, 4},
      );

      expect(schedule.dayLabel, 'Mon, Thu, Sun');
      expect(schedule.summary, '08:00–09:00 · Mon, Thu, Sun');
    });
  });
}
