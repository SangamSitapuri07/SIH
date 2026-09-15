import 'package:flutter/material.dart';

import '../../../../core/design/data_state.dart';
import '../../../../core/design/orca_widgets.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../providers/settings_provider.dart';

/// Provider health table backed solely by `/api/v1/health` observations.
///
/// Sources are grouped by what they mean operationally, so an outage cannot be
/// mistaken for a source that simply needs credentials.
class SourceCatalogHealthView extends StatelessWidget {
  final Map<String, SourceHealthItem> liveSources;
  const SourceCatalogHealthView({super.key, required this.liveSources});

  @override
  Widget build(BuildContext context) {
    if (liveSources.isEmpty) {
      return const OrcaEmptyState(
        state: DataState.error,
        icon: Icons.cloud_off_rounded,
        title: 'Source status unavailable',
        message:
            'The backend returned no provider entries, so ORCA cannot report '
            'which sources are working. Connect to the ORCA backend and retry.',
      );
    }

    final sources = liveSources.values.toList()
      ..sort((a, b) {
        final byGroup = _group(a.status).index.compareTo(_group(b.status).index);
        if (byGroup != 0) return byGroup;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final usable =
        sources.where((s) => _group(s.status) == _Group.usable).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrcaSectionHeader(
          title: 'Data providers',
          subtitle:
              '$usable of ${sources.length} providers are currently usable',
        ),
        const SizedBox(height: 12),
        for (final group in _Group.values)
          if (sources.any((s) => _group(s.status) == group)) ...[
            _GroupHeader(group: group),
            const SizedBox(height: 8),
            for (final source
                in sources.where((s) => _group(s.status) == group))
              _SourceRow(source: source),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  /// Buckets the backend's real status vocabulary. Unknown strings fall into
  /// [_Group.unverified] rather than being assumed healthy.
  static _Group _group(String value) {
    final status = value.toUpperCase();
    if (status == 'FRESH' ||
        status == 'AVAILABLE' ||
        status == 'CACHED' ||
        status == 'CONNECTED') {
      return _Group.usable;
    }
    if (status == 'UNAVAILABLE' ||
        status == 'UNREACHABLE' ||
        status == 'FAILED' ||
        status == 'AUTHENTICATION_FAILED' ||
        status == 'RATE_LIMITED' ||
        status == 'ERROR' ||
        status == 'DOWN') {
      return _Group.down;
    }
    if (status == 'CREDENTIAL_REQUIRED' ||
        status == 'TOKEN_REQUIRED' ||
        status == 'CONFIGURED' ||
        status == 'NOT_INTEGRATED') {
      return _Group.blocked;
    }
    return _Group.unverified;
  }
}

enum _Group {
  usable('WORKING', 'Answering with data ORCA can use'),
  down('NOT REACHABLE', 'The provider did not answer — its fields are unavailable'),
  blocked('NEEDS SETUP', 'Credentials, activation, or a verified integration are still required'),
  unverified('UNVERIFIED', 'ORCA has not confirmed this provider this session');

  final String title;
  final String description;
  const _Group(this.title, this.description);

  Color get color => switch (this) {
        _Group.usable => VerdictColors.go,
        _Group.down => VerdictColors.noGo,
        _Group.blocked => VerdictColors.caution,
        _Group.unverified => VerdictColors.stale,
      };
}

class _GroupHeader extends StatelessWidget {
  final _Group group;
  const _GroupHeader({required this.group});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: group.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            group.title,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: group.color,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              group.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: OrcaTheme.textMuted,
              ),
            ),
          ),
        ],
      );
}

class _SourceRow extends StatelessWidget {
  final SourceHealthItem source;
  const _SourceRow({required this.source});

  @override
  Widget build(BuildContext context) {
    final group = SourceCatalogHealthView._group(source.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: OrcaTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: group.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: OrcaTheme.textPrimary,
                  ),
                ),
                if (source.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    source.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11.5,
                      height: 1.4,
                      color: OrcaTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  // Absence of a checked_at is itself reported.
                  source.checkedAt == null
                      ? 'Last check time unavailable'
                      : 'Last checked '
                          '${DateFormatter.formatIstTime(DateTime.fromMillisecondsSinceEpoch(source.checkedAt! * 1000, isUtc: true))}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    color: OrcaTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                source.status.replaceAll('_', ' '),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9.5,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w800,
                  color: group.color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                source.latencyMs == null
                    ? 'Latency n/a'
                    : '${source.latencyMs} ms',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10.5,
                  color: OrcaTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
