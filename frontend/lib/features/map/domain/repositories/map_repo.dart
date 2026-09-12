import '../../../../core/result/result.dart';

import '../entities/zone_snapshot.dart';

/// Contract for map and GIS probe access (§10).
abstract class MapRepository {
  /// Probes ocean point conditions at [lat], [lon].
  Future<Result<ZoneSnapshot>> probeZone({
    required double lat,
    required double lon,
  });

  /// Retrieves available map layers.
  Future<Result<List<MapLayerEntity>>> getLayers();
}
