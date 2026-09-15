import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/presentation/widgets/variable_provenance.dart';
import '../../domain/entities/agent_reasoning.dart';
import '../providers/agents_provider.dart';

/// Transparent reasoning panel.
///
/// Shows which agents actually ran, how long they took, what they returned and
/// which of them are language-model based. A run that fell back to the
/// deterministic engine is labelled as such — the panel never implies that an
/// LLM produced a result it did not produce.
class AgentReasoningPanel extends ConsumerWidget {
  final AsyncValue<AgentReasoningResult> reasoningState;
  final AsyncValue<List<AgentRuntimeStatus>> runtimeState;
  final VoidCallback onRun;
  final VoidCallback onAskWhy;

  const AgentReasoningPanel({
    super.key,
    required this.reasoningState,
    required this.runtimeState,
    required this.onRun,
    required this.onAskWhy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AgentReasoningResult? reasoning = reasoningState.valueOrNull;
    final bool llmFailed = reasoning != null &&
        reasoning.agents.any((AgentTraceFinding agent) =>
            agent.agentClass == 'LLM' && agent.status.toLowerCase() != 'completed');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: OrcaEyebrow('AGENT NETWORK', color: OrcaTheme.accentDark)),
            OrcaStateChip(
              state: reasoningState.isLoading
                  ? OrcaDataState.loading
                  : reasoning == null || reasoningState.hasError
                      ? OrcaDataState.unavailable
                      : reasoning.staleness.isCached
                          ? OrcaDataState.cached
                          : OrcaDataState.current,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _RegistryCard(
          runtimeState: runtimeState,
          reasoningLoading: reasoningState.isLoading,
          onRun: onRun,
          onAskWhy: onAskWhy,
        ),
        const SizedBox(height: 14),
        ...reasoningState.when(
          loading: () => <Widget>[
            OrcaCard(
              child: Row(
                children: <Widget>[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Running the ORCA agent pipeline…', style: OrcaType.body.copyWith(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],
          error: (Object? error, StackTrace? stack) => <Widget>[
            OrcaUnavailable(
              icon: Icons.hub_outlined,
              title: 'Reasoning trace unavailable',
              message: '$error\nNo agent evidence can be shown until the ORCA Box answers.',
              actionLabel: 'Run reasoning',
              onAction: onRun,
            ),
          ],
          data: (AgentReasoningResult data) => <Widget>[
            if (llmFailed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OrcaNotice(
                  icon: Icons.memory_rounded,
                  title: 'Deterministic fallback in use.',
                  message:
                      'At least one language-model agent did not complete on this ORCA Box, so the deterministic engine produced the result. The verdict remains valid; the narrative explanation does not.',
                  color: VerdictColors.caution,
                  trailingLabel: 'LOCAL MODEL',
                ),
              ),
            _SynthesisCard(reasoning: data, onAskWhy: onAskWhy),
            const SizedBox(height: 14),
            const OrcaEyebrow('AGENT TRACE', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            if (data.agents.isEmpty)
              const OrcaUnavailable(
                icon: Icons.hub_outlined,
                title: 'No agent findings in this run',
                message: 'The reasoning response contained no agent entries, so no trace is shown.',
                compact: true,
              )
            else
              for (final AgentTraceFinding agent in data.agents) ...<Widget>[
                _AgentTile(agent: agent),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ],
    );
  }
}

class _RegistryCard extends ConsumerWidget {
  final AsyncValue<List<AgentRuntimeStatus>> runtimeState;
  final bool reasoningLoading;
  final VoidCallback onRun;
  final VoidCallback onAskWhy;

  const _RegistryCard({
    required this.runtimeState,
    required this.reasoningLoading,
    required this.onRun,
    required this.onAskWhy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AgentRuntimeStatus> agents = runtimeState.valueOrNull ?? const <AgentRuntimeStatus>[];
    final int running = agents.where((AgentRuntimeStatus agent) => agent.isRunning).length;
    final int problems = agents.where((AgentRuntimeStatus agent) => agent.hasProblem).length;
    final String headline = agents.isEmpty
        ? 'UNKNOWN'
        : '$running RUNNING${problems == 0 ? '' : ' · $problems DEGRADED'}';

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OrcaEyebrow(
                  agents.isEmpty
                      ? 'AGENT REGISTRY'
                      : 'AGENT REGISTRY · ${agents.length} AGENTS',
                  color: OrcaTheme.textMuted,
                ),
              ),
              OrcaStateChip(
                state: agents.isEmpty ? OrcaDataState.unavailable : OrcaDataState.current,
                overrideLabel: headline,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (runtimeState.isLoading && agents.isEmpty)
            Text('Reading agent registry from the ORCA Box…', style: OrcaType.body.copyWith(fontSize: 12.5))
          else if (agents.isEmpty)
            Text(
              runtimeState.hasError
                  ? 'Agent registry could not be read. ORCA does not assume an agent status it did not receive.'
                  : 'The ORCA Box returned no agent registry entries.',
              style: OrcaType.body.copyWith(fontSize: 12.5),
            )
          else ...<Widget>[
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final AgentRuntimeStatus agent in agents)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: agent.hasProblem ? OrcaTheme.warnBg : OrcaTheme.accentWash,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: agent.hasProblem ? const Color(0xFFF2DFAE) : OrcaTheme.cardBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: agent.hasProblem
                                ? OrcaTheme.warnFg
                                : agent.isRunning
                                    ? OrcaTheme.liveFg
                                    : OrcaTheme.textFaint,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          agent.name,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: OrcaTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          agent.status.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: OrcaTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'The registry reports IDLE until a reasoning request runs, so IDLE means "not currently running" — it is not a health guarantee. Language-model agents are listed with their real type: ${agents.where((AgentRuntimeStatus agent) => agent.type.toUpperCase().contains('LLM')).length} of ${agents.length}.',
              style: OrcaType.caption,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OrcaPillButton(
                  label: reasoningLoading ? 'Reasoning in progress…' : 'Run reasoning pass',
                  icon: reasoningLoading ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
                  primary: true,
                  onPressed: reasoningLoading ? null : onRun,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OrcaPillButton(
                  label: 'Ask why',
                  icon: Icons.help_outline_rounded,
                  onPressed: onAskWhy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const OrcaProvenance(
            source: 'GET /api/v1/agents · GET /api/v1/reason',
            timeLabel: 'Registry entries and runtime states are reported by the ORCA Box',
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _SynthesisCard extends StatelessWidget {
  final AgentReasoningResult reasoning;
  final VoidCallback onAskWhy;

  const _SynthesisCard({required this.reasoning, required this.onAskWhy});

  @override
  Widget build(BuildContext context) {
    final OrchestratorSynthesis synthesis = reasoning.orchestratorSynthesis;
    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('ORCHESTRATOR SYNTHESIS', color: OrcaTheme.textMuted)),
              OrcaStateChip(
                state: reasoning.staleness.isCached ? OrcaDataState.cached : OrcaDataState.current,
                overrideLabel: verdictWord(reasoning.verdict),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(synthesis.headline, style: OrcaType.body.copyWith(fontSize: 13, color: OrcaTheme.textPrimary)),
          const SizedBox(height: 8),
          Text(synthesis.recommendation, style: OrcaType.body.copyWith(fontSize: 12.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OrcaInfoPill(label: '${reasoning.knownSources}/${reasoning.totalSources} sources verified'),
              OrcaInfoPill(label: 'trace owner ${synthesis.traceOwner}'),
              if (reasoning.sourcesFailed.isNotEmpty)
                OrcaInfoPill(
                  label: 'unavailable: ${reasoning.sourcesFailed.join(', ')}',
                  icon: Icons.error_outline_rounded,
                  tint: VerdictColors.caution,
                ),
            ],
          ),
          if (synthesis.timestamp != null) ...<Widget>[
            const SizedBox(height: 10),
            OrcaProvenance(
              source: 'GET /api/v1/reason',
              timeLabel: 'Trace generated ${DateFormatter.formatIstTime(synthesis.timestamp!)}',
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAskWhy,
              icon: const Icon(Icons.help_outline_rounded, size: 15),
              label: const Text('Explain this verdict in the conversation'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentTile extends StatelessWidget {
  final AgentTraceFinding agent;

  const _AgentTile({required this.agent});

  @override
  Widget build(BuildContext context) {
    final bool completed = agent.status.toLowerCase() == 'completed';
    final Color color = completed ? VerdictColors.go : VerdictColors.fromVerdict(agent.verdict);

    return OrcaCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(agent.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(agent.name, style: OrcaType.metricLabel.copyWith(fontSize: 13, color: OrcaTheme.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: OrcaTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  agent.agentClass,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 8.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                    color: agent.agentClass == 'LLM' ? VerdictColors.info : OrcaTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(agent.summary, style: OrcaType.body.copyWith(fontSize: 12.5)),
          if (agent.evidence.isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            for (final String evidence in agent.evidence.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 7),
                      child: Container(width: 4, height: 4, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    ),
                    Expanded(
                      child: Text(
                        evidence,
                        style: OrcaType.caption.copyWith(fontSize: 11.5, color: OrcaTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (agent.warnings.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            for (final String warning in agent.warnings.take(2))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.warning_amber_rounded, size: 13, color: VerdictColors.caution),
                  const SizedBox(width: 6),
                  Expanded(child: Text(warning, style: OrcaType.caption.copyWith(fontSize: 11.5))),
                ],
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              OrcaStateChip(
                state: completed ? OrcaDataState.current : OrcaDataState.unavailable,
                overrideLabel: agent.status.toUpperCase(),
              ),
              if (agent.durationMs != null) OrcaInfoPill(label: '${agent.durationMs} ms'),
              if (agent.verdict != null)
                OrcaInfoPill(label: 'verdict ${verdictWord(agent.verdict)}', tint: color),
            ],
          ),
        ],
      ),
    );
  }
}
