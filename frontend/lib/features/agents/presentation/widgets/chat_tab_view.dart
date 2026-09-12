import 'package:flutter/material.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';

/// Chat tab view demonstrating honest unavailable / paused status (§4, §8).
class ChatTabView extends StatelessWidget {
  const ChatTabView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Honest Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OrcaTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: VerdictColors.info, width: 1.2),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pause_circle_outline, color: VerdictColors.info, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Ollama LLM Chat: Paused by Design',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'To preserve edge computational resources and battery on the ORCA Box laptop, unstructured conversational chat is currently paused. The 10 specialized deterministic & analytical agents run autonomously in the Trace tab above.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: OrcaTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'LIVE CHAT UNAVAILABLE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: OrcaTheme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          const Text(
            'No live chat response is available. Use the Collaboration Trace after a successful real backend analysis.',
            style: TextStyle(color: OrcaTheme.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _sampleQueryCard(String question, String answer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OrcaTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: OrcaTheme.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            answer,
            style: const TextStyle(
              fontSize: 11.5,
              color: OrcaTheme.textPrimary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
