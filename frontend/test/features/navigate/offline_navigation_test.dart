import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/features/navigate/presentation/providers/offline_navigation_provider.dart';

void main() {
  group('OfflineNavigationProgress', () {
    test('projects GPS fix onto saved route and computes remaining distance', () {
      final progress = OfflineNavigationProgress.calculate(
        latitude: 0.01,
        longitude: 0.5,
        accuracyM: 8,
        observedAt: DateTime.utc(2026, 9, 16),
        geometry: const <List<double>>[
          <double>[0, 0],
          <double>[0, 1],
        ],
      );

      expect(progress.completedKm, closeTo(55.6, 0.5));
      expect(progress.remainingKm, closeTo(55.6, 0.5));
      expect(progress.offRouteKm, closeTo(1.1, 0.1));
      expect(progress.isOffRoute, isFalse);
      expect(progress.bearingToDestination, closeTo(91, 2));
    });

    test('raises off-route warning beyond deterministic two kilometre limit', () {
      final progress = OfflineNavigationProgress.calculate(
        latitude: 0.03,
        longitude: 0.5,
        accuracyM: 5,
        observedAt: DateTime.utc(2026, 9, 16),
        geometry: const <List<double>>[
          <double>[0, 0],
          <double>[0, 1],
        ],
      );

      expect(progress.offRouteKm, greaterThan(3));
      expect(progress.isOffRoute, isTrue);
    });
  });
}
