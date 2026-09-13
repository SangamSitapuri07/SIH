import 'dart:async';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../config/api_paths.dart';
import '../cache/cache_service.dart';

/// Returns the correct default ORCA Box URL for the current platform.
///
/// On the Android emulator, `127.0.0.1` refers to the emulator itself, not the
/// host laptop. The emulator reaches the host through the special alias
/// `10.0.2.2`, so Android defaults to that. Web/desktop keep `127.0.0.1`.
String defaultOrcaBoxUrl() {
  if (!kIsWeb && Platform.isAndroid) {
    return AppConfig.androidEmulatorUrl;
  }
  return AppConfig.defaultBaseUrl;
}


/// Converts the value entered by a user into an HTTP(S) ORCA Box base URL.
///
/// On a physical phone, a bare LAN address such as `192.168.1.15` is the
/// most common input. Dio requires an absolute URL, so supply the protocol
/// and default ORCA Box port for that form before creating a client.
String? normalizeOrcaBoxUrl(String value) {
  var url = value.trim();
  if (url.isEmpty) return null;

  if (!url.contains('://')) {
    url = 'http://$url';
  }

  final uri = Uri.tryParse(url);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }

  // A bare IP/host should point to the FastAPI server's standard port.
  final port = uri.hasPort ? uri.port : AppConfig.defaultPort;
  return uri.replace(port: port, path: '').toString().replaceFirst(RegExp(r'/$'), '');
}

/// State provider storing user-configured ORCA box base URL.
final baseUrlProvider = StateProvider<String>((ref) {
  final savedUrl = ref.watch(cacheServiceProvider).get('settings.base_url')?.data['value'] as String?;
  return normalizeOrcaBoxUrl(savedUrl ?? '') ?? defaultOrcaBoxUrl();
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
