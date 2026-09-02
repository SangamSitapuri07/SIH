import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

/// Renders the list of agent reasoning steps as they stream in.
///
/// Each step is a compact card showing the agent name, summary, and a
/// tiny badge with how long it took. The user gets a visible "thinking
/// is happening" effect because new steps appear at the bottom.
class AgentTraceList extends StatelessWidget {
  final List<AgentStep> steps;
  const AgentTraceList({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Waiting for first agent to respond…',
          style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: steps
          .asMap()
          .entries
          .map((e) => _AgentStepCard(step: e.value, index: e.key + 1))
          .toList(),
    );
  }
}

class _AgentStepCard extends StatelessWidget {
  final AgentStep step;
  final int index;
  const _AgentStepCard({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconFor(step.agent);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(left: BorderSide(color: color, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '#$index · ${step.agent}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: color,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (step.durationMs > 0)
                      Text(
                        '${step.durationMs} ms',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(step.summary, style: const TextStyle(fontSize: 13)),
                if (step.dataSources.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: step.dataSources
                        .map(
                          (s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: color, width: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                fontSize: 10,
                                color: color,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _iconFor(String agent) {
    switch (agent) {
      case 'planner':
        return (Icons.psychology, OrcaColors.oceanBlue);
      case 'weather':
        return (Icons.wb_cloudy, Colors.blueAccent);
      case 'ocean':
        return (Icons.waves, Colors.teal);
      case 'gis':
        return (Icons.map, Colors.deepPurple);
      case 'risk':
        return (Icons.shield, OrcaColors.warnAmber);
      case 'reasoner':
        return (Icons.bolt, OrcaColors.safeGreen);
      default:
        return (Icons.assistant, Colors.grey);
    }
  }
}
