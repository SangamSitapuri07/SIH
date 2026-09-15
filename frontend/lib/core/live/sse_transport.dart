// Opens a live SSE connection: `Stream<SseEvent> connectSse({required Dio dio, required String url})`.
//
// Default export (web) is overridden for platforms where `dart:io` is
// available (Android/iOS/macOS/Windows/Linux), which use Dio's genuinely
// streaming io adapter instead. See `sse_transport_io.dart` and
// `sse_transport_web.dart` for why the two differ.
export 'sse_transport_web.dart' if (dart.library.io) 'sse_transport_io.dart';
