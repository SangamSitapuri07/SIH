import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/network/dio_provider.dart';
import '../../data/datasources/map_remote.dart';
import '../../data/repositories/map_repo_impl.dart';
import '../../domain/entities/zone_snapshot.dart';
import '../../domain/repositories/map_repo.dart';
import '../../domain/usecases/get_zone_snapshot.dart';

final mapRemoteDataSourceProvider = Provider<MapRemoteDataSource>((ref) {
  return MapRemoteDataSource(ref.watch(dioProvider));
});

final mapRepositoryProvider = Provider<MapRepository>((ref) => MapRepositoryImpl(
      remoteDataSource: ref.watch(mapRemoteDataSourceProvider),
      cacheService: ref.watch(cacheServiceProvider),
    ));

final getZoneSnapshotUseCaseProvider = Provider<GetZoneSnapshotUseCase>((ref) {
  return GetZoneSnapshotUseCase(ref.watch(mapRepositoryProvider));
});

/// Layer selection deliberately starts empty. An unavailable backend layer can
/// never appear enabled simply because the client guessed a tile URL.
final mapLayerSelectionProvider = StateProvider<Set<String>>((ref) => <String>{});

final mapLayerCatalogProvider = FutureProvider.family<List<MapLayerEntity>, MapCenter>((ref, center) async {
  final layers = await ref.watch(mapRemoteDataSourceProvider).getLayers(
        lat: center.lat,
        lon: center.lon,
      );
  return layers.map((layer) => layer.toEntity()).toList();
});

/// Request identity is value based, so a forecast timeline selection always
/// obtains the corresponding underlying backend timestep.
class MapGridRequest {
  final double lat;
  final double lon;
  final double span;
  final String? validTime;

  const MapGridRequest({required this.lat, required this.lon, required this.span, this.validTime});

  @override
  bool operator ==(Object other) => other is MapGridRequest &&
      lat == other.lat && lon == other.lon && span == other.span && validTime == other.validTime;

  @override
  int get hashCode => Object.hash(lat, lon, span, validTime);
}

class MapCenter {
  final double lat;
  final double lon;
  const MapCenter(this.lat, this.lon);

  @override
  bool operator ==(Object other) => other is MapCenter && lat == other.lat && lon == other.lon;

  @override
  int get hashCode => Object.hash(lat, lon);
}

final mapPfzProvider = FutureProvider<PfzResponseDto>((ref) {
  return ref.watch(mapRemoteDataSourceProvider).getPfz();
});

final mapGridProvider = FutureProvider.family<MapGridDto, MapGridRequest>((ref, request) {
  return ref.watch(mapRemoteDataSourceProvider).getGrid(
        lat: request.lat,
        lon: request.lon,
        span: request.span,
        validTime: request.validTime,
      );
});

final probedZoneProvider = StateProvider<AsyncValue<ZoneSnapshot?>?>((ref) => null);

Future<void> probeCoordinate(WidgetRef ref, double lat, double lon) async {
  ref.read(probedZoneProvider.notifier).state = const AsyncValue.loading();
  final result = await ref.read(getZoneSnapshotUseCaseProvider).execute(lat: lat, lon: lon);
  result.when(
    ok: (snapshot) => ref.read(probedZoneProvider.notifier).state = AsyncValue.data(snapshot),
    err: (failure) => ref.read(probedZoneProvider.notifier).state = AsyncValue.error(failure.message, StackTrace.current),
  );
}
