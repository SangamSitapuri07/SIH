import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../config/api_paths.dart';
import '../cache/cache_service.dart';

/// State provider storing user-configured ORCA box base URL.
final baseUrlProvider = StateProvider<String>((ref) {
  return ref.watch(cacheServiceProvider).get('settings.base_url')?.data['value'] as String? ??
      AppConfig.defaultBaseUrl;
});

/// Shared Dio client provider configured with 15s timeout & retry-once interceptor.
final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      headers: <String, dynamic>{
        'Accept': 'application/json',
        'User-Agent': 'ORCA-Flutter-Client/1.0 (SIH26176)',
      },
    ),
  );

  // Retry once on network failure & handle legacy path fallback
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (DioException err, ErrorInterceptorHandler handler) async {
        debugPrint('[Dio Error] ${err.requestOptions.path} -> ${err.message}');

        // Retry once on 404 with legacy path if available (§4)
        if (err.response?.statusCode == 404) {
          final path = err.requestOptions.path;
          final fallbackPath = ApiPaths.legacyFallbacks[path];
          if (fallbackPath != null && path != fallbackPath) {
            debugPrint('[Dio Fallback] Trying legacy path: $fallbackPath');
            final options = Options(
              method: err.requestOptions.method,
              headers: err.requestOptions.headers,
            );
            try {
              final response = await dio.request<dynamic>(
                fallbackPath,
                data: err.requestOptions.data,
                queryParameters: err.requestOptions.queryParameters,
                options: options,
              );
              return handler.resolve(response);
            } catch (_) {
              // fallback failed, continue with original error
            }
          }
        }

        // Retry once on connection/timeout error
        final isTimeout = err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError;

        final hasRetried = err.requestOptions.extra['has_retried'] == true;
        if (isTimeout && !hasRetried) {
          err.requestOptions.extra['has_retried'] = true;
          try {
            debugPrint('[Dio Retry] Retrying request: ${err.requestOptions.path}');
            final response = await dio.fetch<dynamic>(err.requestOptions);
            return handler.resolve(response);
          } catch (retryError) {
            if (retryError is DioException) {
              return handler.next(retryError);
            }
          }
        }

        return handler.next(err);
      },
    ),
  );

  return dio;
});
