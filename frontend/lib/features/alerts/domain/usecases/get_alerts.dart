import '../../../../core/result/result.dart';
import '../entities/alert_item.dart';
import '../repositories/alerts_repo.dart';

/// Usecase for retrieving active warnings & simulated alerts (§10).
class GetAlertsUseCase {
  final AlertsRepository _repository;

  GetAlertsUseCase(this._repository);

  Future<Result<List<AlertItem>>> execute({bool forceRefresh = false}) {
    return _repository.getActiveAlerts(forceRefresh: forceRefresh);
  }

  Future<Result<AlertItem>> simulate() {
    return _repository.simulateAlert();
  }
}
