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
      expect(progress.isPlausibleStart, isTrue);
      expect(progress.isRouteProgressReliable, isTrue);
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
      expect(progress.isPlausibleStart, isTrue);
      expect(progress.isRouteProgressReliable, isTrue);
    });

    test('marks an arbitrarily distant endpoint projection as unreliable', () {
      final progress = OfflineNavigationProgress.calculate(
        latitude: 31.22,
        longitude: 75.77,
        accuracyM: 18,
        observedAt: DateTime.utc(2026, 9, 16),
        geometry: const <List<double>>[
          <double>[15.49, 73.83],
          <double>[15.01, 72.11],
        ],
      );

      // Nearest-segment arithmetic still has diagnostic value, but none of its
      // along-route guidance is safe to display from this distant GPS fix.
      expect(progress.offRouteKm, greaterThan(1000));
      expect(progress.isNearRoute, isFalse);
      expect(progress.isPlausibleStart, isFalse);
      expect(progress.isRouteProgressReliable, isFalse);
    });

    test('suppresses progress when reported GPS accuracy is too coarse', () {
      final progress = OfflineNavigationProgress.calculate(
        latitude: 0.01,
        longitude: 0.5,
        accuracyM: 2500,
        observedAt: DateTime.utc(2026, 9, 16),
        geometry: const <List<double>>[
          <double>[0, 0],
          <double>[0, 1],
        ],
      );

      expect(progress.isNearRoute, isTrue);
      expect(progress.hasUsableAccuracy, isFalse);
      expect(progress.isRouteProgressReliable, isFalse);
    });
  });
}
