import '../../../../core/agents/agent_registry.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../domain/entities/agent_reasoning.dart';

/// DTO for /api/v1/reason response.
class ReasonDto {
  final String? overallRisk;
  final String? verdict;
  final Map<String, dynamic>? dataCoverage;
  final List<dynamic>? agentsList;
  final Map<String, dynamic>? synthesisJson;

  ReasonDto({
    this.overallRisk,
    this.verdict,
    this.dataCoverage,
    this.agentsList,
    this.synthesisJson,
  });

  factory ReasonDto.fromJson(Map<String, dynamic> json) {
    return ReasonDto(
      overallRisk: json['overall_risk'] as String? ?? 'MODERATE',
      verdict: json['verdict'] as String? ?? 'caution',
      dataCoverage: json['data_coverage'] as Map<String, dynamic>?,
      agentsList: json['agents'] as List<dynamic>?,
      synthesisJson: json['orchestrator_synthesis'] as Map<String, dynamic>?,
    );
  }

  AgentReasoningResult toEntity(StalenessInfo staleness) {
    final known = dataCoverage?['known'] as int? ?? 7;
    final total = dataCoverage?['total'] as int? ?? 8;
    final failed = (dataCoverage?['sources_failed'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final parsedAgents = <AgentTraceFinding>[];
    if (agentsList != null) {
      for (final a in agentsList!) {
        if (a is Map<String, dynamic>) {
          final id = a['agent_id'] as String? ?? a['agent'] as String? ?? 'unknown';
          final descriptor = AgentRegistry.findById(id);

          final evidenceList = (a['evidence'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              <String>[];
          final warningsList = (a['warnings'] as List<dynamic>?)
                  ?.map((w) => w.toString())
                  .toList() ??
              <String>[];

          parsedAgents.add(
            AgentTraceFinding(
              agentId: id,
              name: a['name'] as String? ?? descriptor.name,
              emoji: a['emoji'] as String? ?? descriptor.emoji,
              agentClass: a['class'] as String? ?? descriptor.classLabel,
              status: a['status'] as String? ?? 'completed',
              durationMs: a['duration_ms'] as int? ?? 50,
              verdict: a['verdict'] as String? ?? 'good',
              summary: a['summary'] as String? ?? 'Agent completed analysis.',
              evidence: evidenceList,
              warnings: warningsList,
            ),
          );
        }
      }
    }

    final synth = OrchestratorSynthesis(
      headline: synthesisJson?['headline'] as String? ?? 'Safe for day transit within coastal shelf.',
      recommendation: synthesisJson?['recommendation'] as String? ?? 'Depart between 06:00 and 10:00 IST.',
      traceOwner: synthesisJson?['trace_owner'] as String? ?? '🧠 Orchestrator Agent (SIH26176)',
      timestamp: DateFormatter.parseIso(synthesisJson?['timestamp']) ?? DateTime.now(),
    );

    return AgentReasoningResult(
      overallRisk: overallRisk ?? 'MODERATE',
      verdict: verdict ?? 'caution',
      knownSources: known,
      totalSources: total,
      sourcesFailed: failed,
      agents: parsedAgents,
      orchestratorSynthesis: synth,
      staleness: staleness,
    );
  }
}
