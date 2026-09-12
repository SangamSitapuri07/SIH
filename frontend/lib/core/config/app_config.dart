/// Application configuration and environment constants.
class AppConfig {
  /// Default ORCA Box URL for Android emulator / local testing.
  static const String defaultBaseUrl = 'http://10.0.2.2:8000';

  /// Fallback desktop/browser default URL.
  static const String defaultLocalhostUrl = 'http://localhost:8000';

  /// Default port for ORCA box.
  static const int defaultPort = 8000;

  /// Default coordinates: Mumbai Offshore Coast (18.92°N, 72.83°E).
  static const double defaultLat = 18.92;
  static const double defaultLon = 72.83;

  /// Timeouts for Dio network requests.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 15);

  /// Default cache TTLs.
  static const Duration advisoryTtl = Duration(minutes: 30);
  static const Duration healthTtl = Duration(minutes: 5);
}
