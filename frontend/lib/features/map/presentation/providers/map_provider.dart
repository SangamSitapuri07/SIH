import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/widgets/orca_app_bar.dart';
import '../../data/datasources/map_remote.dart';
import '../../data/dto/zone_dto.dart';
import '../../data/repositories/map_repo_impl.dart';
import '../../domain/entities/zone_snapshot.dart';
import '../../domain/repositories/map_repo.dart';
import '../../domain/usecases/get_zone_snapshot.dart';

/// Provider for MapRemoteDataSource.
final mapRemoteDataSourceProvider = Provider<MapRemoteDataSource>((ref) {
  final dio = ref.watch(dioProvider);
  return MapRemoteDataSource(dio);
});

/// Provider for MapRepository.
final mapRepositoryProvider = Provider<MapRepository>((ref) {
  final remote = ref.watch(mapRemoteDataSourceProvider);
  final cache = ref.watch(cacheServiceProvider);
  return MapRepositoryImpl(
    remoteDataSource: remote,
    cacheService: cache,
  );
});

/// Provider for GetZoneSnapshotUseCase.
final getZoneSnapshotUseCaseProvider = Provider<GetZoneSnapshotUseCase>((ref) {
  final repo = ref.watch(mapRepositoryProvider);
  return GetZoneSnapshotUseCase(repo);
});

/// Map layers state provider.
final mapLayersProvider = StateProvider<List<MapLayerEntity>>((ref) {
  return const <MapLayerEntity>[
    MapLayerEntity(
      id: 'wave_height',
      name: 'Wave Height Overlay',
      unit: 'm',
      source: 'Open-Meteo Marine',
      tileUrl: '/api/v1/tiles/waves/{z}/{x}/{y}.png',
      isEnabled: true,
    ),
    MapLayerEntity(
      id: 'chlorophyll',
      name: 'Chlorophyll-a (Fish Food)',
      unit: 'mg/m³',
      source: 'NOAA CoastWatch / OCM-3',
      tileUrl: '/api/v1/tiles/chl/{z}/{x}/{y}.png',
      isEnabled: false,
    ),
    MapLayerEntity(
      id: 'incois_pfz',
      name: 'INCOIS PFZ Lines',
      unit: 'WFS',
      source: 'INCOIS Hyderabad',
      tileUrl: '/api/v1/tiles/pfz/{z}/{x}/{y}.png',
      isEnabled: true,
    ),
  ];
});

/// Probed zone snapshot state provider.
final probedZoneProvider = StateProvider<AsyncValue<ZoneSnapshot?>?>((ref) => null);

/// Helper function to probe coordinate.
Future<void> probeCoordinate(WidgetRef ref, double lat, double lon) async {
  ref.read(probedZoneProvider.notifier).state = const AsyncValue.loading();
  final isDemo = ref.read(demoModeProvider);

  if (isDemo) {
    try {
      final raw = await rootBundle.loadString('assets/fixtures/zone.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final dto = ZoneDto.fromJson(json);
      final staleness = StalenessInfo.fromDateTime(DateTime.now());
      ref.read(probedZoneProvider.notifier).state = AsyncValue.data(dto.toEntity(staleness));
      return;
    } catch (e, st) {
      ref.read(probedZoneProvider.notifier).state = AsyncValue.error(e, st);
      return;
    }
  }

  final useCase = ref.read(getZoneSnapshotUseCaseProvider);
  final result = await useCase.execute(lat: lat, lon: lon);

  result.when(
    ok: (snapshot) {
      ref.read(probedZoneProvider.notifier).state = AsyncValue.data(snapshot);
    },
    err: (failure) {
      ref.read(probedZoneProvider.notifier).state = AsyncValue.error(failure.message, StackTrace.current);
    },
  );
}
