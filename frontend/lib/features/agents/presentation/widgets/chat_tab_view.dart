import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/data_state.dart';
import '../../../../core/design/orca_widgets.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../advisory/domain/entities/advisory.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../../command_center/data/datasources/command_center_remote.dart';
import '../../../command_center/data/dto/command_center_dto.dart';
import '../providers/agents_provider.dart';

/// "Ask ORCA" workspace.
///
/// There is deliberately **no free-text LLM chat** here: `ApiPaths.chat` has no
/// counterpart in the FastAPI backend, so a message box would either do nothing
/// or invite a fabricated answer. Instead this tab answers a fixed set of
/// operational questions *directly from the data already fetched from the
/// backend*, and each answer states which provider it came from — or that the
/// value is unavailable.
///
/// Every answer below is a pure function of real provider state. None of them
/// can produce a number that the backend did not return.
class ChatTabView extends ConsumerStatefulWidget {
  const ChatTabView({super.key});

  @override
  ConsumerState<ChatTabView> createState() => _ChatTabViewState();
}

class _ChatTabViewState extends ConsumerState<ChatTabView> {
  /// Questions the user has opened this session, newest first.
  final List<_Question> _asked = <_Question>[];

  @override
  Widget build(BuildContext context) {
    final advisory = ref.watch(advisoryProvider).valueOrNull;
    final command = ref.watch(commandCenterProvider).valueOrNull;
    final reasoning = ref.watch(agentsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OrcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OrcaEyebrow('ASK ORCA'),
              const SizedBox(height: 8),
              const Text(
                'Answers built from the data ORCA actually holds.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  letterSpacing: -0.3,
                  fontWeight: FontWeight.w800,
                  color: OrcaTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick a question. Each answer is assembled from the current '
                'backend response and names its source. Nothing is generated, '
                'guessed or filled in.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  height: 1.5,
                  color: OrcaTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (final q in _Question.values)
                    _QuestionChip(
                      label: q.prompt,
                      selected: _asked.contains(q),
                      onTap: () => setState(() {
                        if (_asked.contains(q)) {
                          _asked.remove(q);
                        } else {
                          _asked.insert(0, q);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_asked.isEmpty)
          const OrcaEmptyState(
            icon: Icons.question_answer_outlined,
            title: 'No question asked yet',
            message:
                'Choose one of the questions above to see what ORCA can and '
                'cannot currently answer for your working location.',
          )
        else
          for (final q in _asked) ...[
            _AnswerCard(
              question: q,
              answer: _answer(
                q,
                advisory: advisory,
                command: command,
                reasoningLoading: reasoning.isLoading,
              ),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 6),
        // Explicit, permanent disclosure about conversational chat.
        const OrcaNoticeBanner(
          state: DataState.unavailable,
          message:
              'Free-text conversation is not available: this deployment has no '
              'conversational endpoint. Optional LLM text, when the backend '
              'provides it, appears in the Agent Network tab as explanation '
              'only — never as the safety decision.',
        ),
      ],
    );
  }

  _Answer _answer(
    _Question question, {
    required AdvisoryEntity? advisory,
    required CommandCenterData? command,
    required bool reasoningLoading,
  }) {
    final conditions = command?.conditions;

    switch (question) {
      case _Question.safeToGo:
        if (advisory == null) {
          return const _Answer(
            state: DataState.unavailable,
            body: 'ORCA cannot answer this. The advisory endpoint has not '
                'returned a deterministic verdict for your working location, '
                'so there is no safety decision to report.',
            source: 'Deterministic Marine Risk Agent (/api/v1/advisory)',
          );
        }
        return _Answer(
          state: advisory.staleness.isStale ? DataState.stale : DataState.live,
          body: '${advisory.verdict.toUpperCase()} — ${advisory.headline}'
              '${advisory.plainEn.isEmpty ? '' : '\n\n${advisory.plainEn.first}'}',
          source: 'Deterministic Marine Risk Agent (/api/v1/advisory)',
          footnote: advisory.totalSources == 0
              ? 'Source coverage unavailable'
              : '${advisory.knownSources} of ${advisory.totalSources} sources verified',
        );

      case _Question.conditionsNow:
        if (conditions == null || conditions.hasError) {
          return _Answer(
            state: DataState.unavailable,
            body: conditions?.error ??
                'No marine readings were returned for this location, so no '
                    'wave, wind or temperature value can be quoted.',
            source: 'Marine providers (/api/v1/zone)',
          );
        }
        final parts = <String>[];
        void add(String label, double? value, String unit, String key) {
          final prov = conditions.provenanceFor(key, hasValue: value != null);
          parts.add(value == null || !prov.hasValue
              ? '$label: unavailable'
              : '$label: ${value.toStringAsFixed(unit == 'kn' ? 0 : 1)} $unit '
                  '(${prov.source ?? 'source unavailable'})');
        }

        add('Wave height', conditions.waveHeightM, 'm', 'wave_height_m');
        add('Wind', conditions.windKn, 'kn', 'wind_speed_kn');
        add('Gust', conditions.windGustKn, 'kn', 'wind_gust_kn');
        add('Sea temperature', conditions.seaTempC, '°C', 'sst_celsius');
        return _Answer(
          state: conditions.isCached ? DataState.cached : DataState.forecast,
          body: parts.join('\n'),
          source: conditions.sources.isEmpty
              ? 'Source unavailable'
              : conditions.sources.join(' · '),
        );

      case _Question.whySoCautious:
        if (advisory == null) {
          return const _Answer(
            state: DataState.unavailable,
            body: 'There is no verdict to explain yet.',
            source: 'Deterministic Marine Risk Agent',
          );
        }
        // Only thresholds the backend actually breached are listed.
        final breached = advisory.variables.values
            .where((v) =>
                v.value != null &&
                v.threshold != null &&
                v.value! >= v.threshold!)
            .map((v) =>
                '${v.key}: ${v.value!.toStringAsFixed(1)} ${v.unit} '
                '(threshold ${v.threshold!.toStringAsFixed(1)} ${v.unit}) — ${v.source}')
            .toList();
        return _Answer(
          state: DataState.live,
          body: breached.isEmpty
              ? 'No published threshold was exceeded in the returned '
                  'variables. The verdict rests on the backend rule set and on '
                  'how many inputs could be verified.'
              : 'Thresholds exceeded:\n${breached.join('\n')}',
          source: 'Backend threshold evaluation (/api/v1/advisory)',
        );

      case _Question.whatIsDown:
        final health = command?.health;
        if (health == null) {
          return const _Answer(
            state: DataState.unavailable,
            body: 'The health endpoint has not answered, so provider status '
                'cannot be reported.',
            source: '/api/v1/health',
          );
        }
        final down = health.sources.where((s) => s.isDown).toList();
        final unverified = health.sources.where((s) => s.isUnverified).toList();
        final buffer = StringBuffer();
        buffer.writeln('Backend status: ${health.overall}.');
        buffer.writeln(down.isEmpty
            ? 'No provider is reporting as down.'
            : 'Down: ${down.map((s) => '${s.name} (${s.status})').join(', ')}.');
        if (unverified.isNotEmpty) {
          buffer.write(
              'Unverified: ${unverified.map((s) => s.name).join(', ')}.');
        }
        return _Answer(
          state: down.isEmpty ? DataState.live : DataState.error,
          body: buffer.toString().trim(),
          source: '/api/v1/health',
        );

      case _Question.howDoYouKnow:
        if (reasoningLoading) {
          return const _Answer(
            state: DataState.loading,
            body: 'Fetching the agent evidence trace…',
            source: '/api/v1/reason',
          );
        }
        final failed = advisory?.sourcesFailed ?? const <String>[];
        return _Answer(
          state: advisory == null ? DataState.unavailable : DataState.live,
          body: advisory == null
              ? 'No evidence trace is available because the reasoning endpoint '
                  'did not return a result.'
              : 'Evidence used: '
                  '${advisory.sources.isEmpty ? 'none credited' : advisory.sources.join(', ')}.'
                  '${failed.isEmpty ? '' : '\nSources that failed: ${failed.join(', ')}.'}'
                  '\n\nOpen the Agent Network tab for the per-agent trace.',
          source: 'Agent evidence trace (/api/v1/reason)',
        );
    }
  }
}

enum _Question {
  safeToGo('Is it safe to go out right now?'),
  conditionsNow('What are the conditions at my location?'),
  whySoCautious('Why did ORCA reach that verdict?'),
  whatIsDown('Which data sources are down?'),
  howDoYouKnow('What evidence is this based on?');

  final String prompt;
  const _Question(this.prompt);
}

class _Answer {
  final DataState state;
  final String body;
  final String source;
  final String? footnote;

  const _Answer({
    required this.state,
    required this.body,
    required this.source,
    this.footnote,
  });
}

class _QuestionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _QuestionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? OrcaTheme.accentSoft : OrcaTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? OrcaTheme.accent : OrcaTheme.cardBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.help_outline_rounded,
                  size: 15,
                  color:
                      selected ? OrcaTheme.accentDark : OrcaTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? OrcaTheme.accentDark
                        : OrcaTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _AnswerCard extends StatelessWidget {
  final _Question question;
  final _Answer answer;

  const _AnswerCard({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    question.prompt,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                      color: OrcaTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OrcaStateBadge(state: answer.state, dense: true),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              answer.body,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.55,
                color: OrcaTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: OrcaTheme.cardBorder),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 13, color: OrcaTheme.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    answer.footnote == null
                        ? answer.source
                        : '${answer.source} · ${answer.footnote}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      height: 1.4,
                      color: OrcaTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
