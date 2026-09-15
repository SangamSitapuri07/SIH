import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/advisory.dart';

/// Spoken-advisory status.
///
/// `/api/v1/voice/tts` intentionally answers 503 on this deployment because no
/// verified advisory-to-speech contract exists yet. The UI therefore reports
/// that spoken advisories are unavailable instead of playing nothing while
/// claiming audio playback.
class AdvisoryAudioNotice extends ConsumerWidget {
  final AdvisoryEntity advisory;

  const AdvisoryAudioNotice({super.key, required this.advisory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String language = ref.watch(selectedLocaleProvider);
    final String languageName = switch (language) {
      'hi' => 'Hindi',
      'te' => 'Telugu',
      _ => 'English',
    };
    final int lineCount = language == 'hi' ? advisory.plainHi.length : advisory.plainEn.length;

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('SPOKEN ADVISORY', color: OrcaTheme.textMuted)),
              const OrcaStateChip(state: OrcaDataState.unavailable, overrideLabel: 'AUDIO UNAVAILABLE'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Voice playback is unavailable on this ORCA Box',
            style: OrcaType.sectionTitle.copyWith(fontSize: 14.5),
          ),
          const SizedBox(height: 6),
          Text(
            lineCount == 0
                ? 'No plain-language lines were returned for $languageName, so there is nothing to read aloud yet.'
                : 'ORCA has $lineCount plain-language ${lineCount == 1 ? 'line' : 'lines'} in $languageName, but the backend text-to-speech contract currently answers 503. No audio is played and no speech is simulated.',
            style: OrcaType.body.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          const OrcaProvenance(
            source: 'POST /api/v1/voice/tts',
            stateLabel: 'UNAVAILABLE',
          ),
        ],
      ),
    );
  }
}
