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

    test('keeps one decimal below 100 Mbps', () {
      expect(formatRate(125000), '1.0 Mbps');
      expect(formatRate(12487500), '99.9 Mbps');
    });

    test('uses compact whole Mbps from 100 Mbps', () {
      expect(formatRate(12550000), '100 Mbps');
      expect(formatRate(106375000), '851 Mbps');
    });

    test('switches to Gbps at gigabit speed', () {
      expect(formatRate(125000000), '1.00 Gbps');
      expect(formatRate(156250000), '1.25 Gbps');
    });
  });
}
