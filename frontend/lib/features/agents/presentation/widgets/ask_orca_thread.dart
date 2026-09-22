import 'package:flutter/material.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/widgets/orca_ui.dart';

/// Where an answer came from. The distinction is shown on every reply so a
/// skipper can tell a deterministic safety calculation apart from an optional
/// language-model explanation.
enum OrcaAnswerKind {
  deterministic,
  evidence,
  providerStatus,
  reasoning,
  guidance,
  unavailable,
}

extension OrcaAnswerKindX on OrcaAnswerKind {
  String get label => switch (this) {
        OrcaAnswerKind.deterministic => 'DETERMINISTIC RESULT',
        OrcaAnswerKind.evidence => 'PROVIDER EVIDENCE',
        OrcaAnswerKind.providerStatus => 'PROVIDER STATUS',
        OrcaAnswerKind.reasoning => 'AGENT EVIDENCE',
        OrcaAnswerKind.guidance => 'GUIDANCE',
        OrcaAnswerKind.unavailable => 'UNAVAILABLE',
      };

  Color get color => switch (this) {
        OrcaAnswerKind.deterministic => OrcaTheme.deepTeal,
        OrcaAnswerKind.evidence => OrcaTheme.accentDark,
        OrcaAnswerKind.providerStatus => OrcaTheme.textSecondary,
        OrcaAnswerKind.reasoning => VerdictColors.info,
        OrcaAnswerKind.guidance => OrcaTheme.textSecondary,
        OrcaAnswerKind.unavailable => VerdictColors.caution,
      };
}

/// A single reply assembled from a real ORCA endpoint response.
class OrcaAnswer {
  final OrcaAnswerKind kind;
  final String title;
  final List<String> lines;
  final List<String> chips;
  final String? source;
  final String? timeLabel;
  final String? optionalExplanation;
  final String? optionalExplanationLabel;

  const OrcaAnswer({
    required this.kind,
    required this.title,
    this.lines = const <String>[],
    this.chips = const <String>[],
    this.source,
    this.timeLabel,
    this.optionalExplanation,
    this.optionalExplanationLabel,
  });
}

class OrcaChatEntry {
  final String question;
  final OrcaAnswer answer;

  const OrcaChatEntry({required this.question, required this.answer});
}

/// Conversational workspace backed by the evidence-grounded Ask ORCA endpoint.
/// Optional Ollama wording is kept separate from deterministic safety facts.
class AskOrcaThread extends StatelessWidget {
  final List<OrcaChatEntry> entries;
  final String? subject;
  final bool loading;
  final Widget composer;

  const AskOrcaThread({
    super.key,
    required this.entries,
    required this.composer,
    this.subject,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (entries.isEmpty)
          OrcaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const OrcaEyebrow('ASK ORCA', color: OrcaTheme.accentDark),
                const SizedBox(height: 6),
                const Text('Ask about this location', style: OrcaType.cardTitle),
                const SizedBox(height: 6),
                Text(
                  subject == null
                      ? 'Every answer is assembled from the ORCA Box advisory, provider health and agent reasoning responses for your working location.'
                      : 'Every answer below is assembled from the ORCA Box responses for $subject.',
                  style: OrcaType.body.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                const OrcaProvenance(
                  source: 'POST /api/v1/chat · deterministic evidence + optional Ollama explanation',
                  timeLabel: 'Ollama may explain supplied evidence but cannot own or change the deterministic verdict',
                  maxLines: 2,
                ),
              ],
            ),
          )
        else
          for (final OrcaChatEntry entry in entries) ...<Widget>[
            _QuestionBubble(question: entry.question),
            const SizedBox(height: 8),
            _AnswerCard(answer: entry.answer),
            const SizedBox(height: 16),
          ],
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: OrcaCard(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Running the ORCA Box evidence pipeline…',
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: OrcaTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        composer,
      ],
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  final String question;

  const _QuestionBubble({required this.question});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFE3F4F3),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(3),
            ),
          ),
          child: Text(
            question,
            style: OrcaType.bubble.copyWith(
              color: const Color(0xFF174757),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

class _AnswerCard extends StatelessWidget {
  final OrcaAnswer answer;

  const _AnswerCard({required this.answer});

  @override
  Widget build(BuildContext context) => OrcaCard(
        padding: const EdgeInsets.all(16),
        borderColor: OrcaTheme.cardBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: answer.kind.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: answer.kind.color.withValues(alpha: 0.32)),
                  ),
                  child: Text(
                    answer.kind.label,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w800,
                      color: answer.kind.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(answer.title, style: OrcaType.sectionTitle.copyWith(fontSize: 15)),
            for (final String line in answer.lines) ...<Widget>[
              const SizedBox(height: 6),
              Text(line, style: OrcaType.body.copyWith(fontSize: 12.5)),
            ],
            if (answer.chips.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String chip in answer.chips)
                    OrcaInfoPill(label: chip, icon: Icons.circle_outlined),
                ],
              ),
            ],
            if (answer.optionalExplanation != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OrcaTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      answer.optionalExplanationLabel ?? 'OPTIONAL LLM EXPLANATION',
                      style: OrcaType.eyebrowMuted.copyWith(fontSize: 9.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      answer.optionalExplanation!,
                      style: OrcaType.body.copyWith(fontSize: 12.5, color: OrcaTheme.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Explanation only — the deterministic Marine Risk agent owns the verdict.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10.5,
                        color: OrcaTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (answer.source != null || answer.timeLabel != null) ...<Widget>[
              const SizedBox(height: 12),
              OrcaProvenance(source: answer.source, timeLabel: answer.timeLabel, maxLines: 3),
            ],
          ],
        ),
      );
}
