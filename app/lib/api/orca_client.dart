/// HTTP + SSE client for the ORCA backend.
///
/// Two ways to call the backend:
///   * `ask`         — POST /ask, returns the full response at once
///   * `askStreaming`— GET /stream, yields agent steps one by one then the
///                     final response, perfect for a "thinking..." UI
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class OrcaException implements Exception {
  final String message;
  OrcaException(this.message);
  @override
  String toString() => 'OrcaException: $message';
}

class OrcaClient {
  /// Base URL for the backend.
  ///
  /// Defaults to 10.0.2.2:8000 which is how the Android emulator reaches
  /// the host machine. For a physical phone, change this to your laptop's
  /// LAN IP (e.g. http://192.168.1.10:8000).
  final Uri baseUrl;

  final http.Client _http;

  OrcaClient({Uri? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? Uri.parse('http://10.0.2.2:8000'),
        _http = client ?? http.Client();

  /// Simple POST /ask — returns the full response in one call.
  Future<OrcaResponse> ask(
    String text, {
    LatLng? location,
    String? language,
  }) async {
    final body = <String, dynamic>{'text': text};
    if (location != null) {
      body['location'] = [location.latitude, location.longitude];
    }
    if (language != null) body['language'] = language;

    final resp = await _http.post(
      baseUrl.replace(path: '/ask'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw OrcaException('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final outer = jsonDecode(resp.body) as Map<String, dynamic>;
    return OrcaResponse.fromJson(outer['response'] as Map<String, dynamic>);
  }

  /// SSE streaming — yields one [AgentStep] at a time as the backend
  /// reports each agent finishing, then yields the final [OrcaResponse].
  Stream<StreamEvent> askStreaming(
    String text, {
    LatLng? location,
    String? language,
  }) async* {
    final params = <String, String>{
      'query_text': text,
      if (location != null) 'lat': location.latitude.toString(),
      if (location != null) 'lon': location.longitude.toString(),
      if (language != null) 'language': language,
    };
    final uri = baseUrl.replace(path: '/stream', queryParameters: params);

    final req = http.Request('GET', uri)
      ..headers['Accept'] = 'text/event-stream';
    final resp = await _http.send(req);
    if (resp.statusCode != 200) {
      throw OrcaException('HTTP ${resp.statusCode}');
    }

    final lines = resp.stream
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());

    String? currentEvent;
    final dataBuf = StringBuffer();

    await for (final line in lines) {
      if (line.isEmpty) {
        // dispatch the event
        if (dataBuf.isNotEmpty) {
          final dataStr = dataBuf.toString();
          dataBuf.clear();
          try {
            final data = jsonDecode(dataStr) as Map<String, dynamic>;
            if (data['event'] == 'step' && data['step'] is Map) {
              yield StreamEvent.step(
                AgentStep.fromJson(data['step'] as Map<String, dynamic>),
              );
            } else if (data['event'] == 'done' && data['response'] is Map) {
              yield StreamEvent.done(
                OrcaResponse.fromJson(data['response'] as Map<String, dynamic>),
              );
            }
          } catch (e) {
            // ignore malformed lines
          }
        }
        currentEvent = null;
      } else if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataBuf.write(line.substring(5).trim());
      }
    }
  }

  void close() => _http.close();
}

/// Discriminated union of events from the streaming endpoint.
class StreamEvent {
  final AgentStep? step;
  final OrcaResponse? done;

  const StreamEvent._({this.step, this.done});

  factory StreamEvent.step(AgentStep s) => StreamEvent._(step: s);
  factory StreamEvent.done(OrcaResponse r) => StreamEvent._(done: r);

  bool get isStep => step != null;
  bool get isDone => done != null;
}
