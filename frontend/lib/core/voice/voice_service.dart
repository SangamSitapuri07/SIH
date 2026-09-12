import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text-to-Speech audio service for low-literacy fishermen (§31).
/// Spoken plain-language safety lines in English, Hindi, and Telugu.
class VoiceService {
  bool _isPlaying = false;
  String? _currentlySpokenText;

  bool get isPlaying => _isPlaying;
  String? get currentlySpokenText => _currentlySpokenText;

  Future<void> speakAdvisory({
    required String verdict,
    required String lang,
    required List<String> plainLines,
  }) async {
    _isPlaying = true;
    _currentlySpokenText = plainLines.join(' ');
    debugPrint('[VoiceService] Speaking advisory in [$lang]: $_currentlySpokenText');

    // Simulate audio playback duration
    await Future.delayed(const Duration(seconds: 4));
    _isPlaying = false;
    _currentlySpokenText = null;
  }

  void stop() {
    _isPlaying = false;
    _currentlySpokenText = null;
  }
}

final voiceServiceProvider = Provider<VoiceService>((ref) {
  return VoiceService();
});
