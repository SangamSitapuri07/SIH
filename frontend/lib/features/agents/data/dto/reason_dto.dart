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
  final DateTime? timestamp;
  final DateTime? sourceTimestamp;
  final bool isCached;

  ReasonDto({
    this.overallRisk,
    this.verdict,
    this.dataCoverage,
    this.agentsList,
    this.synthesisJson,
    this.timestamp,
    this.sourceTimestamp,
    this.isCached = false,
  });

  factory ReasonDto.fromJson(Map<String, dynamic> json) {
    // The backend returns `verdict` (GOOD/CAUTION/DANGER) and top-level
    // `headline_en` / `plain_en` rather than a nested `orchestrator_synthesis`
    // object. Build a synthesis map from those fields when the nested form is
    // absent so the Orchestrator card is populated.
    final synthesis = json['orchestrator_synthesis'] as Map<String, dynamic>? ??
        <String, dynamic>{
          if (json['headline_en'] != null) 'headline': json['headline_en'],
          if (json['plain_en'] is List && (json['plain_en'] as List).isNotEmpty)
            'recommendation': (json['plain_en'] as List).join(' '),
          if (json['timestamp'] != null) 'timestamp': json['timestamp'],
        };

    return ReasonDto(
      overallRisk: json['overall_risk'] as String? ??
          json['verdict'] as String? ??
          'UNAVAILABLE',
      verdict: json['verdict'] as String? ?? 'UNAVAILABLE',
      dataCoverage: json['data_coverage'] as Map<String, dynamic>?,
      agentsList: json['agents'] as List<dynamic>?,
      synthesisJson: synthesis,
      timestamp: _parseTimestamp(json['timestamp']),
      sourceTimestamp: _parseTimestamp(json['source_timestamp']),
      isCached: json['cached'] == true,
    );
  }


  static DateTime? _parseTimestamp(dynamic value) {
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true);
    return DateFormatter.parseIso(value);
  }

  AgentReasoningResult toEntity(StalenessInfo staleness) {
    final known = dataCoverage?['known'] as int? ?? 0;
    final total = dataCoverage?['total'] as int? ?? 0;
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

          // The backend emits `agent_name`, `type`, `findings` and
          // `confidence`; older fixtures used `name`, `class`, `summary`.
          // Fall back through both so the trace is populated either way.
          final rawStatus = a['status'] as String? ?? 'unavailable';
          final rawClass =
              (a['class'] ?? a['type'] ?? descriptor.classLabel).toString();
          // Normalize class label to the DETERMINISTIC / LLM tags the UI shows.
          final agentClass = rawClass.toUpperCase().contains('LLM')
              ? 'LLM'
              : 'DETERMINISTIC';
          // Completion is an execution state, not a safety verdict. Only show
          // a verdict when that specific agent explicitly returned one.
          final verdict = a['verdict'] as String?;

          parsedAgents.add(
            AgentTraceFinding(
              agentId: id,
              name: (a['name'] ?? a['agent_name'] ?? descriptor.name).toString(),
              emoji: (a['emoji'] ?? descriptor.emoji).toString(),
              agentClass: agentClass,
              status: rawStatus,
              durationMs: (a['duration_ms'] as num?)?.toInt(),
              verdict: verdict,
              summary: (a['summary'] ??
                      a['findings'] ??
                      'No verified agent finding was returned.')
                  .toString(),
              evidence: evidenceList,
              warnings: warningsList,
            ),
          );

        }
      }
    }

    final synth = OrchestratorSynthesis(
      headline: synthesisJson?['headline'] as String? ?? 'Synthesis unavailable.',
      recommendation: synthesisJson?['recommendation'] as String? ?? 'No verified synthesis was returned.',
      traceOwner: synthesisJson?['trace_owner'] as String? ?? 'Unavailable',
      timestamp: DateFormatter.parseIso(synthesisJson?['timestamp']) ?? timestamp,
    );

    return AgentReasoningResult(
      overallRisk: overallRisk ?? 'UNAVAILABLE',
      verdict: verdict ?? 'UNAVAILABLE',
      knownSources: known,
      totalSources: total,
      sourcesFailed: failed,
      agents: parsedAgents,
      orchestratorSynthesis: synth,
      staleness: staleness,
    );
  }
}
