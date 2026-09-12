import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/cache/cache_service.dart';

/// Composition root initializing storage, caches, and foundational services (§10).
Future<ProviderContainer> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cacheService = CacheService();
  await cacheService.init();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      debugPrint('[Supabase] Initialized with remote cloud instance: $supabaseUrl');
    } catch (e) {
      debugPrint('[Supabase] Initialization skipped/failed (offline fallback active): $e');
    }
  } else {
    debugPrint('[Supabase] Unconfigured (SUPABASE_URL not provided). Using local Hive storage & mock sync.');
  }

  final container = ProviderContainer(
    overrides: [
      cacheServiceProvider.overrideWithValue(cacheService),
    ],
  );

  return container;
}
