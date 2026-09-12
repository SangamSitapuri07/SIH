/// Application configuration and environment constants.
class AppConfig {
  /// Default ORCA Box URL for local Chrome/web testing on the same laptop.
  static const String defaultBaseUrl = 'http://127.0.0.1:8000';

  /// Fallback desktop/browser default URL.
  static const String defaultLocalhostUrl = 'http://127.0.0.1:8000';

  /// Android emulator ORCA Box URL.
  static const String androidEmulatorUrl = 'http://10.0.2.2:8000';

  /// Default port for ORCA box.
  static const int defaultPort = 8000;

  /// Default coordinates: Mumbai Offshore Coast (18.92°N, 72.83°E).
  static const double defaultLat = 18.92;
  static const double defaultLon = 72.83;

  /// General network timeout for lightweight requests.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 15);

  /// Long-running advisory generation can take up to ~136s on current CPU.
  static const Duration advisoryRequestTimeout = Duration(seconds: 180);

  /// Default cache TTLs.
  static const Duration advisoryTtl = Duration(minutes: 30);
  static const Duration healthTtl = Duration(minutes: 5);
}
