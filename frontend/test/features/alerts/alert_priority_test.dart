import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/features/alerts/presentation/providers/alert_read_state.dart';

/// The priority buckets must classify the severity strings official feeds
/// actually publish, and must never quietly promote an unlabelled alert.
void main() {
  group('AlertPriority.matches', () {
    test('all accepts everything, including a missing severity', () {
      expect(AlertPriority.all.matches('critical'), isTrue);
      expect(AlertPriority.all.matches(null), isTrue);
      expect(AlertPriority.all.matches(''), isTrue);
    });

    test('critical covers the severe/extreme/danger vocabulary', () {
      for (final value in ['critical', 'Extreme', 'SEVERE', 'danger', 'NO-GO']) {
        expect(AlertPriority.critical.matches(value), isTrue,
            reason: '$value should be critical');
      }
    });

    test('warning covers warn/caution/moderate', () {
      for (final value in ['warning', 'Caution', 'MODERATE']) {
        expect(AlertPriority.warning.matches(value), isTrue,
            reason: '$value should be a warning');
      }
    });

    test('advisory covers advisory/info/watch/minor', () {
      for (final value in ['advisory', 'INFO', 'watch', 'Minor']) {
        expect(AlertPriority.advisory.matches(value), isTrue,
            reason: '$value should be advisory');
      }
    });

    test('a missing severity lands in unspecified, never in a real bucket', () {
      expect(AlertPriority.unspecified.matches(null), isTrue);
      expect(AlertPriority.unspecified.matches(''), isTrue);
      expect(AlertPriority.unspecified.matches('   '), isTrue);

      expect(AlertPriority.critical.matches(null), isFalse);
      expect(AlertPriority.warning.matches(null), isFalse);
      expect(AlertPriority.advisory.matches(null), isFalse);
    });

    test('an unrecognised severity is not promoted into a severity bucket', () {
      const odd = 'orange-level-3';
      expect(AlertPriority.critical.matches(odd), isFalse);
      expect(AlertPriority.warning.matches(odd), isFalse);
      expect(AlertPriority.advisory.matches(odd), isFalse);
      expect(AlertPriority.unspecified.matches(odd), isFalse);
      // It remains visible under "All", so nothing is ever hidden outright.
      expect(AlertPriority.all.matches(odd), isTrue);
    });
  });
}
