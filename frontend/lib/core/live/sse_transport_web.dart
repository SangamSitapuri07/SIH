import 'dart:async';
import 'dart:js_interop';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

import '../network/sse.dart';

/// Opens a live SSE connection using the browser's native [web.EventSource].
///
/// Dio's web adapter is XHR-based (`responseType: 'arraybuffer'`) and only
/// delivers a response body once the request fully completes — which never
/// happens for this endpoint's intentionally infinite stream. `dio` is kept
/// as a parameter only for API symmetry with the io transport; it is unused
/// here in favor of the platform's native SSE primitive, which streams
/// incrementally and handles reconnects at the browser level.
Stream<SseEvent> connectSse({required Dio dio, required String url}) {
  final controller = StreamController<SseEvent>();
  final source = web.EventSource(url);
  final subs = <StreamSubscription<void>>[];

  // The backend emits a fixed, known set of named SSE event types (see
  // backend/main.py and backend/ingestion.py) — native EventSource has no
  // wildcard listener, so each must be registered individually.
  const namedEventTypes = <String>['connected', 'telemetry', 'data.updated', 'alert.push'];
  for (final type in namedEventTypes) {
    final sub = web.EventStreamProvider<web.MessageEvent>(type).forTarget(source).listen((event) {
      if (controller.isClosed) return;
      final raw = event.data;
      final text = raw == null ? null : (raw as JSString).toDart;
      if (text != null) {
        controller.add(SseEvent(event: type, data: text));
      }
    });
    subs.add(sub);
  }

  subs.add(source.onError.listen((_) {
    // EventSource retries transient network blips internally; CLOSED means
    // it gave up for good (e.g. the server rejected the request).
    if (source.readyState == web.EventSource.CLOSED && !controller.isClosed) {
      controller.addError(StateError('EventSource connection closed'));
    }
  }));

  controller.onCancel = () async {
    for (final s in subs) {
      await s.cancel();
    }
    source.close();
  };

  return controller.stream;
}
