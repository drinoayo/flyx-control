import 'package:flutter_test/flutter_test.dart';
import 'package:flyx_control/core/formatters.dart';

void main() {
  group('formatRate', () {
    test('uses bps below one kilobit', () {
      expect(formatRate(100), '800 bps');
    });

    test('uses Kbps below one megabit', () {
      expect(formatRate(12500), '100 Kbps');
    });

    test('uses Mbps from one megabit per second', () {
      expect(formatRate(125000), '1.0 Mbps');
      expect(formatRate(1500000), '12.0 Mbps');
    });
  });
}
