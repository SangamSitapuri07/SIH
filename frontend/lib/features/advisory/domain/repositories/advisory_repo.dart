import '../../../../core/result/result.dart';
import '../entities/advisory.dart';

/// Contract for advisory data access (§10, §13).
abstract class AdvisoryRepository {
  /// Fetches advisory with cache-first and staleness tracking.
  Future<Result<AdvisoryEntity>> getAdvisory({
    required double lat,
    required double lon,
    bool forceRefresh = false,
  });

  /// Returns the freshest cached advisory of any age, or null.
  ///
  /// Used by the presentation layer to render instantly (stale-while-
  /// revalidate) while a network refresh runs in the background.
  Future<AdvisoryEntity?> getAdvisoryCached({
    required double lat,
    required double lon,
  });
}
