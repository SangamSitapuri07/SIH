import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/cache/cache_service.dart';

/// Composition root initializing local storage, caches, and foundational services.
///
/// The mobile client is edge-first: safety data comes from the ORCA Box and is
/// cached locally. Optional Supabase sync, when configured, is handled by the
/// ORCA Box backend rather than requiring cloud credentials in the APK.
Future<ProviderContainer> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cacheService = CacheService();
  await cacheService.init();

  final container = ProviderContainer(
    overrides: [
      cacheServiceProvider.overrideWithValue(cacheService),
    ],
  );

  return container;
}
