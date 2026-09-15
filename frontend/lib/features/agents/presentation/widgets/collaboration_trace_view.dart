import 'package:flutter/material.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/widgets/risk_pill.dart';
import '../../../../core/widgets/staleness_badge.dart';
import '../../domain/entities/agent_reasoning.dart';
import 'agent_card.dart';

/// Agent network and evidence trace from the current real backend run.
class CollaborationTraceView extends StatelessWidget {
  final AgentReasoningResult reasoning;
  final Map<String, String> runtimeStates;
  const CollaborationTraceView({super.key, required this.reasoning, this.runtimeStates = const {}});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: OrcaTheme.deepTeal, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('AGENT NETWORK', style: TextStyle(color: OrcaTheme.onDeepTealMuted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1))),
          StalenessBadge(staleness: reasoning.staleness),
        ]),
        const SizedBox(height: 9),
        Row(children: [const Text('Deterministic verdict', style: TextStyle(color: OrcaTheme.onDeepTeal, fontSize: 14, fontWeight: FontWeight.w700)), const SizedBox(width: 10), RiskPill(risk: reasoning.verdict)]),
        const SizedBox(height: 9),
        Text(reasoning.totalSources == 0 ? 'Source coverage unavailable' : '${reasoning.knownSources}/${reasoning.totalSources} sources contributed evidence', style: const TextStyle(color: OrcaTheme.onDeepTealMuted, fontSize: 11.5)),
        if (reasoning.sourcesFailed.isNotEmpty) ...[const SizedBox(height: 5), Text('Unavailable: ${reasoning.sourcesFailed.join(', ')}', style: const TextStyle(color: Color(0xFFFFD28A), fontSize: 10.5))],
      ]),
    ),
    const SizedBox(height: 14),
    const Text('CURRENT EXECUTION STATES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.05, color: OrcaTheme.textSecondary)),
    const SizedBox(height: 8),
    _AgentNetwork(agents: reasoning.agents, runtimeStates: runtimeStates),
    const SizedBox(height: 18),
    Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: OrcaTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: OrcaTheme.cardBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.auto_awesome_outlined, color: OrcaTheme.accentDark, size: 18), SizedBox(width: 8), Text('AI REASONING', style: TextStyle(fontSize: 11, letterSpacing: .9, fontWeight: FontWeight.w800, color: OrcaTheme.accentDark))]),
        const SizedBox(height: 9),
        Text(reasoning.orchestratorSynthesis.headline, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OrcaTheme.textPrimary)),
        const SizedBox(height: 5),
        Text(reasoning.orchestratorSynthesis.recommendation, style: const TextStyle(fontSize: 12, height: 1.4, color: OrcaTheme.textSecondary)),
        const SizedBox(height: 8),
        const Text('Explanation only — the deterministic Marine Risk Agent remains the safety authority.', style: TextStyle(fontSize: 10.5, color: OrcaTheme.textMuted)),
      ]),
    ),
    const SizedBox(height: 18),
    const Text('EVIDENCE TRACE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.05, color: OrcaTheme.textSecondary)),
    const SizedBox(height: 6),
    ...reasoning.agents.map((agent) => AgentCard(finding: agent)),
  ]);
}

class _AgentNetwork extends StatelessWidget {
  final List<AgentTraceFinding> agents;
  final Map<String, String> runtimeStates;
  const _AgentNetwork({required this.agents, required this.runtimeStates});
  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) return const _NetworkUnavailable();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: OrcaTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: OrcaTheme.cardBorder)),
      child: Wrap(spacing: 8, runSpacing: 8, children: agents.map((agent) => _AgentNode(agent: agent, runtimeStatus: runtimeStates[agent.agentId])).toList()),
    );
  }
}

class _AgentNode extends StatelessWidget {
  final AgentTraceFinding agent;
  final String? runtimeStatus;
  const _AgentNode({required this.agent, this.runtimeStatus});
  @override
  Widget build(BuildContext context) {
    final state = _stateFor(runtimeStatus ?? agent.status);
    final color = _colorFor(state);
    return Semantics(
      label: '${agent.name}, $state',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 138,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: .45))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text(agent.emoji, style: const TextStyle(fontSize: 16)), const SizedBox(width: 5), Expanded(child: Text(state, style: TextStyle(fontSize: 8.8, letterSpacing: .5, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 5),
          Text(agent.name.replaceAll(' Agent', ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: OrcaTheme.textPrimary)),
        ]),
      ),
    );
  }

  String _stateFor(String value) {
    switch (value.toLowerCase()) {
      case 'completed': case 'idle': return 'IDLE';
      case 'running': case 'processing': return 'PROCESSING';
      case 'degraded': return 'DEGRADED';
      case 'failed': return 'FAILED';
      case 'active': return 'ACTIVE';
      default: return 'UNAVAILABLE';
    }
  }
  Color _colorFor(String value) {
    switch (value) {
      case 'IDLE': case 'ACTIVE': return VerdictColors.go;
      case 'PROCESSING': return OrcaTheme.accentDark;
      case 'DEGRADED': return VerdictColors.caution;
      case 'FAILED': return VerdictColors.noGo;
      default: return VerdictColors.stale;
    }
  }
}

class _NetworkUnavailable extends StatelessWidget {
  const _NetworkUnavailable();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: OrcaTheme.surfaceElevated, borderRadius: BorderRadius.circular(12)), child: const Text('Agent state unavailable: the backend returned no execution trace.', style: TextStyle(fontSize: 12, color: OrcaTheme.textSecondary)));
}
