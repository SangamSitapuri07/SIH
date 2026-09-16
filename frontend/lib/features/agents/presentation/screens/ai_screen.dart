import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_paths.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/live/live_channel.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/domain/entities/advisory.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../../advisory/presentation/widgets/variable_provenance.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/agent_reasoning.dart';
import '../providers/agents_provider.dart';
import '../widgets/agent_reasoning_panel.dart';
import '../widgets/ask_orca_thread.dart';

/// Ask ORCA workspace: a conversational surface plus a transparent agent
/// reasoning panel.
///
/// Replies use the evidence-grounded `/api/v1/chat` endpoint, with
/// `/api/v1/advisory`, `/api/v1/health` and `/api/v1/reason` fallbacks and are labelled with the evidence class they
/// belong to. Agent names and statuses come from the real `/api/v1/agents`
/// registry; nothing is reported as ready until the backend says so.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<OrcaChatEntry> _entries = <OrcaChatEntry>[];
  bool _asking = false;

  static const List<String> _suggestions = <String>[
    'Can I go out today?',
    'When is my departure window?',
    'Which sources are unavailable?',
    'Why this verdict?',
    'What is the route safety process?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AdvisoryEntity> advisoryState = ref.watch(advisoryProvider);
    final AsyncValue<AgentReasoningResult> reasoningState = ref.watch(agentsProvider);
    final AsyncValue<SystemHealthSnapshot> healthState = ref.watch(healthProvider);
    final AsyncValue<List<AgentRuntimeStatus>> runtimeState = ref.watch(agentRuntimeStatusProvider);
    final bool online = ref.watch(isOnlineProvider);
    final bool streamLive = ref.watch(liveChannelProvider) == LiveStreamStatus.connected;
    final Map<String, double> coords = ref.watch(advisoryLocationProvider);
    final double lat = coords['lat'] ?? AppConfig.defaultLat;
    final double lon = coords['lon'] ?? AppConfig.defaultLon;

    final AdvisoryEntity? advisory = advisoryState.valueOrNull;
    final AgentReasoningResult? reasoning = reasoningState.valueOrNull;
    final SystemHealthSnapshot? health = healthState.valueOrNull;

    Future<void> ask(String rawQuestion) async {
      final String question = rawQuestion.trim();
      if (question.isEmpty || _asking) return;
      setState(() {
        _asking = true;
        _controller.clear();
      });

      OrcaAnswer answer;
      if (online) {
        try {
          final response = await ref.read(dioProvider).post<Map<String, dynamic>>(
            ApiPaths.chat,
            data: <String, dynamic>{
              'question': question,
              'latitude': lat,
              'longitude': lon,
            },
          );
          final payload = response.data;
          if (payload == null) throw const FormatException('Empty Ask ORCA response');
          answer = _remoteAnswer(payload);
        } catch (_) {
          answer = _answer(
            question,
            advisory: advisory,
            reasoning: reasoning,
            health: health,
            online: online,
            streamLive: streamLive,
          );
        }
      } else {
        answer = _answer(
          question,
          advisory: advisory,
          reasoning: reasoning,
          health: health,
          online: online,
          streamLive: streamLive,
        );
      }
      if (!mounted) return;
      setState(() {
        _entries.add(OrcaChatEntry(question: question, answer: answer));
        _asking = false;
      });
    }

    final Widget conversation = AskOrcaThread(
      entries: _entries,
      subject: advisory == null ? null : GeoUtils.formatCoordinate(lat, lon),
      loading: _asking,
      composer: _Composer(
        controller: _controller,
        suggestions: _suggestions,
        onSubmit: (String question) {
          ask(question);
        },
      ),
    );

    final Widget panel = AgentReasoningPanel(
      reasoningState: reasoningState,
      runtimeState: runtimeState,
      onRun: () {
        ref.invalidate(agentRuntimeStatusProvider);
        ref.read(agentsProvider.notifier).fetch(forceRefresh: true);
      },
      onAskWhy: () {
        ask('Why this verdict?');
      },
    );

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.tabAi ?? 'AI Agents',
      subtitle: 'Reasoning, evidence and service status',
      locationLabel: 'Working location',
      coordinateLabel: GeoUtils.formatCoordinate(lat, lon),
      updatedAt: reasoning?.orchestratorSynthesis.timestamp ?? advisory?.timestamp,
      stateLabel: !online
          ? 'OFFLINE'
          : streamLive
              ? 'LIVE CHANNEL OPEN'
              : 'DIRECT REQUESTS',
      onRefresh: () async {
        // Refresh live evidence without starting a heavyweight Ollama pass.
        // The explicit Run reasoning button remains the only reasoning trigger.
        await Future.wait(<Future<void>>[
          ref.read(advisoryProvider.notifier).fetch(forceRefresh: true),
          ref.read(healthProvider.notifier).checkHealth(),
        ]);
        ref.invalidate(agentRuntimeStatusProvider);
      },
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool twoColumn = constraints.maxWidth > OrcaTheme.compactBreakpoint;
          final Widget scrollableConversation = ListView(
            padding: orcaContentPadding(wide: twoColumn),
            children: <Widget>[conversation],
          );
          final Widget scrollablePanel = ListView(
            padding: orcaContentPadding(wide: twoColumn).copyWith(left: twoColumn ? 4 : 16),
            children: <Widget>[panel],
          );

          if (!twoColumn) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: <Widget>[
                conversation,
                const SizedBox(height: 22),
                panel,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 6, child: scrollableConversation),
              Container(width: 1, color: OrcaTheme.cardBorder),
              Expanded(flex: 4, child: Container(color: OrcaTheme.background, child: scrollablePanel)),
            ],
          );
        },
      ),
    );
  }

  OrcaAnswer _remoteAnswer(Map<String, dynamic> payload) {
    final facts = (payload['facts'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => item.toString())
        .toList();
    final sources = (payload['sources'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => item is Map<String, dynamic>
            ? item['name']?.toString()
            : item.toString())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
    final explanation = payload['explanation']?.toString().trim();
    final providerState = payload['provider_state']?.toString() ?? 'UNAVAILABLE';
    final model = payload['model']?.toString();
    return OrcaAnswer(
      kind: explanation != null && explanation.isNotEmpty
          ? OrcaAnswerKind.reasoning
          : OrcaAnswerKind.deterministic,
      title: '${payload['title'] ?? 'ORCA evidence answer'} · ${payload['verdict'] ?? 'UNVERIFIED'}',
      lines: facts,
      chips: <String>[
        providerState.replaceAll('_', ' '),
        if (model != null && model.isNotEmpty) model,
      ],
      optionalExplanation: explanation == null || explanation.isEmpty ? null : explanation,
      optionalExplanationLabel: 'OPTIONAL OLLAMA EXPLANATION',
      source: sources.isEmpty
          ? 'POST /api/v1/chat · deterministic ORCA evidence'
          : sources.join(' · '),
      timeLabel: 'Answer generated for the displayed working coordinate',
    );
  }

  OrcaAnswer _answer(
    String question, {
    required AdvisoryEntity? advisory,
    required AgentReasoningResult? reasoning,
    required SystemHealthSnapshot? health,
    required bool online,
    required bool streamLive,
  }) {
    final String q = question.toLowerCase();
    final bool fallbackRun = reasoning != null &&
        reasoning.agents.any((AgentTraceFinding agent) => agent.agentClass == 'LLM' && agent.status.toLowerCase() != 'completed');

    if (!online && advisory == null && reasoning == null) {
      return const OrcaAnswer(
        kind: OrcaAnswerKind.unavailable,
        title: 'ORCA is offline',
        lines: <String>[
          'This device has no connection to the ORCA Box, so there is no verified evidence to answer with.',
          'Stored payloads, if any, are visible on the overview and advisory screens with their retrieval time.',
        ],
      );
    }

    bool matches(List<String> keywords) => keywords.any((String keyword) => q.contains(keyword));

    // Departure window
    if (matches(<String>['window', 'depart', 'when should', 'what time', 'leave'])) {
      final SafeWindow? window = advisory?.safeWindow;
      if (window == null) {
        return OrcaAnswer(
          kind: OrcaAnswerKind.unavailable,
          title: 'No departure window was computed',
          lines: <String>[
            'The ORCA Box did not return a safe-departure-window calculation for this request, so ORCA cannot name a time.',
          ],
          source: 'GET /api/v1/advisory → safe_window',
          timeLabel: advisory == null ? null : 'Snapshot retrieved ${DateFormatter.formatIstTime(advisory.timestamp)}',
        );
      }
      final bool hasWindow = window.from.isNotEmpty && window.to.isNotEmpty;
      return OrcaAnswer(
        kind: OrcaAnswerKind.deterministic,
        title: hasWindow
            ? 'The engine window is ${_short(window.from)} → ${_short(window.to)}'
            : 'The engine published no qualifying window',
        lines: <String>[
          if (hasWindow && window.hoursRemaining != null)
            '${window.hoursRemaining!.toStringAsFixed(0)} hour window${window.quality == null ? '' : ' · engine quality ${window.quality}'}.',
          if (window.maxWaveM != null || window.maxWindKn != null)
            'Within the window the engine reports a peak wave of ${window.maxWaveM?.toStringAsFixed(1) ?? 'unavailable'} m and peak wind of ${window.maxWindKn?.toStringAsFixed(1) ?? 'unavailable'} kn.',
          if (window.recommendationEn != null && window.recommendationEn!.isNotEmpty) window.recommendationEn!,
          if (window.note != null && window.note!.isNotEmpty) window.note!,
          if (!hasWindow) 'Status reported by the engine: ${window.status ?? 'unavailable'}.',
        ],
        chips: <String>[
          if (window.status != null) 'status ${window.status}',
          if (window.maxGustKn != null) 'peak gust ${window.maxGustKn!.toStringAsFixed(1)} kn',
        ],
        source: 'ORCA deterministic safe-window engine',
        timeLabel: 'GOOD limits wave < 2.0 m, wind < 15 kn, gust < 25 kn',
      );
    }

    // Source / provider health
    if (matches(<String>['source', 'provider', 'unavailable', 'missing', 'stale', 'health', 'data'] )) {
      final List<String> lines = <String>[];
      if (health != null) {
        final List<SourceHealthItem> sources = health.dataSources.values.toList();
        if (sources.isEmpty) {
          lines.add('The health endpoint returned no provider entries for this deployment.');
        } else {
          for (final SourceHealthItem source in sources) {
            final String note = source.note == null ? '' : ' — ${source.note}';
            lines.add('${source.name}: ${source.status.replaceAll('_', ' ')}$note');
          }
        }
      } else {
        lines.add('Provider health could not be read from the ORCA Box, so no source state can be reported.');
      }
      if (advisory != null && advisory.sourcesFailed.isNotEmpty) {
        lines.add('For this advisory the following sources did not contribute evidence: ${advisory.sourcesFailed.join(', ')}.');
      }
      return OrcaAnswer(
        kind: OrcaAnswerKind.providerStatus,
        title: health == null ? 'Provider status unavailable' : 'Provider status: ${health.status.replaceAll('_', ' ')}',
        lines: lines,
        chips: advisory == null
            ? const <String>[]
            : <String>['advisory coverage ${advisory.knownSources}/${advisory.totalSources}'],
        source: 'GET /api/v1/health',
        timeLabel: health?.timestamp == null
            ? null
            : 'Checked ${DateFormatter.formatIstTime(DateTime.fromMillisecondsSinceEpoch(health!.timestamp! * 1000, isUtc: true))}',
      );
    }

    // Reasoning / why
    if (matches(<String>['why', 'reason', 'agent', 'evidence', 'explain', 'confidence'])) {
      if (reasoning == null) {
        return const OrcaAnswer(
          kind: OrcaAnswerKind.unavailable,
          title: 'No reasoning run available yet',
          lines: <String>[
            'The multi-agent pipeline has not returned a trace in this session. Run the reasoning pass from the panel to request one.',
          ],
          source: 'GET /api/v1/reason',
        );
      }
      final List<AgentTraceFinding> completed = reasoning.agents
          .where((AgentTraceFinding agent) => agent.evidence.isNotEmpty || agent.summary.isNotEmpty)
          .take(4)
          .toList();
      return OrcaAnswer(
        kind: OrcaAnswerKind.reasoning,
        title: 'Reasoning run verdict: ${verdictWord(reasoning.verdict)}',
        lines: <String>[
          'Overall risk reported by the engine: ${reasoning.overallRisk}.',
          'Evidence coverage: ${reasoning.knownSources} of ${reasoning.totalSources} sources.',
          for (final AgentTraceFinding agent in completed) '${agent.name}: ${agent.summary}',
          if (reasoning.sourcesFailed.isNotEmpty)
            'Sources that did not contribute: ${reasoning.sourcesFailed.join(', ')}.',
        ],
        chips: <String>[
          'trace ${reasoning.orchestratorSynthesis.traceOwner}',
          if (reasoning.staleness.isCached) 'cached trace',
        ],
        optionalExplanation: reasoning.orchestratorSynthesis.recommendation,
        optionalExplanationLabel: fallbackRun
            ? 'DETERMINISTIC FALLBACK — NO LLM IN THIS RUN'
            : 'OPTIONAL LLM EXPLANATION',
        source: 'GET /api/v1/reason',
        timeLabel: reasoning.orchestratorSynthesis.timestamp == null
            ? null
            : 'Trace generated ${DateFormatter.formatIstTime(reasoning.orchestratorSynthesis.timestamp!)}',
      );
    }

    // Route intent → guidance, never a fabricated answer
    if (matches(<String>['route', 'trip', 'course', 'waypoint', 'destination', 'harbour', 'harbor'])) {
      return const OrcaAnswer(
        kind: OrcaAnswerKind.guidance,
        title: 'Route safety is computed on demand',
        lines: <String>[
          'ORCA does not hold a pre-computed answer for a course. Open the route planner, enter the departure and destination coordinates, and the ORCA Box samples the real marine inputs along the leg.',
          'Land clearance is reported only when a verified land-mask source answers; otherwise the route stays unverified.',
        ],
        source: 'GET /api/v1/route-check · GET /api/v1/route-advisory',
      );
    }

    // Verdict
    if (matches(<String>['go out', 'safe', 'verdict', 'today', 'fishing', 'can i'])) {
      if (advisory == null) {
        return const OrcaAnswer(
          kind: OrcaAnswerKind.unavailable,
          title: 'No advisory is available for this coordinate',
          lines: <String>[
            'The deterministic engine has not returned a verdict for this request, so ORCA will not state one.',
            'Check the provider status to see whether the marine sources are reachable.',
          ],
          source: 'GET /api/v1/advisory',
        );
      }
      return OrcaAnswer(
        kind: OrcaAnswerKind.deterministic,
        title: 'Deterministic verdict: ${verdictWord(advisory.verdict)}',
        lines: <String>[
          advisory.headline,
          ...advisory.plainEn.take(3),
        ],
        chips: <String>[
          '${advisory.knownSources}/${advisory.totalSources} sources verified',
          if (advisory.staleness.isCached) 'cached payload',
        ],
        source: advisory.sources.isEmpty ? 'No verified source' : advisory.sources.join(' · '),
        timeLabel: 'Snapshot retrieved ${DateFormatter.formatIstTime(advisory.timestamp)}',
      );
    }

    // Forecast detail
    if (matches(<String>['forecast', 'wave', 'wind', 'swell', 'temperature', 'chlorophyll', 'current'])) {
      if (advisory == null || advisory.variables.isEmpty) {
        return const OrcaAnswer(
          kind: OrcaAnswerKind.unavailable,
          title: 'No marine values were published for this request',
          lines: <String>[
            'The advisory response carried no per-variable values, so none can be quoted.',
          ],
          source: 'GET /api/v1/advisory → variables',
        );
      }
      final List<String> lines = <String>[
        for (final MapEntry<String, VariableItem> entry in advisory.variables.entries)
          if (entry.value.value != null)
            '${entry.key.replaceAll('_', ' ')}: ${entry.value.value!.toStringAsFixed(entry.key.contains('chlorophyll') ? 2 : 1)} ${unitSuffix(entry.value.unit)} — ${entry.value.source}, ${variableTimeLabel(entry.value)}',
      ];
      return OrcaAnswer(
        kind: OrcaAnswerKind.evidence,
        title: 'Published marine values at this coordinate',
        lines: lines.isEmpty ? <String>['Every published variable was null; ORCA does not estimate missing values.'] : lines,
        source: 'GET /api/v1/advisory → variables',
        timeLabel: 'Snapshot retrieved ${DateFormatter.formatIstTime(advisory.timestamp)}',
      );
    }

    return const OrcaAnswer(
      kind: OrcaAnswerKind.guidance,
      title: 'ORCA answers from verified endpoints only',
      lines: <String>[
        'This workspace is a data-backed question surface, not an open-ended language model. Ask about the safety verdict, the departure window, provider availability, the reason trace or the route-check process.',
      ],
      source: 'GET /api/v1/advisory · /api/v1/health · /api/v1/reason',
    );
  }

  static String _short(String raw) {
    final DateTime? parsed = DateFormatter.parseIso(raw);
    if (parsed == null) return raw;
    return DateFormatter.formatIstTime(parsed);
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final List<String> suggestions;
  final ValueChanged<String> onSubmit;

  const _Composer({
    required this.controller,
    required this.suggestions,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controller,
                    onSubmitted: onSubmit,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Ask about this coordinate…',
                      prefixIcon: Icon(Icons.forum_outlined, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => onSubmit(controller.text),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                    label: const Text('Ask'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String suggestion in suggestions)
                  ActionChip(
                    label: Text(suggestion, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    onPressed: () => onSubmit(suggestion),
                    backgroundColor: OrcaTheme.surface,
                    side: const BorderSide(color: OrcaTheme.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline_rounded, size: 14, color: VerdictColors.stale),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Questions go to the ORCA Box. Ollama may explain the live evidence when idle; deterministic marine facts are always returned and remain the safety authority.',
                    style: OrcaType.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
