import '../../../../core/result/result.dart';
import '../entities/alert_item.dart';
import '../repositories/alerts_repo.dart';

/// Retrieves current verified provider alerts.
class GetAlertsUseCase {
  final AlertsRepository _repository;
  GetAlertsUseCase(this._repository);

  Future<Result<List<AlertItem>>> execute({bool forceRefresh = false}) {
    return _repository.getActiveAlerts(forceRefresh: forceRefresh);
  }
}
