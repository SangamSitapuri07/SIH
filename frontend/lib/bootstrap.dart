import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/cache/cache_service.dart';

/// Composition root initializing storage, caches, and foundational services (§10).
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
