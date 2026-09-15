import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../network/sse.dart';

/// Opens a live SSE connection using Dio's `dart:io`-backed adapter, which
/// delivers response bytes progressively as they arrive on the socket —
/// unlike the browser's XHR-based web adapter, this genuinely streams.
Stream<SseEvent> connectSse({required Dio dio, required String url}) {
  final controller = StreamController<SseEvent>();

  Future<void> run() async {
    try {
      final response = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          // This connection is deliberately unbounded (server keepalives
          // every 5s, no natural completion) — a finite receiveTimeout
          // would abort it on a fixed schedule regardless of keepalives.
          receiveTimeout: Duration.zero,
          headers: <String, dynamic>{
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
        ),
      );
      final stream = response.data?.stream;
      if (stream == null) {
        controller.addError(StateError('SSE response had no body stream'));
        return;
      }
      await controller.addStream(
        stream.cast<List<int>>().transform(utf8.decoder).transform(const SseDecoder()),
      );
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  run();
  return controller.stream;
}
