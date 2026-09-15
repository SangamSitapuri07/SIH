import '../../../../core/result/result.dart';
import '../entities/alert_item.dart';

abstract class AlertsRepository {
  Future<Result<List<AlertItem>>> getActiveAlerts({bool forceRefresh = false});
}
