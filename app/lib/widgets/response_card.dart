import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'agent_trace.dart';
import 'alert_banner.dart';

/// The big card at the bottom of the chat that shows:
///   * the final answer text
///   * alerts
///   * safety score
///   * the reasoning trace (collapsible)
class OrcaResponseCard extends StatelessWidget {
  final OrcaResponse response;
  final bool reasoningExpanded;
  final VoidCallback? onToggleReasoning;

  const OrcaResponseCard({
    super.key,
    required this.response,
    this.reasoningExpanded = true,
    this.onToggleReasoning,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: intent + safety score
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OrcaColors.oceanBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    response.intent.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: OrcaColors.oceanBlue,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SafetyScorePill(score: response.safetyScore),
                const Spacer(),
                Text(
                  '${(response.confidence * 100).toStringAsFixed(0)}% conf',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Final answer
            _MarkdownLiteText(response.answerText),
            if (response.alerts.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...response.alerts.map((a) => AlertBanner(message: a)),
            ],
            // Reasoning trace
            if (response.reasoning.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onToggleReasoning,
                child: Row(
                  children: [
                    Icon(
                      reasoningExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Reasoning trace (${response.reasoning.length} agents)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              if (reasoningExpanded) ...[
                const SizedBox(height: 4),
                AgentTraceList(steps: response.reasoning),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Tiny **bold** markdown renderer so the answer can include `**...**`.
class _MarkdownLiteText extends StatelessWidget {
  final String text;
  const _MarkdownLiteText(this.text);

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 15,
          color: Colors.black87,
          height: 1.4,
        ),
        children: spans,
      ),
    );
  }
}
