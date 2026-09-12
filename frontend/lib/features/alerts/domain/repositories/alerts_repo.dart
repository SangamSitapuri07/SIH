import '../../../../core/result/result.dart';
import '../entities/alert_item.dart';

/// Contract for Alerts access (§10).
abstract class AlertsRepository {
  /// Fetches active alerts.
  Future<Result<List<AlertItem>>> getActiveAlerts({bool forceRefresh = false});

  /// Simulates demo alert.
  Future<Result<AlertItem>> simulateAlert();
}
