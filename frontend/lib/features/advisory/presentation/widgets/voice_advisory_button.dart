import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/voice/voice_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/advisory.dart';

class VoiceAdvisoryButton extends ConsumerStatefulWidget {
  final AdvisoryEntity advisory;

  const VoiceAdvisoryButton({
    super.key,
    required this.advisory,
  });

  @override
  ConsumerState<VoiceAdvisoryButton> createState() => _VoiceAdvisoryButtonState();
}

class _VoiceAdvisoryButtonState extends ConsumerState<VoiceAdvisoryButton> {
  bool _speaking = false;

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(selectedLocaleProvider);
    final voice = ref.watch(voiceServiceProvider);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton.icon(
        onPressed: () async {
          if (_speaking) {
            voice.stop();
            setState(() => _speaking = false);
          } else {
            setState(() => _speaking = true);
            await voice.speakAdvisory(
              verdict: widget.advisory.verdict,
              lang: lang,
              plainLines: lang == 'hi' ? widget.advisory.plainHi : widget.advisory.plainEn,
            );
            if (mounted) setState(() => _speaking = false);
          }
        },
        icon: Icon(
          _speaking ? Icons.stop_circle : Icons.volume_up_rounded,
          size: 24,
        ),
        label: Text(
          _speaking ? 'STOP AUDIO ADVISORY' : 'LISTEN TO ADVISORY (AUDIO)',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 1.1,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _speaking ? Colors.redAccent : OrcaTheme.accent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
    );
  }
}
