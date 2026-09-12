import 'dart:async';
import 'dart:convert';

/// Represents a parsed Server-Sent Event (§4, §16).
class SseEvent {
  final String event;
  final String data;
  final String? id;
  final int? retry;

  const SseEvent({
    required this.event,
    required this.data,
    this.id,
    this.retry,
  });

  /// Decodes data as JSON map if valid.
  dynamic get jsonData {
    try {
      return jsonDecode(data);
    } catch (_) {
      return data;
    }
  }

  @override
  String toString() => 'SseEvent(event: $event, data: $data)';
}

/// Transformer that decodes a stream of text chunks into typed [SseEvent]s.
class SseDecoder extends StreamTransformerBase<String, SseEvent> {
  const SseDecoder();

  @override
  Stream<SseEvent> bind(Stream<String> stream) {
    return Stream<SseEvent>.eventTransformed(
      stream,
      (EventSink<SseEvent> sink) => _SseEventSink(sink),
    );
  }
}

class _SseEventSink implements EventSink<String> {
  final EventSink<SseEvent> _outputSink;
  String _buffer = '';

  _SseEventSink(this._outputSink);

  @override
  void add(String chunk) {
    _buffer += chunk;
    final lines = _buffer.split(RegExp(r'\r\n|\r|\n'));
    // The last element is the incomplete remainder
    _buffer = lines.removeLast();

    String currentEvent = 'message';
    String currentData = '';
    String? currentId;

    for (final line in lines) {
      if (line.isEmpty) {
        // Empty line signals end of event block
        if (currentData.isNotEmpty) {
          _outputSink.add(
            SseEvent(
              event: currentEvent,
              data: currentData.trimRight(),
              id: currentId,
            ),
          );
          currentEvent = 'message';
          currentData = '';
          currentId = null;
        }
      } else if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final dataLine = line.substring(5).trim();
        if (currentData.isEmpty) {
          currentData = dataLine;
        } else {
          currentData += '\n$dataLine';
        }
      } else if (line.startsWith('id:')) {
        currentId = line.substring(3).trim();
      }
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outputSink.addError(error, stackTrace);
  }

  @override
  void close() {
    if (_buffer.isNotEmpty && _buffer.contains('data:')) {
      // Flush any remaining complete event
      final line = _buffer.trim();
      if (line.startsWith('data:')) {
        _outputSink.add(
          SseEvent(
            event: 'message',
            data: line.substring(5).trim(),
          ),
        );
      }
    }
    _outputSink.close();
  }
}
