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

  /// Incomplete trailing text from the previous chunk.
  String _buffer = '';

  // Event-block accumulators.
  //
  // These MUST live on the instance, not inside [add]. A single SSE event can
  // be split across any number of network chunks (the ORCA backend emits
  // `event:` and `data:` on separate writes, and keepalives arrive in between),
  // so per-call locals silently dropped every event whose field lines did not
  // land in the same chunk. Keeping them here lets a block accumulate across
  // chunks and dispatch only on the terminating blank line.
  String _currentEvent = 'message';
  String _currentData = '';
  String? _currentId;
  int? _currentRetry;

  _SseEventSink(this._outputSink);

  void _resetBlock() {
    _currentEvent = 'message';
    _currentData = '';
    _currentId = null;
    _currentRetry = null;
  }

  void _dispatchBlock() {
    if (_currentData.isEmpty) {
      // A block with no data payload (e.g. a lone `id:` or a comment run)
      // carries no event; discard it without emitting a fake message.
      _resetBlock();
      return;
    }
    _outputSink.add(
      SseEvent(
        event: _currentEvent,
        data: _currentData.trimRight(),
        id: _currentId,
        retry: _currentRetry,
      ),
    );
    _resetBlock();
  }

  @override
  void add(String chunk) {
    _buffer += chunk;
    final lines = _buffer.split(RegExp(r'\r\n|\r|\n'));
    // The last element is the incomplete remainder of this chunk.
    _buffer = lines.removeLast();

    for (final line in lines) {
      if (line.isEmpty) {
        // Blank line terminates the current event block.
        _dispatchBlock();
      } else if (line.startsWith(':')) {
        // Comment line — the backend uses `: keepalive` to hold the
        // connection open. Never surfaced as an event.
        continue;
      } else if (line.startsWith('event:')) {
        _currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final dataLine = line.substring(5).trim();
        if (_currentData.isEmpty) {
          _currentData = dataLine;
        } else {
          _currentData += '\n$dataLine';
        }
      } else if (line.startsWith('id:')) {
        _currentId = line.substring(3).trim();
      } else if (line.startsWith('retry:')) {
        _currentRetry = int.tryParse(line.substring(6).trim());
      }
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _outputSink.addError(error, stackTrace);
  }

  @override
  void close() {
    // Fold any trailing partial line into the open block, then flush it so a
    // final event that arrived without its terminating blank line is not lost.
    final remainder = _buffer.trim();
    _buffer = '';
    if (remainder.startsWith('data:')) {
      final dataLine = remainder.substring(5).trim();
      _currentData =
          _currentData.isEmpty ? dataLine : '$_currentData\n$dataLine';
    } else if (remainder.startsWith('event:')) {
      _currentEvent = remainder.substring(6).trim();
    } else if (remainder.startsWith('id:')) {
      _currentId = remainder.substring(3).trim();
    }
    _dispatchBlock();
    _outputSink.close();
  }
}
