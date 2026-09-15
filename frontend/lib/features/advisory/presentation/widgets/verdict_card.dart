import 'package:flutter/material.dart';

import '../../../../core/cache/staleness.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/advisory.dart';

/// Primary skipper safety verdict card.
///
/// The deterministic backend verdict is rendered first and at display size,
/// followed by the backend's own plain-language lines. Nothing here is written
/// by the client.
class VerdictCard extends StatelessWidget {
  final AdvisoryEntity advisory;

  const VerdictCard({super.key, required this.advisory});

  @override
  Widget build(BuildContext context) {
    final String verdictText = _verdictText(advisory.verdict);
    final IconData shape = VerdictColors.iconForVerdict(advisory.verdict);
    final OrcaDataState state = resolveDataState(
      hasValue: true,
      isCached: advisory.staleness.isCached,
      isStale: advisory.staleness.state == StalenessState.stale,
    );

    return OrcaHeroPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('DEPARTURE SAFETY VERDICT', color: OrcaTheme.onDeepTealMuted)),
              OrcaStateChip(state: state, onDark: true),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Can I go fishing today?', style: OrcaType.heroTitle),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  verdictText,
                  style: OrcaType.heroVerdict,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(shape, color: OrcaTheme.onDeepTealStrong, size: 26),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(advisory.headline, style: OrcaType.heroBody.copyWith(fontWeight: FontWeight.w700)),
          if (advisory.headlineHi != null && advisory.headlineHi!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              advisory.headlineHi!,
              style: OrcaType.heroBody.copyWith(color: OrcaTheme.onDeepTealMuted),
            ),
          ],
          if (advisory.plainEn.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
            const SizedBox(height: 14),
            for (final String bullet in advisory.plainEn.take(4)) ...<Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 5, color: OrcaTheme.onDeepTealStrong),
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: Text(bullet, style: OrcaType.heroBody.copyWith(fontSize: 12.5))),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OrcaInfoPill(
                icon: Icons.fact_check_outlined,
                label: '${advisory.knownSources}/${advisory.totalSources} sources verified',
                onDark: true,
              ),
              OrcaInfoPill(
                icon: Icons.schedule_outlined,
                label: _windowLabel(advisory.safeWindow),
                onDark: true,
              ),
              OrcaInfoPill(
                icon: Icons.update_rounded,
                label: 'Retrieved ${DateFormatter.formatIstTime(advisory.timestamp)}',
                onDark: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _windowLabel(SafeWindow? window) {
    if (window == null) return 'Departure window unavailable';
    if (window.from.isEmpty || window.to.isEmpty) {
      return window.status == 'UNAVAILABLE' ? 'No safe window in forecast' : 'Departure window unavailable';
    }
    return 'Window ${_short(window.from)}–${_short(window.to)}';
  }

  String _short(String raw) {
    final DateTime? parsed = DateFormatter.parseIso(raw);
    if (parsed == null) return raw;
    return DateFormatter.formatIstTime(parsed);
  }

  String _verdictText(String value) {
    final String normal = value.toLowerCase().replaceAll('-', '_');
    if (normal.contains('go') && !normal.contains('no_go') && !normal.contains('nogo')) {
      return 'GO SAFE ✔';
    }
    if (normal.contains('caution') || normal.contains('mod')) {
      return 'CAUTION ⚠';
    }
    if (normal.contains('no_go') || normal.contains('nogo') || normal.contains('danger')) {
      return 'NO-GO ⛔';
    }
    return value.toUpperCase();
  }
}
